"""
Safety alerts: SOS from a child, and the parent's alert feed
(SOS alerts + safe-zone enter/exit events).
"""
from typing import Optional

from fastapi import APIRouter, HTTPException, status, Depends, Query
from pydantic import BaseModel, Field

from app.services.firebase_service import get_firebase_service
from app.middleware.auth import get_current_user

router = APIRouter()
firebase_service = get_firebase_service()


class SOSRequest(BaseModel):
    """SOS from a child. Location is optional: if GPS fails the last known position is used."""
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    accuracy: Optional[float] = None
    message: Optional[str] = Field(default=None, max_length=500)


@router.post("/sos", status_code=status.HTTP_201_CREATED)
async def trigger_sos(request: SOSRequest, current_user: dict = Depends(get_current_user)):
    """Child triggers an emergency SOS. The parent gets a high-priority push."""
    if current_user.get("role") != "child":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only children can send SOS alerts")
    if not current_user.get("family_id"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You are not linked to a parent yet. Accept a family invitation first."
        )

    latitude, longitude, accuracy = request.latitude, request.longitude, request.accuracy
    has_fix = latitude is not None and longitude is not None
    if has_fix:
        try:
            await firebase_service.save_location(current_user["id"], latitude, longitude, accuracy)
        except Exception as e:
            print(f"SOS: saving location failed: {e}")
    else:
        last = await firebase_service.get_latest_location(current_user["id"])
        if last:
            latitude, longitude, accuracy = last.get("latitude"), last.get("longitude"), last.get("accuracy")

    message = (request.message or "").strip() or "I need help!"
    try:
        alert = await firebase_service.create_sos_alert(current_user, latitude, longitude, accuracy, message)
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to send SOS: {e}")

    child_name = current_user.get("full_name") or "Your child"
    where = f" ({latitude:.5f}, {longitude:.5f})" if latitude is not None and longitude is not None else ""
    notified = await firebase_service.notify_parent_of(
        current_user,
        title=f"🚨 SOS from {child_name}",
        body=f"{message}{where}",
        data={
            "type": "sos",
            "alert_id": alert["id"],
            "child_id": current_user["id"],
            "child_name": child_name,
            "latitude": latitude if latitude is not None else "",
            "longitude": longitude if longitude is not None else "",
            "message": message,
        },
        urgent=True,
    )

    return {
        "message": "SOS sent",
        "alert_id": alert["id"],
        "parent_notified": notified,
        "location_included": latitude is not None,
        "location_is_live": has_fix,
    }


@router.get("/")
async def get_alerts(
    days: int = Query(7, ge=1, le=90),
    current_user: dict = Depends(get_current_user),
):
    """
    Parent's alert feed: SOS alerts (active ones always included) and safe-zone
    enter/exit events for all children in the family, newest first.
    """
    if current_user.get("role") != "parent":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only parents can view alerts")
    family_id = current_user.get("family_id")
    if not family_id:
        return {"sos": [], "geofence_events": [], "active_sos_count": 0}
    try:
        sos = await firebase_service.get_sos_alerts(family_id, days)
        events = await firebase_service.get_geofence_events(family_id, days)
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to load alerts: {e}")
    return {
        "sos": sos,
        "geofence_events": events,
        "active_sos_count": sum(1 for a in sos if a.get("status") == "active"),
    }


@router.post("/sos/{alert_id}/resolve")
async def resolve_sos(alert_id: str, current_user: dict = Depends(get_current_user)):
    """Parent marks an SOS alert as handled."""
    if current_user.get("role") != "parent":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only parents can resolve alerts")
    alert = await firebase_service.get_sos_alert(alert_id)
    if not alert:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert not found")
    if not current_user.get("family_id") or alert.get("family_id") != current_user["family_id"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="This alert is not in your family")
    await firebase_service.resolve_sos_alert(alert_id, current_user["id"])

    await firebase_service.notify_user(
        alert["child_id"],
        title="Your parent has seen your SOS",
        body="Help is on the way.",
        data={"type": "sos_resolved", "alert_id": alert_id},
    )
    return {"message": "Alert resolved"}
