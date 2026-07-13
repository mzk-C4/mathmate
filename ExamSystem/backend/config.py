from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "MathMate Exam System"
    app_env: str = "development"
    api_prefix: str = "/api"

    json_database_path: str = "db/exam_data.json"

    llm_api_key: str = ""
    llm_base_url: str = "https://api.openai.com/v1"
    llm_model: str = "gpt-4.1-mini"
    llm_timeout_seconds: int = 30

    ocr_api_key: str = ""
    ocr_base_url: str = ""

    upload_dir: str = "uploads"
    max_upload_mb: int = Field(default=8, ge=1, le=50)

    auth_secret_path: str = "/opt/mathmate/auth_secret.txt"
    auth_token_max_age_seconds: int = Field(default=604800, ge=300)
    cors_origins: str = "https://mathmate.top,https://www.mathmate.top"

    @property
    def cors_origin_list(self) -> list[str]:
        return [
            origin.strip()
            for origin in self.cors_origins.split(",")
            if origin.strip()
        ]

    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parents[1] / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
