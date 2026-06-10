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
		SELECT id,user_id,date,check_in,check_out,status,COALESCE(location,'')
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
		rows.Scan(&a.ID, &a.UserID, &a.Date, &a.CheckIn, &a.CheckOut, &a.Status, &a.Location)
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
	utils.Decode(r, &req)
	now := time.Now()
	today := now.Format("2006-01-02")
	status := "present"
	if now.Hour() > 9 || (now.Hour() == 9 && now.Minute() > 15) {
		status = "late"
	}
	var a models.Attendance
	err := c.DB.QueryRow(`
		INSERT INTO attendance (user_id,date,check_in,status,location)
		VALUES ($1,$2,$3,$4,$5)
		ON CONFLICT (user_id,date) DO UPDATE SET check_in=$3,status=$4,location=$5
		RETURNING id,user_id,date,check_in,status,COALESCE(location,'')`,
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
	c.DB.Exec(`UPDATE attendance SET check_out=$1 WHERE user_id=$2 AND date=$3`, now, userID, today)
	utils.OK(w, map[string]string{"message": "checked out", "time": now.Format("15:04")})
}
