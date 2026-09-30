from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional


class LocationUpdate(BaseModel):
    """Location update model."""
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy: Optional[float] = None
    timestamp: Optional[datetime] = None


class LocationResponse(BaseModel):
    """Location response model."""
    id: str
    user_id: str
    latitude: float
    longitude: float
    accuracy: Optional[float]
    timestamp: datetime
    
    class Config:
        from_attributes = True


class CheckInRequest(BaseModel):
    """Check-in request model."""
    message: Optional[str] = "I'm safe!"
    latitude: float
    longitude: float


class GeofenceCreate(BaseModel):
    """Geofence creation model."""
    name: str
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    radius: int = Field(gt=0, description="Radius in meters")


class GeofenceResponse(BaseModel):
    """Geofence response model."""
    id: str
    family_id: str
    name: str
    latitude: float
    longitude: float
    radius: int
    created_at: datetime
    
    class Config:
        from_attributes = True
