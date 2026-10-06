"""Environment-based backend configuration."""

from dataclasses import dataclass
import os
from pathlib import Path

from dotenv import load_dotenv


load_dotenv(Path(__file__).resolve().parents[1] / ".env")


@dataclass(frozen=True)
class Settings:
    """Keep database and Firebase credentials outside tracked source files."""

    mysql_host: str = os.getenv("MYSQL_HOST", "127.0.0.1")
    mysql_port: int = int(os.getenv("MYSQL_PORT", "3306"))
    mysql_user: str = os.getenv("MYSQL_USER", "root")
    mysql_password: str = os.getenv("MYSQL_PASSWORD", "")
    mysql_database: str = os.getenv("MYSQL_DATABASE", "shupick_v2")
    firebase_project_id: str = os.getenv("FIREBASE_PROJECT_ID", "")
    firebase_credentials_path: str = os.getenv("FIREBASE_CREDENTIALS_PATH", "")
    outbox_worker_secret: str = os.getenv("OUTBOX_WORKER_SECRET", "")
    # Social provider secrets stay on the server, never in Flutter assets.
    kakao_app_id: int = int(os.getenv("KAKAO_APP_ID", "0"))
    naver_client_id: str = os.getenv("NAVER_CLIENT_ID", "")
    naver_client_secret: str = os.getenv("NAVER_CLIENT_SECRET", "")
    naver_redirect_uri: str = os.getenv(
        "NAVER_REDIRECT_URI", "http://10.0.2.2:8000/auth/social/naver/callback"
    )


settings = Settings()
