# Getting Started - GuardianLink

## Prerequisites

- Python 3.10+
- Flutter 3.x and Android Studio
- An Android device or emulator
- A Firebase project with Firestore enabled (see [FIREBASE_COMPLETE_SETUP.md](FIREBASE_COMPLETE_SETUP.md))

## 1. Configure the backend

```bash
cd backend
python -m venv venv
venv\Scripts\activate          # Linux/macOS: source venv/bin/activate
pip install -r requirements.txt
copy .env.example .env         # Linux/macOS: cp .env.example .env
```

Edit `backend/.env`:

- `SECRET_KEY` - any long random string
- `FIREBASE_CREDENTIALS_PATH` - `./firebase-credentials.json`
- `FIREBASE_DATABASE_URL` - your Firebase project URL

Place your Firebase service account key at `backend/firebase-credentials.json`.

## 2. Start the backend

```bash
cd backend
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

The API documentation is then available at `http://localhost:8000/docs`.

On Linux/macOS you can use `bash start_backend.sh` and `bash stop_backend.sh` from the repository root instead.

## 3. Point the app at the backend

Edit `guardianlink_app/lib/core/constants/api_constants.dart`:

```dart
static const String baseUrl = 'http://YOUR_COMPUTER_IP:8000';
```

- Physical device: use your computer's IP address on the same Wi-Fi network.
- Android emulator: use `http://10.0.2.2:8000`.

## 4. Run the app

Place your `google-services.json` in `guardianlink_app/android/app/`, then:

```bash
cd guardianlink_app
flutter pub get
flutter run
```

To build an APK: `flutter build apk --release`.

## 5. Try it out

1. Register one parent account and one child account in the app.
2. As the parent, open **Manage Family** and invite the child by email.
3. As the child, accept the invitation from the mail icon.
4. As the child, open **My Location** and send a check-in.
5. As the parent, open the child's **Location** and **Check-ins**, create a safe zone, and create a task with a coin reward.
6. As the child, complete the task to earn Focus Coins and a sticker.

## Permissions

- **Location** - for location sharing and check-ins
- **Notifications** - for check-in alerts

## Troubleshooting

### The app cannot log in or shows no data
1. Check the backend is running and reachable from the device: open `http://YOUR_COMPUTER_IP:8000/docs` in the device browser.
2. Check `baseUrl` in `api_constants.dart`.
3. Check that the Firestore composite indexes are created and enabled.

### "Index required" errors in the backend log
Create the indexes listed in [FIREBASE_COMPLETE_SETUP.md](FIREBASE_COMPLETE_SETUP.md).
