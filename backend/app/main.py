import mimetypes
import os
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from . import auth as authlib
from .config import settings
from .db import SessionLocal, init_db
from .models import POST_TYPES, Brand, Post, Research, User
from .scheduler import create_daily_posts
from .template_registry import TEMPLATES
from .video_styles import VIDEO_STYLES
from .worker import enqueue, enqueue_research

PREVIEW_DIR = Path(__file__).parent / "previews"

# Slim images may lack /etc/mime.types; the WASM build needs these served with the right types.
mimetypes.add_type("text/javascript", ".mjs")
mimetypes.add_type("application/wasm", ".wasm")


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    yield


os.makedirs(settings.media_dir, exist_ok=True)
app = FastAPI(title="Postyar", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
app.mount("/media", StaticFiles(directory=settings.media_dir), name="media")
if PREVIEW_DIR.is_dir():
    app.mount("/previews", StaticFiles(directory=PREVIEW_DIR), name="previews")


def get_db():
    with SessionLocal() as db:
        yield db


def current_user(authorization: str = Header(""), db: Session = Depends(get_db)) -> User:
    user_id = authlib.read_token(authorization.removeprefix("Bearer ").strip())
    user = db.get(User, user_id) if user_id else None
    if not user:
        raise HTTPException(401, "invalid token")
    return user


def admin(authorization: str = Header("")):
    if authorization != f"Bearer {settings.admin_token}":
        raise HTTPException(401, "invalid token")


def _404():
    raise HTTPException(404, "not found")


def own_brand(brand_id: str, user: User, db: Session) -> Brand:
    b = db.get(Brand, brand_id)
    if not b or b.owner_id != user.id:
        _404()
    return b


def own_post(post_id: str, user: User, db: Session) -> Post:
    p = db.get(Post, post_id)
    if not p:
        _404()
    own_brand(p.brand_id, user, db)
    return p


# ---------- auth ----------

class RegisterIn(BaseModel):
    email: str = Field(pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    password: str = Field(min_length=8)
    name: str = ""


class LoginIn(BaseModel):
    email: str
    password: str


class MeIn(BaseModel):
    name: str | None = None
    password: str | None = Field(None, min_length=8)


def user_out(u: User) -> dict:
    return {"id": u.id, "email": u.email, "name": u.name}


@app.post("/auth/register")
def register(body: RegisterIn, db: Session = Depends(get_db)):
    if not settings.allow_signup:
        raise HTTPException(403, "signup is closed")
    email = body.email.strip().lower()
    if db.scalar(select(User.id).where(User.email == email)):
        raise HTTPException(409, "email already registered")
    u = User(email=email, name=body.name.strip(), password_hash=authlib.hash_password(body.password))
    db.add(u)
    db.commit()
    return {"token": authlib.make_token(u.id), "user": user_out(u)}


@app.post("/auth/login")
def login(body: LoginIn, db: Session = Depends(get_db)):
    u = db.scalars(select(User).where(User.email == body.email.strip().lower())).first()
    if not u or not authlib.verify_password(body.password, u.password_hash):
        raise HTTPException(401, "wrong email or password")
    return {"token": authlib.make_token(u.id), "user": user_out(u)}


@app.get("/auth/me")
def me(user: User = Depends(current_user)):
    return user_out(user)


@app.put("/auth/me")
def update_me(body: MeIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if body.name is not None:
        user.name = body.name.strip()
    if body.password:
        user.password_hash = authlib.hash_password(body.password)
    db.merge(user)
    db.commit()
    return user_out(user)


# ---------- projects (brands) ----------

class BrandIn(BaseModel):
    name: str = Field(min_length=1, pattern=r"\S")
    industry: str = Field(min_length=1, pattern=r"\S")
    language: str = Field("fa", pattern="^(fa|en)$")
    description: str = ""
    website: str = ""
    instagram: str = ""
    products: list[dict] = []
    audience: str = ""
    tone: str = ""
    colors: dict = {}
    forbidden_topics: list[str] = []
    cta: str = ""
    hashtags: list[str] = []
    weekly_plan: dict[str, list[str]] = {}


def brand_out(b: Brand) -> dict:
    # Plain read, no validation: projects saved before a rule was added must still load.
    return {"id": b.id, **{k: getattr(b, k) for k in BrandIn.model_fields}}


@app.post("/brands")
def create_brand(body: BrandIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    b = Brand(owner_id=user.id, **body.model_dump())
    db.add(b)
    db.commit()
    return {"id": b.id}


@app.get("/brands")
def list_brands(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return [brand_out(b) for b in db.scalars(select(Brand).where(Brand.owner_id == user.id).order_by(Brand.created_at))]


@app.get("/brands/{brand_id}")
def get_brand(brand_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return brand_out(own_brand(brand_id, user, db))


@app.put("/brands/{brand_id}")
def update_brand(brand_id: str, body: BrandIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    b = own_brand(brand_id, user, db)
    for k, v in body.model_dump().items():
        setattr(b, k, v)
    db.commit()
    return {"id": b.id}


@app.delete("/brands/{brand_id}")
def delete_brand(brand_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    db.delete(own_brand(brand_id, user, db))
    db.commit()
    return {"ok": True}


# ---------- catalog ----------

@app.get("/catalog")
def catalog():
    """Every slide template and video style the generator can use (public: no user data)."""
    return {
        "templates": [
            {
                "code": code, "name": spec["name_fa"], "description": spec["desc_fa"], "post_types": spec["types"],
                "carousel": spec.get("carousel", False), "has_image": spec["image"],
                "preview": f"/previews/{code}.png" if (PREVIEW_DIR / f"{code}.png").exists() else None,
            }
            for code, spec in TEMPLATES.items()
        ],
        "video_styles": [
            {k: s[k] for k in ("id", "name_fa", "description_fa", "best_for", "pacing")} | {"beats": s["beats"]}
            for s in VIDEO_STYLES
        ],
    }


# ---------- research ----------

class ResearchIn(BaseModel):
    focus: str = ""


def research_out(r: Research) -> dict:
    return {"id": r.id, "status": r.status, "focus": r.focus, "report": r.report, "error": r.error,
            "created_at": r.created_at}


@app.post("/brands/{brand_id}/research")
def start_research(brand_id: str, body: ResearchIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    own_brand(brand_id, user, db)
    busy = db.scalar(select(Research.id).where(Research.brand_id == brand_id, Research.status.in_(["queued", "running"])))
    if busy:
        raise HTTPException(409, "research already running")
    r = Research(brand_id=brand_id, focus=body.focus.strip())
    db.add(r)
    db.flush()
    enqueue_research(db, r)
    db.commit()
    return research_out(r)


@app.get("/brands/{brand_id}/research")
def list_research(brand_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    own_brand(brand_id, user, db)
    rows = db.scalars(select(Research).where(Research.brand_id == brand_id).order_by(Research.created_at.desc()).limit(20))
    return [research_out(r) for r in rows]


# ---------- posts ----------

class GenerateIn(BaseModel):
    post_type: str
    mode: str = Field("single", pattern="^(single|carousel|video)$")
    topic_hint: str = ""
    template: str = ""  # single mode: a template code from /catalog; empty = automatic rotation
    video_style: str = ""  # video_prompt: a style id from /catalog
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


@app.post("/brands/{brand_id}/generate")
def generate(brand_id: str, body: GenerateIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    own_brand(brand_id, user, db)
    if body.post_type not in POST_TYPES:
        raise HTTPException(422, f"post_type must be one of {POST_TYPES}")
    if body.template and body.template not in TEMPLATES:
        raise HTTPException(422, "unknown template")
    mode = "video" if body.post_type == "video_prompt" else body.mode
    if mode == "video" and body.post_type != "video_prompt":
        raise HTTPException(422, "mode=video requires post_type=video_prompt")
    today = datetime.now(ZoneInfo(settings.timezone)).date().isoformat()
    opts = {"n_body": body.n_body, "target_seconds": body.target_seconds}
    if body.template:
        opts["template"] = body.template
    if body.video_style:
        opts["video_style"] = body.video_style
    post = Post(brand_id=brand_id, post_type=body.post_type, mode=mode, topic_hint=body.topic_hint,
                content=opts, for_date=today)
    db.add(post)
    db.flush()
    enqueue(db, post)
    db.commit()
    return post_out(post)


@app.get("/brands/{brand_id}/posts")
def list_posts(brand_id: str, date: str | None = None, user: User = Depends(current_user),
               db: Session = Depends(get_db)):
    own_brand(brand_id, user, db)
    q = select(Post).where(Post.brand_id == brand_id).order_by(Post.created_at.desc()).limit(100)
    if date:
        q = q.where(Post.for_date == date)
    return [post_out(p) for p in db.scalars(q)]


@app.get("/posts/{post_id}")
def get_post(post_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return post_out(own_post(post_id, user, db))


@app.put("/posts/{post_id}")
def edit_post(post_id: str, body: PostEdit, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """User edited the text: save and re-render (free, no model calls)."""
    p = own_post(post_id, user, db)
    if p.status not in ("ready", "approved"):
        raise HTTPException(409, "post is not ready yet")
    p.content = body.content
    if p.mode != "video":
        p.status = "queued"
        enqueue(db, p, kind="rerender")
    db.commit()
    return post_out(p)


@app.post("/posts/{post_id}/{action}")
def review(post_id: str, action: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    p = own_post(post_id, user, db)
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


@app.post("/admin/run-daily", dependencies=[Depends(admin)])
def run_daily():
    return {"queued": create_daily_posts()}


# The PWA (Flutter web build) is served from the same origin as the API. Mounted last so API routes win.
if os.path.isdir(settings.web_dir):
    app.mount("/", StaticFiles(directory=settings.web_dir, html=True), name="web")
