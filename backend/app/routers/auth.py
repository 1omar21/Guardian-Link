from fastapi import APIRouter, HTTPException, status, Depends
from app.models.user import UserCreate, UserLogin, UserResponse, Token, FCMTokenRequest
from app.services.firebase_service import get_firebase_service
from app.middleware.auth import create_access_token, get_password_hash, verify_password, get_current_user

router = APIRouter()
firebase_service = get_firebase_service()


@router.post("/register", response_model=Token, status_code=status.HTTP_201_CREATED)
async def register(user_data: UserCreate):
    """
    Register a new user (Parent or Child).

    - Stores user profile in Firestore
    - Returns JWT token for immediate login
    - Users never pick their own family: parents get one automatically on their
      first invitation, children join only by accepting an invitation.
    """
    try:
        existing_user = await firebase_service.get_user_by_email(user_data.email)
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User with this email already exists"
            )

        hashed_password = get_password_hash(user_data.password)

        user_id = await firebase_service.create_user(
            email=user_data.email,
            password=hashed_password,
            full_name=user_data.full_name,
            role=user_data.role.value,
            family_id=None,
        )

        user = await firebase_service.get_user_by_id(user_id)
        access_token = create_access_token(data={"user_id": user_id})

        return Token(access_token=access_token, user=UserResponse(**user))

    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Registration failed: {str(e)}"
        )


@router.post("/login", response_model=Token)
async def login(credentials: UserLogin):
    """Login user and return JWT token."""
    try:
        user = await firebase_service.get_user_by_email(credentials.email)

        if not user or not verify_password(credentials.password, user.get("password_hash")):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid email or password"
            )

        access_token = create_access_token(data={"user_id": user["id"]})

        return Token(access_token=access_token, user=UserResponse(**user))

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Login failed: {str(e)}"
        )


@router.get("/me", response_model=UserResponse)
async def get_current_user_info(current_user: dict = Depends(get_current_user)):
    """Get current authenticated user information."""
    try:
        user_data = await firebase_service.get_user_by_id(current_user["id"])
        if not user_data:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
        return UserResponse(**user_data)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get user info: {str(e)}"
        )


@router.post("/fcm-token")
async def save_fcm_token(
    request: FCMTokenRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Save FCM token for push notifications.

    Body: {"fcm_token": "<token>"}
    """
    try:
        await firebase_service.save_fcm_token(current_user["id"], request.fcm_token)
        return {"message": "FCM token saved successfully"}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to save FCM token: {str(e)}"
        )


@router.post("/fcm-token/remove")
async def remove_fcm_token(
    request: FCMTokenRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Unregister this device's FCM token (call on logout), so the device stops
    receiving this user's notifications.

    Body: {"fcm_token": "<token>"}
    """
    try:
        await firebase_service.remove_fcm_token(current_user["id"], request.fcm_token)
        return {"message": "FCM token removed"}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to remove FCM token: {str(e)}"
        )
