from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://hashtpa:hashtpa@db:5432/hashtpa"
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

    # Images: cloudflare (Workers AI, Flux schnell) | none (brand-colour gradient)
    image_provider: str = "none"
    cf_account_id: str = ""
    cf_api_token: str = ""
    cf_image_model: str = "@cf/black-forest-labs/flux-1-schnell"

    chromium_path: str = ""  # optional explicit Chromium binary

    # Market research
    research_provider: str = "gemini"  # gemini (Google Search grounding) | llm (no web access) | fake
    gemini_research_model: str = "gemini-flash-latest"
    youtube_api_key: str = ""  # YouTube Data API v3: most-viewed recent videos per keyword
    apify_token: str = ""  # optional: Instagram hashtag top posts via Apify
    research_max_age_days: int = 3  # daily batch refreshes research older than this

    daily_run_hour: int = 7  # server-local hour for the daily batch
    timezone: str = "Asia/Tehran"


settings = Settings()
