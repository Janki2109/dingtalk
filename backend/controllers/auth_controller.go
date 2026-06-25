package controllers

import (
	"database/sql"
	"log"
	"net/http"
	"strings"

	"dingtalk/middleware"
	"dingtalk/models"
	"dingtalk/utils"

	"golang.org/x/crypto/bcrypt"
)

type AuthController struct{ DB *sql.DB }

func NewAuthController(db *sql.DB) *AuthController {
	return &AuthController{DB: db}
}

func extractDomain(email string) string {
	parts := strings.Split(strings.ToLower(strings.TrimSpace(email)), "@")
	if len(parts) == 2 {
		return parts[1]
	}
	return ""
}

func (c *AuthController) Register(w http.ResponseWriter, r *http.Request) {
	var req models.RegisterRequest
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid request body")
		return
	}
	if req.Name == "" || req.Email == "" || req.Password == "" {
		utils.BadRequest(w, "name, email and password are required")
		return
	}
	if len(req.Password) < 6 {
		utils.BadRequest(w, "password must be at least 6 characters")
		return
	}

	domain := extractDomain(req.Email)
	if domain == "" {
		utils.BadRequest(w, "invalid email address")
		return
	}

	// FIX BUG #10: check Scan error in duplicate-email check
	var existing int
	if err := c.DB.QueryRow(`SELECT COUNT(*) FROM users WHERE email=$1`, req.Email).Scan(&existing); err != nil {
		utils.InternalError(w, err)
		return
	}
	if existing > 0 {
		utils.Error(w, http.StatusConflict, "email already registered")
		return
	}

	wantAdmin := strings.ToLower(req.UserRole) == "admin"
	userRole := "employee"

	if wantAdmin {
		// FIX BUG #11: check Scan error for adminCount
		// DB failure must NOT silently make everyone admin
		var adminCount int
		if err := c.DB.QueryRow(
			`SELECT COUNT(*) FROM users WHERE domain=$1 AND LOWER(user_role)='admin'`, domain,
		).Scan(&adminCount); err != nil {
			// On DB error, safely default to employee — never grant admin
			log.Printf("⚠️ Admin count query failed for domain %s: %v — defaulting to employee", domain, err)
			userRole = "employee"
		} else if adminCount > 0 {
			userRole = "employee"
			log.Printf("⚠️ Domain %s already has admin — registering %s as employee", domain, req.Email)
		} else {
			userRole = "admin"
		}
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		utils.InternalError(w, err)
		return
	}

	if req.Role == "" {
		req.Role = "Employee"
	}
	if req.Department == "" {
		req.Department = "General"
	}
	if userRole == "admin" {
		req.Role = "Administrator"
	}

	log.Printf("📝 Registering: %s | domain: %s | user_role: %s", req.Email, domain, userRole)

	// FIX BUG #12: removed ALTER TABLE DDL from HTTP handler
	// DDL now only runs in migrate() at startup — not on every registration

	var user models.User
	err = c.DB.QueryRow(`
		INSERT INTO users (name, email, password_hash, role, department, status, user_role, domain)
		VALUES ($1,$2,$3,$4,$5,'online',$6,$7)
		RETURNING id, name, email, role, department, status,
		          COALESCE(user_role,'employee'), COALESCE(domain,''), created_at`,
		req.Name, req.Email, string(hash), req.Role, req.Department, userRole, domain,
	).Scan(&user.ID, &user.Name, &user.Email, &user.Role, &user.Department,
		&user.Status, &user.UserRole, &user.Domain, &user.CreatedAt)
	if err != nil {
		log.Println("❌ Insert error:", err)
		utils.InternalError(w, err)
		return
	}

	token, err := middleware.GenerateToken(user.ID, user.Email)
	if err != nil {
		utils.InternalError(w, err)
		return
	}

	if wantAdmin && userRole == "employee" {
		user.Bio = "Note: This domain already has an admin. You have been registered as an employee."
	}

	log.Printf("✅ Registered: %s | domain: %s | user_role: %s", user.Email, user.Domain, user.UserRole)
	utils.Created(w, models.AuthResponse{Token: token, User: user})
}

func (c *AuthController) Login(w http.ResponseWriter, r *http.Request) {
	var req models.LoginRequest
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid request body")
		return
	}
	if req.Email == "" || req.Password == "" {
		utils.BadRequest(w, "email and password are required")
		return
	}
	var user models.User
	var hash string
	err := c.DB.QueryRow(`
		SELECT id, name, email, password_hash,
		       COALESCE(role,''), COALESCE(department,''),
		       COALESCE(status,'online'), COALESCE(avatar_url,''),
		       COALESCE(phone,''), COALESCE(user_role,'employee'),
		       COALESCE(bio,''), COALESCE(domain,'')
		FROM users WHERE email=$1`, req.Email,
	).Scan(&user.ID, &user.Name, &user.Email, &hash,
		&user.Role, &user.Department, &user.Status,
		&user.AvatarURL, &user.Phone, &user.UserRole, &user.Bio, &user.Domain)
	if err == sql.ErrNoRows {
		utils.Error(w, http.StatusUnauthorized, "invalid email or password")
		return
	}
	if err != nil {
		utils.Error(w, http.StatusUnauthorized, "invalid email or password")
		return
	}
	if err = bcrypt.CompareHashAndPassword([]byte(hash), []byte(req.Password)); err != nil {
		utils.Error(w, http.StatusUnauthorized, "invalid email or password")
		return
	}

	if user.Domain == "" {
		domain := extractDomain(req.Email)
		c.DB.Exec(`UPDATE users SET domain=$1 WHERE id=$2`, domain, user.ID)
		user.Domain = domain
	}

	c.DB.Exec(`UPDATE users SET status='online', updated_at=NOW() WHERE id=$1`, user.ID)
	user.Status = "online"
	token, err := middleware.GenerateToken(user.ID, user.Email)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	log.Printf("✅ Login: %s | domain: %s | user_role: %s", user.Email, user.Domain, user.UserRole)
	utils.OK(w, models.AuthResponse{Token: token, User: user})
}

func (c *AuthController) Me(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var user models.User
	err := c.DB.QueryRow(`
		SELECT id, name, email,
		       COALESCE(role,''), COALESCE(department,''),
		       COALESCE(status,'online'), COALESCE(avatar_url,''),
		       COALESCE(phone,''), COALESCE(user_role,'employee'),
		       COALESCE(bio,''), COALESCE(domain,'')
		FROM users WHERE id=$1`, userID,
	).Scan(&user.ID, &user.Name, &user.Email,
		&user.Role, &user.Department, &user.Status,
		&user.AvatarURL, &user.Phone, &user.UserRole, &user.Bio, &user.Domain)
	if err != nil {
		utils.NotFound(w, "user not found")
		return
	}
	utils.OK(w, user)
}

func (c *AuthController) Logout(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	c.DB.Exec(`UPDATE users SET status='offline', last_seen=NOW(), updated_at=NOW() WHERE id=$1`, userID)
	utils.OK(w, map[string]string{"message": "logged out"})
}

func (c *AuthController) ChangePassword(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var req struct {
		OldPassword string `json:"old_password"`
		NewPassword string `json:"new_password"`
	}
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}
	if req.OldPassword == "" || req.NewPassword == "" {
		utils.BadRequest(w, "old and new password required")
		return
	}
	if len(req.NewPassword) < 6 {
		utils.BadRequest(w, "password must be at least 6 characters")
		return
	}
	var hash string
	err := c.DB.QueryRow(`SELECT password_hash FROM users WHERE id=$1`, userID).Scan(&hash)
	if err != nil {
		utils.NotFound(w, "user not found")
		return
	}
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(req.OldPassword)); err != nil {
		utils.Error(w, http.StatusUnauthorized, "current password is incorrect")
		return
	}
	newHash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	c.DB.Exec(`UPDATE users SET password_hash=$1, updated_at=NOW() WHERE id=$2`, string(newHash), userID)
	utils.OK(w, map[string]string{"message": "password changed successfully"})
}

func (c *AuthController) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var req struct {
		Name      string `json:"name"`
		Bio       string `json:"bio"`
		AvatarURL string `json:"avatar_url"`
		Role      string `json:"role"`
		Phone     string `json:"phone"`
	}
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}
	_, err := c.DB.Exec(`
		UPDATE users
		SET name       = COALESCE(NULLIF($1,''), name),
		    bio        = $2,
		    avatar_url = COALESCE(NULLIF($3,''), avatar_url),
		    role       = COALESCE(NULLIF($4,''), role),
		    phone      = COALESCE(NULLIF($5,''), phone),
		    updated_at = NOW()
		WHERE id = $6`,
		req.Name, req.Bio, req.AvatarURL, req.Role, req.Phone, userID)
	if err != nil {
		utils.InternalError(w, err)
		return
	}

	// FIX BUG #13: check Scan error in UpdateProfile
	var user models.User
	if err := c.DB.QueryRow(`
		SELECT id, name, email,
		       COALESCE(role,''), COALESCE(department,''),
		       COALESCE(status,'online'), COALESCE(avatar_url,''),
		       COALESCE(phone,''), COALESCE(user_role,'employee'),
		       COALESCE(bio,''), COALESCE(domain,'')
		FROM users WHERE id=$1`, userID,
	).Scan(&user.ID, &user.Name, &user.Email,
		&user.Role, &user.Department, &user.Status,
		&user.AvatarURL, &user.Phone, &user.UserRole, &user.Bio, &user.Domain); err != nil {
		utils.InternalError(w, err)
		return
	}
	utils.OK(w, user)
}
