# WorkSpace Pro — DingTalk Clone
**Full-stack workplace communication app**
Flutter (frontend) + Go (backend) + PostgreSQL (database)

---

## 📁 Project Structure (paste into VS Code as-is)

```
DINGTALK/
├── backend/                          ← Go REST API server
│   ├── config/config.go              ← App config & env loader
│   ├── controllers/
│   │   ├── auth_controller.go        ← Register, Login, Logout, Me
│   │   ├── chat_controller.go        ← Chats, Messages, AI Chat
│   │   ├── meeting_controller.go     ← Meetings CRUD
│   │   ├── task_controller.go        ← Tasks CRUD + status updates
│   │   ├── attendance_controller.go  ← Check-in, Check-out, History
│   │   ├── notification_controller.go← Get, MarkRead
│   │   ├── approval_controller.go    ← Approvals CRUD
│   │   └── user_controller.go        ← Users, Status, DingTalk webhook
│   ├── middleware/middleware.go       ← JWT Auth, CORS, Logger
│   ├── models/models.go              ← All Go structs
│   ├── routes/routes.go              ← All API routes
│   ├── utils/response.go             ← JSON helpers
│   ├── .env                          ← 🔑 Edit this first!
│   ├── go.mod
│   └── main.go                       ← Server entry point
│
├── frontend/                         ← Flutter app
│   ├── lib/
│   │   ├── main.dart                 ← App entry, Splash, Shell, Nav
│   │   ├── core/
│   │   │   ├── theme/app_theme.dart  ← Colors, fonts, MaterialTheme
│   │   │   └── constants/            ← API base URL (edit this!)
│   │   ├── data/
│   │   │   ├── models/app_models.dart← All Dart data models
│   │   │   └── services/
│   │   │       ├── api_service.dart  ← All HTTP calls to backend
│   │   │       └── auth_provider.dart← Auth state (Provider)
│   │   ├── features/
│   │   │   ├── auth/screens/         ← Login & Register screen
│   │   │   ├── chat/screens/         ← Chat list + AI chat detail
│   │   │   ├── meeting/screens/      ← Meeting list + video room
│   │   │   ├── calendar/screens/     ← Monthly calendar + events
│   │   │   ├── attendance/screens/   ← Check-in/out + history
│   │   │   ├── tasks/screens/        ← Kanban tasks + approvals
│   │   │   ├── files/screens/        ← File management
│   │   │   ├── contacts/screens/     ← Contacts + org chart
│   │   │   ├── notifications/screens/← Notification center
│   │   │   └── profile/screens/      ← Profile + settings
│   │   └── shared/widgets/           ← Reusable UI components
│   └── pubspec.yaml
│
└── database/schema.sql               ← PostgreSQL schema + seed data
```

---

## 🚀 Quick Start

### 1. Setup PostgreSQL
```bash
createdb dingtalk
psql -U postgres -d dingtalk -f database/schema.sql
```

### 2. Configure Backend
Edit `backend/.env`:
```env
DB_PASSWORD=your_postgres_password
ANTHROPIC_API_KEY=sk-ant-your-key-here
JWT_SECRET=any-long-random-string
```

### 3. Run Backend
```bash
cd backend
go mod tidy
go run main.go
# ✅ Server running on http://localhost:8080
```

### 4. Configure Flutter
Edit `frontend/lib/core/constants/app_constants.dart`:
```dart
// For desktop/web:
static const String baseUrl = 'http://localhost:8080';
// For Android emulator:
static const String baseUrl = 'http://10.0.2.2:8080';
// For real device/production:
static const String baseUrl = 'https://your-domain.com';
```

### 5. Run Flutter
```bash
cd frontend
flutter pub get
flutter run -d chrome          # Web
flutter run -d android         # Android
flutter run                    # iOS
```

### 6. Login with demo account
```
Email:    demo@company.com
Password: password123
```

---

## 🔌 API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /api/auth/register | Register |
| POST | /api/auth/login | Login |
| GET  | /api/auth/me | Current user |
| GET  | /api/chats | List chats |
| GET  | /api/chats/:id/messages | Get messages |
| POST | /api/chats/:id/messages | Send message |
| POST | /api/chat/ai | AI chat (Claude) |
| GET  | /api/meetings | List meetings |
| POST | /api/meetings | Create meeting |
| GET  | /api/tasks | List tasks |
| POST | /api/tasks | Create task |
| PATCH| /api/tasks/:id/status | Update status |
| GET  | /api/attendance | History |
| POST | /api/attendance/checkin | Check in |
| POST | /api/attendance/checkout | Check out |
| GET  | /api/notifications | Get notifications |
| GET  | /api/approvals | Get approvals |
| POST | /api/approvals | Create approval |

---

## 🎨 Features

| Feature | Screen | Status |
|---------|--------|--------|
| 💬 Chat | ChatListScreen + ChatDetailScreen | ✅ |
| 🤖 AI Chat | ChatDetailScreen (AI tab) | ✅ |
| 📹 Video Meeting | MeetingScreen + MeetingRoomScreen | ✅ |
| 📅 Calendar | CalendarScreen | ✅ |
| 🕐 Attendance | AttendanceScreen | ✅ |
| ✅ Tasks | TasksScreen (Kanban) | ✅ |
| 📋 Approvals | TasksScreen (Approvals tab) | ✅ |
| 📁 Files | FilesScreen | ✅ |
| 👥 Contacts | ContactsScreen | ✅ |
| 🏢 Org Chart | ContactsScreen (Org tab) | ✅ |
| 🔔 Notifications | NotificationsScreen | ✅ |
| 👤 Profile | ProfileScreen | ✅ |
| 🔐 Auth | LoginScreen (Login + Register) | ✅ |
