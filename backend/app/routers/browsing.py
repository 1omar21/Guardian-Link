"""
Browsing history monitoring (browsers only).

The child's phone runs an Android AccessibilityService that reads the address
bar of supported browsers and uploads visited URLs here. Parents can read
their own children's history.
"""
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, HTTPException, status, Depends, Query
from pydantic import BaseModel, Field

from app.services.firebase_service import get_firebase_service
from app.middleware.auth import get_current_user

router = APIRouter()
firebase_service = get_firebase_service()


class BrowsingVisit(BaseModel):
    url: str = Field(..., min_length=1, max_length=2048)
    title: Optional[str] = Field(default=None, max_length=500)
    browser: Optional[str] = Field(default=None, max_length=200)
    visited_at: Optional[datetime] = None


class BrowsingLogRequest(BaseModel):
    visits: List[BrowsingVisit] = Field(..., min_length=1, max_length=200)


@router.post("/log", status_code=status.HTTP_201_CREATED)
async def log_visits(request: BrowsingLogRequest, current_user: dict = Depends(get_current_user)):
    """Child device uploads visited browser URLs (batched)."""
    if current_user.get("role") != "child":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only child accounts upload browsing history")
    try:
        saved = await firebase_service.save_browsing_visits(
            current_user, [v.model_dump(mode="python") for v in request.visits]
        )
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to save history: {e}")
    return {"saved": saved}


@router.get("/history/{child_id}")
async def get_history(
    child_id: str,
    days: int = Query(7, ge=1, le=90),
    current_user: dict = Depends(get_current_user),
):
    """Parent reads a child's browsing history, newest first."""
    if current_user.get("role") != "parent":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only parents can view browsing history")
    if not await firebase_service.is_parent_of_child(current_user["id"], child_id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied - you are not the parent of this child")
    try:
        return await firebase_service.get_browsing_history(child_id, days)
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to load history: {e}")
