from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://postyar:postyar@db:5432/postyar"
    media_dir: str = "/data/media"
    web_dir: str = "/app/web"  # built Flutter PWA; served at / when present
    admin_token: str = "change-me"  # only for /admin/* endpoints
    secret_key: str = "dev-secret-change-me"  # signs login tokens
    allow_signup: bool = True

    # Text model: any OpenAI-compatible chat endpoint (your gateway, or Gemini's
    # https://generativelanguage.googleapis.com/v1beta/openai/).
    llm_provider: str = "openai_compat"  # openai_compat | fake
    llm_base_url: str = "https://generativelanguage.googleapis.com/v1beta/openai/"
    llm_api_key: str = ""
    llm_model: str = "gemini-flash-latest"
    # Tried when the primary model fails (quota, 402, outage). OpenAI-compatible; empty = no fallback.
    llm_fallback_url: str = "https://text.pollinations.ai/openai"
    llm_fallback_model: str = "openai"

    # Images: pollinations (free, no key) | cloudflare (Workers AI, Flux schnell) | none (brand-colour background)
    image_provider: str = "pollinations"
    cf_account_id: str = ""
    cf_api_token: str = ""
    cf_image_model: str = "@cf/black-forest-labs/flux-1-schnell"

    chromium_path: str = ""  # optional explicit Chromium binary

    # Market research
    research_provider: str = "free"  # free (ddgs + yt-dlp, no keys) | gemini (Google Search grounding, falls back to free) | fake
    gemini_research_model: str = "gemini-flash-latest"
    youtube_api_key: str = ""  # YouTube Data API v3: most-viewed recent videos per keyword
    apify_token: str = ""  # optional: Instagram hashtag top posts via Apify
    research_max_age_days: int = 3  # daily batch refreshes research older than this

    daily_run_hour: int = 7  # server-local hour for the daily batch
    timezone: str = "Asia/Tehran"

    # Competitor scans: bounded so a slow competitor never blocks the single worker for long
    competitor_scan_budget_seconds: int = 720  # whole-scan wall clock budget (12 min)
    competitor_site_budget_seconds: int = 90  # per-competitor website budget


settings = Settings()
