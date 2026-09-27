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


# Columns added after the first release: (table, column, SQL type, default literal).
_ADDED_COLUMNS = [
    ("brands", "telegram", "VARCHAR(100)", "''"),
    ("brands", "competitors", "JSON", "'[]'"),
    ("jobs", "competitor_scan_id", "VARCHAR(36)", "NULL"),
]


def init_db(bind=None):
    from sqlalchemy import inspect, text

    from . import models  # noqa: F401

    bind = bind or engine
    Base.metadata.create_all(bind)
    # Tiny forward-only migration: add new columns to existing tables.
    insp = inspect(bind)
    with bind.begin() as conn:
        for table, col, typ, default in _ADDED_COLUMNS:
            if table in insp.get_table_names() and col not in {c["name"] for c in insp.get_columns(table)}:
                conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {col} {typ} DEFAULT {default}"))
