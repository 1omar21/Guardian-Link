from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional
from enum import Enum


class TaskStatus(str, Enum):
    """Task status enumeration."""
    PENDING = "pending"
    ACCEPTED = "accepted"
    REJECTED = "rejected"
    SCHEDULED = "scheduled"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    VERIFIED = "verified"
    CANCELLED = "cancelled"
    DELETED = "deleted"


class TaskPriority(str, Enum):
    """Task priority enumeration."""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class TaskBase(BaseModel):
    """Base task model."""
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    priority: Optional[TaskPriority] = TaskPriority.MEDIUM
    reward_coins: int = Field(default=10, ge=0, le=1000)
    due_date: Optional[datetime] = None


class TaskCreate(TaskBase):
    """Task creation model."""
    assigned_to: str  # Child user ID


class TaskUpdate(BaseModel):
    """Task update model (parent). Status is changed only through the task actions."""
    title: Optional[str] = Field(default=None, min_length=1, max_length=200)
    description: Optional[str] = None
    priority: Optional[TaskPriority] = None
    reward_coins: Optional[int] = Field(default=None, ge=0, le=1000)
    due_date: Optional[datetime] = None


class TaskResponse(TaskBase):
    """Task response model."""
    id: str
    assigned_to: str
    created_by: str
    status: TaskStatus
    created_at: datetime
    updated_at: datetime
    completed_at: Optional[datetime] = None
    rejected_by: Optional[str] = None  # 'child' or 'parent'
    verification_feedback: Optional[str] = None
    rejection_feedback: Optional[str] = None
    
    class Config:
        from_attributes = True


class TaskCompletionRequest(BaseModel):
    """Task completion request from child."""
    task_id: str
    completion_note: Optional[str] = None


class TaskVerificationRequest(BaseModel):
    """Task verification request from parent."""
    task_id: str
    approved: bool
    feedback: Optional[str] = None


class TaskScheduleRequest(BaseModel):
    """Child schedules a task for later. Send ISO-8601 (UTC recommended)."""
    scheduled_for: datetime
