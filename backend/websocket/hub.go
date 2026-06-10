package websocket

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"
)

// ── Structs ───────────────────────────────────────────────────────────────────
type Participant struct {
	UserID   string    `json:"user_id"`
	UserName string    `json:"user_name"`
	IsHost   bool      `json:"is_host"`
	JoinedAt time.Time `json:"joined_at"`
}

type WaitingPerson struct {
	UserID   string    `json:"user_id"`
	UserName string    `json:"user_name"`
	AskedAt  time.Time `json:"asked_at"`
}

type MeetingRoom struct {
	ID           string          `json:"id"`
	Title        string          `json:"title"`
	HostID       string          `json:"host_id"`
	HostName     string          `json:"host_name"`
	MeetingLink  string          `json:"meeting_link"`
	Participants []Participant   `json:"participants"`
	WaitingRoom  []WaitingPerson `json:"waiting_room"`
	CreatedAt    time.Time       `json:"created_at"`
	IsActive     bool            `json:"is_active"`
	mu           sync.RWMutex
}

// ── Hub ───────────────────────────────────────────────────────────────────────
type Hub struct {
	Rooms map[string]*MeetingRoom
	mu    sync.RWMutex
}

var GlobalHub = &Hub{Rooms: make(map[string]*MeetingRoom)}

func (h *Hub) CreateRoom(hostID, hostName, title, roomID string) *MeetingRoom {
	// Use the meeting code from Jitsi so the room ID matches the meeting code
	room := &MeetingRoom{
		ID:       roomID,
		Title:    title,
		HostID:   hostID,
		HostName: hostName,
		// ✅ FIXED: use Render URL not localhost
		MeetingLink: fmt.Sprintf("https://dingtalk.onrender.com/join/%s", roomID),
		Participants: []Participant{
			{UserID: hostID, UserName: hostName, IsHost: true, JoinedAt: time.Now()},
		},
		WaitingRoom: []WaitingPerson{},
		CreatedAt:   time.Now(),
		IsActive:    true,
	}
	h.mu.Lock()
	h.Rooms[roomID] = room
	h.mu.Unlock()
	return room
}

func (h *Hub) GetRoom(id string) (*MeetingRoom, bool) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	r, ok := h.Rooms[id]
	return r, ok
}

func (h *Hub) DeleteRoom(id string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.Rooms, id)
}

func (r *MeetingRoom) AddToWaiting(userID, userName string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	// Already in waiting room
	for _, p := range r.WaitingRoom {
		if p.UserID == userID {
			return
		}
	}
	// Already admitted
	for _, p := range r.Participants {
		if p.UserID == userID {
			return
		}
	}
	r.WaitingRoom = append(r.WaitingRoom, WaitingPerson{
		UserID: userID, UserName: userName, AskedAt: time.Now(),
	})
}

func (r *MeetingRoom) Admit(userID string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	for i, p := range r.WaitingRoom {
		if p.UserID == userID {
			r.WaitingRoom = append(r.WaitingRoom[:i], r.WaitingRoom[i+1:]...)
			r.Participants = append(r.Participants, Participant{
				UserID: userID, UserName: p.UserName,
				IsHost: false, JoinedAt: time.Now(),
			})
			return true
		}
	}
	return false
}

func (r *MeetingRoom) Deny(userID string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	for i, p := range r.WaitingRoom {
		if p.UserID == userID {
			r.WaitingRoom = append(r.WaitingRoom[:i], r.WaitingRoom[i+1:]...)
			return true
		}
	}
	return false
}

func (r *MeetingRoom) CheckStatus(userID string) string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	for _, p := range r.Participants {
		if p.UserID == userID {
			return "admitted"
		}
	}
	for _, p := range r.WaitingRoom {
		if p.UserID == userID {
			return "waiting"
		}
	}
	return "denied"
}

func (r *MeetingRoom) RemoveParticipant(userID string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for i, p := range r.Participants {
		if p.UserID == userID {
			r.Participants = append(r.Participants[:i], r.Participants[i+1:]...)
			return
		}
	}
}

// ── HTTP Handlers ─────────────────────────────────────────────────────────────

// POST /api/room/create
// Called by admin when they start a meeting — creates the in-memory room
func CreateInstantMeeting(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
	var req struct {
		HostID    string `json:"host_id"`
		HostName  string `json:"host_name"`
		Title     string `json:"title"`
		MeetingID string `json:"meeting_id"` // pass the Jitsi code so room ID matches
	}
	json.NewDecoder(r.Body).Decode(&req)
	if req.Title == "" {
		req.Title = "My Meeting"
	}
	if req.MeetingID == "" {
		req.MeetingID = generateID()
	}

	// If room already exists (host rejoining), just return it
	if existing, ok := GlobalHub.GetRoom(req.MeetingID); ok {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"meeting_id":   existing.ID,
			"meeting_link": existing.MeetingLink,
			"title":        existing.Title,
			"host_name":    existing.HostName,
		})
		return
	}

	room := GlobalHub.CreateRoom(req.HostID, req.HostName, req.Title, req.MeetingID)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"meeting_id":   room.ID,
		"meeting_link": room.MeetingLink,
		"title":        room.Title,
		"host_name":    room.HostName,
	})
}

// POST /api/room/join
// Called by user when they want to join — puts them in waiting room
func JoinWaitingRoom(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
	var req struct {
		MeetingID string `json:"meeting_id"`
		UserID    string `json:"user_id"`
		UserName  string `json:"user_name"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	room, ok := GlobalHub.GetRoom(req.MeetingID)
	if !ok {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Meeting not found. The host may not have started yet.",
		})
		return
	}

	// If host is joining their own room, admit directly
	if room.HostID == req.UserID {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"status":    "admitted",
			"host_name": room.HostName,
			"title":     room.Title,
		})
		return
	}

	room.AddToWaiting(req.UserID, req.UserName)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":    "waiting",
		"host_name": room.HostName,
		"title":     room.Title,
	})
}

// GET /api/room/status?meeting_id=XXX&user_id=YYY
// Polled by user every 3 seconds to check if they've been admitted
func CheckParticipantStatus(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	meetingID := r.URL.Query().Get("meeting_id")
	userID := r.URL.Query().Get("user_id")

	room, ok := GlobalHub.GetRoom(meetingID)
	if !ok {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "not_found"})
		return
	}

	status := room.CheckStatus(userID)
	room.mu.RLock()
	defer room.mu.RUnlock()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":       status,
		"meeting_id":   meetingID,
		"title":        room.Title,
		"host_name":    room.HostName,
		"participants": room.Participants,
	})
}

// GET /api/room/waiting?meeting_id=XXX
// Polled by admin every 3 seconds to see who is in the waiting room
func GetWaitingRoom(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	// ✅ FIXED: use query param instead of path parsing
	meetingID := r.URL.Query().Get("meeting_id")

	room, ok := GlobalHub.GetRoom(meetingID)
	if !ok {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"waiting":      []interface{}{},
			"participants": []interface{}{},
		})
		return
	}

	room.mu.RLock()
	defer room.mu.RUnlock()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"waiting":      room.WaitingRoom,
		"participants": room.Participants,
		"title":        room.Title,
		"host_name":    room.HostName,
	})
}

// POST /api/room/admit
// Called by admin to admit or deny a user from the waiting room
func AdmitParticipant(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
	var req struct {
		MeetingID string `json:"meeting_id"`
		UserID    string `json:"user_id"`
		Action    string `json:"action"` // "admit" or "deny"
	}
	json.NewDecoder(r.Body).Decode(&req)

	room, ok := GlobalHub.GetRoom(req.MeetingID)
	if !ok {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "room not found"})
		return
	}

	if req.Action == "admit" {
		room.Admit(req.UserID)
	} else {
		room.Deny(req.UserID)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// POST /api/room/end
// Called by admin when they end the meeting
func EndMeeting(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
	var req struct {
		MeetingID string `json:"meeting_id"`
	}
	json.NewDecoder(r.Body).Decode(&req)
	GlobalHub.DeleteRoom(req.MeetingID)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ended"})
}

// ── Helpers ───────────────────────────────────────────────────────────────────
func generateID() string {
	b := make([]byte, 6)
	rand.Read(b)
	chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	r := make([]byte, 11)
	r[0] = chars[b[0]%32]
	r[1] = chars[b[1]%32]
	r[2] = chars[b[2]%32]
	r[3] = '-'
	r[4] = chars[b[3]%32]
	r[5] = chars[b[4]%32]
	r[6] = chars[b[5]%32]
	r[7] = '-'
	r[8] = chars[(b[0]+b[3])%32]
	r[9] = chars[(b[1]+b[4])%32]
	r[10] = chars[(b[2]+b[5])%32]
	return string(r)
}

func setCORS(w http.ResponseWriter) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type,Authorization")
}

func splitPath(path string) []string {
	return strings.Split(strings.Trim(path, "/"), "/")
}
