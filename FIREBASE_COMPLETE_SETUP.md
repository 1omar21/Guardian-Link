# Firebase Setup Guide - GuardianLink

## Complete Firebase Configuration from Scratch

This guide provides detailed step-by-step instructions for setting up Firebase for GuardianLink, including how to migrate to a new Firebase account.

---

## Table of Contents
1. [Create New Firebase Project](#1-create-new-firebase-project)
2. [Enable Required Services](#2-enable-required-services)
3. [Configure Firestore Database](#3-configure-firestore-database)
4. [Create Composite Indexes](#4-create-composite-indexes)
5. [Set Up Authentication](#5-set-up-authentication)
6. [Download Credentials](#6-download-credentials)
7. [Configure Flutter App](#7-configure-flutter-app)
8. [Create Test Accounts](#8-create-test-accounts)
9. [Verify Setup](#9-verify-setup)
10. [Migration Guide](#10-migration-guide)

---

## 1. Create New Firebase Project

### Step 1.1: Go to Firebase Console
1. Open browser and navigate to: https://console.firebase.google.com/
2. Sign in with Google account (use client's Google account for production)

### Step 1.2: Create Project
1. Click **"Add project"** or **"Create a project"**
2. Enter project name: `guardianlink` (or client's preferred name)
3. Click **Continue**

### Step 1.3: Google Analytics (Optional)
1. Toggle **"Enable Google Analytics"** (recommended for production)
2. Select or create Analytics account
3. Click **Create project**
4. Wait for project creation (30-60 seconds)

### Step 1.4: Access Project
1. Click **Continue** when project is ready
2. You'll be taken to the project dashboard

---

## 2. Enable Required Services

### Step 2.1: Enable Firestore Database
1. In left sidebar, click **"Build"** → **"Firestore Database"**
2. Click **"Create database"**
3. Select **"Start in production mode"** (we'll configure rules later)
4. Choose database location:
   - For Pakistan/Middle East: `asia-south1` (Mumbai)
   - For US: `us-central1`
   - For Europe: `europe-west1`
5. Click **Enable**
6. Wait for database creation (1-2 minutes)

### Step 2.2: Enable Authentication
1. In left sidebar, click **"Build"** → **"Authentication"**
2. Click **"Get started"**
3. Click **"Sign-in method"** tab
4. Click **"Email/Password"**
5. Toggle **"Enable"** switch
6. Click **Save**

### Step 2.3: Enable Cloud Storage (Optional)
1. In left sidebar, click **"Build"** → **"Storage"**
2. Click **"Get started"**
3. Click **"Next"** (use default rules)
4. Select same location as Firestore
5. Click **Done**

---

## 3. Configure Firestore Database

### Step 3.1: Create Collections
Go to **Firestore Database** → **Data** tab

Create these collections (they'll be auto-created when app runs, but good to know):

1. **users** - User accounts
   - Fields: `id`, `email`, `role`, `full_name`, `family_id`, `created_at`

2. **families** - Family relationships
   - Fields: `id`, `parent_id`, `children` (array), `created_at`

3. **locations** - GPS tracking data
   - Fields: `id`, `user_id`, `latitude`, `longitude`, `accuracy`, `timestamp`

4. **check_ins** - Safety check-ins
   - Fields: `id`, `user_id`, `message`, `timestamp`, `location`

5. **tasks** - Task assignments
   - Fields: `id`, `title`, `description`, `assigned_to`, `created_by`, `status`, `due_date`

### Step 3.2: Configure Security Rules
1. Click **"Rules"** tab
2. Replace default rules with:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Helper function to check if user is authenticated
    function isSignedIn() {
      return request.auth != null;
    }
    
    // Helper function to check if user owns the document
    function isOwner(userId) {
      return isSignedIn() && request.auth.uid == userId;
    }
    
    // Users collection
    match /users/{userId} {
      allow read: if isSignedIn();
      allow write: if isOwner(userId);
    }
    
    // Families collection
    match /families/{familyId} {
      allow read: if isSignedIn();
      allow write: if isSignedIn();
    }
    
    // Locations collection
    match /locations/{locationId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn();
      allow update, delete: if isOwner(resource.data.user_id);
    }
    
    // Check-ins collection
    match /check_ins/{checkInId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn();
      allow update, delete: if isOwner(resource.data.user_id);
    }
    
    // Tasks collection
    match /tasks/{taskId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn();
      allow update, delete: if isSignedIn();
    }
    
    // Family invitations collection
    match /family_invitations/{invitationId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn();
      allow update: if isSignedIn();
    }
  }
}
```

3. Click **Publish**

---

## 4. Create Composite Indexes

**CRITICAL:** These indexes are required for the app to work!

### Step 4.1: Access Indexes
1. Go to **Firestore Database** → **Indexes** tab
2. Click **"Composite"** tab

### Step 4.2: Create Index for Locations
1. Click **"Create Index"**
2. Fill in:
   - **Collection ID:** `locations`
   - **Fields to index:**
     - Field 1: `user_id` → **Ascending**
     - Field 2: `timestamp` → **Descending**
   - **Query scope:** Collection
3. Click **Create**
4. Wait for status to change from "Building" to "Enabled" (1-5 minutes)

### Step 4.3: Create Index for Check-ins
1. Click **"Create Index"**
2. Fill in:
   - **Collection ID:** `check_ins`
   - **Fields to index:**
     - Field 1: `user_id` → **Ascending**
     - Field 2: `timestamp` → **Descending**
   - **Query scope:** Collection
3. Click **Create**
4. Wait for "Enabled" status

### Step 4.4: Verify All Indexes
Both indexes should show status: **Enabled** (green checkmark)

---

## 5. Set Up Authentication

### Step 5.1: Configure Email/Password
Already done in Step 2.2, but verify:
1. Go to **Authentication** → **Sign-in method**
2. Ensure **Email/Password** is **Enabled**

### Step 5.2: Add Authorized Domains (for web)
1. Go to **Authentication** → **Settings** → **Authorized domains**
2. Add your domain if deploying web version (optional for mobile-only)

---

## 6. Download Credentials

### Step 6.1: Create Service Account
1. Click **Project Settings** (gear icon in left sidebar)
2. Go to **Service accounts** tab
3. Click **"Generate new private key"**
4. Click **Generate key** in confirmation dialog
5. A JSON file will download: `guardianlink-xxxxx-firebase-adminsdk-xxxxx.json`

### Step 6.2: Rename and Place Credentials
1. Rename downloaded file to: `firebase-credentials.json`
2. Copy to backend directory:
   ```bash
   cp ~/Downloads/guardianlink-*-firebase-adminsdk-*.json \
      "GuardianLink/backend/firebase-credentials.json"
   ```

### Step 6.3: Secure Credentials
**IMPORTANT:** Never commit this file to git!

Add to `.gitignore`:
```
backend/firebase-credentials.json
```

---

## 7. Configure Flutter App

### Step 7.1: Get Firebase Config for Android
1. In **Project Settings** → **General**
2. Scroll to **"Your apps"** section
3. Click **Android icon** to add Android app
4. Fill in:
   - **Android package name:** `com.guardianlink.app`
   - **App nickname:** GuardianLink (optional)
   - **Debug signing certificate SHA-1:** (optional, for Google Sign-In)
5. Click **Register app**

### Step 7.2: Download google-services.json
1. Click **Download google-services.json**
2. Copy file to Flutter app:
   ```bash
   cp ~/Downloads/google-services.json \
      "GuardianLink/guardianlink_app/android/app/"
   ```

### Step 7.3: Verify Firebase Configuration
Check that `google-services.json` is in:
```
guardianlink_app/android/app/google-services.json
```

---

## 8. Create Test Accounts

### Step 8.1: Create Users in Firebase Console

1. Go to **Authentication** → **Users** tab
2. Click **"Add user"**
3. Create parent account:
   - **Email:** parent@example.com
   - **Password:** (choose a strong password)
   - Click **Add user**
4. Note the **User UID** (e.g., `bgkAfoNCXr8RTWTHafSR`)
5. Repeat for child account:
   - **Email:** child@example.com
   - **Password:** (choose a strong password)
   - Note the **User UID**

### Step 8.2: Create User Documents in Firestore

1. Go to **Firestore Database** → **Data**
2. Click **"Start collection"** → Enter: `users`
3. Add parent document:
   - **Document ID:** (User UID from Authentication)
   - **Fields:**
     ```
     id: "bgkAfoNCXr8RTWTHafSR"
     email: "parent@example.com"
     role: "parent"
     full_name: "Parent Name"
     family_id: "family_001"
     created_at: (timestamp)
     ```
4. Add child document similarly with `role: "child"`

### Step 8.3: Create Family Document

1. Create `families` collection
2. Add document:
   - **Document ID:** `family_001`
   - **Fields:**
     ```
     id: "family_001"
     parent_id: "bgkAfoNCXr8RTWTHafSR"
     children: ["Y0WI4sVDoz4Xxep3fJ9m"]  (array)
     created_at: (timestamp)
     ```

---

## 9. Verify Setup

### Step 9.1: Check Firestore Rules
1. Go to **Firestore Database** → **Rules**
2. Ensure rules are published (green checkmark)

### Step 9.2: Check Indexes
1. Go to **Firestore Database** → **Indexes**
2. Both indexes should be **Enabled**

### Step 9.3: Check Authentication
1. Go to **Authentication** → **Users**
2. Should see 2 users (parent and child)

### Step 9.4: Test Backend Connection
Start the backend (see [GETTING_STARTED.md](GETTING_STARTED.md)) and open `http://localhost:8000/health`. It should return `{"status": "healthy"}`.

---

## 10. Migration Guide

### Migrating to New Firebase Account

#### Step 10.1: Export Data from Old Firebase
1. Go to old Firebase project
2. **Firestore Database** → **Import/Export**
3. Click **Export**
4. Select Cloud Storage bucket
5. Click **Export**
6. Download exported data

#### Step 10.2: Set Up New Firebase Project
Follow steps 1-7 above with new account

#### Step 10.3: Import Data to New Firebase
1. Go to new Firebase project
2. **Firestore Database** → **Import/Export**
3. Click **Import**
4. Upload exported data
5. Click **Import**

#### Step 10.4: Update Backend Credentials
1. Download new `firebase-credentials.json` (Step 6)
2. Replace old file in `backend/` directory
3. Restart backend:
   ```bash
   bash stop_backend.sh
   bash start_backend.sh
   ```

#### Step 10.5: Update Flutter App
1. Download new `google-services.json` (Step 7.2)
2. Replace old file in `guardianlink_app/android/app/`
3. Rebuild app:
   ```bash
   cd guardianlink_app
   flutter clean
   flutter build apk --release
   ```

#### Step 10.6: Recreate Indexes
Follow Step 4 to create both composite indexes in new project

#### Step 10.7: Test Migration
1. Install new APK on device
2. Login with test accounts
3. Verify all features work:
   - Location tracking
   - Check-ins
   - Tasks and rewards

---

## Troubleshooting

### Issue: "Permission denied" errors
**Solution:** Check Firestore security rules are published

### Issue: "Index required" errors
**Solution:** Ensure both composite indexes are created and **Enabled**

### Issue: "Invalid credentials" errors
**Solution:** Verify `firebase-credentials.json` is correct and in `backend/` directory

### Issue: App can't connect to Firebase
**Solution:** Check `google-services.json` is in `android/app/` directory

### Issue: Authentication fails
**Solution:** Verify Email/Password is enabled in Authentication settings

---

## Security Best Practices

1. **Never commit credentials to git**
   - Add `firebase-credentials.json` to `.gitignore`
   - Add `google-services.json` to `.gitignore`

2. **Use strong passwords** for production accounts

3. **Enable 2FA** on Firebase Console account

4. **Regularly review** Firestore security rules

5. **Monitor usage** in Firebase Console to detect anomalies

6. **Set up billing alerts** to avoid unexpected charges

7. **Backup data regularly** using Export feature

---

## Quick Reference

### Required Indexes
| Collection | Field 1 | Field 2 | Query Scope |
|------------|---------|---------|-------------|
| locations | user_id (Asc) | timestamp (Desc) | Collection |
| check_ins | user_id (Asc) | timestamp (Desc) | Collection |

### Required Files
- `backend/firebase-credentials.json` - Service account key
- `guardianlink_app/android/app/google-services.json` - Android config

---

## Support

For Firebase-specific issues:
- Firebase Documentation: https://firebase.google.com/docs
- Firebase Console: https://console.firebase.google.com/
- Firebase Support: https://firebase.google.com/support

For app-specific issues, see:
- [GETTING_STARTED.md](GETTING_STARTED.md)
