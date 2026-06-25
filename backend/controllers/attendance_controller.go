package controllers

import (
	"database/sql"
	"dingtalk/models"
	"dingtalk/utils"
	"net/http"
	"time"
)

type AttendanceController struct{ DB *sql.DB }

func NewAttendanceController(db *sql.DB) *AttendanceController {
	return &AttendanceController{DB: db}
}

func (c *AttendanceController) GetHistory(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	rows, err := c.DB.Query(`
		SELECT id, user_id, date, check_in, check_out, status, COALESCE(location,'')
		FROM attendance WHERE user_id=$1
		ORDER BY date DESC LIMIT 30`, userID)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer rows.Close()

	var records []models.Attendance
	for rows.Next() {
		var a models.Attendance
		// FIX BUG #31: check Scan error in GetHistory
		if err := rows.Scan(
			&a.ID, &a.UserID, &a.Date, &a.CheckIn,
			&a.CheckOut, &a.Status, &a.Location,
		); err != nil {
			continue
		}
		records = append(records, a)
	}
	if records == nil {
		records = []models.Attendance{}
	}
	utils.OK(w, records)
}

func (c *AttendanceController) CheckIn(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var req models.CheckInRequest

	// FIX BUG #30: check utils.Decode error — malformed body no longer silently proceeds
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid request body")
		return
	}

	now := time.Now()
	today := now.Format("2006-01-02")
	status := "present"
	if now.Hour() > 9 || (now.Hour() == 9 && now.Minute() > 15) {
		status = "late"
	}

	var a models.Attendance
	err := c.DB.QueryRow(`
		INSERT INTO attendance (user_id, date, check_in, status, location)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (user_id, date) DO UPDATE
		SET check_in=$3, status=$4, location=$5
		RETURNING id, user_id, date, check_in, status, COALESCE(location,'')`,
		userID, today, now, status, req.Location,
	).Scan(&a.ID, &a.UserID, &a.Date, &a.CheckIn, &a.Status, &a.Location)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	utils.OK(w, a)
}

func (c *AttendanceController) CheckOut(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	now := time.Now()
	today := now.Format("2006-01-02")

	if _, err := c.DB.Exec(
		`UPDATE attendance SET check_out=$1 WHERE user_id=$2 AND date=$3`,
		now, userID, today,
	); err != nil {
		utils.InternalError(w, err)
		return
	}

	utils.OK(w, map[string]string{
		"message": "checked out",
		"time":    now.Format("15:04"),
	})
}

// GetAdminAttendance returns attendance records for all users in the same domain
func (c *AttendanceController) GetAdminAttendance(w http.ResponseWriter, r *http.Request) {
	userEmail := r.Header.Get("X-User-Email")
	domain := extractDomain(userEmail)

	var rows *sql.Rows
	var err error

	if domain == "" {
		rows, err = c.DB.Query(`
			SELECT a.id, a.user_id, COALESCE(u.name,''), a.date,
			       a.check_in, a.check_out, a.status, COALESCE(a.location,'')
			FROM attendance a
			LEFT JOIN users u ON u.id = a.user_id
			ORDER BY a.date DESC LIMIT 200`)
	} else {
		rows, err = c.DB.Query(`
			SELECT a.id, a.user_id, COALESCE(u.name,''), a.date,
			       a.check_in, a.check_out, a.status, COALESCE(a.location,'')
			FROM attendance a
			LEFT JOIN users u ON u.id = a.user_id
			WHERE LOWER(u.domain) = LOWER($1)
			ORDER BY a.date DESC LIMIT 200`, domain)
	}
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer rows.Close()

	type AdminRecord struct {
		ID       string      `json:"id"`
		UserID   string      `json:"user_id"`
		UserName string      `json:"user_name"`
		Date     interface{} `json:"date"`
		CheckIn  interface{} `json:"check_in"`
		CheckOut interface{} `json:"check_out"`
		Status   string      `json:"status"`
		Location string      `json:"location"`
	}

	var records []AdminRecord
	for rows.Next() {
		var rec AdminRecord
		if err := rows.Scan(
			&rec.ID, &rec.UserID, &rec.UserName, &rec.Date,
			&rec.CheckIn, &rec.CheckOut, &rec.Status, &rec.Location,
		); err != nil {
			continue
		}
		records = append(records, rec)
	}
	if records == nil {
		records = []AdminRecord{}
	}
	utils.OK(w, records)
}
