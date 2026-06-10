package routes

import (
	"database/sql"
	"net/http"

	"dingtalk/controllers"
	"dingtalk/middleware"
	wsig "dingtalk/websocket"
)

func Setup(db *sql.DB) http.Handler {
	mux := http.NewServeMux()

	auth := controllers.NewAuthController(db)
	chat := controllers.NewChatController(db)
	meet := controllers.NewMeetingController(db)
	task := controllers.NewTaskController(db)
	attend := controllers.NewAttendanceController(db)
	notif := controllers.NewNotificationController(db)
	approv := controllers.NewApprovalController(db)
	user := controllers.NewUserController(db)
	file := controllers.NewFileController(db)
	upload := controllers.NewUploadController()

	// ── Public ────────────────────────────────────────────────────────────────
	mux.HandleFunc("POST /api/auth/register", auth.Register)
	mux.HandleFunc("POST /api/auth/login", auth.Login)
	mux.HandleFunc("POST /api/webhook/dingtalk", user.DingTalkWebhook)

	// ── Protected ─────────────────────────────────────────────────────────────
	protected := http.NewServeMux()

	// Auth
	protected.HandleFunc("GET  /api/auth/me", auth.Me)
	protected.HandleFunc("POST /api/auth/logout", auth.Logout)
	protected.HandleFunc("POST /api/auth/change-password", auth.ChangePassword)
	protected.HandleFunc("PUT  /api/auth/profile", auth.UpdateProfile)

	// Users
	protected.HandleFunc("GET   /api/users", user.GetUsers)
	protected.HandleFunc("PATCH /api/users/status", user.UpdateStatus)

	// Chats
	protected.HandleFunc("GET  /api/chats", chat.GetChats)
	protected.HandleFunc("POST /api/chats", chat.CreateChat)
	protected.HandleFunc("GET  /api/chats/{id}/messages", chat.GetMessages)
	protected.HandleFunc("POST /api/chats/{id}/messages", chat.SendMessage)
	protected.HandleFunc("PATCH  /api/chats/{id}/read", chat.MarkChatRead)
	protected.HandleFunc("DELETE /api/chats/{id}", chat.DeleteChat)
	protected.HandleFunc("POST /api/chat/ai", chat.AIChat)

	// Meetings
	protected.HandleFunc("GET    /api/meetings", meet.GetMeetings)
	protected.HandleFunc("POST   /api/meetings", meet.CreateMeeting)
	protected.HandleFunc("POST   /api/meetings/request", meet.RequestMeeting)
	protected.HandleFunc("PATCH  /api/meetings/{id}/status", meet.UpdateStatus)
	protected.HandleFunc("POST   /api/meetings/{id}/invite", meet.InviteParticipants)
	protected.HandleFunc("GET    /api/meetings/{id}/participants", meet.GetParticipants)
	protected.HandleFunc("DELETE /api/meetings/{id}/participants/{userId}", meet.RemoveParticipant)

	// Tasks
	protected.HandleFunc("GET   /api/tasks", task.GetTasks)
	protected.HandleFunc("POST  /api/tasks", task.CreateTask)
	protected.HandleFunc("PATCH /api/tasks/{id}/status", task.UpdateStatus)

	// Attendance
	protected.HandleFunc("GET  /api/attendance", attend.GetHistory)
	protected.HandleFunc("POST /api/attendance/checkin", attend.CheckIn)
	protected.HandleFunc("POST /api/attendance/checkout", attend.CheckOut)

	// Notifications
	protected.HandleFunc("GET   /api/notifications", notif.GetNotifications)
	protected.HandleFunc("PATCH /api/notifications/{id}/read", notif.MarkRead)
	protected.HandleFunc("POST  /api/notifications/read-all", notif.MarkAllRead)

	// Approvals
	protected.HandleFunc("GET   /api/approvals", approv.GetApprovals)
	protected.HandleFunc("POST  /api/approvals", approv.CreateApproval)
	protected.HandleFunc("PATCH /api/approvals/{id}/status", approv.UpdateStatus)

	// Files
	protected.HandleFunc("GET    /api/files", file.GetFiles)
	protected.HandleFunc("POST   /api/files", file.UploadFile)
	protected.HandleFunc("DELETE /api/files/{id}", file.DeleteFile)

	// Upload (multipart)
	protected.HandleFunc("POST /api/upload", upload.Upload)

	// Mount protected
	mux.Handle("/api/auth/me", middleware.Auth(protected))
	mux.Handle("/api/auth/logout", middleware.Auth(protected))
	mux.Handle("/api/auth/change-password", middleware.Auth(protected))
	mux.Handle("/api/auth/profile", middleware.Auth(protected))
	mux.Handle("/api/users", middleware.Auth(protected))
	mux.Handle("/api/users/", middleware.Auth(protected))
	mux.Handle("/api/chats", middleware.Auth(protected))
	mux.Handle("/api/chats/", middleware.Auth(protected))
	mux.Handle("/api/chat/", middleware.Auth(protected))
	mux.Handle("/api/meetings", middleware.Auth(protected))
	mux.Handle("/api/meetings/", middleware.Auth(protected))
	mux.Handle("/api/tasks", middleware.Auth(protected))
	mux.Handle("/api/tasks/", middleware.Auth(protected))
	mux.Handle("/api/attendance", middleware.Auth(protected))
	mux.Handle("/api/attendance/", middleware.Auth(protected))
	mux.Handle("/api/notifications", middleware.Auth(protected))
	mux.Handle("/api/notifications/", middleware.Auth(protected))
	mux.Handle("/api/approvals", middleware.Auth(protected))
	mux.Handle("/api/approvals/", middleware.Auth(protected))
	mux.Handle("/api/files", middleware.Auth(protected))
	mux.Handle("/api/files/", middleware.Auth(protected))
	mux.Handle("/api/upload", middleware.Auth(protected))

	// Meeting by code — registered directly to avoid route conflict
	mux.HandleFunc("GET /api/meetings/bycode/{code}", func(w http.ResponseWriter, r *http.Request) {
		middleware.Auth(http.HandlerFunc(meet.GetMeetingByCode)).ServeHTTP(w, r)
	})

	// Serve uploaded files (no auth required — URLs are unguessable by timestamp)
	mux.Handle("/uploads/", http.StripPrefix("/uploads/", http.FileServer(http.Dir("uploads"))))

	// WebSocket meeting signaling (auth via ?token= query param)
	mux.Handle("/ws/meeting", wsig.GlobalSigHub)

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"status":"ok","service":"WorkSpace Pro API"}`))
	})

	return middleware.Logger(middleware.CORS(mux))
}