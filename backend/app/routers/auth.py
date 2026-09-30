from fastapi import APIRouter, HTTPException, status, Depends
from app.models.user import UserCreate, UserLogin, UserResponse, Token
from app.services.firebase_service import FirebaseService
from app.middleware.auth import create_access_token, get_password_hash, verify_password, get_current_user
from datetime import timedelta
from app.config import get_settings

router = APIRouter()
settings = get_settings()
firebase_service = FirebaseService()


@router.post("/register", response_model=Token, status_code=status.HTTP_201_CREATED)
async def register(user_data: UserCreate):
    """
    Register a new user (Parent or Child).
    
    - Creates user in Firebase Authentication
    - Stores user profile in Firestore
    - Returns JWT token for immediate login
    """
    try:
        # Check if user already exists
        existing_user = await firebase_service.get_user_by_email(user_data.email)
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User with this email already exists"
            )
        
        # Hash password
        hashed_password = get_password_hash(user_data.password)
        
        # Create user in Firebase
        user_id = await firebase_service.create_user(
            email=user_data.email,
            password=hashed_password,
            full_name=user_data.full_name,
            role=user_data.role,
            family_id=user_data.family_id
        )
        
        # Get created user
        user = await firebase_service.get_user_by_id(user_id)
        
        # Create access token
        access_token = create_access_token(
            data={"user_id": user_id, "role": user_data.role.value, "email": user_data.email}
        )
        
        return Token(
            access_token=access_token,
            user=UserResponse(**user)
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Registration failed: {str(e)}"
        )


@router.post("/login", response_model=Token)
async def login(credentials: UserLogin):
    """
    Login user and return JWT token.
    
    - Validates credentials against Firebase
    - Returns JWT token with user information
    """
    try:
        # Get user by email
        user = await firebase_service.get_user_by_email(credentials.email)
        
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid email or password"
            )
        
        # Verify password
        if not verify_password(credentials.password, user.get("password_hash")):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid email or password"
            )
        
        # Create access token
        access_token = create_access_token(
            data={
                "user_id": user["id"],
                "role": user["role"],
                "email": user["email"],
                "family_id": user.get("family_id")  # Include family_id for authorization
            }
        )
        
        return Token(
            access_token=access_token,
            user=UserResponse(**user)
        )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Login failed: {str(e)}"
        )


@router.get("/me", response_model=UserResponse)
async def get_current_user_info(current_user: dict = Depends(get_current_user)):
    """
    Get current authenticated user information.
    
    Requires: Valid JWT token in Authorization header
    """
    try:
        # Get full user data from Firebase using user_id from token
        user_data = await firebase_service.get_user_by_id(current_user["id"])
        if not user_data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
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
    fcm_token: str,
    current_user: dict = Depends(get_current_user)
):
    """
    Save FCM token for push notifications.
    
    Requires: Valid JWT token in Authorization header
    """
    try:
        await firebase_service.save_fcm_token(current_user["id"], fcm_token)
        return {"message": "FCM token saved successfully"}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to save FCM token: {str(e)}"
        )
