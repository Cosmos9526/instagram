from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://hashtpa:hashtpa@db:5432/hashtpa"
    media_dir: str = "/data/media"
    admin_token: str = "change-me"

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

    daily_run_hour: int = 7  # server-local hour for the daily batch
    timezone: str = "Asia/Tehran"


settings = Settings()
