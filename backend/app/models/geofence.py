from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class Geofence(BaseModel):
    """Geofence model."""
    name: str
    latitude: float
    longitude: float
    radius_meters: float
    created_by: str
    
class GeofenceCreate(BaseModel):
    """Create geofence request."""
    name: str
    latitude: float
    longitude: float
    radius_meters: float = 100.0
    
class GeofenceResponse(BaseModel):
    """Geofence response."""
    id: str
    name: str
    latitude: float
    longitude: float
    radius_meters: float
    created_by: str
    created_at: str
