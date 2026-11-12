from pydantic import BaseModel, EmailStr, Field, field_validator
from datetime import datetime
from typing import Optional
from enum import Enum


class UserRole(str, Enum):
    """User role enumeration."""
    PARENT = "parent"
    CHILD = "child"


class UserBase(BaseModel):
    """Base user model."""
    email: EmailStr
    role: UserRole
    family_id: Optional[str] = None


class UserCreate(UserBase):
    """User creation model."""
    password: str = Field(..., min_length=6)
    full_name: str = Field(..., min_length=1, max_length=100)

    @field_validator("password")
    @classmethod
    def password_fits_bcrypt(cls, v: str) -> str:
        if len(v.encode("utf-8")) > 72:
            raise ValueError("Password is too long (max 72 bytes)")
        return v

    @field_validator("full_name")
    @classmethod
    def strip_name(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Full name is required")
        return v


class UserLogin(BaseModel):
    """User login model."""
    email: EmailStr
    password: str


class UserResponse(UserBase):
    """User response model."""
    id: str
    full_name: str = ""
    created_at: Optional[datetime] = None
    focus_coins: int = 0
    stickers: list[str] = []
    
    class Config:
        from_attributes = True


class Token(BaseModel):
    """JWT token response."""
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


class FCMTokenRequest(BaseModel):
    """FCM token registration."""
    fcm_token: str = Field(..., min_length=1, max_length=4096)


class TokenData(BaseModel):
    """Token payload data."""
    user_id: str
    role: UserRole
    email: str
