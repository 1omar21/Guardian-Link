# GuardianLink — Project Overview

GuardianLink is a family-safety application for Android. A parent and a child each install the same app and sign in with their own account. Once the child accepts the parent's invitation, the parent can see the child's last shared location, define safe zones, read the child's safety check-ins, and assign tasks that reward the child with Focus Coins and stickers.

The project has two parts that live in one repository:

| Part | Folder | What it is |
|---|---|---|
| Mobile app | [guardianlink_app/](../guardianlink_app/) | Flutter app, written in Dart, targeting Android |
| Backend | [backend/](../backend/) | REST API, written in Python with FastAPI, storing data in Firebase Firestore |

Related documents:

- [ARCHITECTURE.md](ARCHITECTURE.md) — how the system is structured
- [WORKFLOWS.md](WORKFLOWS.md) — step-by-step flows for every feature
- [MODULES.md](MODULES.md) — what each module and file does
- [../GETTING_STARTED.md](../GETTING_STARTED.md) and [../FIREBASE_COMPLETE_SETUP.md](../FIREBASE_COMPLETE_SETUP.md) — setup instructions

---

## 1. Features

| Feature | Who uses it | Status |
|---|---|---|
| Registration and login with parent / child roles | Both | Working |
| Family linking by invitation (parent invites, child accepts or rejects) | Both | Working |
| Tasks with coin rewards: create, complete, reject, schedule for later, delete | Both | Working |
| Focus Coins balance and sticker collection | Child | Working |
| Location sharing and "last known location" view | Both | Working (shared only while the child has the location screen open) |
| Safety check-in with history | Both | Check-in and history working; the push notification to the parent is not delivered (see section 8) |
| Safe zones (geofences) with inside / distance status | Both | Screens and endpoints exist; creation and listing fail on the server (see section 8) |
| Light / dark theme | Both | Working |
| SOS alert, leave-zone alerts, map view, browsing-history monitoring | — | Planned, not started |

---

## 2. Languages

| Language | Where | Used for |
|---|---|---|
| Dart (SDK `>=3.0.0 <4.0.0`) | `guardianlink_app/lib/` | All app code: screens, state, networking |
| Python 3.10+ | `backend/app/` | All backend code |
| Kotlin | `guardianlink_app/android/.../MainActivity.kt` | Android entry point only (an empty `FlutterActivity`) |
| Gradle Kotlin DSL | `guardianlink_app/android/*.gradle.kts` | Android build configuration |
| Bash | `start_backend.sh`, `stop_backend.sh` | Starting and stopping the backend on Linux / macOS |

The `ios/`, `linux/`, `macos/`, `windows/` and `web/` folders inside the app are the default Flutter scaffolding. Only Android is configured and supported.

---

## 3. Frameworks and libraries

### 3.1 Mobile app

Packages the code imports and depends on:

| Package | Purpose in this project |
|---|---|
| `flutter` (Material 3) | UI toolkit |
| `provider` | State management (`AuthProvider`, `ThemeProvider`) |
| `http` | All REST calls to the backend |
| `shared_preferences` | Stores the JWT (`auth_token`) and the theme choice (`themeMode`) on the device |
| `geolocator` | Reads the device GPS position and computes distances |
| `permission_handler` | Requests foreground and background location permission |
| `firebase_core`, `firebase_messaging` | Firebase start-up and push-notification token / listeners |
| `intl` | Date formatting in the check-in history |

Packages declared in [pubspec.yaml](../guardianlink_app/pubspec.yaml) but not used by any code yet: `firebase_auth`, `firebase_storage`, `google_maps_flutter`, `location`, `dio`, `flutter_foreground_task`, `lottie`, `shimmer`, `fl_chart`, `animations`, `uuid`, `timeago`, `jwt_decoder`, `cached_network_image`, `image_picker`. `cloud_firestore` is imported in one screen only for a type that is never used; the app never reads or writes Firestore directly.

### 3.2 Backend

| Package | Purpose in this project |
|---|---|
| `fastapi` | Web framework, request validation, automatic API docs |
| `uvicorn` | ASGI server that runs the app |
| `pydantic`, `pydantic-settings` | Request / response models and `.env` configuration |
| `firebase-admin` | Firestore database client and Firebase Cloud Messaging sender |
| `python-jose` | Creating and verifying JWT access tokens |
| `passlib[bcrypt]` | Password hashing |

Listed in [requirements.txt](../backend/requirements.txt) but not imported by the application: `sqlalchemy`, `httpx`, `requests`, `PyJWT`, `python-multipart`, and the development tools `pytest`, `black`, `flake8`, `mypy`.

---

## 4. External services and APIs

| Service | How it is accessed | What it does here |
|---|---|---|
| **Cloud Firestore** | Backend only, through the Firebase Admin SDK with a service-account key | The only database. Holds users, families, invitations, tasks, locations, check-ins and geofences |
| **Firebase Cloud Messaging (FCM)** | Backend sends through the Admin SDK; the app receives through `firebase_messaging` | Push notification to the parent when the child checks in |
| **Device location (Android GPS)** | App, through `geolocator` | Source of the child's coordinates |
| **GuardianLink REST API** | App, through `http` with a Bearer JWT | The project's own API, described below |

Firebase Authentication is **not** used. Accounts are documents in the Firestore `users` collection, passwords are hashed with bcrypt by the backend, and sessions are JWTs issued by the backend. Google Maps is declared as a dependency but no map is shown yet; locations are displayed as coordinates.

---

## 5. REST API reference

Base URL during development: `http://<backend-host>:8000`. Interactive documentation is generated by FastAPI at `/docs` (Swagger UI) and `/redoc`.

Every endpoint except register, login, `/` and `/health` requires the header `Authorization: Bearer <token>`.

### Authentication — `/api/auth`

| Method | Path | Role | Description | Called by the app |
|---|---|---|---|---|
| POST | `/register` | Public | Create an account, returns a token and the user | Yes |
| POST | `/login` | Public | Verify credentials, returns a token and the user | Yes |
| GET | `/me` | Any | Current user's profile, including coins and stickers | Yes |
| POST | `/fcm-token` | Any | Store the device's push token | Yes (request format mismatch, see section 8) |

### Family — `/api/family`

| Method | Path | Role | Description | Called by the app |
|---|---|---|---|---|
| POST | `/invite` | Parent | Invite a child by email; creates the family on first use | Yes |
| GET | `/invitations` | Any | Child: pending invitations received. Parent: all invitations sent | Yes |
| POST | `/accept/{invitation_id}` | Child | Accept and join the family | Yes |
| POST | `/reject/{invitation_id}` | Child | Reject the invitation | Yes |
| GET | `/children` | Parent | Children in the parent's family | Yes |
| GET | `/members` | Any | Everyone in the caller's family | Client method exists; no screen uses it |

### Tasks — `/api/tasks`

| Method | Path | Role | Description | Called by the app |
|---|---|---|---|---|
| POST | `/` | Parent | Create a task for a child | Yes |
| GET | `/` | Any | Child: tasks assigned to them. Parent: tasks they created. Optional `status_filter` | Yes |
| PUT | `/{task_id}` | Parent | Edit a task | No |
| POST | `/complete` | Child | Mark complete, award coins and a sticker | Yes |
| POST | `/reject/{task_id}` | Child | Reject a task | Yes |
| POST | `/schedule/{task_id}` | Child | Postpone a task to a given time | Yes |
| POST | `/accept/{task_id}` | Child | Accept a task | No |
| POST | `/verify` | Parent | Approve or reject a completion | No |
| DELETE | `/{task_id}` | Creator or assignee | Soft delete (status becomes `deleted`) | Yes |

### Location — `/api/location`

| Method | Path | Role | Description | Called by the app |
|---|---|---|---|---|
| POST | `/update` | Any | Store a location point for the caller | Yes |
| GET | `/current/{child_id}` | Parent of that child | Latest location of the child | Yes |
| GET | `/history/{child_id}` | Parent | Location points for the last `days` (default 7) | Client method exists; no screen uses it |
| POST | `/check-in` | Any | Store a check-in and notify the parent | Yes |
| GET | `/check-ins/{child_id}` | Parent of that child | Check-ins for the last `days` (default 7) | Yes |
| POST | `/geofence` | Parent | Create a safe zone for the family | Yes |
| GET | `/geofences` | Any | Safe zones of the caller's family | Yes |
| DELETE | `/geofence/{geofence_id}` | Parent | Delete a safe zone | No |

### Geofence (alternative router) — `/api/geofence`

A second, older geofence implementation: `POST /create`, `GET /list`, `POST /check`, `DELETE /{geofence_id}`. It is registered but the app does not call it. See [ARCHITECTURE.md](ARCHITECTURE.md#known-structural-issues).

### Service

| Method | Path | Description |
|---|---|---|
| GET | `/` | Name, version and status of the API |
| GET | `/health` | Returns `{"status": "healthy"}` |

---

## 6. How the project works

1. **The backend is the single gateway to data.** The app never talks to the database. Every read and write is an HTTP request to the FastAPI server, which validates it, checks the caller's token and role, and then reads or writes Firestore through the Admin SDK.
2. **One app, two experiences.** After login the app looks at the user's `role`. A parent lands on the Parent Dashboard, a child on the child's "My Dashboard". The two dashboards share the same networking and state code.
3. **Sessions are JWTs.** Login returns a token signed with `SECRET_KEY` (HS256, 30 minutes by default). The app saves it in `SharedPreferences` and sends it on every request. On the next launch the app calls `/api/auth/me`; if the token is still valid the user goes straight to their dashboard, otherwise to the login screen.
4. **A family ties accounts together.** A parent's first invitation creates a `families` document. When the child accepts, the child's `family_id` is set to that family. The backend uses this link to decide whether a parent may read a given child's location and check-ins.
5. **Tasks drive the reward loop.** The parent creates a task with a coin value. The child completes it, and the backend immediately adds the coins to the child's balance and appends one random sticker to their collection.
6. **Location is pulled, not streamed.** When the child opens **My Location**, the app reads the GPS once and posts it. The parent's screen fetches the latest stored point when opened or refreshed. There is no background tracking and no live updates.
7. **Safe-zone status is calculated on the phone.** The app downloads the family's zones and compares each zone's centre and radius with the current position to show "inside" or the distance away.

The detailed sequence for each of these is in [WORKFLOWS.md](WORKFLOWS.md).

---

## 7. Configuration

| Item | Location | Notes |
|---|---|---|
| Backend settings | `backend/.env` (template: [.env.example](../backend/.env.example)) | `SECRET_KEY`, `FIREBASE_CREDENTIALS_PATH` and `FIREBASE_DATABASE_URL` are required. Optional: `ALGORITHM`, `ACCESS_TOKEN_EXPIRE_MINUTES`, `ALLOWED_ORIGINS`, `API_HOST`, `API_PORT`, `DEBUG` |
| Firebase service-account key | `backend/firebase-credentials.json` | Not in the repository |
| Firebase Android config | `guardianlink_app/android/app/google-services.json` | Not in the repository |
| Backend address used by the app | [api_constants.dart](../guardianlink_app/lib/core/constants/api_constants.dart) | Hard-coded `baseUrl`; must be changed to the machine running the backend |
| Firestore composite indexes | Firebase console | `locations (user_id ↑, timestamp ↓)` and `check_ins (user_id ↑, timestamp ↓)` are required |

Build facts: app version `1.0.26+40`, application ID `com.guardianlink.app`, compile SDK 36, Java 11, Android Gradle Plugin 8.9.1, Kotlin 2.1.0. Release builds are currently signed with the debug key.

---

## 8. Current state and known gaps

These were found by reading the code in the repository. They explain where observed behaviour differs from the intended design.

| # | Area | What happens | Cause |
|---|---|---|---|
| 1 | Safe zones | Creating a safe zone returns HTTP 500, and the zone list is always empty | The auth dependency returns only `id`, `email` and `role` ([auth.py:101-105](../backend/app/middleware/auth.py#L101-L105)), but the location router reads `current_user["family_id"]` ([location.py:244](../backend/app/routers/location.py#L244), [location.py:270](../backend/app/routers/location.py#L270)) |
| 2 | Check-in notification | The check-in is saved but no push is sent to the parent; the child's name would also fall back to "Your child" | Same cause: `family_id` and `full_name` are not in `current_user` ([location.py:157-160](../backend/app/routers/location.py#L157-L160)) |
| 3 | Location history | `GET /api/location/history/{child_id}` answers 403 for any linked child | Same cause ([location.py:123](../backend/app/routers/location.py#L123)) |
| 4 | Push token registration | The device token is not stored | The app sends `fcm_token` in the JSON body ([api_service.dart:393](../guardianlink_app/lib/core/services/api_service.dart#L393)); the endpoint expects a query parameter ([auth.py:138-141](../backend/app/routers/auth.py#L138-L141)). It is also sent at app start, before the user has logged in |
| 5 | Firebase on Android | `Firebase.initializeApp()` cannot find its configuration, so push is disabled and the app continues without it | The Android Gradle files do not apply the `com.google.gms.google-services` plugin that reads `google-services.json` |
| 6 | Notifications in the foreground | A received message is only printed to the log | No local-notification display or tap navigation is implemented in [fcm_service.dart](../guardianlink_app/lib/core/services/fcm_service.dart) |
| 7 | Location tracking | The child's position is only updated while the child has **My Location** open | No background or periodic tracking is implemented |
| 8 | Session length | After 30 minutes requests start failing until the app is restarted and the user logs in again | No token refresh; the token lifetime is `ACCESS_TOKEN_EXPIRE_MINUTES` |
| 9 | Task completion | The API does not check that the task belongs to the caller or is still open, so repeating the call awards coins again | No ownership or status check in [tasks.py:108-176](../backend/app/routers/tasks.py#L108-L176) |
| 10 | Task "notified" messages | The app says the other party "has been notified" after rejecting or deleting a task, but nothing is sent | Only check-ins attempt a notification |
| 11 | Duplicate registration | Returns HTTP 500 instead of 400 (the message is still correct) | The 400 is caught by a generic `except` in [auth.py:56-60](../backend/app/routers/auth.py#L56-L60) |
| 12 | Tests | No working automated tests | `test/widget_test.dart` is the unmodified Flutter counter template; the backend has none |

Items 1–3 share one fix: load the user's `family_id` and `full_name` in `get_current_user`, or look the user up in the three endpoints the way `/api/family/members` already does.
