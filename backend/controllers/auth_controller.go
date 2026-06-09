package controllers

import (
	"database/sql"
	"log"
	"net/http"

	"dingtalk/middleware"
	"dingtalk/models"
	"dingtalk/utils"

	"golang.org/x/crypto/bcrypt"
)

type AuthController struct{ DB *sql.DB }

func NewAuthController(db *sql.DB) *AuthController {
	return &AuthController{DB: db}
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
	var existing int
	c.DB.QueryRow(`SELECT COUNT(*) FROM users WHERE email=$1`, req.Email).Scan(&existing)
	if existing > 0 {
		utils.Error(w, http.StatusConflict, "email already registered")
		return
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
	userRole := "employee"
	if req.Role == "Administrator" {
		userRole = "admin"
	}

	log.Printf("📝 Registering: %s | role: %s | user_role: %s", req.Email, req.Role, userRole)

	var user models.User
	err = c.DB.QueryRow(`
		INSERT INTO users (name, email, password_hash, role, department, status, user_role)
		VALUES ($1,$2,$3,$4,$5,'online',$6)
		RETURNING id, name, email, role, department, status,
		          COALESCE(user_role,'employee'), created_at`,
		req.Name, req.Email, string(hash), req.Role, req.Department, userRole,
	).Scan(&user.ID, &user.Name, &user.Email, &user.Role, &user.Department,
		&user.Status, &user.UserRole, &user.CreatedAt)
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
	log.Printf("✅ Registered: %s | user_role: %s", user.Email, user.UserRole)
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
		       COALESCE(bio,'')
		FROM users WHERE email=$1`, req.Email,
	).Scan(&user.ID, &user.Name, &user.Email, &hash,
		&user.Role, &user.Department, &user.Status,
		&user.AvatarURL, &user.Phone, &user.UserRole, &user.Bio)
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
	c.DB.Exec(`UPDATE users SET status='online', updated_at=NOW() WHERE id=$1`, user.ID)
	user.Status = "online"
	token, err := middleware.GenerateToken(user.ID, user.Email)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	log.Printf("✅ Login: %s | user_role: %s", user.Email, user.UserRole)
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
		       COALESCE(bio,'')
		FROM users WHERE id=$1`, userID,
	).Scan(&user.ID, &user.Name, &user.Email,
		&user.Role, &user.Department, &user.Status,
		&user.AvatarURL, &user.Phone, &user.UserRole, &user.Bio)
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

// ── Update Profile (name, bio, avatar_url) ────────────────────────────────────
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
	var user models.User
	c.DB.QueryRow(`
		SELECT id, name, email,
		       COALESCE(role,''), COALESCE(department,''),
		       COALESCE(status,'online'), COALESCE(avatar_url,''),
		       COALESCE(phone,''), COALESCE(user_role,'employee'),
		       COALESCE(bio,'')
		FROM users WHERE id=$1`, userID,
	).Scan(&user.ID, &user.Name, &user.Email,
		&user.Role, &user.Department, &user.Status,
		&user.AvatarURL, &user.Phone, &user.UserRole, &user.Bio)
	utils.OK(w, user)
}
