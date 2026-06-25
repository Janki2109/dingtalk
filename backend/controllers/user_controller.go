package controllers

import (
	"database/sql"
	"encoding/json"
	"net/http"

	"dingtalk/utils"
)

type UserController struct{ DB *sql.DB }

func NewUserController(db *sql.DB) *UserController {
	return &UserController{DB: db}
}

func (c *UserController) GetUsers(w http.ResponseWriter, r *http.Request) {
	userEmail := r.Header.Get("X-User-Email")
	domain := extractDomain(userEmail)

	var rows *sql.Rows
	var err error

	if domain == "" {
		rows, err = c.DB.Query(`
			SELECT id, name, email, COALESCE(role,''), COALESCE(department,''),
			       COALESCE(status,'offline'), COALESCE(avatar_url,''),
			       COALESCE(phone,''), COALESCE(user_role,'employee'),
			       COALESCE(bio,''), COALESCE(domain,'')
			FROM users ORDER BY name`)
	} else {
		rows, err = c.DB.Query(`
			SELECT id, name, email, COALESCE(role,''), COALESCE(department,''),
			       COALESCE(status,'offline'), COALESCE(avatar_url,''),
			       COALESCE(phone,''), COALESCE(user_role,'employee'),
			       COALESCE(bio,''), COALESCE(domain,'')
			FROM users
			WHERE LOWER(domain) = LOWER($1)
			ORDER BY name`, domain)
	}
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer rows.Close()

	type UserOut struct {
		ID         string `json:"id"`
		Name       string `json:"name"`
		Email      string `json:"email"`
		Role       string `json:"role"`
		Department string `json:"department"`
		Status     string `json:"status"`
		AvatarURL  string `json:"avatar_url"`
		Phone      string `json:"phone"`
		UserRole   string `json:"user_role"`
		Bio        string `json:"bio"`
		Domain     string `json:"domain"`
	}

	var users []UserOut
	for rows.Next() {
		var u UserOut
		// FIX BUG #20: check Scan error
		if err := rows.Scan(
			&u.ID, &u.Name, &u.Email, &u.Role, &u.Department,
			&u.Status, &u.AvatarURL, &u.Phone, &u.UserRole, &u.Bio, &u.Domain,
		); err != nil {
			continue
		}
		users = append(users, u)
	}
	if users == nil {
		users = []UserOut{}
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
	c.DB.Exec(`UPDATE users SET status=$1, updated_at=NOW() WHERE id=$2`, req.Status, userID)
	utils.OK(w, map[string]string{"message": "status updated"})
}

func (c *UserController) DingTalkWebhook(w http.ResponseWriter, r *http.Request) {
	var payload map[string]interface{}
	// FIX BUG #21: check json.Decode error
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		utils.BadRequest(w, "invalid webhook payload")
		return
	}
	utils.OK(w, map[string]string{"message": "webhook received"})
}

// FIX BUG #22: removed dead duplicate extractDomainFromEmail function
// extractDomain already exists in auth_controller.go and is used directly
