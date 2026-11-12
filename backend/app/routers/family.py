from fastapi import APIRouter, HTTPException, status, Depends
from app.middleware.auth import get_current_user
from app.services.firebase_service import get_firebase_service
from pydantic import BaseModel, EmailStr
from typing import List

router = APIRouter()
firebase_service = get_firebase_service()


class SendInvitationRequest(BaseModel):
    """Request to send family invitation to a child."""
    child_email: EmailStr


class InvitationResponse(BaseModel):
    """Family invitation response."""
    id: str
    parent_name: str
    parent_email: str
    child_email: str
    status: str
    created_at: str


class FamilyMemberResponse(BaseModel):
    """Family member response."""
    id: str
    email: str
    full_name: str
    role: str


@router.post("/invite")
async def send_invitation(
    request: SendInvitationRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Send family invitation to a child (Parent only).
    
    - Parent provides child's email
    - Creates pending invitation
    - Child must accept to join family
    """
    if current_user.get("role") != "parent":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only parents can send invitations"
        )
    
    try:
        invitation_id = await firebase_service.create_family_invitation(
            current_user["id"],
            request.child_email
        )
        
        return {
            "message": f"Invitation sent to {request.child_email}",
            "invitation_id": invitation_id
        }
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        print(f"Send invitation error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to send invitation: {str(e)}"
        )


@router.get("/invitations", response_model=List[InvitationResponse])
async def get_invitations(current_user: dict = Depends(get_current_user)):
    """
    Get invitations.
    
    - Child: Get pending invitations received
    - Parent: Get all invitations sent
    """
    try:
        if current_user.get("role") == "child":
            invitations = await firebase_service.get_pending_invitations(current_user["id"])
        else:
            invitations = await firebase_service.get_sent_invitations(current_user["id"])
        
        return [InvitationResponse(**inv) for inv in invitations]
    except Exception as e:
        print(f"Get invitations error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get invitations: {str(e)}"
        )


@router.post("/accept/{invitation_id}")
async def accept_invitation(
    invitation_id: str,
    current_user: dict = Depends(get_current_user)
):
    """
    Accept a family invitation (Child only).
    
    - Child accepts invitation
    - Child is added to parent's family
    - Invitation status updated to 'accepted'
    """
    if current_user.get("role") != "child":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only children can accept invitations"
        )
    
    try:
        await firebase_service.accept_invitation(invitation_id, current_user["id"])
        return {"message": "Invitation accepted! You are now part of the family."}
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        print(f"Accept invitation error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to accept invitation: {str(e)}"
        )


@router.post("/reject/{invitation_id}")
async def reject_invitation(
    invitation_id: str,
    current_user: dict = Depends(get_current_user)
):
    """
    Reject a family invitation (Child only).
    
    - Child rejects invitation
    - Invitation status updated to 'rejected'
    """
    if current_user.get("role") != "child":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only children can reject invitations"
        )
    
    try:
        await firebase_service.reject_invitation(invitation_id, current_user["id"])
        return {"message": "Invitation rejected."}
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        print(f"Reject invitation error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to reject invitation: {str(e)}"
        )


@router.get("/children", response_model=List[FamilyMemberResponse])
async def get_children(current_user: dict = Depends(get_current_user)):
    """
    Get all children linked to the parent (Parent only).
    
    Returns list of children in the parent's family.
    """
    if current_user.get("role") != "parent":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only parents can view children"
        )
    
    try:
        children = await firebase_service.get_children_for_parent(current_user["id"])
        return [FamilyMemberResponse(**child) for child in children]
    except Exception as e:
        print(f"Get children error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get children: {str(e)}"
        )


@router.get("/members", response_model=List[FamilyMemberResponse])
async def get_family_members(current_user: dict = Depends(get_current_user)):
    """
    Get all family members.
    
    Returns list of all users in the current user's family.
    """
    try:
        # Get user's family_id
        user = await firebase_service.get_user_by_id(current_user["id"])
        family_id = user.get("family_id")
        
        if not family_id:
            return []
        
        members = await firebase_service.get_family_members(family_id)
        return [FamilyMemberResponse(**member) for member in members]
    except Exception as e:
        print(f"Get family members error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get family members: {str(e)}"
        )
