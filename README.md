# 💬 Flutter Chat App (Firebase Free Tier)

A fully functional, real-time chat application built using **Flutter** and **Firebase**, designed for seamless cross-platform communication with support for one-on-one and group chats.

---

## 🎯 Objective

To build a **modern**, **responsive**, and **reliable** chat application using only **Firebase’s free-tier services**, avoiding any paid services (like Firebase Storage). The app supports real-time messaging, group chats, user presence, and session persistence with smooth user experience across Android, iOS, and Web.

---

## ⚙️ Tech Stack

- **Frontend:** Flutter (Android, iOS, Web)
- **Backend:** Firebase
  - **Authentication:** Email & Password only (No Google/Anonymous login)
  - **Cloud Firestore:** User metadata, presence tracking
  - **Realtime Database:** Storing chat messages
  - **Local Storage:** `shared_preferences` or `Hive` for persistent local sessions

---

## ✅ Core Features

- 🔐 **Secure Authentication**
  - Email and Password only (no social login)
  - Custom error handling for invalid credentials
- 💬 **Real-Time Messaging**
  - Instant message delivery using Firebase Realtime Database
- 👥 **One-on-One & Group Chat**
  - Private and group conversations with typing indicators
- 👁️ **Read Receipts**
  - Single/double tick for send/read status (like WhatsApp)
- 🧠 **Typing Indicators**
  - Live updates when someone is typing
- 📶 **User Presence Detection**
  - Show online/offline status in real-time using Firestore
- 💡 **Network Resilience**
  - "No Internet" screen with automatic resume
- 💾 **Local Session Storage**
  - Auto login, session memory using local storage
- ❌ **No Media Support**
  - Text-only messaging to stay within Firebase's free tier

---

## ✨ Advanced Features

- 🔄 **Auto Sync**: Messages sync across all logged-in devices in real-time
- 🕓 **Live Status Updates**: Last seen and online status displayed for each user
- 📋 **Unread Message Badges**: Show count of unread messages per chat
- 🔍 **Search & Filter**: Quickly find users or messages
- 🛑 **Message Deletion**: Delete messages (for me/for everyone)
- 🧑‍🤝‍🧑 **Group Management**: Custom group creation with selected users
- 🧠 **Smart Scroll**: Automatically scroll to the latest message with smooth animation
- 📲 **Deep Linking Ready**: Future-ready for invite/shareable chat links

---

## 🧩 App Screens

### 1. 🔐 Login Screen
- Fields: Email, Password
- Validation and error messages
- Animated transitions

### 2. 📝 Registration Screen
- Fields: Name, Email, Password, Confirm Password
- Real-time validation
- Attractive onboarding animation

### 3. 📃 User List Screen
- Shows all users or group members
- Displays:
  - Avatar (default if none)
  - Name
  - Last message preview
  - Timestamp
  - Online/offline status
  - Search bar with animation

### 4. 💬 Chat Screen
- One-on-one and group chat support
- Displays:
  - Message bubbles (with timestamps)
  - Read/unread tick marks
  - Typing status
  - Animated message transitions

### 5. 👤 User Profile Screen
- Fields: Name, Email
- Logout option
- Responsive layout

### 6. 👨‍👩‍👧‍👦 Group Creation Screen
- Select users and name the group
- Confirmation modal before creation
- Group appears instantly in chat list

### 7. 🚫 No Internet Screen
- Auto-detected
- Informative message with reconnect animation
- Auto return to last screen once internet is back

---

## 🎨 UI & UX Design Highlights

- Smooth screen transitions using `PageRouteBuilder` or `Hero` animations
- Theme-adaptive color palette (light/dark mode ready)
- Custom animated typing indicators
- Toasts/snackbars for feedback (e.g., “Message sent”, “User is typing”)
- Lottie animations for onboarding and no-data screens

---

## 🚧 Limitations

- ❌ No media attachments (images, video, docs)
- ❌ No push notifications (can be added later)
- ❌ No voice/video calls (text-only communication)

---

## 🔐 Authentication Policy

- Only **Email & Password** login/registration
- Firebase Authentication rules applied for all reads/writes
- No Google, phone, or anonymous auth to reduce dependencies

---

## 🚀 Future Enhancements (Optional)

- Push Notifications (Firebase Cloud Messaging)
- Admin panel for user management
- Firebase Functions for moderation
- UI themes and custom avatars

---

## 📦 Project Status

> ✅ **UI & architecture completed**  
> 🚧 Code implementation in progress (message to enable code)

---

Let me know when you're ready to start coding — I can guide you through each part step-by-step or generate a production-ready codebase.

