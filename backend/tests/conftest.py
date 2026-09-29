import os
import tempfile

_tmp = tempfile.mkdtemp()
os.environ.update(
    DATABASE_URL=f"sqlite:///{_tmp}/test.db",
    MEDIA_DIR=f"{_tmp}/media",
    LLM_PROVIDER="fake",
    IMAGE_PROVIDER="none",
    PROMPT_ONLY="false",  # Legacy renderer tests; prompt-only flow has dedicated coverage.
    ADMIN_TOKEN="t",
)
