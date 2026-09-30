from fastapi import APIRouter, HTTPException, Depends
from app.services.firebase_service import FirebaseService
from app.middleware.auth import get_current_user
from app.models.geofence import GeofenceCreate, GeofenceResponse
from datetime import datetime
import math

router = APIRouter()
firebase_service = FirebaseService()

def calculate_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two points in meters using Haversine formula."""
    R = 6371000  # Earth's radius in meters
    
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    
    a = math.sin(delta_phi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c

@router.post("/create")
async def create_geofence(
    data: GeofenceCreate,
    current_user: dict = Depends(get_current_user)
):
    """Create a geofence zone."""
    try:
        if current_user["role"] != "parent":
            raise HTTPException(status_code=403, detail="Only parents can create geofences")
        
        geofence_data = {
            "name": data.name,
            "latitude": data.latitude,
            "longitude": data.longitude,
            "radius_meters": data.radius_meters,
            "created_by": current_user["id"],
            "created_at": datetime.utcnow()
        }
        
        doc_ref = firebase_service.db.collection('geofences').document()
        doc_ref.set(geofence_data)
        
        return {
            "id": doc_ref.id,
            **geofence_data,
            "created_at": geofence_data["created_at"].isoformat()
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/list")
async def list_geofences(current_user: dict = Depends(get_current_user)):
    """List all geofences for current user."""
    try:
        user_id = current_user["id"]
        
        geofences = []
        docs = firebase_service.db.collection('geofences')\
            .where('created_by', '==', user_id)\
            .stream()
        
        for doc in docs:
            data = doc.to_dict()
            geofences.append({
                "id": doc.id,
                **data,
                "created_at": data.get("created_at", datetime.utcnow()).isoformat()
            })
        
        return {"geofences": geofences}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/check")
async def check_geofence(
    latitude: float,
    longitude: float,
    current_user: dict = Depends(get_current_user)
):
    """Check if location is within any geofence."""
    try:
        # Get user's parent geofences
        user_id = current_user["id"]
        user_ref = firebase_service.db.collection('users').document(user_id)
        user_doc = user_ref.get()
        
        if not user_doc.exists:
            return {"inside_geofence": False}
        
        user_data = user_doc.to_dict()
        parent_id = user_data.get('parent_id', user_id)
        
        # Get all geofences
        geofences = []
        docs = firebase_service.db.collection('geofences')\
            .where('created_by', '==', parent_id)\
            .stream()
        
        for doc in docs:
            data = doc.to_dict()
            distance = calculate_distance(
                latitude, longitude,
                data['latitude'], data['longitude']
            )
            
            if distance <= data['radius_meters']:
                geofences.append({
                    "id": doc.id,
                    "name": data['name'],
                    "distance_meters": round(distance, 2)
                })
        
        return {
            "inside_geofence": len(geofences) > 0,
            "geofences": geofences
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/{geofence_id}")
async def delete_geofence(
    geofence_id: str,
    current_user: dict = Depends(get_current_user)
):
    """Delete a geofence."""
    try:
        firebase_service.db.collection('geofences').document(geofence_id).delete()
        return {"message": "Geofence deleted successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
