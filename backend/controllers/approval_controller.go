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
	rows, err := c.DB.Query(`
		SELECT a.id,a.title,a.approval_type,a.requester_id,COALESCE(u1.name,''),
		       COALESCE(a.approver_id::text,''),COALESCE(u2.name,''),
		       COALESCE(a.description,''),a.status,a.created_at
		FROM approvals a
		LEFT JOIN users u1 ON u1.id=a.requester_id
		LEFT JOIN users u2 ON u2.id=a.approver_id
		WHERE a.requester_id=$1 OR a.approver_id=$1
		ORDER BY a.created_at DESC`, userID)
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

	var a models.Approval
	err := c.DB.QueryRow(`
		INSERT INTO approvals (title,approval_type,requester_id,approver_id,description,status)
		VALUES ($1,$2,$3,$4,$5,'pending')
		RETURNING id,title,approval_type,requester_id,status,created_at`,
		req.Title, req.ApprovalType, userID, req.ApproverID, req.Description,
	).Scan(&a.ID, &a.Title, &a.ApprovalType, &a.RequesterID, &a.Status, &a.CreatedAt)
	if err != nil {
		utils.InternalError(w, err)
		return
	}

	// Get requester name
	var requesterName string
	c.DB.QueryRow(`SELECT name FROM users WHERE id=$1`, userID).Scan(&requesterName)

	// Notify the approver (admin) about the new request
	if req.ApproverID != "" {
		c.DB.Exec(`
			INSERT INTO notifications (user_id, title, message, notification_type)
			VALUES ($1, $2, $3, 'approval')`,
			req.ApproverID,
			"New Approval Request 📋",
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

	// Notify the requester (employee) about the decision
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
				INSERT INTO notifications (user_id, title, message, notification_type)
				VALUES ($1, $2, $3, 'approval')`,
				requesterID, notifTitle, notifMsg,
			)
		}
	}

	utils.OK(w, map[string]string{"message": "updated"})
}
