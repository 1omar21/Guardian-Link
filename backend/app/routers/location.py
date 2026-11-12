from typing import List

from fastapi import APIRouter, HTTPException, status, Depends, Query

from app.models.location import LocationUpdate, LocationResponse, CheckInRequest, GeofenceCreate, GeofenceResponse
from app.services.firebase_service import get_firebase_service
from app.middleware.auth import get_current_user

router = APIRouter()
firebase_service = get_firebase_service()


async def _require_parent_of(current_user: dict, child_id: str) -> None:
    """403 unless the current user is the parent who owns this child's family."""
    if current_user.get("role") != "parent":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only parents can view this")
    if not await firebase_service.is_parent_of_child(current_user["id"], child_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied - you are not the parent of this child"
        )


@router.post("/update", status_code=status.HTTP_201_CREATED)
async def update_location(
    location: LocationUpdate,
    current_user: dict = Depends(get_current_user)
):
    """
    Update the current user's location.

    For a child, the new position is also checked against the family's safe
    zones; entering or leaving a zone notifies the parent.
    """
    try:
        location_id = await firebase_service.save_location(
            user_id=current_user["id"],
            latitude=location.latitude,
            longitude=location.longitude,
            accuracy=location.accuracy,
            timestamp=location.timestamp,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update location: {str(e)}"
        )

    # Zone alerts are best-effort: they must never fail the location update.
    events = []
    try:
        events = await firebase_service.process_geofence_transitions(
            current_user, location.latitude, location.longitude, location.accuracy
        )
        child_name = current_user.get("full_name") or "Your child"
        for event in events:
            verb = "arrived at" if event["event"] == "enter" else "left"
            await firebase_service.notify_parent_of(
                current_user,
                title=f"{child_name} {verb} {event['geofence_name']}",
                body=f"Safe zone {('entered' if event['event'] == 'enter' else 'exited')}",
                data={
                    "type": "geofence",
                    "event": event["event"],
                    "child_id": current_user["id"],
                    "child_name": child_name,
                    "geofence_id": event["geofence_id"],
                    "geofence_name": event["geofence_name"],
                    "latitude": location.latitude,
                    "longitude": location.longitude,
                },
            )
    except Exception as e:
        print(f"Geofence processing failed: {e}")

    return {
        "message": "Location updated successfully",
        "location_id": location_id,
        "geofence_events": [{"geofence_name": e["geofence_name"], "event": e["event"]} for e in events],
    }


@router.get("/current/{child_id}", response_model=LocationResponse)
async def get_current_location(
    child_id: str,
    current_user: dict = Depends(get_current_user)
):
    """Get child's most recent location (parent only)."""
    await _require_parent_of(current_user, child_id)
    try:
        location = await firebase_service.get_latest_location(child_id)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get location: {str(e)}"
        )
    if not location:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No location data found")
    return location


@router.get("/history/{child_id}", response_model=List[LocationResponse])
async def get_location_history(
    child_id: str,
    days: int = Query(7, ge=1, le=90),
    current_user: dict = Depends(get_current_user)
):
    """Get child's location history (parent only)."""
    await _require_parent_of(current_user, child_id)
    try:
        return await firebase_service.get_location_history(child_id, days)
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
    """Child safety check-in. Notifies the family's parent if they have push enabled."""
    message = (check_in_data.message or "I'm safe!").strip() or "I'm safe!"
    try:
        check_in_id = await firebase_service.save_check_in(
            user_id=current_user["id"],
            message=message,
            latitude=check_in_data.latitude,
            longitude=check_in_data.longitude
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to check in: {str(e)}"
        )

    # Notification is best-effort: a push failure must not fail the check-in.
    child_name = current_user.get("full_name") or "Your child"
    notified = await firebase_service.notify_parent_of(
        current_user,
        title=f"{child_name} checked in",
        body=message,
        data={
            "type": "check_in",
            "child_id": current_user["id"],
            "child_name": child_name,
            "latitude": check_in_data.latitude,
            "longitude": check_in_data.longitude,
            "check_in_id": check_in_id,
        },
    )

    return {"message": "Check-in successful", "check_in_id": check_in_id, "parent_notified": notified}


@router.get("/check-ins/{child_id}")
async def get_check_ins(
    child_id: str,
    days: int = Query(7, ge=1, le=90),
    current_user: dict = Depends(get_current_user)
):
    """Get child's check-in history (parent only)."""
    await _require_parent_of(current_user, child_id)
    try:
        return await firebase_service.get_check_ins(child_id, days)
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
    """Create a safe zone geofence for the parent's family (parent only)."""
    if current_user.get("role") != "parent":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only parents can create geofences")
    try:
        family_id = await firebase_service.get_or_create_family_for_parent(current_user["id"])
        geofence_id = await firebase_service.create_geofence(
            family_id=family_id,
            name=geofence.name,
            latitude=geofence.latitude,
            longitude=geofence.longitude,
            radius=geofence.radius,
            created_by=current_user["id"],
        )
        return await firebase_service.get_geofence(geofence_id)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create geofence: {str(e)}"
        )


@router.get("/geofences", response_model=List[GeofenceResponse])
async def get_geofences(current_user: dict = Depends(get_current_user)):
    """Get all geofences for the current user's family (parent or child)."""
    if not current_user.get("family_id"):
        return []
    try:
        return await firebase_service.get_family_geofences(current_user["family_id"])
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
    """Delete a geofence (parent only, own family's geofences)."""
    if current_user.get("role") != "parent":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only parents can delete geofences")

    geofence = await firebase_service.get_geofence(geofence_id)
    if not geofence:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Geofence not found")
    if not current_user.get("family_id") or geofence.get("family_id") != current_user["family_id"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="This geofence is not in your family")

    try:
        await firebase_service.delete_geofence(geofence_id)
        return {"message": "Geofence deleted successfully"}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete geofence: {str(e)}"
        )
