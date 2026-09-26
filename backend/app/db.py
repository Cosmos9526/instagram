from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from .config import settings


class Base(DeclarativeBase):
    pass


def make_engine(url: str):
    kw = {"connect_args": {"check_same_thread": False}} if url.startswith("sqlite") else {"pool_size": 5}
    return create_engine(url, **kw)


engine = make_engine(settings.database_url)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def init_db(bind=None):
    from . import models  # noqa: F401

    Base.metadata.create_all(bind or engine)
