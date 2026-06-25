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

	// FIX BUG #33: check Scan error for userRole
	var userRole string
	if err := c.DB.QueryRow(
		`SELECT COALESCE(user_role,'employee') FROM users WHERE id=$1`, userID,
	).Scan(&userRole); err != nil {
		utils.InternalError(w, err)
		return
	}

	// FIX BUG #34: get user domain for cross-tenant filtering
	var userDomain string
	c.DB.QueryRow(`SELECT COALESCE(domain,'') FROM users WHERE id=$1`, userID).Scan(&userDomain)

	var rows *sql.Rows
	var err error

	if userRole == "admin" {
		// FIX BUG #34: admin only sees approvals from their own domain
		rows, err = c.DB.Query(`
			SELECT a.id, a.title, a.approval_type, a.requester_id, COALESCE(u1.name,''),
			       COALESCE(a.approver_id::text,''), COALESCE(u2.name,''),
			       COALESCE(a.description,''), a.status, a.created_at
			FROM approvals a
			LEFT JOIN users u1 ON u1.id = a.requester_id
			LEFT JOIN users u2 ON u2.id = a.approver_id
			WHERE (a.approver_id = $1 OR a.approval_type = 'work_report')
			  AND COALESCE(u1.domain,'') = $2
			ORDER BY a.created_at DESC`, userID, userDomain)
	} else {
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
		// FIX BUG #33: check Scan error in loop
		if err := rows.Scan(
			&a.ID, &a.Title, &a.ApprovalType, &a.RequesterID, &a.RequesterName,
			&a.ApproverID, &a.ApproverName, &a.Description, &a.Status, &a.CreatedAt,
		); err != nil {
			continue
		}
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

	// FIX BUG #34: get domain of requester to only notify same-domain admins
	var userDomain string
	c.DB.QueryRow(`SELECT COALESCE(domain,'') FROM users WHERE id=$1`, userID).Scan(&userDomain)

	// For work reports with no approver, find first admin in same domain
	if req.ApproverID == "" || req.ApprovalType == "work_report" {
		var adminID string
		c.DB.QueryRow(
			`SELECT id FROM users WHERE LOWER(user_role)='admin' AND domain=$1 LIMIT 1`,
			userDomain,
		).Scan(&adminID)
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

	var requesterName string
	c.DB.QueryRow(`SELECT name FROM users WHERE id=$1`, userID).Scan(&requesterName)

	// FIX BUG #34: only notify admins in the same domain
	if req.ApprovalType == "work_report" {
		adminRows, err := c.DB.Query(
			`SELECT id FROM users WHERE LOWER(user_role)='admin' AND domain=$1`,
			userDomain,
		)
		if err == nil && adminRows != nil {
			defer adminRows.Close()
			for adminRows.Next() {
				var adminID string
				if scanErr := adminRows.Scan(&adminID); scanErr != nil {
					continue
				}
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

	var requesterID, title, approvalType string
	c.DB.QueryRow(`
		SELECT requester_id, title, approval_type FROM approvals WHERE id=$1`, id,
	).Scan(&requesterID, &title, &approvalType)

	var adminName string
	c.DB.QueryRow(`SELECT name FROM users WHERE id=$1`, userID).Scan(&adminName)

	// FIX BUG #35: check status update error instead of silently ignoring
	if _, err := c.DB.Exec(
		`UPDATE approvals SET status=$1, updated_at=NOW() WHERE id=$2`, req.Status, id,
	); err != nil {
		utils.InternalError(w, err)
		return
	}

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
