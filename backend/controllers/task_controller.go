package controllers

import (
	"database/sql"
	"dingtalk/models"
	"dingtalk/utils"
	"net/http"
	"strings"
	"time"
)

type TaskController struct{ DB *sql.DB }

func NewTaskController(db *sql.DB) *TaskController { return &TaskController{DB: db} }

func (c *TaskController) GetTasks(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	// Returns tasks where:
	// 1. I am the assignee (tasks given to me)
	// 2. I created the task (tasks I gave to others)
	rows, err := c.DB.Query(`
		SELECT t.id, t.title, COALESCE(t.description,''),
		       t.assignee_id, COALESCE(u.name,'Unknown'),
		       t.created_by, COALESCE(cb.name,'Unknown'),
		       COALESCE(t.project_name,'General'),
		       COALESCE(t.due_date, NOW()),
		       t.priority, t.status, t.created_at
		FROM tasks t
		LEFT JOIN users u  ON u.id  = t.assignee_id
		LEFT JOIN users cb ON cb.id = t.created_by
		WHERE t.assignee_id = $1
		   OR t.created_by  = $1
		ORDER BY t.created_at DESC
		LIMIT 200`, userID)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer rows.Close()

	var tasks []map[string]interface{}
	for rows.Next() {
		var (
			id, title, desc          string
			assigneeID, assigneeName string
			createdBy, creatorName   string
			projectName              string
			dueDate                  interface{}
			priority, status         string
			createdAt                interface{}
		)
		rows.Scan(&id, &title, &desc,
			&assigneeID, &assigneeName,
			&createdBy, &creatorName,
			&projectName, &dueDate,
			&priority, &status, &createdAt)

		tasks = append(tasks, map[string]interface{}{
			"id":            id,
			"title":         title,
			"description":   desc,
			"assignee_id":   assigneeID,
			"assignee_name": assigneeName,
			"created_by":    createdBy,
			"creator_name":  creatorName,
			"project_name":  projectName,
			"due_date":      dueDate,
			"priority":      priority,
			"status":        status,
			"created_at":    createdAt,
			"is_mine":       assigneeID == userID,
			"i_created":     createdBy == userID,
		})
	}
	if tasks == nil {
		tasks = []map[string]interface{}{}
	}
	utils.OK(w, tasks)
}

func (c *TaskController) CreateTask(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var req models.CreateTaskRequest
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}
	if req.Title == "" {
		utils.BadRequest(w, "title required")
		return
	}
	if req.AssigneeID == "" {
		req.AssigneeID = userID
	}

	var taskID string
	dueDate := req.DueDate
	if dueDate == "" {
		dueDate = time.Now().Add(7 * 24 * time.Hour).Format(time.RFC3339)
	}

	err := c.DB.QueryRow(`
		INSERT INTO tasks
		  (title, description, assignee_id, created_by,
		   project_name, due_date, priority, status)
		VALUES ($1,$2,$3,$4,$5,$6::timestamp,$7,'todo')
		RETURNING id`,
		req.Title, req.Description, req.AssigneeID, userID,
		req.ProjectName, dueDate, req.Priority,
	).Scan(&taskID)
	if err != nil {
		utils.InternalError(w, err)
		return
	}

	// Send notification to assignee if different from creator
	if req.AssigneeID != userID {
		var creatorName string
		c.DB.QueryRow(`SELECT name FROM users WHERE id=$1`, userID).Scan(&creatorName)
		c.DB.Exec(`
			INSERT INTO notifications (user_id, title, message, notification_type)
			VALUES ($1, $2, $3, 'task')`,
			req.AssigneeID,
			"New Task Assigned",
			creatorName+" assigned you: "+req.Title,
		)
	}

	// Return full task
	var t map[string]interface{}
	row := c.DB.QueryRow(`
		SELECT t.id, t.title, COALESCE(t.description,''),
		       t.assignee_id, COALESCE(u.name,''),
		       t.created_by,
		       COALESCE(t.project_name,'General'),
		       t.priority, t.status, t.created_at
		FROM tasks t
		LEFT JOIN users u ON u.id = t.assignee_id
		WHERE t.id = $1`, taskID)
	var id, title, desc, assigneeID, assigneeName, createdBy, proj, pri, status string
	var createdAt interface{}
	row.Scan(&id, &title, &desc, &assigneeID, &assigneeName,
		&createdBy, &proj, &pri, &status, &createdAt)
	t = map[string]interface{}{
		"id":            id,
		"title":         title,
		"description":   desc,
		"assignee_id":   assigneeID,
		"assignee_name": assigneeName,
		"created_by":    createdBy,
		"project_name":  proj,
		"priority":      pri,
		"status":        status,
		"created_at":    createdAt,
		"is_mine":       assigneeID == userID,
		"i_created":     createdBy == userID,
	}
	utils.Created(w, t)
}

func (c *TaskController) UpdateStatus(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var req models.UpdateTaskStatusRequest
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	taskID := parts[len(parts)-2]

	// Get task info before update
	var createdBy, title, assigneeName string
	c.DB.QueryRow(`
		SELECT t.created_by, t.title, COALESCE(u.name,'')
		FROM tasks t
		LEFT JOIN users u ON u.id = t.assignee_id
		WHERE t.id = $1`, taskID,
	).Scan(&createdBy, &title, &assigneeName)

	// Update status
	c.DB.Exec(`
		UPDATE tasks SET status=$1, updated_at=NOW()
		WHERE id=$2`, req.Status, taskID)

	// If marked done — notify the person who created the task
	if req.Status == "done" && createdBy != userID {
		c.DB.Exec(`
			INSERT INTO notifications (user_id, title, message, notification_type)
			VALUES ($1, $2, $3, 'task')`,
			createdBy,
			"Task Completed ✅",
			assigneeName+" completed: "+title+". Please review and approve.",
		)
	}

	// If approved — notify assignee
	if req.Status == "approved" {
		var assigneeID string
		c.DB.QueryRow(`SELECT assignee_id FROM tasks WHERE id=$1`, taskID).Scan(&assigneeID)
		if assigneeID != userID {
			c.DB.Exec(`
				INSERT INTO notifications (user_id, title, message, notification_type)
				VALUES ($1, $2, $3, 'task')`,
				assigneeID,
				"Task Approved ✅",
				"Your task \""+title+"\" has been approved!",
			)
		}
	}

	utils.OK(w, map[string]string{"message": "updated"})
}
