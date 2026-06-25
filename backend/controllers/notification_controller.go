package controllers

import (
	"database/sql"
	"dingtalk/models"
	"dingtalk/utils"
	"net/http"
	"strings"
)

type NotificationController struct{ DB *sql.DB }

func NewNotificationController(db *sql.DB) *NotificationController {
	return &NotificationController{DB: db}
}

func (c *NotificationController) GetNotifications(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	rows, err := c.DB.Query(`
		SELECT id, user_id, title, COALESCE(body,''), notification_type, is_read,
		       COALESCE(action_id::text,''), created_at
		FROM notifications WHERE user_id=$1
		ORDER BY created_at DESC LIMIT 50`, userID)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer rows.Close()

	var notifs []models.Notification
	for rows.Next() {
		var n models.Notification
		// FIX BUG #32: check Scan error in GetNotifications
		if err := rows.Scan(
			&n.ID, &n.UserID, &n.Title, &n.Body,
			&n.NotificationType, &n.IsRead, &n.ActionID, &n.CreatedAt,
		); err != nil {
			continue
		}
		notifs = append(notifs, n)
	}
	if notifs == nil {
		notifs = []models.Notification{}
	}
	utils.OK(w, notifs)
}

func (c *NotificationController) MarkRead(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) >= 3 && parts[len(parts)-1] == "read" {
		id := parts[len(parts)-2]
		if id == "" {
			utils.BadRequest(w, "missing notification id")
			return
		}
		if _, err := c.DB.Exec(
			`UPDATE notifications SET is_read=true WHERE id=$1 AND user_id=$2`,
			id, userID,
		); err != nil {
			utils.InternalError(w, err)
			return
		}
	}
	utils.OK(w, map[string]string{"message": "marked read"})
}

func (c *NotificationController) MarkAllRead(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	if _, err := c.DB.Exec(
		`UPDATE notifications SET is_read=true WHERE user_id=$1`, userID,
	); err != nil {
		utils.InternalError(w, err)
		return
	}
	utils.OK(w, map[string]string{"message": "all marked read"})
}

// GetUnreadCount returns count of unread notifications for the user
func (c *NotificationController) GetUnreadCount(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var count int
	if err := c.DB.QueryRow(
		`SELECT COUNT(*) FROM notifications WHERE user_id=$1 AND is_read=false`,
		userID,
	).Scan(&count); err != nil {
		if err == sql.ErrNoRows {
			count = 0
		} else {
			utils.InternalError(w, err)
			return
		}
	}
	utils.OK(w, map[string]int{"unread_count": count})
}
