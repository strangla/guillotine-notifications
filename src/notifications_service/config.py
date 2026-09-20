from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/trading_platform"
    notification_api_key: str = ""
    source_sha: str = "unknown"

settings = Settings()
