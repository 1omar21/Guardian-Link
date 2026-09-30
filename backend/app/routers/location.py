from fastapi import APIRouter, HTTPException, status, Depends
from app.models.location import LocationUpdate, LocationResponse, CheckInRequest, GeofenceCreate, GeofenceResponse
from app.services.firebase_service import FirebaseService
from app.middleware.auth import get_current_user
from typing import List

router = APIRouter()
firebase_service = FirebaseService()


@router.post("/update", status_code=status.HTTP_201_CREATED)
async def update_location(
    location: LocationUpdate,
    current_user: dict = Depends(get_current_user)
):
    """Update user's current location."""
    try:
        from datetime import datetime
        
        location_id = await firebase_service.save_location(
            user_id=current_user["id"],
            latitude=location.latitude,
            longitude=location.longitude,
            accuracy=location.accuracy,
            timestamp=location.timestamp or datetime.utcnow()
        )
        
        return {
            "message": "Location updated successfully",
            "location_id": location_id
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update location: {str(e)}"
        )


@router.get("/current/{child_id}", response_model=LocationResponse)
async def get_current_location(
    child_id: str,
    current_user: dict = Depends(get_current_user)
):
    """Get child's most recent location (parent only)."""
    try:
        # Debug logging
        print(f"🔍 Location request - Parent: {current_user.get('id')}, Child: {child_id}")
        
        # Get child user
        child_user = await firebase_service.get_user_by_id(child_id)
        if not child_user:
            print(f"❌ Child not found: {child_id}")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Child not found"
            )
        
        # Get child's family_id
        child_family_id = child_user.get('family_id')
        print(f"🔍 Child family_id: {child_family_id}")
        
        if not child_family_id:
            print(f"❌ Child has no family")
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Child is not in a family"
            )
        
        # Check if current user is the parent of this family
        family = await firebase_service.get_family_by_id(child_family_id)
        if not family:
            print(f"❌ Family not found: {child_family_id}")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Family not found"
            )
        
        parent_id = family.get('parent_id')
        print(f"🔍 Family parent_id: {parent_id}, Current user: {current_user.get('id')}")
        
        if parent_id != current_user.get('id'):
            print(f"❌ Access denied - not the parent of this family")
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access denied - you are not the parent of this child"
            )
        
        print(f"✅ Access granted - parent verified via families collection")
        
        location = await firebase_service.get_latest_location(child_id)
        
        if not location:
            print(f"⚠️ No location data for child: {child_id}")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No location data found"
            )
        
        print(f"✅ Returning location: {location}")
        return location
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Location error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get location: {str(e)}"
        )


@router.get("/history/{child_id}", response_model=List[LocationResponse])
async def get_location_history(
    child_id: str,
    days: int = 7,
    current_user: dict = Depends(get_current_user)
):
    """Get child's location history (parent only)."""
    try:
        # Verify parent has access
        user = await firebase_service.get_user_by_id(child_id)
        if not user or user.get('family_id') != current_user.get('family_id'):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access denied"
            )
        
        history = await firebase_service.get_location_history(child_id, days)
        return history
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get location history: {str(e)}"
        )


@router.post("/check-in", status_code=status.HTTP_201_CREATED)
async def check_in(
    check_in_data: CheckInRequest,
    current_user: dict = Depends(get_current_user)
):
    """Child safety check-in."""
    try:
        # Save check-in
        check_in_id = await firebase_service.save_check_in(
            user_id=current_user["id"],
            message=check_in_data.message,
            latitude=check_in_data.latitude,
            longitude=check_in_data.longitude
        )
        
        # Send notification to parent via FCM
        if current_user.get("family_id"):
            parent = await firebase_service.get_parent_by_family_id(current_user["family_id"])
            if parent and parent.get("fcm_token"):
                child_name = current_user.get("full_name", "Your child")
                await firebase_service.send_notification(
                    token=parent["fcm_token"],
                    title=f"{child_name} checked in",
                    body=check_in_data.message,
                    data={
                        "type": "check_in",
                        "child_id": current_user["id"],
                        "child_name": child_name,
                        "latitude": str(check_in_data.latitude),
                        "longitude": str(check_in_data.longitude),
                        "check_in_id": check_in_id
                    }
                )
        
        return {
            "message": "Check-in successful",
            "check_in_id": check_in_id
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to check in: {str(e)}"
        )


@router.get("/check-ins/{child_id}")
async def get_check_ins(
    child_id: str,
    days: int = 7,
    current_user: dict = Depends(get_current_user)
):
    """Get child's check-in history (parent only)."""
    try:
        # Get child user
        child_user = await firebase_service.get_user_by_id(child_id)
        if not child_user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Child not found"
            )
        
        # Get child's family_id and verify parent access via families collection
        child_family_id = child_user.get('family_id')
        if not child_family_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Child is not in a family"
            )
        
        family = await firebase_service.get_family_by_id(child_family_id)
        if not family or family.get('parent_id') != current_user.get('id'):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access denied"
            )
        
        check_ins = await firebase_service.get_check_ins(child_id, days)
        return check_ins
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get check-ins: {str(e)}"
        )


@router.post("/geofence", response_model=GeofenceResponse, status_code=status.HTTP_201_CREATED)
async def create_geofence(
    geofence: GeofenceCreate,
    current_user: dict = Depends(get_current_user)
):
    """Create a safe zone geofence (parent only)."""
    try:
        if current_user.get("role") != "parent":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only parents can create geofences"
            )
        
        geofence_id = await firebase_service.create_geofence(
            family_id=current_user["family_id"],
            name=geofence.name,
            latitude=geofence.latitude,
            longitude=geofence.longitude,
            radius=geofence.radius
        )
        
        # Get created geofence
        created_geofence = await firebase_service.get_geofence(geofence_id)
        return created_geofence
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create geofence: {str(e)}"
        )


@router.get("/geofences", response_model=List[GeofenceResponse])
async def get_geofences(
    current_user: dict = Depends(get_current_user)
):
    """Get all geofences for family."""
    try:
        if not current_user.get("family_id"):
            return []
        
        geofences = await firebase_service.get_family_geofences(current_user["family_id"])
        return geofences
        
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get geofences: {str(e)}"
        )


@router.delete("/geofence/{geofence_id}")
async def delete_geofence(
    geofence_id: str,
    current_user: dict = Depends(get_current_user)
):
    """Delete a geofence (parent only)."""
    try:
        if current_user.get("role") != "parent":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only parents can delete geofences"
            )
        
        await firebase_service.delete_geofence(geofence_id)
        return {"message": "Geofence deleted successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete geofence: {str(e)}"
        )
