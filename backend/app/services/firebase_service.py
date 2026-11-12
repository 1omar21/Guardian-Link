import math
import os
from datetime import datetime, timedelta, timezone
from typing import Optional, List, Dict

import firebase_admin
from firebase_admin import credentials, firestore, messaging
from google.api_core.exceptions import FailedPrecondition

from app.config import get_settings

settings = get_settings()


class TaskError(ValueError):
    """Raised when a task action isn't allowed. `status_code` maps to the HTTP response."""

    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.status_code = status_code


def utcnow() -> datetime:
    """Timezone-aware current UTC time."""
    return datetime.now(timezone.utc)


def to_utc(value: Optional[datetime]) -> Optional[datetime]:
    """Normalise a datetime to aware UTC. Naive values are treated as UTC."""
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def serialize_datetime(data: Dict) -> Dict:
    """Convert datetime objects to ISO format strings for JSON serialization."""
    if not data:
        return data

    serialized = {}
    for key, value in data.items():
        if isinstance(value, datetime):
            serialized[key] = to_utc(value).isoformat()
        elif isinstance(value, dict):
            serialized[key] = serialize_datetime(value)
        elif isinstance(value, list):
            serialized[key] = [serialize_datetime(item) if isinstance(item, dict) else item for item in value]
        else:
            serialized[key] = value
    return serialized


def _sort_key_timestamp(item: Dict, field: str) -> datetime:
    value = item.get(field)
    if isinstance(value, datetime):
        return to_utc(value)
    return datetime.min.replace(tzinfo=timezone.utc)


def distance_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Distance between two points in meters (Haversine)."""
    r = 6371000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)
    a = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# Statuses from which a child may act on a task
CHILD_ACTIONABLE_STATUSES = {"pending", "accepted", "scheduled", "in_progress"}

# Statuses in which the assigned child may delete a task. Completed tasks are
# waiting for the parent's review, so the child can't make them disappear.
CHILD_DELETABLE_STATUSES = CHILD_ACTIONABLE_STATUSES | {"rejected"}

# Geofence alerts: a child must be this many meters beyond the radius before an
# "exit" is reported, so GPS jitter at the boundary doesn't spam the parent.
GEOFENCE_EXIT_MARGIN_M = 25
# Readings less accurate than this are stored but not used for zone alerts.
GEOFENCE_MAX_ACCURACY_M = 100

# Android notification channels (created natively in MainActivity.kt)
CHANNEL_ALERTS = "guardian_alerts"
CHANNEL_SOS = "sos_alerts"


class FirebaseService:
    """Service for Firebase operations."""

    def __init__(self):
        """Initialize Firebase Admin SDK (once per process)."""
        if not firebase_admin._apps:
            cred_path = settings.firebase_credentials_path
            if not os.path.exists(cred_path):
                raise RuntimeError(
                    f"Firebase credentials file not found at '{cred_path}'. "
                    "Set FIREBASE_CREDENTIALS_PATH in backend/.env (path is relative to the backend folder)."
                )
            cred = credentials.Certificate(cred_path)
            options = {'databaseURL': settings.firebase_database_url} if settings.firebase_database_url else None
            firebase_admin.initialize_app(cred, options)

        self.db = firestore.client()

    # ------------------------------------------------------------------ #
    # User Management
    # ------------------------------------------------------------------ #
    async def create_user(self, email: str, password: str, full_name: str, role: str, family_id: Optional[str] = None) -> str:
        """Create a new user in Firestore. `password` must already be hashed."""
        user_ref = self.db.collection('users').document()
        now = utcnow()
        user_data = {
            'id': user_ref.id,
            'email': email.strip().lower(),
            'password_hash': password,
            'full_name': full_name,
            'role': role,
            'family_id': family_id,
            'focus_coins': 0,
            'stickers': [],
            'created_at': now,
            'updated_at': now
        }
        user_ref.set(user_data)
        return user_ref.id

    async def get_user_by_email(self, email: str) -> Optional[Dict]:
        """Get user by email. New accounts are stored lower-cased; the exact
        spelling is also tried so accounts created before that still work."""
        email = (email or '').strip()
        for candidate in dict.fromkeys([email.lower(), email]):
            users = self.db.collection('users').where('email', '==', candidate).limit(1).stream()
            for user in users:
                return user.to_dict()
        return None

    async def get_user_by_id(self, user_id: str) -> Optional[Dict]:
        """Get user by ID."""
        if not user_id:
            return None
        user = self.db.collection('users').document(user_id).get()
        if user.exists:
            return user.to_dict()
        return None

    async def get_family_by_id(self, family_id: str) -> Optional[Dict]:
        """Get family by ID."""
        if not family_id:
            return None
        family = self.db.collection('families').document(family_id).get()
        if family.exists:
            return family.to_dict()
        return None

    async def is_parent_of_child(self, parent_id: str, child_id: str) -> bool:
        """True if `child_id` is a child in a family owned by `parent_id`."""
        child = await self.get_user_by_id(child_id)
        if not child or child.get('role') != 'child':
            return False
        family = await self.get_family_by_id(child.get('family_id'))
        return bool(family) and family.get('parent_id') == parent_id

    async def update_user_coins(self, user_id: str, coins_to_add: int) -> int:
        """Atomically add coins to a user and return the new total."""
        user_ref = self.db.collection('users').document(user_id)

        @firestore.transactional
        def txn(transaction):
            snapshot = user_ref.get(transaction=transaction)
            if not snapshot.exists:
                raise ValueError("User not found")
            new_total = max(0, (snapshot.to_dict().get('focus_coins') or 0) + coins_to_add)
            transaction.update(user_ref, {'focus_coins': new_total, 'updated_at': utcnow()})
            return new_total

        return txn(self.db.transaction())

    async def add_user_sticker(self, user_id: str, sticker: str) -> bool:
        """Add a sticker to user's collection (atomic append)."""
        user_ref = self.db.collection('users').document(user_id)

        @firestore.transactional
        def txn(transaction):
            snapshot = user_ref.get(transaction=transaction)
            if not snapshot.exists:
                raise ValueError("User not found")
            stickers = list(snapshot.to_dict().get('stickers') or [])
            stickers.append(sticker)  # duplicates allowed: it's a collection
            transaction.update(user_ref, {'stickers': stickers, 'updated_at': utcnow()})

        txn(self.db.transaction())
        return True

    # ------------------------------------------------------------------ #
    # Task Management
    # ------------------------------------------------------------------ #
    async def create_task(self, task_data: Dict, created_by: str) -> str:
        """Create a new task."""
        task_ref = self.db.collection('tasks').document()
        now = utcnow()
        task_data = dict(task_data)
        if task_data.get('due_date') is not None:
            task_data['due_date'] = to_utc(task_data['due_date'])
        task_data.update({
            'id': task_ref.id,
            'created_by': created_by,
            'status': 'pending',
            'created_at': now,
            'updated_at': now
        })
        task_ref.set(task_data)
        return task_ref.id

    async def get_task(self, task_id: str) -> Optional[Dict]:
        """Get task by ID."""
        if not task_id:
            return None
        task = self.db.collection('tasks').document(task_id).get()
        if task.exists:
            return task.to_dict()
        return None

    async def get_user_tasks(self, user_id: str, status_filter: Optional[str] = None) -> List[Dict]:
        """Get tasks assigned to a user (newest first)."""
        query = self.db.collection('tasks').where('assigned_to', '==', user_id)
        if status_filter:
            query = query.where('status', '==', status_filter)
        task_list = [task.to_dict() for task in query.stream()]
        task_list.sort(key=lambda x: _sort_key_timestamp(x, 'created_at'), reverse=True)
        return [serialize_datetime(t) for t in task_list]

    async def get_tasks_by_creator(self, creator_id: str, status_filter: Optional[str] = None) -> List[Dict]:
        """Get tasks created by a specific user (for parents, newest first)."""
        query = self.db.collection('tasks').where('created_by', '==', creator_id)
        if status_filter:
            query = query.where('status', '==', status_filter)
        task_list = [task.to_dict() for task in query.stream()]
        task_list.sort(key=lambda x: _sort_key_timestamp(x, 'created_at'), reverse=True)
        return [serialize_datetime(t) for t in task_list]

    def _get_child_task_for_update(self, transaction, task_ref, child_id: str) -> Dict:
        snapshot = task_ref.get(transaction=transaction)
        if not snapshot.exists:
            raise TaskError("Task not found", 404)
        task = snapshot.to_dict()
        if task.get('assigned_to') != child_id:
            raise TaskError("This task is not assigned to you", 403)
        if task.get('status') not in CHILD_ACTIONABLE_STATUSES:
            raise TaskError(f"Task can't be changed from status '{task.get('status')}'", 400)
        return task

    async def _child_set_status(self, task_id: str, child_id: str, updates: Dict) -> None:
        task_ref = self.db.collection('tasks').document(task_id)

        @firestore.transactional
        def txn(transaction):
            self._get_child_task_for_update(transaction, task_ref, child_id)
            now = utcnow()
            transaction.update(task_ref, {**updates, 'child_response_at': now, 'updated_at': now})

        txn(self.db.transaction())

    async def accept_task(self, task_id: str, child_id: str) -> None:
        """Child accepts a task."""
        await self._child_set_status(task_id, child_id, {'status': 'accepted'})

    async def reject_task(self, task_id: str, child_id: str) -> None:
        """Child rejects a task (final decision)."""
        await self._child_set_status(task_id, child_id, {'status': 'rejected', 'rejected_by': 'child'})

    async def schedule_task(self, task_id: str, child_id: str, scheduled_time: datetime) -> None:
        """Child schedules a task for later."""
        await self._child_set_status(
            task_id, child_id, {'status': 'scheduled', 'scheduled_for': to_utc(scheduled_time)}
        )

    async def complete_task_and_award(self, task_id: str, child_id: str) -> Dict:
        """
        Child completes a task. Marks it completed and awards its coins in ONE
        transaction, so a task can only ever pay out once.
        Returns {'coins_awarded', 'new_coin_total'}.
        """
        task_ref = self.db.collection('tasks').document(task_id)
        user_ref = self.db.collection('users').document(child_id)

        @firestore.transactional
        def txn(transaction):
            task = self._get_child_task_for_update(transaction, task_ref, child_id)
            user_snapshot = user_ref.get(transaction=transaction)
            if not user_snapshot.exists:
                raise TaskError("User not found", 404)

            reward = int(task.get('reward_coins') or 0)
            new_total = (user_snapshot.to_dict().get('focus_coins') or 0) + reward
            now = utcnow()

            transaction.update(task_ref, {
                'status': 'completed',
                'completed_at': now,
                'coins_awarded': reward,
                'updated_at': now,
            })
            transaction.update(user_ref, {'focus_coins': new_total, 'updated_at': now})
            return {'coins_awarded': reward, 'new_coin_total': new_total}

        return txn(self.db.transaction())

    async def set_task_sticker(self, task_id: str, sticker: str) -> None:
        """Remember which sticker a task paid out, so it can be taken back on rejection."""
        self.db.collection('tasks').document(task_id).update({'sticker_awarded': sticker})

    async def update_task(self, task_id: str, update_data: Dict) -> None:
        """Update a task."""
        update_data = dict(update_data)
        if update_data.get('due_date') is not None:
            update_data['due_date'] = to_utc(update_data['due_date'])
        update_data['updated_at'] = utcnow()
        self.db.collection('tasks').document(task_id).update(update_data)

    async def delete_task(self, task_id: str, deleted_by: str) -> None:
        """Soft delete a task by marking it as deleted."""
        now = utcnow()
        self.db.collection('tasks').document(task_id).update({
            'status': 'deleted',
            'deleted_by': deleted_by,
            'deleted_at': now,
            'updated_at': now
        })

    async def verify_task(self, task_id: str, parent_id: str, approved: bool, feedback: Optional[str] = None) -> None:
        """
        Parent verifies a completed task.
        Coins were already awarded when the child completed it, so:
          - approve -> status 'verified' (no extra coins)
          - reject  -> status 'rejected' and the awarded coins are taken back
        """
        task_ref = self.db.collection('tasks').document(task_id)

        @firestore.transactional
        def txn(transaction):
            snapshot = task_ref.get(transaction=transaction)
            if not snapshot.exists:
                raise TaskError("Task not found", 404)
            task = snapshot.to_dict()
            if task.get('created_by') != parent_id:
                raise TaskError("You can only verify tasks you created", 403)
            if task.get('status') != 'completed':
                raise TaskError("Only completed tasks can be verified", 400)

            now = utcnow()
            if approved:
                transaction.update(task_ref, {
                    'status': 'verified',
                    'verified_at': now,
                    'verification_feedback': feedback,
                    'updated_at': now,
                })
                return

            awarded = int(task.get('coins_awarded') or 0)
            sticker = task.get('sticker_awarded')
            child_ref = self.db.collection('users').document(task['assigned_to'])
            child_snapshot = child_ref.get(transaction=transaction)
            if child_snapshot.exists and (awarded or sticker):
                child_data = child_snapshot.to_dict()
                child_updates = {'updated_at': now}
                if awarded:
                    current = child_data.get('focus_coins') or 0
                    child_updates['focus_coins'] = max(0, current - awarded)
                if sticker:
                    stickers = list(child_data.get('stickers') or [])
                    if sticker in stickers:
                        stickers.remove(sticker)  # take back one copy
                        child_updates['stickers'] = stickers
                transaction.update(child_ref, child_updates)
            transaction.update(task_ref, {
                'status': 'rejected',
                'rejected_by': 'parent',
                'rejected_at': now,
                'rejection_feedback': feedback,
                'coins_awarded': 0,
                'sticker_awarded': None,
                'updated_at': now,
            })

        txn(self.db.transaction())

    # ------------------------------------------------------------------ #
    # Family Management
    # ------------------------------------------------------------------ #
    async def create_family(self, parent_id: str) -> str:
        """Create a new family with parent as owner."""
        family_ref = self.db.collection('families').document()
        now = utcnow()
        family_ref.set({
            'id': family_ref.id,
            'parent_id': parent_id,
            'created_at': now,
            'updated_at': now
        })
        self.db.collection('users').document(parent_id).update({'family_id': family_ref.id})
        return family_ref.id

    async def get_or_create_family_for_parent(self, parent_id: str) -> str:
        """Return the parent's family id, creating the family if needed."""
        parent = await self.get_user_by_id(parent_id)
        if not parent:
            raise ValueError("User not found")
        if parent.get('role') != 'parent':
            raise ValueError("Only parents own families")
        family_id = parent.get('family_id')
        if family_id and await self.get_family_by_id(family_id):
            return family_id
        return await self.create_family(parent_id)

    async def add_child_to_family(self, family_id: str, child_id: str) -> None:
        """Add a child to a family."""
        now = utcnow()
        self.db.collection('users').document(child_id).update({'family_id': family_id, 'updated_at': now})
        self.db.collection('families').document(family_id).update({'updated_at': now})

    async def get_family_members(self, family_id: str) -> List[Dict]:
        """Get all members of a family."""
        users = self.db.collection('users').where('family_id', '==', family_id).stream()
        return [serialize_datetime(user.to_dict()) for user in users]

    async def get_children_for_parent(self, parent_id: str) -> List[Dict]:
        """Get all children linked to a parent."""
        parent = await self.get_user_by_id(parent_id)
        if not parent or not parent.get('family_id'):
            return []
        users = self.db.collection('users') \
            .where('family_id', '==', parent['family_id']) \
            .where('role', '==', 'child') \
            .stream()
        return [serialize_datetime(user.to_dict()) for user in users]

    # Family Management - Secure Invitation System
    async def create_family_invitation(self, parent_id: str, child_email: str) -> str:
        """Create a family invitation that requires child acceptance."""
        parent = await self.get_user_by_id(parent_id)
        if not parent:
            raise ValueError("User not found")

        child = await self.get_user_by_email(child_email)
        if not child or child.get('role') != 'child':
            raise ValueError("Child not found or invalid email")

        family_id = await self.get_or_create_family_for_parent(parent_id)

        if child.get('family_id') == family_id:
            raise ValueError("Child is already in your family")

        existing = self.db.collection('family_invitations') \
            .where('family_id', '==', family_id) \
            .where('child_id', '==', child['id']) \
            .where('status', '==', 'pending') \
            .limit(1) \
            .stream()
        for _ in existing:
            raise ValueError("Invitation already sent to this child")

        invitation_ref = self.db.collection('family_invitations').document()
        now = utcnow()
        invitation_ref.set({
            'id': invitation_ref.id,
            'family_id': family_id,
            'parent_id': parent_id,
            'parent_name': parent.get('full_name') or '',
            'parent_email': parent.get('email') or '',
            'child_id': child['id'],
            'child_email': child.get('email') or child_email,
            'status': 'pending',  # pending, accepted, rejected
            'created_at': now,
            'updated_at': now
        })
        return invitation_ref.id

    async def get_pending_invitations(self, child_id: str) -> List[Dict]:
        """Get all pending invitations for a child."""
        invitations = self.db.collection('family_invitations') \
            .where('child_id', '==', child_id) \
            .where('status', '==', 'pending') \
            .stream()
        return [serialize_datetime(inv.to_dict()) for inv in invitations]

    async def _load_invitation_for_child(self, invitation_id: str, child_id: str):
        invitation_ref = self.db.collection('family_invitations').document(invitation_id)
        invitation = invitation_ref.get()
        if not invitation.exists:
            raise ValueError("Invitation not found")
        inv_data = invitation.to_dict()
        if inv_data.get('child_id') != child_id:
            raise ValueError("This invitation is not for you")
        if inv_data.get('status') != 'pending':
            raise ValueError("Invitation is no longer pending")
        return invitation_ref, inv_data

    async def accept_invitation(self, invitation_id: str, child_id: str) -> None:
        """Child accepts a family invitation."""
        invitation_ref, inv_data = await self._load_invitation_for_child(invitation_id, child_id)

        if not await self.get_family_by_id(inv_data['family_id']):
            raise ValueError("This family no longer exists")

        await self.add_child_to_family(inv_data['family_id'], child_id)

        now = utcnow()
        invitation_ref.update({'status': 'accepted', 'updated_at': now})

        # A child belongs to one family: close any other pending invitations.
        for other in self.db.collection('family_invitations') \
                .where('child_id', '==', child_id) \
                .where('status', '==', 'pending') \
                .stream():
            other.reference.update({'status': 'rejected', 'updated_at': now})

    async def reject_invitation(self, invitation_id: str, child_id: str) -> None:
        """Child rejects a family invitation."""
        invitation_ref, _ = await self._load_invitation_for_child(invitation_id, child_id)
        invitation_ref.update({'status': 'rejected', 'updated_at': utcnow()})

    async def get_sent_invitations(self, parent_id: str) -> List[Dict]:
        """Get all invitations sent by a parent."""
        invitations = self.db.collection('family_invitations') \
            .where('parent_id', '==', parent_id) \
            .stream()
        return [serialize_datetime(inv.to_dict()) for inv in invitations]

    # ------------------------------------------------------------------ #
    # Location Management
    # ------------------------------------------------------------------ #
    async def save_location(self, user_id: str, latitude: float, longitude: float, accuracy: float = None, timestamp: datetime = None) -> str:
        """Save a location update (history + 'latest' snapshot for fast lookup)."""
        location_ref = self.db.collection('locations').document()
        location_data = {
            'id': location_ref.id,
            'user_id': user_id,
            'latitude': latitude,
            'longitude': longitude,
            'accuracy': accuracy,
            'timestamp': to_utc(timestamp) or utcnow()
        }
        location_ref.set(location_data)
        # One doc per user -> reading the latest location needs no composite index.
        self.db.collection('latest_locations').document(user_id).set(location_data)
        return location_ref.id

    def _query_user_docs_in_range(self, collection: str, user_id: str, days: int) -> List[Dict]:
        """
        Docs for a user within the last `days`, newest first.
        Uses the composite index (user_id + timestamp) if it exists; otherwise
        falls back to an index-free query and filters in Python.
        """
        end_date = utcnow()
        start_date = end_date - timedelta(days=days)
        try:
            docs = self.db.collection(collection) \
                .where('user_id', '==', user_id) \
                .where('timestamp', '>=', start_date) \
                .where('timestamp', '<=', end_date) \
                .order_by('timestamp', direction=firestore.Query.DESCENDING) \
                .stream()
            return [d.to_dict() for d in docs]
        except FailedPrecondition:
            docs = self.db.collection(collection).where('user_id', '==', user_id).stream()
            items = [
                d.to_dict() for d in docs
                if start_date <= _sort_key_timestamp(d.to_dict(), 'timestamp') <= end_date
            ]
            items.sort(key=lambda x: _sort_key_timestamp(x, 'timestamp'), reverse=True)
            return items

    async def get_latest_location(self, user_id: str) -> Optional[Dict]:
        """Get user's most recent location."""
        latest = self.db.collection('latest_locations').document(user_id).get()
        if latest.exists:
            return serialize_datetime(latest.to_dict())

        # Older data saved before 'latest_locations' existed.
        items = self._query_user_docs_in_range('locations', user_id, days=3650)
        if items:
            self.db.collection('latest_locations').document(user_id).set(items[0])
            return serialize_datetime(items[0])
        return None

    async def get_location_history(self, user_id: str, days: int = 7) -> List[Dict]:
        """Get location history for past N days."""
        return [serialize_datetime(x) for x in self._query_user_docs_in_range('locations', user_id, days)]

    async def save_check_in(self, user_id: str, message: str, latitude: float, longitude: float) -> str:
        """Save child safety check-in."""
        check_in_ref = self.db.collection('check_ins').document()
        check_in_ref.set({
            'id': check_in_ref.id,
            'user_id': user_id,
            'message': message,
            'latitude': latitude,
            'longitude': longitude,
            'timestamp': utcnow()
        })
        return check_in_ref.id

    async def get_check_ins(self, user_id: str, days: int = 7) -> List[Dict]:
        """Get check-in history for past N days."""
        return [serialize_datetime(x) for x in self._query_user_docs_in_range('check_ins', user_id, days)]

    # ------------------------------------------------------------------ #
    # Geofences
    # ------------------------------------------------------------------ #
    async def create_geofence(self, family_id: str, name: str, latitude: float, longitude: float, radius: int, created_by: Optional[str] = None) -> str:
        """Create a geofence (safe zone)."""
        geofence_ref = self.db.collection('geofences').document()
        geofence_ref.set({
            'id': geofence_ref.id,
            'family_id': family_id,
            'name': name,
            'latitude': latitude,
            'longitude': longitude,
            'radius': radius,
            'created_by': created_by,
            'created_at': utcnow()
        })
        return geofence_ref.id

    async def get_geofence(self, geofence_id: str) -> Optional[Dict]:
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

    # ------------------------------------------------------------------ #
    # FCM
    # ------------------------------------------------------------------ #
    async def save_fcm_token(self, user_id: str, fcm_token: str) -> None:
        """
        Register a device token for a user. A user may have several devices.
        A device belongs to whoever logged in on it last, so the token is
        removed from any other account first (shared phones).
        """
        users = self.db.collection('users')
        for other in users.where('fcm_tokens', 'array_contains', fcm_token).stream():
            if other.id != user_id:
                await self.remove_fcm_token(other.id, fcm_token)
        for other in users.where('fcm_token', '==', fcm_token).stream():
            if other.id != user_id:
                await self.remove_fcm_token(other.id, fcm_token)

        users.document(user_id).update({
            'fcm_token': fcm_token,  # most recent device (kept for older code)
            'fcm_tokens': firestore.ArrayUnion([fcm_token]),
            'fcm_token_updated_at': utcnow()
        })

    async def remove_fcm_token(self, user_id: str, fcm_token: str) -> None:
        """Unregister a device token (logout, or token no longer valid)."""
        user_ref = self.db.collection('users').document(user_id)
        snapshot = user_ref.get()
        if not snapshot.exists:
            return
        updates = {'fcm_tokens': firestore.ArrayRemove([fcm_token])}
        if snapshot.to_dict().get('fcm_token') == fcm_token:
            updates['fcm_token'] = firestore.DELETE_FIELD
        user_ref.update(updates)

    async def get_parent_by_family_id(self, family_id: str) -> Optional[Dict]:
        """Get the parent (owner) of a family."""
        family = await self.get_family_by_id(family_id)
        if not family:
            return None
        return await self.get_user_by_id(family.get('parent_id'))

    async def send_notification(self, token: str, title: str, body: str,
                                data: Optional[Dict] = None, urgent: bool = False) -> bool:
        """
        Send one FCM push. Never raises. Returns True on success, False on a
        temporary failure, and None when FCM says the token is dead (so the
        caller can drop it).
        """
        try:
            message = messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                data={k: str(v) for k, v in (data or {}).items()},
                android=messaging.AndroidConfig(
                    priority='high',
                    notification=messaging.AndroidNotification(
                        channel_id=CHANNEL_SOS if urgent else CHANNEL_ALERTS,
                        sound='default',
                        default_vibrate_timings=True,
                    ),
                ),
                token=token,
            )
            messaging.send(message)
            return True
        except Exception as e:
            dead = type(e).__name__ in ('UnregisteredError', 'SenderIdMismatchError') or \
                'registration-token-not-registered' in str(e)
            print(f"[error] Failed to send notification: {e}")
            return None if dead else False

    async def notify_user(self, user_id: str, title: str, body: str,
                          data: Optional[Dict] = None, urgent: bool = False) -> bool:
        """Push to every device of a user. Never raises. True if any device got it."""
        try:
            user = await self.get_user_by_id(user_id)
            if not user:
                return False
            tokens = list(dict.fromkeys(
                [t for t in (user.get('fcm_tokens') or []) if t] +
                ([user['fcm_token']] if user.get('fcm_token') else [])
            ))
            delivered = False
            for token in tokens:
                result = await self.send_notification(token, title, body, data, urgent)
                if result is None:
                    await self.remove_fcm_token(user_id, token)
                delivered = delivered or bool(result)
            return delivered
        except Exception as e:
            print(f"[error] notify_user failed: {e}")
            return False

    async def notify_parent_of(self, child: Dict, title: str, body: str,
                               data: Optional[Dict] = None, urgent: bool = False) -> bool:
        """Push to the parent who owns the child's family. Never raises."""
        try:
            if not child.get('family_id'):
                return False
            parent = await self.get_parent_by_family_id(child['family_id'])
            if not parent or parent.get('id') == child.get('id'):
                return False
            return await self.notify_user(parent['id'], title, body, data, urgent)
        except Exception as e:
            print(f"[error] notify_parent_of failed: {e}")
            return False

    # ------------------------------------------------------------------ #
    # Geofence enter / exit detection
    # ------------------------------------------------------------------ #
    async def process_geofence_transitions(self, child: Dict, latitude: float, longitude: float,
                                           accuracy: Optional[float] = None) -> List[Dict]:
        """
        Compare the child's new position with every zone of their family and
        record an 'enter' / 'exit' event for each zone whose state changed.
        The first reading for a zone only records the state (no alert).
        Returns the new events.
        """
        family_id = child.get('family_id')
        if not family_id or child.get('role') != 'child':
            return []
        if accuracy is not None and accuracy > GEOFENCE_MAX_ACCURACY_M:
            return []

        zones = await self.get_family_geofences(family_id)
        state_ref = self.db.collection('geofence_states').document(child['id'])
        snapshot = state_ref.get()
        previous = (snapshot.to_dict() or {}).get('zones', {}) if snapshot.exists else {}

        now = utcnow()
        new_states: Dict[str, bool] = {}
        events: List[Dict] = []
        for zone in zones:
            radius = float(zone.get('radius') or zone.get('radius_meters') or 0)
            if radius <= 0:
                continue
            dist = distance_meters(latitude, longitude, zone['latitude'], zone['longitude'])
            was_inside = previous.get(zone['id'])
            if was_inside is True:
                inside = dist <= radius + GEOFENCE_EXIT_MARGIN_M  # hysteresis
            else:
                inside = dist <= radius
            new_states[zone['id']] = inside

            if was_inside is None or was_inside == inside:
                continue

            event_ref = self.db.collection('geofence_events').document()
            event = {
                'id': event_ref.id,
                'child_id': child['id'],
                'child_name': child.get('full_name') or '',
                'family_id': family_id,
                'geofence_id': zone['id'],
                'geofence_name': zone.get('name') or 'Safe zone',
                'event': 'enter' if inside else 'exit',
                'latitude': latitude,
                'longitude': longitude,
                'timestamp': now,
            }
            event_ref.set(event)
            events.append(event)

        state_ref.set({'zones': new_states, 'updated_at': now})
        return [serialize_datetime(e) for e in events]

    async def get_geofence_events(self, family_id: str, days: int = 7) -> List[Dict]:
        """Zone enter/exit events of a family, newest first (no composite index needed)."""
        since = utcnow() - timedelta(days=days)
        docs = self.db.collection('geofence_events').where('family_id', '==', family_id).stream()
        items = [d.to_dict() for d in docs]
        items = [i for i in items if _sort_key_timestamp(i, 'timestamp') >= since]
        items.sort(key=lambda x: _sort_key_timestamp(x, 'timestamp'), reverse=True)
        return [serialize_datetime(i) for i in items]

    # ------------------------------------------------------------------ #
    # SOS alerts
    # ------------------------------------------------------------------ #
    async def create_sos_alert(self, child: Dict, latitude: Optional[float], longitude: Optional[float],
                               accuracy: Optional[float], message: str) -> Dict:
        """Store an active SOS alert from a child."""
        ref = self.db.collection('sos_alerts').document()
        alert = {
            'id': ref.id,
            'child_id': child['id'],
            'child_name': child.get('full_name') or '',
            'family_id': child.get('family_id'),
            'latitude': latitude,
            'longitude': longitude,
            'accuracy': accuracy,
            'message': message,
            'status': 'active',  # active -> resolved
            'timestamp': utcnow(),
        }
        ref.set(alert)
        return serialize_datetime(alert)

    async def get_sos_alert(self, alert_id: str) -> Optional[Dict]:
        snapshot = self.db.collection('sos_alerts').document(alert_id).get()
        return serialize_datetime(snapshot.to_dict()) if snapshot.exists else None

    async def resolve_sos_alert(self, alert_id: str, resolved_by: str) -> None:
        self.db.collection('sos_alerts').document(alert_id).update({
            'status': 'resolved',
            'resolved_by': resolved_by,
            'resolved_at': utcnow(),
        })

    async def get_sos_alerts(self, family_id: str, days: int = 7) -> List[Dict]:
        """SOS alerts of a family, newest first (no composite index needed)."""
        since = utcnow() - timedelta(days=days)
        docs = self.db.collection('sos_alerts').where('family_id', '==', family_id).stream()
        items = [d.to_dict() for d in docs]
        # Active alerts are always returned, however old.
        items = [i for i in items if i.get('status') == 'active' or _sort_key_timestamp(i, 'timestamp') >= since]
        items.sort(key=lambda x: _sort_key_timestamp(x, 'timestamp'), reverse=True)
        return [serialize_datetime(i) for i in items]

    # ------------------------------------------------------------------ #
    # Browsing history (browsers only)
    # ------------------------------------------------------------------ #
    async def save_browsing_visits(self, child: Dict, visits: List[Dict]) -> int:
        """Store visited browser URLs reported by the child's device."""
        batch = self.db.batch()
        now = utcnow()
        for visit in visits:
            ref = self.db.collection('browsing_history').document()
            batch.set(ref, {
                'id': ref.id,
                'user_id': child['id'],
                'family_id': child.get('family_id'),
                'url': visit['url'],
                'title': visit.get('title'),
                'browser': visit.get('browser'),
                # Device clocks can run ahead; never store a visit in the future.
                'timestamp': min(to_utc(visit.get('visited_at')) or now, now),
            })
        batch.commit()
        return len(visits)

    async def get_browsing_history(self, user_id: str, days: int = 7, limit: int = 500) -> List[Dict]:
        items = self._query_user_docs_in_range('browsing_history', user_id, days)[:limit]
        return [serialize_datetime(i) for i in items]


_firebase_service: Optional[FirebaseService] = None


def get_firebase_service() -> FirebaseService:
    """Shared FirebaseService instance."""
    global _firebase_service
    if _firebase_service is None:
        _firebase_service = FirebaseService()
    return _firebase_service
