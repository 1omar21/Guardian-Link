from pydantic import BaseModel, EmailStr, Field
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
    full_name: str


class UserLogin(BaseModel):
    """User login model."""
    email: EmailStr
    password: str


class UserResponse(UserBase):
    """User response model."""
    id: str
    full_name: str
    created_at: datetime
    focus_coins: int = 0
    stickers: list[str] = []
    
    class Config:
        from_attributes = True


class Token(BaseModel):
    """JWT token response."""
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


class TokenData(BaseModel):
    """Token payload data."""
    user_id: str
    role: UserRole
    email: str
