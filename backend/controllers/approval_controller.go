package controllers

import (
	"database/sql"
	"dingtalk/models"
	"dingtalk/utils"
	"net/http"
	"strings"
)

type ApprovalController struct{ DB *sql.DB }

func NewApprovalController(db *sql.DB) *ApprovalController { return &ApprovalController{DB: db} }

func (c *ApprovalController) GetApprovals(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	// Get user role
	var userRole string
	c.DB.QueryRow(`SELECT COALESCE(user_role,'employee') FROM users WHERE id=$1`, userID).Scan(&userRole)

	var rows *sql.Rows
	var err error

	if userRole == "admin" {
		// Admin sees:
		// 1. Requests sent directly to them (approver_id = admin)
		// 2. Work reports from ALL employees (approval_type = 'work_report')
		rows, err = c.DB.Query(`
			SELECT a.id, a.title, a.approval_type, a.requester_id, COALESCE(u1.name,''),
			       COALESCE(a.approver_id::text,''), COALESCE(u2.name,''),
			       COALESCE(a.description,''), a.status, a.created_at
			FROM approvals a
			LEFT JOIN users u1 ON u1.id = a.requester_id
			LEFT JOIN users u2 ON u2.id = a.approver_id
			WHERE a.approver_id = $1
			   OR a.approval_type = 'work_report'
			ORDER BY a.created_at DESC`, userID)
	} else {
		// Employee sees only their own approvals
		rows, err = c.DB.Query(`
			SELECT a.id, a.title, a.approval_type, a.requester_id, COALESCE(u1.name,''),
			       COALESCE(a.approver_id::text,''), COALESCE(u2.name,''),
			       COALESCE(a.description,''), a.status, a.created_at
			FROM approvals a
			LEFT JOIN users u1 ON u1.id = a.requester_id
			LEFT JOIN users u2 ON u2.id = a.approver_id
			WHERE a.requester_id = $1
			ORDER BY a.created_at DESC`, userID)
	}

	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer rows.Close()

	var approvals []models.Approval
	for rows.Next() {
		var a models.Approval
		rows.Scan(&a.ID, &a.Title, &a.ApprovalType, &a.RequesterID, &a.RequesterName,
			&a.ApproverID, &a.ApproverName, &a.Description, &a.Status, &a.CreatedAt)
		approvals = append(approvals, a)
	}
	if approvals == nil {
		approvals = []models.Approval{}
	}
	utils.OK(w, approvals)
}

func (c *ApprovalController) CreateApproval(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var req models.CreateApprovalRequest
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}

	// For work reports with no approver, find first admin
	if req.ApproverID == "" || req.ApprovalType == "work_report" {
		var adminID string
		c.DB.QueryRow(`SELECT id FROM users WHERE LOWER(user_role)='admin' LIMIT 1`).Scan(&adminID)
		if adminID != "" {
			req.ApproverID = adminID
		}
	}

	var a models.Approval
	err := c.DB.QueryRow(`
		INSERT INTO approvals (title, approval_type, requester_id, approver_id, description, status)
		VALUES ($1, $2, $3, $4, $5, 'pending')
		RETURNING id, title, approval_type, requester_id, status, created_at`,
		req.Title, req.ApprovalType, userID, req.ApproverID, req.Description,
	).Scan(&a.ID, &a.Title, &a.ApprovalType, &a.RequesterID, &a.Status, &a.CreatedAt)
	if err != nil {
		utils.InternalError(w, err)
		return
	}

	// Get requester name
	var requesterName string
	c.DB.QueryRow(`SELECT name FROM users WHERE id=$1`, userID).Scan(&requesterName)

	// ✅ For work reports — notify ALL admins
	if req.ApprovalType == "work_report" {
		adminRows, _ := c.DB.Query(`SELECT id FROM users WHERE LOWER(user_role)='admin'`)
		if adminRows != nil {
			defer adminRows.Close()
			for adminRows.Next() {
				var adminID string
				adminRows.Scan(&adminID)
				c.DB.Exec(`
					INSERT INTO notifications (user_id, title, body, notification_type)
					VALUES ($1, $2, $3, 'approval')`,
					adminID,
					"📋 Work Report from "+requesterName,
					requesterName+" submitted their daily work report",
				)
			}
		}
	} else if req.ApproverID != "" {
		// For leave requests — notify the specific admin
		c.DB.Exec(`
			INSERT INTO notifications (user_id, title, body, notification_type)
			VALUES ($1, $2, $3, 'approval')`,
			req.ApproverID,
			"New "+req.ApprovalType+" Request 📋",
			requesterName+" sent a "+req.ApprovalType+" request: "+req.Title,
		)
	}

	utils.Created(w, a)
}

func (c *ApprovalController) UpdateStatus(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	var req struct {
		Status string `json:"status"`
	}
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) < 3 {
		utils.BadRequest(w, "missing id")
		return
	}
	id := parts[len(parts)-2]

	// Get approval info before updating
	var requesterID, title, approvalType string
	c.DB.QueryRow(`
		SELECT requester_id, title, approval_type FROM approvals WHERE id=$1`, id,
	).Scan(&requesterID, &title, &approvalType)

	// Get admin name
	var adminName string
	c.DB.QueryRow(`SELECT name FROM users WHERE id=$1`, userID).Scan(&adminName)

	// Update status
	c.DB.Exec(`UPDATE approvals SET status=$1, updated_at=NOW() WHERE id=$2`, req.Status, id)

	// Notify the requester about the decision
	if requesterID != "" && requesterID != userID {
		var notifTitle, notifMsg string
		if req.Status == "approved" {
			notifTitle = "Request Approved ✅"
			notifMsg = adminName + " approved your " + approvalType + " request: " + title
		} else if req.Status == "rejected" {
			notifTitle = "Request Rejected ❌"
			notifMsg = adminName + " rejected your " + approvalType + " request: " + title
		}
		if notifTitle != "" {
			c.DB.Exec(`
				INSERT INTO notifications (user_id, title, body, notification_type)
				VALUES ($1, $2, $3, 'approval')`,
				requesterID, notifTitle, notifMsg,
			)
		}
	}

	utils.OK(w, map[string]string{"message": "updated"})
}
