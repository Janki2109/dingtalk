package websocket

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"dingtalk/middleware"

	"github.com/gorilla/websocket"
)

// ── Message structs ───────────────────────────────────────────────────────────

type SigMsg struct {
	Type         string      `json:"type"`
	FromID       string      `json:"from_id,omitempty"`
	TargetID     string      `json:"target_id,omitempty"`
	UserID       string      `json:"user_id,omitempty"`
	SDP          string      `json:"sdp,omitempty"`
	Candidate    interface{} `json:"candidate,omitempty"`
	Content      string      `json:"content,omitempty"`
	Raised       bool        `json:"raised"`
	AudioEnabled *bool       `json:"audio_enabled,omitempty"`
	VideoEnabled *bool       `json:"video_enabled,omitempty"`
	Payload      interface{} `json:"payload,omitempty"`
	Time         string      `json:"time,omitempty"`
}

type SigParticipant struct {
	UserID       string    `json:"user_id"`
	UserName     string    `json:"user_name"`
	IsHost       bool      `json:"is_host"`
	AudioEnabled bool      `json:"audio_enabled"`
	VideoEnabled bool      `json:"video_enabled"`
	HandRaised   bool      `json:"hand_raised"`
	JoinedAt     time.Time `json:"joined_at"`
}

type SigWaiting struct {
	UserID   string    `json:"user_id"`
	UserName string    `json:"user_name"`
	AskedAt  time.Time `json:"asked_at"`
}

// ── Client ────────────────────────────────────────────────────────────────────

type SigClient struct {
	UserID       string
	UserName     string
	IsHost       bool
	IsAdmitted   bool
	AudioEnabled bool
	VideoEnabled bool
	HandRaised   bool
	JoinedAt     time.Time
	RoomCode     string

	conn   *websocket.Conn
	send   chan []byte
	once   sync.Once
	closed bool
	mu     sync.Mutex
}

func (c *SigClient) write(msg SigMsg) {
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return
	}
	select {
	case c.send <- data:
	default:
	}
}

func (c *SigClient) safeClose() {
	c.once.Do(func() {
		c.mu.Lock()
		c.closed = true
		c.mu.Unlock()
		close(c.send)
	})
}

func (c *SigClient) toParticipant() SigParticipant {
	return SigParticipant{
		UserID: c.UserID, UserName: c.UserName,
		IsHost: c.IsHost, AudioEnabled: c.AudioEnabled,
		VideoEnabled: c.VideoEnabled, HandRaised: c.HandRaised,
		JoinedAt: c.JoinedAt,
	}
}

func (c *SigClient) writePump() {
	defer c.conn.Close()
	for data := range c.send {
		if err := c.conn.WriteMessage(websocket.TextMessage, data); err != nil {
			return
		}
	}
}

// ── Room ──────────────────────────────────────────────────────────────────────

type SigRoom struct {
	Code      string
	MeetingID string
	HostID    string
	StartedAt time.Time

	clients map[string]*SigClient
	waiting map[string]*SigWaiting
	mu      sync.RWMutex
	db      *sql.DB
}

func newSigRoom(code, meetingID string, db *sql.DB) *SigRoom {
	return &SigRoom{
		Code:      code,
		MeetingID: meetingID,
		StartedAt: time.Now(),
		clients:   make(map[string]*SigClient),
		waiting:   make(map[string]*SigWaiting),
		db:        db,
	}
}

func (r *SigRoom) participantList() []SigParticipant {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := []SigParticipant{}
	for _, c := range r.clients {
		if c.IsAdmitted {
			out = append(out, c.toParticipant())
		}
	}
	return out
}

func (r *SigRoom) waitingList() []SigWaiting {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := []SigWaiting{}
	for _, w := range r.waiting {
		out = append(out, *w)
	}
	return out
}

func (r *SigRoom) broadcastAdmitted(msg SigMsg, skipID string) {
	r.mu.RLock()
	targets := make([]*SigClient, 0)
	for _, c := range r.clients {
		if c.IsAdmitted && c.UserID != skipID {
			targets = append(targets, c)
		}
	}
	r.mu.RUnlock()
	for _, c := range targets {
		c.write(msg)
	}
}

func (r *SigRoom) sendTo(userID string, msg SigMsg) {
	r.mu.RLock()
	c, ok := r.clients[userID]
	r.mu.RUnlock()
	if ok {
		c.write(msg)
	}
}

// ── Hub ───────────────────────────────────────────────────────────────────────

type SigHub struct {
	rooms map[string]*SigRoom
	mu    sync.RWMutex
	db    *sql.DB
}

var GlobalSigHub *SigHub

func NewSigHub(db *sql.DB) *SigHub {
	return &SigHub{rooms: make(map[string]*SigRoom), db: db}
}

func (h *SigHub) getOrCreate(code, meetingID string) *SigRoom {
	h.mu.Lock()
	defer h.mu.Unlock()
	if r, ok := h.rooms[code]; ok {
		return r
	}
	r := newSigRoom(code, meetingID, h.db)
	h.rooms[code] = r
	return r
}

func (h *SigHub) deleteRoom(code string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.rooms, code)
}

// ── Upgrader ──────────────────────────────────────────────────────────────────

var sigUpgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

// ── HTTP Handler ──────────────────────────────────────────────────────────────

func (h *SigHub) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// JWT auth via query param (browsers cannot set WS headers)
	token := r.URL.Query().Get("token")
	if token == "" {
		auth := r.Header.Get("Authorization")
		token = strings.TrimPrefix(auth, "Bearer ")
	}
	claims, err := middleware.ValidateToken(token)
	if err != nil || claims == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	userID := claims.UserID
	userName := r.URL.Query().Get("name")
	if userName == "" {
		h.db.QueryRow(`SELECT COALESCE(name,'') FROM users WHERE id=$1`, userID).Scan(&userName)
	}

	roomCode := r.URL.Query().Get("room")
	meetingID := r.URL.Query().Get("meeting_id")

	// FIX BUG 26: never trust is_host from client — verify from DB only
	isHostParam := false
	if meetingID != "" {
		var dbOrgID string
		h.db.QueryRow(`SELECT organizer_id FROM meetings WHERE id=$1`, meetingID).Scan(&dbOrgID)
		isHostParam = dbOrgID == userID
	}

	if roomCode == "" {
		http.Error(w, `{"error":"room required"}`, http.StatusBadRequest)
		return
	}

	conn, err := sigUpgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("WS upgrade error:", err)
		return
	}

	room := h.getOrCreate(roomCode, meetingID)

	// First host to join owns the room
	isHost := isHostParam || room.HostID == userID
	if isHostParam && room.HostID == "" {
		room.HostID = userID
		if meetingID != "" {
			h.db.Exec(`UPDATE meetings SET status='ongoing' WHERE id=$1`, meetingID)
		}
	}

	client := &SigClient{
		UserID:       userID,
		UserName:     userName,
		IsHost:       isHost,
		IsAdmitted:   isHost,
		AudioEnabled: true,
		VideoEnabled: true,
		JoinedAt:     time.Now(),
		RoomCode:     roomCode,
		conn:         conn,
		send:         make(chan []byte, 256),
	}

	room.mu.Lock()
	room.clients[userID] = client
	if !client.IsAdmitted {
		room.waiting[userID] = &SigWaiting{
			UserID: userID, UserName: userName, AskedAt: time.Now(),
		}
	}
	room.mu.Unlock()

	if client.IsAdmitted {
		room.broadcastAdmitted(SigMsg{
			Type:    "participant_joined",
			Payload: client.toParticipant(),
		}, userID)
		client.write(SigMsg{Type: "participants_update", Payload: room.participantList()})
		client.write(SigMsg{Type: "waiting_update", Payload: room.waitingList()})
	} else {
		room.sendTo(room.HostID, SigMsg{
			Type:    "waiting_update",
			Payload: room.waitingList(),
		})
		client.write(SigMsg{Type: "waiting_room", Payload: map[string]string{
			"status":  "waiting",
			"message": "Waiting for the host to admit you",
		}})
	}

	if meetingID != "" {
		h.db.Exec(`
			INSERT INTO meeting_attendance (meeting_id, user_id, joined_at, status)
			VALUES ($1,$2,NOW(),'attended')
			ON CONFLICT (meeting_id, user_id) DO UPDATE SET joined_at=EXCLUDED.joined_at`,
			meetingID, userID)
	}

	go client.writePump()
	h.readPump(client, room)
}

// ── Read Pump ─────────────────────────────────────────────────────────────────

func (h *SigHub) readPump(client *SigClient, room *SigRoom) {
	defer h.handleLeave(client, room)
	client.conn.SetReadLimit(65536)

	for {
		_, raw, err := client.conn.ReadMessage()
		if err != nil {
			break
		}
		var msg SigMsg
		if json.Unmarshal(raw, &msg) != nil {
			continue
		}
		msg.FromID = client.UserID

		switch msg.Type {

		case "offer", "answer", "ice_candidate":
			if msg.TargetID != "" {
				room.sendTo(msg.TargetID, msg)
			}

		case "raise_hand":
			client.HandRaised = msg.Raised
			room.broadcastAdmitted(SigMsg{
				Type: "hand_raised",
				Payload: map[string]interface{}{
					"user_id": client.UserID,
					"raised":  msg.Raised,
				},
			}, "")

		case "chat":
			if !client.IsAdmitted {
				break
			}
			chatMsg := SigMsg{
				Type:    "chat_message",
				FromID:  client.UserID,
				Content: msg.Content,
				Time:    time.Now().Format(time.RFC3339),
				Payload: map[string]string{
					"user_id":   client.UserID,
					"user_name": client.UserName,
					"content":   msg.Content,
				},
			}
			// FIX BUG 09: skip sender to prevent duplicate message
			room.broadcastAdmitted(chatMsg, client.UserID)
			if room.MeetingID != "" {
				h.db.Exec(`INSERT INTO meeting_chat_messages (meeting_id, sender_id, content) VALUES ($1,$2,$3)`,
					room.MeetingID, client.UserID, msg.Content)
			}

		case "media_state":
			if msg.AudioEnabled != nil {
				client.AudioEnabled = *msg.AudioEnabled
			}
			if msg.VideoEnabled != nil {
				client.VideoEnabled = *msg.VideoEnabled
			}
			room.broadcastAdmitted(SigMsg{
				Type: "media_state_update",
				Payload: map[string]interface{}{
					"user_id":       client.UserID,
					"audio_enabled": client.AudioEnabled,
					"video_enabled": client.VideoEnabled,
				},
			}, client.UserID)

		case "admit_user":
			if client.UserID != room.HostID {
				break
			}
			targetID := msg.UserID
			room.mu.Lock()
			delete(room.waiting, targetID)
			if tc, ok := room.clients[targetID]; ok {
				tc.IsAdmitted = true
			}
			room.mu.Unlock()

			existing := room.participantList()
			room.sendTo(targetID, SigMsg{Type: "admitted"})
			room.sendTo(targetID, SigMsg{Type: "existing_participants", Payload: existing})

			room.mu.RLock()
			tc, exists := room.clients[targetID]
			room.mu.RUnlock()
			if exists {
				room.broadcastAdmitted(SigMsg{
					Type:    "participant_joined",
					Payload: tc.toParticipant(),
				}, targetID)
			}
			room.sendTo(room.HostID, SigMsg{Type: "waiting_update", Payload: room.waitingList()})

			if room.MeetingID != "" {
				h.db.Exec(`INSERT INTO meeting_participants (meeting_id, user_id) VALUES ($1,$2) ON CONFLICT DO NOTHING`,
					room.MeetingID, targetID)
			}

		case "reject_user":
			if client.UserID != room.HostID {
				break
			}
			targetID := msg.UserID
			room.mu.Lock()
			delete(room.waiting, targetID)
			tc, exists := room.clients[targetID]
			if exists {
				delete(room.clients, targetID)
			}
			room.mu.Unlock()
			if exists {
				tc.write(SigMsg{Type: "rejected"})
				tc.safeClose()
			}
			room.sendTo(room.HostID, SigMsg{Type: "waiting_update", Payload: room.waitingList()})
			if room.MeetingID != "" {
				h.db.Exec(`UPDATE meeting_attendance SET status='rejected' WHERE meeting_id=$1 AND user_id=$2`,
					room.MeetingID, targetID)
			}

		case "mute_user":
			if client.UserID != room.HostID {
				break
			}
			room.sendTo(msg.UserID, SigMsg{
				Type:    "muted",
				Payload: map[string]interface{}{"user_id": msg.UserID, "by_admin": true},
			})
			room.mu.Lock()
			if tc, ok := room.clients[msg.UserID]; ok {
				tc.AudioEnabled = false
			}
			room.mu.Unlock()
			f := false
			room.broadcastAdmitted(SigMsg{
				Type: "media_state_update",
				Payload: map[string]interface{}{
					"user_id": msg.UserID, "audio_enabled": f,
				},
			}, "")

		case "disable_video":
			if client.UserID != room.HostID {
				break
			}
			room.sendTo(msg.UserID, SigMsg{
				Type:    "video_disabled",
				Payload: map[string]interface{}{"user_id": msg.UserID, "by_admin": true},
			})
			room.mu.Lock()
			if tc, ok := room.clients[msg.UserID]; ok {
				tc.VideoEnabled = false
			}
			room.mu.Unlock()
			f := false
			room.broadcastAdmitted(SigMsg{
				Type: "media_state_update",
				Payload: map[string]interface{}{
					"user_id": msg.UserID, "video_enabled": f,
				},
			}, "")

		case "remove_participant":
			if client.UserID != room.HostID {
				break
			}
			targetID := msg.UserID
			room.mu.Lock()
			tc, exists := room.clients[targetID]
			if exists {
				delete(room.clients, targetID)
			}
			room.mu.Unlock()
			if exists {
				tc.write(SigMsg{Type: "removed"})
				tc.safeClose()
			}
			room.broadcastAdmitted(SigMsg{
				Type:    "participant_left",
				Payload: map[string]string{"user_id": targetID},
			}, "")
			room.sendTo(room.HostID, SigMsg{Type: "participants_update", Payload: room.participantList()})

		case "end_meeting":
			if client.UserID != room.HostID {
				break
			}
			if room.MeetingID != "" {
				h.db.Exec(`UPDATE meetings SET status='ended' WHERE id=$1`, room.MeetingID)
				h.db.Exec(`UPDATE meeting_attendance SET left_at=NOW() WHERE meeting_id=$1 AND left_at IS NULL`,
					room.MeetingID)
			}
			room.broadcastAdmitted(SigMsg{Type: "meeting_ended"}, client.UserID)
			room.mu.RLock()
			toClose := make([]*SigClient, 0, len(room.clients))
			for _, tc := range room.clients {
				if tc.UserID != client.UserID {
					toClose = append(toClose, tc)
				}
			}
			room.mu.RUnlock()
			for _, tc := range toClose {
				tc.safeClose()
			}
			h.deleteRoom(room.Code)
			return
		}
	}
}

// ── Leave handler ─────────────────────────────────────────────────────────────

func (h *SigHub) handleLeave(client *SigClient, room *SigRoom) {
	client.safeClose()

	room.mu.Lock()
	delete(room.clients, client.UserID)
	delete(room.waiting, client.UserID)
	remaining := len(room.clients)
	room.mu.Unlock()

	if room.MeetingID != "" {
		h.db.Exec(`UPDATE meeting_attendance SET left_at=NOW()
			WHERE meeting_id=$1 AND user_id=$2 AND left_at IS NULL`,
			room.MeetingID, client.UserID)
	}

	if client.IsAdmitted {
		room.broadcastAdmitted(SigMsg{
			Type:    "participant_left",
			Payload: map[string]string{"user_id": client.UserID},
		}, "")
	}

	if client.UserID == room.HostID {
		if room.MeetingID != "" {
			h.db.Exec(`UPDATE meetings SET status='ended' WHERE id=$1`, room.MeetingID)
		}
		room.broadcastAdmitted(SigMsg{Type: "meeting_ended"}, "")
		// FIX BUG 11: close all remaining connections before deleting room
		room.mu.Lock()
		for _, c := range room.clients {
			if c.UserID != client.UserID {
				c.safeClose()
			}
		}
		room.mu.Unlock()
		h.deleteRoom(room.Code)
	} else if remaining == 0 {
		h.deleteRoom(room.Code)
	}
}
