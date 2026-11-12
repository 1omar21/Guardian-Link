from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""
    
    # API Configuration
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    secret_key: str
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 30  # 30 days; the app has no token refresh
    
    # Firebase Configuration
    firebase_credentials_path: str
    firebase_database_url: str = ""  # optional; only Firestore is used
    
    # CORS Configuration
    allowed_origins: str = "http://localhost:*"
    
    # Environment
    environment: str = "development"
    debug: bool = False
    
    class Config:
        env_file = ".env"
        case_sensitive = False
        extra = "ignore"


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()
