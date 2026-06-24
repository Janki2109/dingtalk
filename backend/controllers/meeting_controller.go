package controllers

import (
	"database/sql"
	"fmt"
	"math/rand"
	"net/http"
	"strings"
	"time"

	"dingtalk/models"
	"dingtalk/utils"
)

type MeetingController struct{ DB *sql.DB }

func NewMeetingController(db *sql.DB) *MeetingController {
	return &MeetingController{DB: db}
}

// FIX BUG 01: use local rand source — no global state, no data race
func generateCode() string {
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	b := make([]byte, 6)
	for i := range b {
		b[i] = chars[r.Intn(len(chars))]
	}
	return string(b)
}

func (c *MeetingController) notifyMeeting(userID, title, body, meetingID string) {
	c.DB.Exec(`INSERT INTO notifications (user_id, title, body, notification_type, action_id)
		VALUES ($1, $2, $3, 'meeting', $4)`, userID, title, body, meetingID)
}

func (c *MeetingController) GetMeetings(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	rows, err := c.DB.Query(`
		SELECT m.id, m.title, COALESCE(m.description,''),
		       m.organizer_id, COALESCE(u.name,''),
		       m.start_time, m.end_time,
		       COALESCE(m.meeting_link,''),
		       COALESCE(m.code,''),
		       COALESCE(m.status,'upcoming'),
		       m.created_at
		FROM meetings m
		LEFT JOIN users u ON u.id = m.organizer_id
		WHERE m.organizer_id = $1
		   OR EXISTS (
		      SELECT 1 FROM meeting_participants mp
		      WHERE mp.meeting_id = m.id AND mp.user_id = $1
		   )
		ORDER BY m.start_time DESC`, userID)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer rows.Close()

	var meetings []map[string]interface{}
	for rows.Next() {
		var id, title, desc, orgID, orgName, link, code, status string
		var start, end, created time.Time
		if err := rows.Scan(&id, &title, &desc, &orgID, &orgName,
			&start, &end, &link, &code, &status, &created); err != nil {
			continue
		}

		pRows, _ := c.DB.Query(`
			SELECT u.id, COALESCE(u.name,''), COALESCE(u.avatar_url,''), COALESCE(u.status,'offline')
			FROM meeting_participants mp
			JOIN users u ON u.id = mp.user_id
			WHERE mp.meeting_id = $1`, id)
		var parts []map[string]interface{}
		if pRows != nil {
			for pRows.Next() {
				var pID, pName, pAvatar, pStatus string
				pRows.Scan(&pID, &pName, &pAvatar, &pStatus)
				parts = append(parts, map[string]interface{}{
					"id": pID, "name": pName, "avatar_url": pAvatar, "status": pStatus,
				})
			}
			pRows.Close()
		}
		if parts == nil {
			parts = []map[string]interface{}{}
		}

		jitsiLink := fmt.Sprintf("https://meet.jit.si/WorkspacePro-%s", code)
		meetings = append(meetings, map[string]interface{}{
			"id": id, "title": title, "description": desc,
			"organizer_id": orgID, "organizer": orgName,
			"start_time": start, "end_time": end,
			"meeting_link": link, "code": code,
			"invite_link": jitsiLink,
			"status":      status, "created_at": created,
			"participants": parts,
		})
	}
	if meetings == nil {
		meetings = []map[string]interface{}{}
	}
	utils.OK(w, meetings)
}

func (c *MeetingController) CreateMeeting(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var req models.CreateMeetingRequest
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}
	if req.Title == "" {
		req.Title = "Meeting"
	}

	// FIX BUG 12: validate end time is after start time
	if !req.EndTime.IsZero() && !req.StartTime.IsZero() && !req.EndTime.After(req.StartTime) {
		utils.BadRequest(w, "end_time must be after start_time")
		return
	}

	code := generateCode()
	for {
		var exists int
		c.DB.QueryRow(`SELECT COUNT(*) FROM meetings WHERE code=$1`, code).Scan(&exists)
		if exists == 0 {
			break
		}
		code = generateCode()
	}

	jitsiLink := fmt.Sprintf("https://meet.jit.si/WorkspacePro-%s", code)

	var id, title, desc, link, codeOut, status string
	var start, end, created time.Time

	err := c.DB.QueryRow(`
		INSERT INTO meetings (title, description, organizer_id, start_time, end_time,
		                      meeting_link, code, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, 'upcoming')
		RETURNING id, title, COALESCE(description,''), start_time, end_time,
		          COALESCE(meeting_link,''), COALESCE(code,''), status, created_at`,
		req.Title, req.Description, userID, req.StartTime, req.EndTime, jitsiLink, code,
	).Scan(&id, &title, &desc, &start, &end, &link, &codeOut, &status, &created)
	if err != nil {
		utils.InternalError(w, err)
		return
	}

	var orgName string
	c.DB.QueryRow(`SELECT COALESCE(name,'') FROM users WHERE id=$1`, userID).Scan(&orgName)

	var participants []map[string]interface{}
	for _, pid := range req.ParticipantIDs {
		if pid == userID {
			continue
		}
		c.DB.Exec(`INSERT INTO meeting_participants (meeting_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, id, pid)
		body := fmt.Sprintf("%s invited you · Code: %s · %s", orgName, codeOut, jitsiLink)
		c.notifyMeeting(pid, "Meeting Invite: "+title, body, id)
		var pName, pAvatar string
		c.DB.QueryRow(`SELECT COALESCE(name,''), COALESCE(avatar_url,'') FROM users WHERE id=$1`, pid).Scan(&pName, &pAvatar)
		participants = append(participants, map[string]interface{}{
			"id": pid, "name": pName, "avatar_url": pAvatar,
		})
	}
	if participants == nil {
		participants = []map[string]interface{}{}
	}

	utils.Created(w, map[string]interface{}{
		"id": id, "title": title, "description": desc,
		"organizer_id": userID, "organizer": orgName,
		"start_time": start, "end_time": end,
		"meeting_link": link, "code": codeOut,
		"invite_link": jitsiLink,
		"status":      status, "created_at": created,
		"participants": participants,
	})
}

func (c *MeetingController) GetMeetingByCode(w http.ResponseWriter, r *http.Request) {
	code := r.PathValue("code")
	if code == "" {
		parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
		for i, p := range parts {
			if p == "code" && i+1 < len(parts) {
				code = parts[i+1]
				break
			}
		}
	}
	if code == "" {
		utils.BadRequest(w, "missing code")
		return
	}

	var id, title, desc, orgID, orgName, link, codeOut, status string
	var start, end, created time.Time

	err := c.DB.QueryRow(`
		SELECT m.id, m.title, COALESCE(m.description,''),
		       m.organizer_id, COALESCE(u.name,''),
		       m.start_time, m.end_time,
		       COALESCE(m.meeting_link,''),
		       COALESCE(m.code,''),
		       COALESCE(m.status,'upcoming'),
		       m.created_at
		FROM meetings m
		LEFT JOIN users u ON u.id = m.organizer_id
		WHERE UPPER(m.code) = UPPER($1)`, code,
	).Scan(&id, &title, &desc, &orgID, &orgName, &start, &end, &link, &codeOut, &status, &created)

	if err == sql.ErrNoRows {
		utils.Error(w, http.StatusNotFound, "meeting not found")
		return
	}
	if err != nil {
		utils.InternalError(w, err)
		return
	}

	jitsiLink := fmt.Sprintf("https://meet.jit.si/WorkspacePro-%s", codeOut)

	// FIX BUG 17: fetch real participants instead of hardcoding empty array
	pRows, _ := c.DB.Query(`
		SELECT u.id, COALESCE(u.name,''), COALESCE(u.avatar_url,''), COALESCE(u.status,'offline')
		FROM meeting_participants mp
		JOIN users u ON u.id = mp.user_id
		WHERE mp.meeting_id = $1`, id)
	var participants []map[string]interface{}
	if pRows != nil {
		for pRows.Next() {
			var pID, pName, pAvatar, pStatus string
			pRows.Scan(&pID, &pName, &pAvatar, &pStatus)
			participants = append(participants, map[string]interface{}{
				"id": pID, "name": pName, "avatar_url": pAvatar, "status": pStatus,
			})
		}
		pRows.Close()
	}
	if participants == nil {
		participants = []map[string]interface{}{}
	}

	utils.OK(w, map[string]interface{}{
		"id": id, "title": title, "description": desc,
		"organizer_id": orgID, "organizer": orgName,
		"start_time": start, "end_time": end,
		"meeting_link": link, "code": codeOut,
		"invite_link": jitsiLink,
		"status":      status, "created_at": created,
		"participants": participants,
	})
}

func (c *MeetingController) GetByCode(w http.ResponseWriter, r *http.Request) {
	c.GetMeetingByCode(w, r)
}

func (c *MeetingController) DeleteMeeting(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	meetID := r.PathValue("id")
	if meetID == "" {
		parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
		for i, p := range parts {
			if p == "meetings" && i+1 < len(parts) {
				next := parts[i+1]
				if next != "code" && next != "request" {
					meetID = next
					break
				}
			}
		}
	}
	if meetID == "" {
		utils.BadRequest(w, "missing meeting id")
		return
	}

	// FIX BUG 30: admin can only delete meetings in their own domain
	var orgID, userDomain, meetingDomain string
	var isAdmin bool
	c.DB.QueryRow(`SELECT organizer_id FROM meetings WHERE id=$1`, meetID).Scan(&orgID)
	c.DB.QueryRow(`SELECT LOWER(user_role)='admin', COALESCE(domain,'') FROM users WHERE id=$1`, userID).Scan(&isAdmin, &userDomain)
	c.DB.QueryRow(`SELECT COALESCE(u.domain,'') FROM meetings m JOIN users u ON u.id=m.organizer_id WHERE m.id=$1`, meetID).Scan(&meetingDomain)

	if orgID != userID && (!isAdmin || userDomain != meetingDomain) {
		utils.Error(w, http.StatusForbidden, "only organizer or admin of the same domain can delete meetings")
		return
	}

	c.DB.Exec(`DELETE FROM meeting_participants WHERE meeting_id=$1`, meetID)
	c.DB.Exec(`DELETE FROM meeting_attendance WHERE meeting_id=$1`, meetID)
	c.DB.Exec(`DELETE FROM notifications WHERE action_id=$1`, meetID)

	result, err := c.DB.Exec(`DELETE FROM meetings WHERE id=$1`, meetID)
	if err != nil {
		utils.InternalError(w, err)
		return
	}

	rows, _ := result.RowsAffected()
	if rows == 0 {
		utils.Error(w, http.StatusNotFound, "meeting not found")
		return
	}

	utils.OK(w, map[string]string{"message": "meeting deleted"})
}

func (c *MeetingController) UpdateStatus(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	meetID := r.PathValue("id")
	if meetID == "" {
		parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
		for i, p := range parts {
			if p == "meetings" && i+1 < len(parts) {
				meetID = parts[i+1]
				break
			}
		}
	}

	// FIX BUG 04: only organizer can update status
	var orgID string
	c.DB.QueryRow(`SELECT organizer_id FROM meetings WHERE id=$1`, meetID).Scan(&orgID)
	if orgID != userID {
		utils.Error(w, http.StatusForbidden, "only the organizer can update meeting status")
		return
	}

	var req struct {
		Status string `json:"status"`
	}
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}

	// FIX BUG 02: validate status against allowed values only
	allowed := map[string]bool{"upcoming": true, "ongoing": true, "ended": true}
	if !allowed[req.Status] {
		utils.BadRequest(w, "invalid status — must be: upcoming, ongoing, or ended")
		return
	}

	c.DB.Exec(`UPDATE meetings SET status=$1 WHERE id=$2`, req.Status, meetID)
	utils.OK(w, map[string]string{"message": "updated"})
}

func (c *MeetingController) InviteParticipants(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	meetID := r.PathValue("id")
	if meetID == "" {
		parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
		for i, p := range parts {
			if p == "meetings" && i+1 < len(parts) {
				next := parts[i+1]
				if next != "code" && next != "request" {
					meetID = next
					break
				}
			}
		}
	}
	if meetID == "" {
		utils.BadRequest(w, "missing meeting id")
		return
	}

	// FIX BUG 03: only organizer can invite participants
	var orgID string
	c.DB.QueryRow(`SELECT organizer_id FROM meetings WHERE id=$1`, meetID).Scan(&orgID)
	if orgID != userID {
		utils.Error(w, http.StatusForbidden, "only the organizer can invite participants")
		return
	}

	var req struct {
		ParticipantIDs []string `json:"participant_ids"`
	}
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}

	var title, code, orgName string
	c.DB.QueryRow(`
		SELECT m.title, COALESCE(m.code,''), COALESCE(u.name,'')
		FROM meetings m LEFT JOIN users u ON u.id = m.organizer_id
		WHERE m.id=$1`, meetID).Scan(&title, &code, &orgName)

	jitsiLink := fmt.Sprintf("https://meet.jit.si/WorkspacePro-%s", code)
	for _, pid := range req.ParticipantIDs {
		c.DB.Exec(`INSERT INTO meeting_participants (meeting_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, meetID, pid)
		body := fmt.Sprintf("%s invited you · Code: %s · %s", orgName, code, jitsiLink)
		c.notifyMeeting(pid, "Meeting Invite: "+title, body, meetID)
	}

	utils.OK(w, map[string]string{"message": "invited"})
}

func (c *MeetingController) RequestMeeting(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var req struct {
		MeetingID string `json:"meeting_id"`
		Message   string `json:"message"`
	}
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}

	var userName string
	c.DB.QueryRow(`SELECT COALESCE(name,'') FROM users WHERE id=$1`, userID).Scan(&userName)

	var meetTitle, code string
	c.DB.QueryRow(`SELECT COALESCE(title,'Meeting'), COALESCE(code,'') FROM meetings WHERE id=$1`, req.MeetingID).Scan(&meetTitle, &code)

	msg := req.Message
	if msg == "" {
		msg = fmt.Sprintf("%s wants you to join '%s' · Code: %s", userName, meetTitle, code)
	}

	// FIX BUG 05: only notify admins in the same domain as the requester
	adminRows, err := c.DB.Query(`
		SELECT id FROM users
		WHERE LOWER(user_role)='admin'
		  AND id != $1
		  AND domain = (SELECT domain FROM users WHERE id=$1)`, userID)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer adminRows.Close()

	count := 0
	for adminRows.Next() {
		var adminID string
		adminRows.Scan(&adminID)
		c.notifyMeeting(adminID, "Meeting Request from "+userName, msg, req.MeetingID)
		count++
	}

	utils.OK(w, map[string]interface{}{"message": "request sent", "admins_notified": count})
}

func (c *MeetingController) GetParticipants(w http.ResponseWriter, r *http.Request) {
	meetID := r.PathValue("id")
	if meetID == "" {
		parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
		for i, p := range parts {
			if p == "meetings" && i+1 < len(parts) {
				meetID = parts[i+1]
				break
			}
		}
	}

	rows, err := c.DB.Query(`
		SELECT u.id, COALESCE(u.name,''), COALESCE(u.avatar_url,''),
		       COALESCE(u.role,''), COALESCE(u.status,'offline')
		FROM meeting_participants mp
		JOIN users u ON u.id = mp.user_id
		WHERE mp.meeting_id = $1
		ORDER BY u.name`, meetID)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer rows.Close()

	var participants []map[string]interface{}
	for rows.Next() {
		var id, name, avatar, role, status string
		rows.Scan(&id, &name, &avatar, &role, &status)
		participants = append(participants, map[string]interface{}{
			"id": id, "name": name, "avatar_url": avatar, "role": role, "status": status,
		})
	}
	if participants == nil {
		participants = []map[string]interface{}{}
	}
	utils.OK(w, participants)
}

func (c *MeetingController) RemoveParticipant(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	meetID := r.PathValue("id")
	targetID := r.PathValue("userId")

	if meetID == "" || targetID == "" {
		parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
		for i, p := range parts {
			if p == "meetings" && i+1 < len(parts) {
				meetID = parts[i+1]
			}
			if p == "participants" && i+1 < len(parts) {
				targetID = parts[i+1]
			}
		}
	}
	if meetID == "" || targetID == "" {
		utils.BadRequest(w, "missing id")
		return
	}

	var orgID string
	c.DB.QueryRow(`SELECT organizer_id FROM meetings WHERE id=$1`, meetID).Scan(&orgID)
	if orgID != userID {
		utils.Error(w, http.StatusForbidden, "only organizer can remove participants")
		return
	}

	c.DB.Exec(`DELETE FROM meeting_participants WHERE meeting_id=$1 AND user_id=$2`, meetID, targetID)
	utils.OK(w, map[string]string{"message": "removed"})
}
