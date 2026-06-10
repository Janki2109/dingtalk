package websocket

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"

	_ "github.com/lib/pq"
)

// ── Global DB reference ───────────────────────────────────────────────────────
var DB *sql.DB

// ── Mutex for concurrent requests ────────────────────────────────────────────
var mu sync.Mutex

// ── HTTP Handlers ─────────────────────────────────────────────────────────────

// POST /api/room/create
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
		MeetingID string `json:"meeting_id"`
	}
	json.NewDecoder(r.Body).Decode(&req)
	if req.Title == "" {
		req.Title = "My Meeting"
	}
	if req.MeetingID == "" {
		req.MeetingID = generateID()
	}

	mu.Lock()
	defer mu.Unlock()

	// Check if room already exists
	var existingID string
	err := DB.QueryRow(`SELECT id FROM meeting_rooms WHERE id=$1 AND is_active=true`, req.MeetingID).Scan(&existingID)
	if err == nil {
		// Room exists — just return it
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"meeting_id":   existingID,
			"meeting_link": fmt.Sprintf("https://dingtalk-1b41.onrender.com/join/%s", existingID),
			"title":        req.Title,
			"host_name":    req.HostName,
		})
		return
	}

	// Create new room in DB
	_, err = DB.Exec(`
		INSERT INTO meeting_rooms (id, title, host_id, host_name, is_active, created_at)
		VALUES ($1, $2, $3, $4, true, NOW())
		ON CONFLICT (id) DO UPDATE SET is_active=true, host_id=$3, host_name=$4`,
		req.MeetingID, req.Title, req.HostID, req.HostName)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "failed to create room"})
		return
	}

	// Add host as participant
	DB.Exec(`
		INSERT INTO room_participants (room_id, user_id, user_name, is_host, joined_at)
		VALUES ($1, $2, $3, true, NOW())
		ON CONFLICT (room_id, user_id) DO NOTHING`,
		req.MeetingID, req.HostID, req.HostName)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"meeting_id":   req.MeetingID,
		"meeting_link": fmt.Sprintf("https://dingtalk-1b41.onrender.com/join/%s", req.MeetingID),
		"title":        req.Title,
		"host_name":    req.HostName,
	})
}

// POST /api/room/join
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

	mu.Lock()
	defer mu.Unlock()

	// Check room exists
	var hostID, hostName, title string
	err := DB.QueryRow(`
		SELECT host_id, host_name, title FROM meeting_rooms
		WHERE id=$1 AND is_active=true`, req.MeetingID).Scan(&hostID, &hostName, &title)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Meeting not found. The host may not have started yet.",
		})
		return
	}

	// If this is the host, admit directly
	if hostID == req.UserID {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"status":    "admitted",
			"host_name": hostName,
			"title":     title,
		})
		return
	}

	// Check if already admitted
	var existingParticipant string
	err = DB.QueryRow(`
		SELECT user_id FROM room_participants
		WHERE room_id=$1 AND user_id=$2`, req.MeetingID, req.UserID).Scan(&existingParticipant)
	if err == nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"status":    "admitted",
			"host_name": hostName,
			"title":     title,
		})
		return
	}

	// Add to waiting room
	DB.Exec(`
		INSERT INTO room_waiting (room_id, user_id, user_name, asked_at)
		VALUES ($1, $2, $3, NOW())
		ON CONFLICT (room_id, user_id) DO NOTHING`,
		req.MeetingID, req.UserID, req.UserName)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":    "waiting",
		"host_name": hostName,
		"title":     title,
	})
}

// GET /api/room/status?meeting_id=XXX&user_id=YYY
func CheckParticipantStatus(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	meetingID := r.URL.Query().Get("meeting_id")
	userID := r.URL.Query().Get("user_id")

	// Check if room exists
	var exists bool
	DB.QueryRow(`SELECT EXISTS(SELECT 1 FROM meeting_rooms WHERE id=$1 AND is_active=true)`,
		meetingID).Scan(&exists)
	if !exists {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "not_found"})
		return
	}

	// Check if admitted
	var participantExists bool
	DB.QueryRow(`SELECT EXISTS(SELECT 1 FROM room_participants WHERE room_id=$1 AND user_id=$2)`,
		meetingID, userID).Scan(&participantExists)
	if participantExists {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "admitted"})
		return
	}

	// Check if waiting
	var waitingExists bool
	DB.QueryRow(`SELECT EXISTS(SELECT 1 FROM room_waiting WHERE room_id=$1 AND user_id=$2)`,
		meetingID, userID).Scan(&waitingExists)
	if waitingExists {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "waiting"})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "denied"})
}

// GET /api/room/waiting?meeting_id=XXX
func GetWaitingRoom(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	meetingID := r.URL.Query().Get("meeting_id")

	// Get waiting list
	waitingRows, err := DB.Query(`
		SELECT user_id, user_name, asked_at FROM room_waiting
		WHERE room_id=$1 ORDER BY asked_at ASC`, meetingID)
	waiting := []map[string]interface{}{}
	if err == nil {
		defer waitingRows.Close()
		for waitingRows.Next() {
			var uid, uname string
			var askedAt time.Time
			waitingRows.Scan(&uid, &uname, &askedAt)
			waiting = append(waiting, map[string]interface{}{
				"user_id":   uid,
				"user_name": uname,
				"asked_at":  askedAt,
			})
		}
	}

	// Get participants list
	partRows, err := DB.Query(`
		SELECT user_id, user_name, is_host FROM room_participants
		WHERE room_id=$1 ORDER BY joined_at ASC`, meetingID)
	participants := []map[string]interface{}{}
	if err == nil {
		defer partRows.Close()
		for partRows.Next() {
			var uid, uname string
			var isHost bool
			partRows.Scan(&uid, &uname, &isHost)
			participants = append(participants, map[string]interface{}{
				"user_id":   uid,
				"user_name": uname,
				"is_host":   isHost,
			})
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"waiting":      waiting,
		"participants": participants,
	})
}

// POST /api/room/admit
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

	mu.Lock()
	defer mu.Unlock()

	if req.Action == "admit" {
		// Get user name from waiting room
		var userName string
		DB.QueryRow(`SELECT user_name FROM room_waiting WHERE room_id=$1 AND user_id=$2`,
			req.MeetingID, req.UserID).Scan(&userName)

		// Move from waiting to participants
		DB.Exec(`DELETE FROM room_waiting WHERE room_id=$1 AND user_id=$2`,
			req.MeetingID, req.UserID)
		DB.Exec(`
			INSERT INTO room_participants (room_id, user_id, user_name, is_host, joined_at)
			VALUES ($1, $2, $3, false, NOW())
			ON CONFLICT (room_id, user_id) DO NOTHING`,
			req.MeetingID, req.UserID, userName)
	} else {
		// Deny — just remove from waiting
		DB.Exec(`DELETE FROM room_waiting WHERE room_id=$1 AND user_id=$2`,
			req.MeetingID, req.UserID)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// POST /api/room/end
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

	mu.Lock()
	defer mu.Unlock()

	// Mark room inactive and clean up
	DB.Exec(`UPDATE meeting_rooms SET is_active=false WHERE id=$1`, req.MeetingID)
	DB.Exec(`DELETE FROM room_waiting WHERE room_id=$1`, req.MeetingID)
	DB.Exec(`DELETE FROM room_participants WHERE room_id=$1`, req.MeetingID)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ended"})
}

// ── Helpers ───────────────────────────────────────────────────────────────────
func generateID() string {
	b := make([]byte, 6)
	for i := range b {
		b[i] = byte(time.Now().UnixNano()>>uint(i*8)) & 0xff
	}
	chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	r := make([]byte, 6)
	for i, v := range b {
		r[i] = chars[int(v)%32]
	}
	return string(r)
}

func setCORS(w http.ResponseWriter) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type,Authorization")
}
