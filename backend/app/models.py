import uuid
from datetime import datetime, timezone

from sqlalchemy import JSON, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base

POST_TYPES = ("educational", "news", "promo", "sales", "video_prompt")


def _id() -> str:
    return str(uuid.uuid4())


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Brand(Base):
    __tablename__ = "brands"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_id)
    name: Mapped[str] = mapped_column(String(200))
    industry: Mapped[str] = mapped_column(String(200))
    language: Mapped[str] = mapped_column(String(8), default="fa")  # fa | en
    description: Mapped[str] = mapped_column(Text, default="")
    products: Mapped[list] = mapped_column(JSON, default=list)  # [{name, desc, price?, url?}]
    audience: Mapped[str] = mapped_column(Text, default="")
    tone: Mapped[str] = mapped_column(Text, default="")
    colors: Mapped[dict] = mapped_column(JSON, default=dict)  # primary, secondary, bg, text
    forbidden_topics: Mapped[list] = mapped_column(JSON, default=list)
    cta: Mapped[str] = mapped_column(Text, default="")
    hashtags: Mapped[list] = mapped_column(JSON, default=list)
    # weekday (0=Monday .. 6=Sunday, Python convention) -> list of post types
    weekly_plan: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class Post(Base):
    __tablename__ = "posts"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_id)
    brand_id: Mapped[str] = mapped_column(ForeignKey("brands.id", ondelete="CASCADE"), index=True)
    post_type: Mapped[str] = mapped_column(String(20))
    mode: Mapped[str] = mapped_column(String(10), default="single")  # single | carousel | video
    topic_hint: Mapped[str] = mapped_column(Text, default="")  # optional trend/news pasted by user
    status: Mapped[str] = mapped_column(String(20), default="queued")
    # queued | running | ready | approved | rejected | failed
    content: Mapped[dict] = mapped_column(JSON, default=dict)  # LLM output
    slides: Mapped[list] = mapped_column(JSON, default=list)  # rendered PNG paths (relative to media)
    error: Mapped[str] = mapped_column(Text, default="")
    for_date: Mapped[str] = mapped_column(String(10), default="")  # YYYY-MM-DD of the daily batch
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, onupdate=_now)

    brand: Mapped[Brand] = relationship()


class Job(Base):
    """Minimal Postgres-backed queue. One worker process, concurrency 1."""

    __tablename__ = "jobs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    post_id: Mapped[str] = mapped_column(ForeignKey("posts.id", ondelete="CASCADE"))
    kind: Mapped[str] = mapped_column(String(10), default="generate")  # generate | rerender
    status: Mapped[str] = mapped_column(String(10), default="queued", index=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
