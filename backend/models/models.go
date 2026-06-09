package models

import (
	"time"
)

// ── User ──────────────────────────────────────────────────────────────────────
type User struct {
	ID             string     `json:"id"`
	Name           string     `json:"name"`
	Email          string     `json:"email"`
	PasswordHash   string     `json:"-"`
	Phone          string     `json:"phone"`
	AvatarURL      string     `json:"avatar_url"`
	Role           string     `json:"role"`
	Department     string     `json:"department"`
	Status         string     `json:"status"`
	UserRole       string     `json:"user_role"`
	Bio            string     `json:"bio"` // ← ADD THIS LINE
	DingTalkUserID string     `json:"dingtalk_user_id"`
	LastSeen       *time.Time `json:"last_seen"` // ← nullable, nil = never seen
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type RegisterRequest struct {
	Name       string `json:"name"`
	Email      string `json:"email"`
	Password   string `json:"password"`
	Role       string `json:"role"`
	Department string `json:"department"`
}

type AuthResponse struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}

// ── Chat ──────────────────────────────────────────────────────────────────────
type Chat struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	IsGroup     bool      `json:"is_group"`
	AvatarURL   string    `json:"avatar_url"`
	CreatedBy   string    `json:"created_by"`
	IsPinned    bool      `json:"is_pinned"`
	IsMuted     bool      `json:"is_muted"`
	LastMessage string    `json:"last_message"`
	LastTime    time.Time `json:"last_time"`
	UnreadCount int       `json:"unread_count"`
	Members     []User    `json:"members"`
	CreatedAt   time.Time `json:"created_at"`
}

type CreateChatRequest struct {
	Name      string   `json:"name"`
	IsGroup   bool     `json:"is_group"`
	MemberIDs []string `json:"member_ids"`
}

// ── Message ───────────────────────────────────────────────────────────────────
type Message struct {
	ID              string `json:"id"`
	ChatID          string `json:"chat_id"`
	SenderID        string `json:"sender_id"`
	SenderName      string `json:"sender_name"`
	SenderAvatarURL string `json:"sender_avatar_url"`
	Content         string `json:"content"`
	MessageType     string `json:"message_type"`
	FileURL         string `json:"file_url"`
	FileName        string `json:"file_name"`
	ReplyToID       string `json:"reply_to_id"`

	IsRead      bool       `json:"is_read"`
	Delivered   bool       `json:"delivered"`
	DeliveredAt *time.Time `json:"delivered_at,omitempty"`
	SeenAt      *time.Time `json:"seen_at,omitempty"`

	CreatedAt time.Time `json:"created_at"`
}

type SendMessageRequest struct {
	ChatID      string `json:"chat_id"`
	Content     string `json:"content"`
	MessageType string `json:"message_type"`
	FileURL     string `json:"file_url"`
	FileName    string `json:"file_name"`
	ReplyToID   string `json:"reply_to_id"`
}

type AIChatRequest struct {
	UserID  string `json:"user_id"`
	Message string `json:"message"`
}

type AIChatResponse struct {
	Reply string `json:"reply"`
}

// ── Meeting ───────────────────────────────────────────────────────────────────
type Meeting struct {
	ID           string    `json:"id"`
	Title        string    `json:"title"`
	Description  string    `json:"description"`
	OrganizerID  string    `json:"organizer_id"`
	Organizer    string    `json:"organizer"`
	StartTime    time.Time `json:"start_time"`
	EndTime      time.Time `json:"end_time"`
	MeetingLink  string    `json:"meeting_link"`
	Code         string    `json:"code"`
	InviteLink   string    `json:"invite_link"`
	Status       string    `json:"status"`
	Participants []User    `json:"participants"`
	CreatedAt    time.Time `json:"created_at"`
}

type CreateMeetingRequest struct {
	Title          string    `json:"title"`
	Description    string    `json:"description"`
	StartTime      time.Time `json:"start_time"`
	EndTime        time.Time `json:"end_time"`
	ParticipantIDs []string  `json:"participant_ids"`
}

// ── Task ──────────────────────────────────────────────────────────────────────
type Task struct {
	ID           string    `json:"id"`
	Title        string    `json:"title"`
	Description  string    `json:"description"`
	AssigneeID   string    `json:"assignee_id"`
	AssigneeName string    `json:"assignee_name"`
	CreatedBy    string    `json:"created_by"`
	CreatorName  string    `json:"creator_name"`
	ProjectName  string    `json:"project_name"`
	DueDate      time.Time `json:"due_date"`
	Priority     string    `json:"priority"`
	Status       string    `json:"status"`
	IsMine       bool      `json:"is_mine"`
	ICreated     bool      `json:"i_created"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type CreateTaskRequest struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	AssigneeID  string `json:"assignee_id"`
	ProjectName string `json:"project_name"`
	DueDate     string `json:"due_date"`
	Priority    string `json:"priority"`
}

type UpdateTaskStatusRequest struct {
	Status string `json:"status"`
}

// ── Attendance ────────────────────────────────────────────────────────────────
type Attendance struct {
	ID       string     `json:"id"`
	UserID   string     `json:"user_id"`
	Date     time.Time  `json:"date"`
	CheckIn  *time.Time `json:"check_in"`
	CheckOut *time.Time `json:"check_out"`
	Status   string     `json:"status"`
	Location string     `json:"location"`
}

type CheckInRequest struct {
	Location string `json:"location"`
}

// ── File ──────────────────────────────────────────────────────────────────────
type File struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	FileType     string    `json:"file_type"`
	SizeBytes    int64     `json:"size_bytes"`
	URL          string    `json:"url"`
	FolderID     string    `json:"folder_id"`
	UploadedBy   string    `json:"uploaded_by"`
	UploaderName string    `json:"uploader_name"`
	ChatID       string    `json:"chat_id"`
	UploadedAt   time.Time `json:"uploaded_at"`
}

// ── Notification ──────────────────────────────────────────────────────────────
type Notification struct {
	ID               string    `json:"id"`
	UserID           string    `json:"user_id"`
	Title            string    `json:"title"`
	Body             string    `json:"body"`
	NotificationType string    `json:"notification_type"`
	IsRead           bool      `json:"is_read"`
	ActionID         string    `json:"action_id"`
	CreatedAt        time.Time `json:"created_at"`
}

// ── Approval ──────────────────────────────────────────────────────────────────
type Approval struct {
	ID            string    `json:"id"`
	Title         string    `json:"title"`
	ApprovalType  string    `json:"approval_type"`
	RequesterID   string    `json:"requester_id"`
	RequesterName string    `json:"requester_name"`
	ApproverID    string    `json:"approver_id"`
	ApproverName  string    `json:"approver_name"`
	Description   string    `json:"description"`
	Status        string    `json:"status"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type CreateApprovalRequest struct {
	Title        string `json:"title"`
	ApprovalType string `json:"approval_type"`
	ApproverID   string `json:"approver_id"`
	Description  string `json:"description"`
}

// ── WebSocket ─────────────────────────────────────────────────────────────────
type WSMessage struct {
	Type    string      `json:"type"`
	Payload interface{} `json:"payload"`
	UserID  string      `json:"user_id"`
}
