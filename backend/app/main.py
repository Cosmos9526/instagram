import os
from contextlib import asynccontextmanager
from datetime import datetime
from zoneinfo import ZoneInfo

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import settings
from .db import SessionLocal, init_db
from .models import POST_TYPES, Brand, Post
from .scheduler import create_daily_posts
from .worker import enqueue


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    yield


os.makedirs(settings.media_dir, exist_ok=True)
app = FastAPI(title="Hashtpa", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
app.mount("/media", StaticFiles(directory=settings.media_dir), name="media")


def get_db():
    with SessionLocal() as db:
        yield db


def auth(authorization: str = Header("")):
    if authorization != f"Bearer {settings.admin_token}":
        raise HTTPException(401, "invalid token")


class BrandIn(BaseModel):
    name: str
    industry: str
    language: str = Field("fa", pattern="^(fa|en)$")
    description: str = ""
    products: list[dict] = []
    audience: str = ""
    tone: str = ""
    colors: dict = {}
    forbidden_topics: list[str] = []
    cta: str = ""
    hashtags: list[str] = []
    weekly_plan: dict[str, list[str]] = {}


class GenerateIn(BaseModel):
    post_type: str
    mode: str = Field("single", pattern="^(single|carousel|video)$")
    topic_hint: str = ""
    n_body: int = Field(4, ge=2, le=8)
    target_seconds: int = Field(24, ge=10, le=40)


class PostEdit(BaseModel):
    content: dict


def post_out(p: Post) -> dict:
    return {
        "id": p.id, "brand_id": p.brand_id, "post_type": p.post_type, "mode": p.mode,
        "status": p.status, "content": p.content, "error": p.error, "for_date": p.for_date,
        "slides": [f"/media/{s}" for s in p.slides], "created_at": p.created_at,
    }


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/brands", dependencies=[Depends(auth)])
def create_brand(body: BrandIn, db: Session = Depends(get_db)):
    b = Brand(**body.model_dump())
    db.add(b)
    db.commit()
    return {"id": b.id}


@app.get("/brands", dependencies=[Depends(auth)])
def list_brands(db: Session = Depends(get_db)):
    return [{"id": b.id, "name": b.name, **BrandIn.model_validate(b, from_attributes=True).model_dump()}
            for b in db.scalars(select(Brand))]


@app.put("/brands/{brand_id}", dependencies=[Depends(auth)])
def update_brand(brand_id: str, body: BrandIn, db: Session = Depends(get_db)):
    b = db.get(Brand, brand_id) or _404()
    for k, v in body.model_dump().items():
        setattr(b, k, v)
    db.commit()
    return {"id": b.id}


@app.post("/brands/{brand_id}/generate", dependencies=[Depends(auth)])
def generate(brand_id: str, body: GenerateIn, db: Session = Depends(get_db)):
    db.get(Brand, brand_id) or _404()
    if body.post_type not in POST_TYPES:
        raise HTTPException(422, f"post_type must be one of {POST_TYPES}")
    mode = "video" if body.post_type == "video_prompt" else body.mode
    if mode == "video" and body.post_type != "video_prompt":
        raise HTTPException(422, "mode=video requires post_type=video_prompt")
    today = datetime.now(ZoneInfo(settings.timezone)).date().isoformat()
    post = Post(brand_id=brand_id, post_type=body.post_type, mode=mode, topic_hint=body.topic_hint,
                content={"n_body": body.n_body, "target_seconds": body.target_seconds}, for_date=today)
    db.add(post)
    db.flush()
    enqueue(db, post)
    db.commit()
    return post_out(post)


@app.get("/brands/{brand_id}/posts", dependencies=[Depends(auth)])
def list_posts(brand_id: str, date: str | None = None, db: Session = Depends(get_db)):
    q = select(Post).where(Post.brand_id == brand_id).order_by(Post.created_at.desc()).limit(100)
    if date:
        q = q.where(Post.for_date == date)
    return [post_out(p) for p in db.scalars(q)]


@app.get("/posts/{post_id}", dependencies=[Depends(auth)])
def get_post(post_id: str, db: Session = Depends(get_db)):
    return post_out(db.get(Post, post_id) or _404())


@app.put("/posts/{post_id}", dependencies=[Depends(auth)])
def edit_post(post_id: str, body: PostEdit, db: Session = Depends(get_db)):
    """User edited the text: save and re-render (free, no model calls)."""
    p = db.get(Post, post_id) or _404()
    if p.status not in ("ready", "approved"):
        raise HTTPException(409, "post is not ready yet")
    p.content = body.content
    if p.mode != "video":
        p.status = "queued"
        enqueue(db, p, kind="rerender")
    db.commit()
    return post_out(p)


@app.post("/posts/{post_id}/{action}", dependencies=[Depends(auth)])
def review(post_id: str, action: str, db: Session = Depends(get_db)):
    p = db.get(Post, post_id) or _404()
    if action == "approve":
        p.status = "approved"
    elif action == "reject":
        p.status = "rejected"
    elif action == "regenerate":
        p.status = "queued"
        enqueue(db, p)
    else:
        raise HTTPException(404, "unknown action")
    db.commit()
    return post_out(p)


@app.post("/admin/run-daily", dependencies=[Depends(auth)])
def run_daily():
    return {"queued": create_daily_posts()}


def _404():
    raise HTTPException(404, "not found")
