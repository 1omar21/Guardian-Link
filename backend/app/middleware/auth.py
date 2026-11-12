from datetime import datetime, timedelta, timezone
from typing import Optional
from jose import JWTError, jwt
import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from app.config import get_settings
from app.services.firebase_service import get_firebase_service

settings = get_settings()

# JWT token bearer
security = HTTPBearer()

# bcrypt only uses the first 72 bytes of a password; bcrypt>=5 raises for longer input.
BCRYPT_MAX_BYTES = 72


def verify_password(plain_password: str, hashed_password: Optional[str]) -> bool:
    """Verify a password against its hash. Never raises; returns False on any problem."""
    if not plain_password or not hashed_password:
        return False
    password_bytes = plain_password.encode("utf-8")
    if len(password_bytes) > BCRYPT_MAX_BYTES:
        return False
    try:
        return bcrypt.checkpw(password_bytes, hashed_password.encode("utf-8"))
    except (ValueError, TypeError):
        # Malformed / legacy hash stored in the database
        return False


def get_password_hash(password: str) -> str:
    """Hash a password."""
    password_bytes = password.encode("utf-8")
    if len(password_bytes) > BCRYPT_MAX_BYTES:
        raise ValueError(f"Password must be at most {BCRYPT_MAX_BYTES} bytes")
    return bcrypt.hashpw(password_bytes, bcrypt.gensalt()).decode("utf-8")


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create a signed JWT access token."""
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(minutes=settings.access_token_expire_minutes)
    )
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.secret_key, algorithm=settings.algorithm)


def _credentials_exception() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )


def decode_access_token(token: str) -> dict:
    """Decode and verify a JWT access token."""
    try:
        return jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
    except JWTError:
        raise _credentials_exception()


async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)) -> dict:
    """
    Resolve the authenticated user.

    The token only proves identity (user_id). Role, family and name are always
    loaded fresh from Firestore so that changes (e.g. a child joining a family
    after login) take effect immediately and a deleted user can't keep using
    an old token.
    """
    payload = decode_access_token(credentials.credentials)

    user_id = payload.get("user_id")
    if not user_id:
        raise _credentials_exception()

    user = await get_firebase_service().get_user_by_id(user_id)
    if not user:
        raise _credentials_exception()

    return {
        "id": user_id,
        "email": user.get("email"),
        "role": user.get("role"),
        "family_id": user.get("family_id"),
        "full_name": user.get("full_name"),
    }


def require_role(required_role: str):
    """
    Dependency factory to require a specific user role.

    Usage:
        @router.get("/admin")
        async def admin_only(user: dict = Depends(require_role("parent"))):
            ...
    """
    async def role_checker(current_user: dict = Depends(get_current_user)) -> dict:
        if current_user.get("role") != required_role:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"This endpoint requires {required_role} role"
            )
        return current_user

    return role_checker
