from functools import lru_cache
from typing import Annotated, Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration, sourced entirely from the environment."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Spry API"
    app_env: Literal["development", "test", "production"] = "development"
    log_level: str = "info"

    database_url: str = "postgresql+asyncpg://spry:spry@db:5432/spry"
    # Off on Lambda: a warm but idle execution environment would otherwise hold
    # pooled connections open, and Aurora Serverless only pauses at zero.
    db_pooling: bool = True
    # NoDecode keeps pydantic-settings from JSON-parsing the env value, so the
    # validator below can accept the comma-separated form Compose passes.
    cors_origins: Annotated[list[str], NoDecode] = Field(
        default_factory=lambda: ["http://localhost:3000"]
    )

    # Working week used by the insights (FR-8). One shared setting until
    # members have their own profile.
    work_timezone: str = "Europe/Kyiv"
    work_start_hour: int = 9
    work_end_hour: int = 18
    # Contiguous free time shorter than this is not "deep work" (FR-9).
    deep_work_min_minutes: int = 60
    # Smallest block Spry proposes to reserve (FR-14).
    deep_work_block_minutes: int = 120

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_origins(cls, value: object) -> object:
        """Accept a comma-separated string, since that is how Compose passes it."""
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value

    @property
    def is_development(self) -> bool:
        return self.app_env == "development"


@lru_cache
def get_settings() -> Settings:
    return Settings()
