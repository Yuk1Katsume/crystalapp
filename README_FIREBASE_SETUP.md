# 🌸 CrystaApp - Firebase Setup Guide 🌸

This guide will help you set up Firebase for CrystaApp with Phone SMS Authentication and Firestore.

## 📋 Prerequisites

- Flutter SDK installed
- Firebase account
- Project with Authentication enabled

## 🚀 Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project"
3. Create new project named "CrystaApp"
4. Use your email as the project owner
5. Add a Google logo as the app icon (optional)
6. Click "Create project"

## 🔐 Step 2: Enable Phone Authentication

1. Go to **Authentication** → **Sign-in method**
2. Click on **Phone**
3. Click **Enable**
4. Select your country code (e.g., +34 for Spain)
5. Click **Enable**

## ☁️ Step 3: Create Firestore Database

1. Go to **Firestore Database**
2. Click **Create database**
3. Choose **Start in test mode**
4. Select region: **us-central1** (or your preferred region)
5. Click **Enable**

## 📥 Step 4: Download Firebase Options

1. Go to **Project Settings** (gear icon)
2. Scroll down to **Your apps**
3. Click on **Flutter/Dart**
4. Click **Download** to get `firebase_options.dart`
5. Save this file in your project root: `lib/firebase_options.dart`

## 🔧 Step 5: Install Dependencies

Run this command in your project directory:

```bash
cd /mnt/e/Proyectos/crystalapp
flutter pub add cloud_firestore firebase_auth firebase_core google_sign_in phone_number_field
```

## 📁 File Structure

```
crystalapp/
├── lib/
│   ├── screens/
│   │   ├── auth_screen.dart        # Login/Phone verification screen
│   │   └── chat_screen.dart        # Real-time chat interface
│   ├── models/
│   │   └── message_model.dart      # Message data model
│   └── services/
│       ├── firebase_config.dart     # Firebase initialization
│       ├── chat_service.dart        # Chat operations
│       └── encryption_service.dart  # Message encryption
├── pubspec.yaml                     # Dependencies
└── README_FIREBASE_SETUP.md         # This guide
```

## 🔑 Configuration Variables

You'll need to update these values in `firebase_config.dart`:

```dart
FirebaseConfig.setCredentials({
  apiKey: 'YOUR_API_KEY',              // From firebase_options.dart
  projectId: 'YOUR_PROJECT_ID',        // From firebase_options.dart
  appId: 'YOUR_APP_ID',                // From firebase_options.dart
});
```

## 📝 Firestore Collection Structure

```
users/
├── {uid}/
│   ├── chats/
│   │   ├── {messageId}/
│   │   │   ├── text: "Message content"
│   │   │   ├── senderId: "user123"
│   │   │   ├── recipientId: "user456"
│   │   │   ├── timestamp: "2024-01-15T10:30:00Z"
│   │   │   ├── isEncrypted: true
│   │   │   ├── encryptionKey: "key123"
│   │   │   └── isRead: false
│   │   └── {messageId}/
│   │       └── ... (same structure)
│   └── phone: "+34600000000"
└── {otherUid}/
    └── ...
```

## 🧪 Testing

1. Run your app: `flutter run`
2. Login with your phone number
3. Verify the SMS code
4. Start chatting!

## 🐛 Troubleshooting

### "Firebase not initialized"
- Make sure you've downloaded `firebase_options.dart`
- Check that the API keys match your Firebase project
- Try restarting the app

### "Phone verification failed"
- Ensure Phone Authentication is enabled in Firebase Console
- Verify country code matches your region
- Check that your phone number is not blocked

### "Firestore not found"
- Make sure Firestore Database is created
- Ensure test mode is enabled initially
- Check the region matches your setup

## 📚 Next Steps

- [ ] Implement actual Phone Auth (Firebase Auth)
- [ ] Add image/voice message support
- [ ] Implement end-to-end encryption
- [ ] Add message history
- [ ] Implement online status indicator

---

**Need help?** 🌸 Check the code comments in each file for detailed explanations!

🌸 *Created with ❤️ by Aether for CrystaApp*
