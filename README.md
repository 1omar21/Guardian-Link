# GuardianLink

GuardianLink is an Android application that helps parents keep their children safe in a responsible and transparent way. It focuses on a small set of essential safety features instead of heavy restrictions: location tracking with safe zones, safety alerts to the parent, and a gamified dashboard that rewards positive behaviour.

## Features

| Feature | Status |
|---|---|
| Parent and child accounts, linked through family invitations | Implemented |
| Child location sharing, viewable by the parent | Implemented |
| Safe zones (geofences) with inside / distance status | Implemented |
| Safety check-in from the child, pushed to the parent through Firebase Cloud Messaging | Implemented |
| Gamified dashboard: tasks, Focus Coins and sticker rewards | Implemented |
| SOS emergency alert | Planned |
| Alerts when the child leaves a safe zone | Planned |
| Map view (Google Maps) | Planned |
| Browsing history monitoring (browsers only) | Planned |

## Repository layout

```
GuardianLink/
├── guardianlink_app/   Flutter app (Android)
├── backend/            FastAPI server, stores data in Firebase Firestore
├── GETTING_STARTED.md  How to run the backend and the app
└── FIREBASE_COMPLETE_SETUP.md  Firebase project setup
```

## Tech stack

- **App:** Flutter (Dart), Provider
- **Backend:** Python, FastAPI, JWT authentication
- **Database:** Firebase Firestore
- **Notifications:** Firebase Cloud Messaging
- **Location:** geolocator

## Quick start

1. Set up a Firebase project by following [FIREBASE_COMPLETE_SETUP.md](FIREBASE_COMPLETE_SETUP.md).
2. Start the backend and run the app by following [GETTING_STARTED.md](GETTING_STARTED.md).

## Files you must provide yourself

These files hold secrets and are not in the repository:

- `backend/.env` (copy `backend/.env.example` and fill it in)
- `backend/firebase-credentials.json` (Firebase service account key)
- `guardianlink_app/android/app/google-services.json` (Firebase Android config for package `com.guardianlink.app`)

## Scope

The app targets Android devices and needs an internet connection.
