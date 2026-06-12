package routes

import (
	"database/sql"
	"net/http"
	"strings"

	"dingtalk/controllers"
	"dingtalk/middleware"
	"dingtalk/websocket"
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

	// helper: inline auth wrapper
	withAuth := func(h http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
				http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
				return
			}
			claims, err := middleware.ValidateToken(strings.TrimPrefix(authHeader, "Bearer "))
			if err != nil {
				http.Error(w, `{"error":"invalid token"}`, http.StatusUnauthorized)
				return
			}
			r.Header.Set("X-User-ID", claims.UserID)
			r.Header.Set("X-User-Email", claims.Email)
			h(w, r)
		}
	}

	// ── Public ────────────────────────────────────────────────────────────────
	mux.HandleFunc("POST /api/auth/register", auth.Register)
	mux.HandleFunc("POST /api/auth/login", auth.Login)
	mux.HandleFunc("POST /api/webhook/dingtalk", user.DingTalkWebhook)

	// ── WebSocket ─────────────────────────────────────────────────────────────
	mux.Handle("/ws/meeting", websocket.GlobalSigHub)
	mux.Handle("/ws", websocket.GlobalSigHub)

	// ── Health ────────────────────────────────────────────────────────────────
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"status":"ok","service":"WorkSpace Pro API"}`))
	})

	// ── Auth ──────────────────────────────────────────────────────────────────
	mux.HandleFunc("GET /api/auth/me", withAuth(auth.Me))
	mux.HandleFunc("POST /api/auth/logout", withAuth(auth.Logout))
	mux.HandleFunc("POST /api/auth/change-password", withAuth(auth.ChangePassword))
	mux.HandleFunc("PUT /api/auth/profile", withAuth(auth.UpdateProfile))

	// ── Users ─────────────────────────────────────────────────────────────────
	mux.HandleFunc("GET /api/users", withAuth(user.GetUsers))
	mux.HandleFunc("PATCH /api/users/status", withAuth(user.UpdateStatus))

	// ── Chats ─────────────────────────────────────────────────────────────────
	mux.HandleFunc("GET /api/chats", withAuth(chat.GetChats))
	mux.HandleFunc("POST /api/chats", withAuth(chat.CreateChat))
	mux.HandleFunc("GET /api/chats/{id}/messages", withAuth(chat.GetMessages))
	mux.HandleFunc("POST /api/chats/{id}/messages", withAuth(chat.SendMessage))
	mux.HandleFunc("PATCH /api/chats/{id}/read", withAuth(chat.MarkChatRead))
	mux.HandleFunc("DELETE /api/chats/{id}", withAuth(chat.DeleteChat))
	mux.HandleFunc("POST /api/chat/ai", withAuth(chat.AIChat))

	// ── Meetings ──────────────────────────────────────────────────────────────
	mux.HandleFunc("GET /api/meetings", withAuth(meet.GetMeetings))
	mux.HandleFunc("POST /api/meetings", withAuth(meet.CreateMeeting))
	mux.HandleFunc("GET /api/meetings/code/{code}", withAuth(meet.GetMeetingByCode))
	mux.HandleFunc("DELETE /api/meetings/{id}", withAuth(meet.DeleteMeeting))
	mux.HandleFunc("PATCH /api/meetings/{id}/status", withAuth(meet.UpdateStatus))
	mux.HandleFunc("POST /api/meetings/{id}/invite", withAuth(meet.InviteParticipants))
	mux.HandleFunc("GET /api/meetings/{id}/participants", withAuth(meet.GetParticipants))
	mux.HandleFunc("DELETE /api/meetings/{id}/participants/{userId}", withAuth(meet.RemoveParticipant))

	// ── Tasks ─────────────────────────────────────────────────────────────────
	mux.HandleFunc("GET /api/tasks", withAuth(task.GetTasks))
	mux.HandleFunc("POST /api/tasks", withAuth(task.CreateTask))
	mux.HandleFunc("PATCH /api/tasks/{id}/status", withAuth(task.UpdateStatus))

	// ── Attendance ────────────────────────────────────────────────────────────
	mux.HandleFunc("GET /api/attendance", withAuth(attend.GetHistory))
	mux.HandleFunc("POST /api/attendance/checkin", withAuth(attend.CheckIn))
	mux.HandleFunc("POST /api/attendance/checkout", withAuth(attend.CheckOut))

	// ── Notifications ─────────────────────────────────────────────────────────
	mux.HandleFunc("GET /api/notifications", withAuth(notif.GetNotifications))
	mux.HandleFunc("PATCH /api/notifications/{id}/read", withAuth(notif.MarkRead))
	mux.HandleFunc("POST /api/notifications/read-all", withAuth(notif.MarkAllRead))

	// ── Approvals ─────────────────────────────────────────────────────────────
	mux.HandleFunc("GET /api/approvals", withAuth(approv.GetApprovals))
	mux.HandleFunc("POST /api/approvals", withAuth(approv.CreateApproval))
	mux.HandleFunc("PATCH /api/approvals/{id}/status", withAuth(approv.UpdateStatus))

	// ── Files ─────────────────────────────────────────────────────────────────
	mux.HandleFunc("GET /api/files", withAuth(file.GetFiles))
	mux.HandleFunc("POST /api/files", withAuth(file.UploadFile))
	mux.HandleFunc("DELETE /api/files/{id}", withAuth(file.DeleteFile))

	// ── Upload ────────────────────────────────────────────────────────────────
	mux.HandleFunc("POST /api/upload", withAuth(upload.Upload))

	// ── Static files ──────────────────────────────────────────────────────────
	mux.Handle("/uploads/", http.StripPrefix("/uploads/", http.FileServer(http.Dir("uploads"))))

	return middleware.Logger(middleware.CORS(mux))
}
