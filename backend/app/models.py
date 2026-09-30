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


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_id)
    email: Mapped[str] = mapped_column(String(200), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(200), default="")
    password_hash: Mapped[str] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class Brand(Base):
    """A user's project: one business/brand with its own profile, plan, posts and research."""

    __tablename__ = "brands"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_id)
    owner_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    website: Mapped[str] = mapped_column(Text, default="")
    instagram: Mapped[str] = mapped_column(String(100), default="")
    telegram: Mapped[str] = mapped_column(String(100), default="")
    competitors: Mapped[list] = mapped_column(JSON, default=list)  # competitor Instagram usernames
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


class Research(Base):
    """Market research snapshot for a project: web facts, trends, keywords, top videos, video styles."""

    __tablename__ = "research"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_id)
    brand_id: Mapped[str] = mapped_column(ForeignKey("brands.id", ondelete="CASCADE"), index=True)
    status: Mapped[str] = mapped_column(String(20), default="queued")  # queued | running | ready | failed
    focus: Mapped[str] = mapped_column(Text, default="")  # optional: product or question to focus on
    report: Mapped[dict] = mapped_column(JSON, default=dict)
    error: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, onupdate=_now)


class MarketAlert(Base):
    """A high-priority, source-backed AI market change shown above the content plan."""

    __tablename__ = "market_alerts"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_id)
    fingerprint: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    title: Mapped[str] = mapped_column(Text)
    summary: Mapped[str] = mapped_column(Text, default="")
    source: Mapped[str] = mapped_column(String(120), default="")
    url: Mapped[str] = mapped_column(Text, default="")
    category: Mapped[str] = mapped_column(String(30), default="news")
    importance: Mapped[int] = mapped_column(Integer, default=1)
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    discovered_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class CompetitorScan(Base):
    """One scan of a project's competitor list: website + Instagram analysis and the synthesized report."""

    __tablename__ = "competitor_scans"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_id)
    brand_id: Mapped[str] = mapped_column(ForeignKey("brands.id", ondelete="CASCADE"), index=True)
    status: Mapped[str] = mapped_column(String(20), default="queued")  # queued | running | ready | failed
    only: Mapped[list] = mapped_column(JSON, default=list)  # competitor ids to scan; empty = all
    report: Mapped[dict] = mapped_column(JSON, default=dict)
    error: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, onupdate=_now)


class Job(Base):
    """Minimal Postgres-backed queue. One worker process, concurrency 1."""

    __tablename__ = "jobs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    post_id: Mapped[str | None] = mapped_column(ForeignKey("posts.id", ondelete="CASCADE"), nullable=True)
    research_id: Mapped[str | None] = mapped_column(ForeignKey("research.id", ondelete="CASCADE"), nullable=True)
    competitor_scan_id: Mapped[str | None] = mapped_column(
        ForeignKey("competitor_scans.id", ondelete="CASCADE"), nullable=True
    )
    kind: Mapped[str] = mapped_column(String(10), default="generate")  # generate | rerender | research | compete
    status: Mapped[str] = mapped_column(String(10), default="queued", index=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
