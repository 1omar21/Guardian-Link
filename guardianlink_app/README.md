# GuardianLink - Flutter app

The Android app for GuardianLink. One app serves both roles: the screen shown after login depends on whether the account is a parent or a child.

## Features

### For parents
- Link children through family invitations
- View each child's latest location
- Create safe zones and see whether the child is inside them
- Receive and review safety check-ins
- Create tasks with Focus Coin rewards

### For children
- Share location and send an "I'm safe" check-in
- See the family's safe zones
- Complete tasks to earn Focus Coins and stickers

## Setup

### Prerequisites

- Flutter SDK 3.0+
- Android Studio or VS Code
- The backend running (see `../backend/README.md`)

### Steps

1. Install dependencies
```bash
flutter pub get
```

2. Add Firebase
   - Register an Android app with package name `com.guardianlink.app` in your Firebase project
   - Download `google-services.json` and place it in `android/app/`

3. Set the backend address in `lib/core/constants/api_constants.dart`

4. Run
```bash
flutter run
```

## Project structure

```
lib/
├── main.dart
├── core/
│   ├── constants/     API endpoints, theme
│   ├── providers/     Theme state
│   ├── services/      API, auth, location, push notifications
│   └── utils/
├── features/
│   ├── auth/          Login, register
│   ├── parent/        Parent dashboard, location, check-ins, family
│   └── child/         Child dashboard, location, invitations, stickers
└── models/
```

## Android permissions

- `INTERNET`, `ACCESS_NETWORK_STATE`
- `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`

## Build

```bash
flutter build apk --release
```
