package controllers

import (
	"database/sql"
	"dingtalk/models"
	"dingtalk/utils"
	"net/http"
	"time"
)

type UserController struct{ DB *sql.DB }

func NewUserController(db *sql.DB) *UserController { return &UserController{DB: db} }

func (c *UserController) GetUsers(w http.ResponseWriter, r *http.Request) {
	rows, err := c.DB.Query(`
		SELECT id, name, email,
		       COALESCE(role,''),
		       COALESCE(department,''),
		       COALESCE(status,'offline'),
		       COALESCE(avatar_url,''),
		       COALESCE(phone,''),
		       COALESCE(user_role,'employee'),
		       last_seen
		FROM users ORDER BY name`)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer rows.Close()

	var users []models.User
	for rows.Next() {
		var u models.User
		var lastSeen sql.NullTime // handles NULL safely
		err := rows.Scan(
			&u.ID, &u.Name, &u.Email,
			&u.Role, &u.Department, &u.Status,
			&u.AvatarURL, &u.Phone,
			&u.UserRole,
			&lastSeen,
		)
		if err != nil {
			continue
		}
		if lastSeen.Valid {
			u.LastSeen = &lastSeen.Time
		}
		users = append(users, u)
	}
	if users == nil {
		users = []models.User{}
	}
	utils.OK(w, users)
}

func (c *UserController) UpdateStatus(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var req struct {
		Status string `json:"status"`
	}
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}

	if req.Status == "offline" {
		// Save last_seen timestamp when going offline
		c.DB.Exec(`
			UPDATE users
			SET status=$1, last_seen=NOW(), updated_at=NOW()
			WHERE id=$2`, req.Status, userID)
	} else {
		// Just update status when coming online
		c.DB.Exec(`
			UPDATE users
			SET status=$1, updated_at=NOW()
			WHERE id=$2`, req.Status, userID)
	}
	utils.OK(w, map[string]string{"message": "status updated"})
}

func (c *UserController) DingTalkWebhook(w http.ResponseWriter, r *http.Request) {
	var event struct {
		SenderID       string                   `json:"senderId"`
		Text           struct{ Content string } `json:"text"`
		SessionWebhook string                   `json:"sessionWebhook"`
	}
	if err := utils.Decode(r, &event); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}
	c.DB.Exec(`
		INSERT INTO users (name, email, password_hash, dingtalk_user_id)
		VALUES ($1,$2,'webhook',$3) ON CONFLICT DO NOTHING`,
		event.SenderID, event.SenderID+"@dingtalk", event.SenderID)
	utils.OK(w, map[string]string{"message": "ok"})
}

func getUser(db *sql.DB, id string) *models.User {
	var u models.User
	var lastSeen sql.NullTime
	err := db.QueryRow(`
		SELECT id, name, email, role, department, status,
		       COALESCE(user_role,'employee'), last_seen
		FROM users WHERE id=$1`, id).
		Scan(&u.ID, &u.Name, &u.Email, &u.Role, &u.Department,
			&u.Status, &u.UserRole, &lastSeen)
	if err != nil {
		return nil
	}
	if lastSeen.Valid {
		u.LastSeen = &lastSeen.Time
	}
	return &u
}

// Keep time import used
var _ = time.Now
