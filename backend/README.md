# GuardianLink - Backend

FastAPI backend for the GuardianLink Android app. Data is stored in Firebase Firestore and push notifications are sent through Firebase Cloud Messaging.

## Features

- **JWT authentication** with parent and child roles
- **Family management** - parents invite children, children accept
- **Location** - location updates, history, safety check-ins
- **Geofences** - safe zones per family
- **Tasks and rewards** - tasks with Focus Coins and stickers

## Setup

### 1. Create a virtual environment

```bash
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

### 2. Install dependencies

```bash
pip install --upgrade pip
pip install -r requirements.txt
```

### 3. Configure the environment

```bash
cp .env.example .env
```

Edit `.env`:

```env
SECRET_KEY=your-secret-key-here
FIREBASE_CREDENTIALS_PATH=./firebase-credentials.json
FIREBASE_DATABASE_URL=https://your-project.firebaseio.com
```

### 4. Firebase

1. Go to the [Firebase Console](https://console.firebase.google.com/) and create a project
2. Enable Firestore Database
3. Go to Project Settings → Service Accounts and click "Generate New Private Key"
4. Save the JSON file as `firebase-credentials.json` in this directory

### 5. Run the server

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

The API is available at `http://localhost:8000` and the interactive documentation at `http://localhost:8000/docs`.

## API endpoints

### Authentication
- `POST /api/auth/register` - Register a user
- `POST /api/auth/login` - Log in
- `GET /api/auth/me` - Current user
- `POST /api/auth/fcm-token` - Save the device's push token

### Family
- `POST /api/family/invite` - Invite a child (parent)
- `GET /api/family/invitations` - List invitations
- `POST /api/family/accept/{invitation_id}` - Accept (child)
- `POST /api/family/reject/{invitation_id}` - Reject (child)
- `GET /api/family/children` - Linked children (parent)
- `GET /api/family/members` - Family members

### Location
- `POST /api/location/update` - Send a location update
- `GET /api/location/current/{child_id}` - Child's latest location (parent)
- `GET /api/location/history/{child_id}` - Location history (parent)
- `POST /api/location/check-in` - Safety check-in, notifies the parent
- `GET /api/location/check-ins/{child_id}` - Check-in history (parent)
- `POST /api/location/geofence` - Create a safe zone (parent)
- `GET /api/location/geofences` - List safe zones
- `DELETE /api/location/geofence/{geofence_id}` - Delete a safe zone

### Tasks
- `POST /api/tasks/` - Create a task (parent)
- `GET /api/tasks/` - List tasks
- `PUT /api/tasks/{task_id}` - Update a task
- `POST /api/tasks/complete` - Complete a task and earn the reward (child)
- `POST /api/tasks/reject/{task_id}` - Reject a task (child)
- `POST /api/tasks/schedule/{task_id}` - Schedule a task for later (child)
- `DELETE /api/tasks/{task_id}` - Delete a task

## Project structure

```
backend/
├── app/
│   ├── main.py              # FastAPI application
│   ├── config.py            # Settings
│   ├── models/              # Pydantic models
│   ├── routers/             # API endpoints
│   ├── services/            # Firebase access
│   └── middleware/          # JWT auth
├── requirements.txt
├── .env.example
└── README.md
```

## Environment variables

| Variable | Description | Required |
|----------|-------------|----------|
| `SECRET_KEY` | JWT secret key | Yes |
| `FIREBASE_CREDENTIALS_PATH` | Path to the Firebase service account key | Yes |
| `FIREBASE_DATABASE_URL` | Firebase database URL | Yes |

## Security notes

- Never commit `.env` or `firebase-credentials.json`
- Use a strong `SECRET_KEY` in production
- Use HTTPS in production
