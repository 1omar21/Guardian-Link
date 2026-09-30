import firebase_admin
from firebase_admin import credentials, firestore, auth, messaging
from app.config import get_settings
from datetime import datetime
from typing import Optional, List, Dict
import os

settings = get_settings()


def serialize_datetime(data: Dict) -> Dict:
    """Convert datetime objects to ISO format strings for JSON serialization."""
    if not data:
        return data
    
    serialized = {}
    for key, value in data.items():
        if isinstance(value, datetime):
            serialized[key] = value.isoformat()
        elif isinstance(value, dict):
            serialized[key] = serialize_datetime(value)
        elif isinstance(value, list):
            serialized[key] = [serialize_datetime(item) if isinstance(item, dict) else item for item in value]
        else:
            serialized[key] = value
    return serialized


class FirebaseService:
    """Service for Firebase operations."""
    
    def __init__(self):
        """Initialize Firebase Admin SDK."""
        if not firebase_admin._apps:
            # Initialize Firebase
            cred_path = settings.firebase_credentials_path
            if os.path.exists(cred_path):
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred, {
                    'databaseURL': settings.firebase_database_url
                })
            else:
                # For development, you might want to use default credentials
                firebase_admin.initialize_app()
        
        self.db = firestore.client()
    
    # User Management
    async def create_user(self, email: str, password: str, full_name: str, role: str, family_id: Optional[str] = None) -> str:
        """Create a new user in Firestore."""
        user_ref = self.db.collection('users').document()
        user_data = {
            'id': user_ref.id,
            'email': email,
            'password_hash': password,  # Already hashed - FIXED: was 'password', should be 'password_hash'
            'full_name': full_name,
            'role': role,
            'family_id': family_id,
            'focus_coins': 0,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        }
        user_ref.set(user_data)
        return user_ref.id
    
    async def get_user_by_email(self, email: str) -> Optional[Dict]:
        """Get user by email."""
        users = self.db.collection('users').where('email', '==', email).limit(1).stream()
        for user in users:
            return user.to_dict()
        return None
    
    async def get_user_by_id(self, user_id: str) -> Optional[Dict]:
        """Get user by ID."""
        user_ref = self.db.collection('users').document(user_id)
        user = user_ref.get()
        if user.exists:
            return user.to_dict()
        return None
    
    async def get_family_by_id(self, family_id: str) -> Optional[Dict]:
        """Get family by ID."""
        family_ref = self.db.collection('families').document(family_id)
        family = family_ref.get()
        if family.exists:
            return family.to_dict()
        return None
    
    async def get_current_user(self, token: str) -> Dict:
        """Get current user from JWT token (dependency injection)."""
        # This will be implemented with JWT middleware
        pass
    
    # Task Management
    async def create_task(self, task_data: Dict, created_by: str) -> str:
        """Create a new task."""
        task_ref = self.db.collection('tasks').document()
        task_data.update({
            'id': task_ref.id,
            'created_by': created_by,
            'status': 'pending',
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        })
        task_ref.set(task_data)
        return task_ref.id
    
    async def get_task(self, task_id: str) -> Optional[Dict]:
        """Get task by ID."""
        task_ref = self.db.collection('tasks').document(task_id)
        task = task_ref.get()
        if task.exists:
            return task.to_dict()
        return None
    
    async def get_user_tasks(self, user_id: str, status_filter: Optional[str] = None) -> List[Dict]:
        """Get tasks for a user."""
        query = self.db.collection('tasks').where('assigned_to', '==', user_id)
        if status_filter:
            query = query.where('status', '==', status_filter)
        # Don't use order_by with where to avoid index requirement
        tasks = query.stream()
        task_list = [serialize_datetime(task.to_dict()) for task in tasks]
        # Sort in Python instead
        task_list.sort(key=lambda x: x.get('created_at', ''), reverse=True)
        return task_list
    
    async def get_family_tasks(self, family_id: str, status_filter: Optional[str] = None) -> List[Dict]:
        """Get all tasks for a family."""
        # First get all family members
        users = self.db.collection('users').where('family_id', '==', family_id).stream()
        user_ids = [user.to_dict()['id'] for user in users]
        
        # Get tasks for all family members
        all_tasks = []
        for user_id in user_ids:
            tasks = await self.get_user_tasks(user_id, status_filter)
            all_tasks.extend(tasks)
        
        return all_tasks
    
    async def get_tasks_by_creator(self, creator_id: str, status_filter: Optional[str] = None) -> List[Dict]:
        """Get tasks created by a specific user (for parents)."""
        query = self.db.collection('tasks').where('created_by', '==', creator_id)
        if status_filter:
            query = query.where('status', '==', status_filter)
        # Don't use order_by with where to avoid index requirement
        tasks = query.stream()
        task_list = [serialize_datetime(task.to_dict()) for task in tasks]
        # Sort in Python instead
        task_list.sort(key=lambda x: x.get('created_at', ''), reverse=True)
        return task_list
    
    async def update_user_coins(self, user_id: str, coins_to_add: int) -> int:
        """Add coins to user's focus_coins and return new total."""
        user_ref = self.db.collection('users').document(user_id)
        user = user_ref.get()
        
        if not user.exists:
            raise ValueError("User not found")
        
        user_data = user.to_dict()
        current_coins = user_data.get('focus_coins', 0)
        new_total = current_coins + coins_to_add
        
        user_ref.update({
            'focus_coins': new_total,
            'updated_at': datetime.utcnow()
        })
        
        return new_total
    
    async def add_user_sticker(self, user_id: str, sticker: str) -> bool:
        """Add a sticker to user's collection."""
        user_ref = self.db.collection('users').document(user_id)
        user = user_ref.get()
        
        if not user.exists:
            raise ValueError("User not found")
        
        user_data = user.to_dict()
        stickers = user_data.get('stickers', [])
        stickers.append(sticker)
        
        user_ref.update({
            'stickers': stickers,
            'updated_at': datetime.utcnow()
        })
        
        return True
    
    async def accept_task(self, task_id: str) -> None:
        """Child accepts a task."""
        task_ref = self.db.collection('tasks').document(task_id)
        task_ref.update({
            'status': 'accepted',
            'child_response_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        })
    
    async def reject_task(self, task_id: str) -> None:
        """Child rejects a task (final decision)."""
        task_ref = self.db.collection('tasks').document(task_id)
        task_ref.update({
            'status': 'rejected',
            'child_response_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        })
    
    async def schedule_task(self, task_id: str, scheduled_time: datetime) -> None:
        """Child schedules a task for later."""
        task_ref = self.db.collection('tasks').document(task_id)
        task_ref.update({
            'status': 'scheduled',
            'scheduled_for': scheduled_time,
            'child_response_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        })
    
    async def update_task(self, task_id: str, update_data: Dict) -> None:
        """Update a task."""
        task_ref = self.db.collection('tasks').document(task_id)
        update_data['updated_at'] = datetime.utcnow()
        task_ref.update(update_data)
    
    async def complete_task(self, task_id: str) -> None:
        """Mark task as completed by child."""
        task_ref = self.db.collection('tasks').document(task_id)
        task_ref.update({
            'status': 'completed',
            'completed_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        })
    
    async def delete_task(self, task_id: str, deleted_by: str) -> None:
        """Soft delete a task by marking it as deleted."""
        task_ref = self.db.collection('tasks').document(task_id)
        task_ref.update({
            'status': 'deleted',
            'deleted_by': deleted_by,
            'deleted_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        })

    
    async def verify_task(self, task_id: str, approved: bool, feedback: Optional[str] = None) -> None:
        """Verify task completion by parent."""
        task = await self.get_task(task_id)
        
        if approved:
            # Award Focus Coins
            user_id = task['assigned_to']
            user_ref = self.db.collection('users').document(user_id)
            user = user_ref.get().to_dict()
            new_coins = user.get('focus_coins', 0) + task['reward_coins']
            user_ref.update({'focus_coins': new_coins})
            
            update_data = {
                'status': 'verified',
                'verified_at': datetime.utcnow(),
                'verification_feedback': feedback
            }
        else:
            update_data = {
                'status': 'rejected',
                'rejected_at': datetime.utcnow(),
                'rejection_feedback': feedback
            }
        
        await self.update_task(task_id, update_data)
    
    # Family Management
    async def create_family(self, parent_id: str) -> str:
        """Create a new family with parent as owner."""
        family_ref = self.db.collection('families').document()
        family_data = {
            'id': family_ref.id,
            'parent_id': parent_id,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        }
        family_ref.set(family_data)
        
        # Update parent's family_id
        user_ref = self.db.collection('users').document(parent_id)
        user_ref.update({'family_id': family_ref.id})
        
        return family_ref.id
    
    async def add_child_to_family(self, family_id: str, child_id: str) -> None:
        """Add a child to a family."""
        # Update child's family_id
        user_ref = self.db.collection('users').document(child_id)
        user_ref.update({'family_id': family_id})
        
        # Update family's updated_at
        family_ref = self.db.collection('families').document(family_id)
        family_ref.update({'updated_at': datetime.utcnow()})
    
    async def get_family_members(self, family_id: str) -> List[Dict]:
        """Get all members of a family."""
        users = self.db.collection('users').where('family_id', '==', family_id).stream()
        return [serialize_datetime(user.to_dict()) for user in users]
    
    async def get_children_for_parent(self, parent_id: str) -> List[Dict]:
        """Get all children linked to a parent."""
        # First get parent's family_id
        parent = await self.get_user_by_id(parent_id)
        if not parent or not parent.get('family_id'):
            return []
        
        # Get all children in the family
        users = self.db.collection('users') \
            .where('family_id', '==', parent['family_id']) \
            .where('role', '==', 'child') \
            .stream()
        return [serialize_datetime(user.to_dict()) for user in users]
    
    # Family Management - Secure Invitation System
    async def create_family_invitation(self, parent_id: str, child_email: str) -> str:
        """Create a family invitation that requires child acceptance."""
        # Get parent's family (create if doesn't exist)
        parent = await self.get_user_by_id(parent_id)
        family_id = parent.get('family_id')
        
        if not family_id:
            family_id = await self.create_family(parent_id)
        
        # Find child by email
        child = await self.get_user_by_email(child_email)
        if not child or child.get('role') != 'child':
            raise ValueError("Child not found or invalid email")
        
        # Check if already in family
        if child.get('family_id') == family_id:
            raise ValueError("Child is already in your family")
        
        # Check if invitation already exists
        existing = self.db.collection('family_invitations') \
            .where('family_id', '==', family_id) \
            .where('child_id', '==', child['id']) \
            .where('status', '==', 'pending') \
            .stream()
        
        for inv in existing:
            raise ValueError("Invitation already sent to this child")
        
        # Create invitation
        invitation_ref = self.db.collection('family_invitations').document()
        invitation_data = {
            'id': invitation_ref.id,
            'family_id': family_id,
            'parent_id': parent_id,
            'parent_name': parent.get('full_name'),
            'parent_email': parent.get('email'),
            'child_id': child['id'],
            'child_email': child_email,
            'status': 'pending',  # pending, accepted, rejected
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        }
        invitation_ref.set(invitation_data)
        
        return invitation_ref.id
    
    async def get_pending_invitations(self, child_id: str) -> List[Dict]:
        """Get all pending invitations for a child."""
        invitations = self.db.collection('family_invitations') \
            .where('child_id', '==', child_id) \
            .where('status', '==', 'pending') \
            .stream()
        return [serialize_datetime(inv.to_dict()) for inv in invitations]
    
    async def accept_invitation(self, invitation_id: str, child_id: str) -> None:
        """Child accepts a family invitation."""
        # Get invitation
        invitation_ref = self.db.collection('family_invitations').document(invitation_id)
        invitation = invitation_ref.get()
        
        if not invitation.exists:
            raise ValueError("Invitation not found")
        
        inv_data = invitation.to_dict()
        
        # Verify invitation is for this child
        if inv_data['child_id'] != child_id:
            raise ValueError("This invitation is not for you")
        
        if inv_data['status'] != 'pending':
            raise ValueError("Invitation is no longer pending")
        
        # Add child to family
        await self.add_child_to_family(inv_data['family_id'], child_id)
        
        # Update invitation status
        invitation_ref.update({
            'status': 'accepted',
            'updated_at': datetime.utcnow()
        })
    
    async def reject_invitation(self, invitation_id: str, child_id: str) -> None:
        """Child rejects a family invitation."""
        # Get invitation
        invitation_ref = self.db.collection('family_invitations').document(invitation_id)
        invitation = invitation_ref.get()
        
        if not invitation.exists:
            raise ValueError("Invitation not found")
        
        inv_data = invitation.to_dict()
        
        # Verify invitation is for this child
        if inv_data['child_id'] != child_id:
            raise ValueError("This invitation is not for you")
        
        if inv_data['status'] != 'pending':
            raise ValueError("Invitation is no longer pending")
        
        # Update invitation status
        invitation_ref.update({
            'status': 'rejected',
            'updated_at': datetime.utcnow()
        })
    
    async def get_sent_invitations(self, parent_id: str) -> List[Dict]:
        """Get all invitations sent by a parent."""
        invitations = self.db.collection('family_invitations') \
            .where('parent_id', '==', parent_id) \
            .stream()
        return [serialize_datetime(inv.to_dict()) for inv in invitations]

    # Location Management
    async def save_location(self, user_id: str, latitude: float, longitude: float, accuracy: float = None, timestamp: datetime = None) -> str:
        """Save user location update."""
        location_ref = self.db.collection('locations').document()
        location_data = {
            'id': location_ref.id,
            'user_id': user_id,
            'latitude': latitude,
            'longitude': longitude,
            'accuracy': accuracy,
            'timestamp': timestamp or datetime.utcnow()
        }
        location_ref.set(location_data)
        return location_ref.id
    
    async def get_latest_location(self, user_id: str) -> Dict:
        """Get user's most recent location."""
        locations = self.db.collection('locations') \
            .where('user_id', '==', user_id) \
            .order_by('timestamp', direction='DESCENDING') \
            .limit(1) \
            .stream()
        
        for loc in locations:
            return serialize_datetime(loc.to_dict())
        return None
    
    async def get_location_history(self, user_id: str, days: int = 7) -> List[Dict]:
        """Get location history for past N days."""
        from datetime import timedelta
        end_date = datetime.utcnow()
        start_date = end_date - timedelta(days=days)
        
        locations = self.db.collection('locations') \
            .where('user_id', '==', user_id) \
            .where('timestamp', '>=', start_date) \
            .where('timestamp', '<=', end_date) \
            .order_by('timestamp', direction='DESCENDING') \
            .stream()
        
        return [serialize_datetime(loc.to_dict()) for loc in locations]
    
    async def save_check_in(self, user_id: str, message: str, latitude: float, longitude: float) -> str:
        """Save child safety check-in."""
        check_in_ref = self.db.collection('check_ins').document()
        check_in_data = {
            'id': check_in_ref.id,
            'user_id': user_id,
            'message': message,
            'latitude': latitude,
            'longitude': longitude,
            'timestamp': datetime.utcnow()
        }
        check_in_ref.set(check_in_data)
        return check_in_ref.id
    
    async def get_check_ins(self, user_id: str, days: int = 7) -> List[Dict]:
        """Get check-in history for past N days."""
        from datetime import timedelta
        end_date = datetime.utcnow()
        start_date = end_date - timedelta(days=days)
        
        check_ins = self.db.collection('check_ins') \
            .where('user_id', '==', user_id) \
            .where('timestamp', '>=', start_date) \
            .where('timestamp', '<=', end_date) \
            .order_by('timestamp', direction='DESCENDING') \
            .stream()
        
        return [serialize_datetime(ci.to_dict()) for ci in check_ins]
    
    async def create_geofence(self, family_id: str, name: str, latitude: float, longitude: float, radius: int) -> str:
        """Create a geofence (safe zone)."""
        geofence_ref = self.db.collection('geofences').document()
        geofence_data = {
            'id': geofence_ref.id,
            'family_id': family_id,
            'name': name,
            'latitude': latitude,
            'longitude': longitude,
            'radius': radius,
            'created_at': datetime.utcnow()
        }
        geofence_ref.set(geofence_data)
        return geofence_ref.id
    
    async def get_geofence(self, geofence_id: str) -> Dict:
        """Get geofence by ID."""
        geofence = self.db.collection('geofences').document(geofence_id).get()
        if geofence.exists:
            return serialize_datetime(geofence.to_dict())
        return None
    
    async def get_family_geofences(self, family_id: str) -> List[Dict]:
        """Get all geofences for a family."""
        geofences = self.db.collection('geofences') \
            .where('family_id', '==', family_id) \
            .stream()
        return [serialize_datetime(g.to_dict()) for g in geofences]
    
    async def delete_geofence(self, geofence_id: str) -> None:
        """Delete a geofence."""
        self.db.collection('geofences').document(geofence_id).delete()
    
    # FCM Token Management
    async def save_fcm_token(self, user_id: str, fcm_token: str) -> None:
        """Save FCM token for push notifications."""
        user_ref = self.db.collection('users').document(user_id)
        user_ref.update({
            'fcm_token': fcm_token,
            'fcm_token_updated_at': datetime.utcnow()
        })
    
    async def get_parent_by_family_id(self, family_id: str) -> Optional[Dict]:
        """Get parent user from family ID."""
        users = self.db.collection('users') \
            .where('family_id', '==', family_id) \
            .where('role', '==', 'parent') \
            .limit(1) \
            .stream()
        
        for user in users:
            return user.to_dict()
        return None
    
    async def send_notification(self, token: str, title: str, body: str, data: Optional[Dict] = None) -> bool:
        """Send FCM push notification."""
        try:
            message = messaging.Message(
                notification=messaging.Notification(
                    title=title,
                    body=body,
                ),
                data=data or {},
                token=token,
            )
            
            response = messaging.send(message)
            print(f"✅ Notification sent successfully: {response}")
            return True
        except Exception as e:
            print(f"❌ Failed to send notification: {e}")
            return False
