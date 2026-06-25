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
		// FIX BUG #23: check Scan error in GetTasks
		if err := rows.Scan(&id, &title, &desc,
			&assigneeID, &assigneeName,
			&createdBy, &creatorName,
			&projectName, &dueDate,
			&priority, &status, &createdAt); err != nil {
			continue
		}

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

	dueDate := req.DueDate
	if dueDate == "" {
		dueDate = time.Now().Add(7 * 24 * time.Hour).Format(time.RFC3339)
	}

	var taskID string
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

	// FIX BUG #25: check Scan error before using creatorName in notification
	if req.AssigneeID != userID {
		var creatorName string
		if err := c.DB.QueryRow(
			`SELECT name FROM users WHERE id=$1`, userID,
		).Scan(&creatorName); err != nil {
			creatorName = "Someone"
		}
		c.DB.Exec(`
			INSERT INTO notifications (user_id, title, message, notification_type)
			VALUES ($1, $2, $3, 'task')`,
			req.AssigneeID,
			"New Task Assigned",
			creatorName+" assigned you: "+req.Title,
		)
	}

	// FIX BUG #24: check Scan error after CreateTask fetch
	var id, title, desc, assigneeID, assigneeName, createdBy, proj, pri, status string
	var createdAt interface{}
	if err := c.DB.QueryRow(`
		SELECT t.id, t.title, COALESCE(t.description,''),
		       t.assignee_id, COALESCE(u.name,''),
		       t.created_by,
		       COALESCE(t.project_name,'General'),
		       t.priority, t.status, t.created_at
		FROM tasks t
		LEFT JOIN users u ON u.id = t.assignee_id
		WHERE t.id = $1`, taskID,
	).Scan(&id, &title, &desc, &assigneeID, &assigneeName,
		&createdBy, &proj, &pri, &status, &createdAt); err != nil {
		utils.InternalError(w, err)
		return
	}

	utils.Created(w, map[string]interface{}{
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
	})
}

func (c *TaskController) UpdateStatus(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var req models.UpdateTaskStatusRequest
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) < 2 {
		utils.BadRequest(w, "missing task id")
		return
	}
	taskID := parts[len(parts)-2]

	var createdBy, title, assigneeName string
	c.DB.QueryRow(`
		SELECT t.created_by, t.title, COALESCE(u.name,'')
		FROM tasks t
		LEFT JOIN users u ON u.id = t.assignee_id
		WHERE t.id = $1`, taskID,
	).Scan(&createdBy, &title, &assigneeName)

	// FIX BUG #26: check DB Exec error in UpdateTaskStatus
	if _, err := c.DB.Exec(
		`UPDATE tasks SET status=$1, updated_at=NOW() WHERE id=$2`,
		req.Status, taskID,
	); err != nil {
		utils.InternalError(w, err)
		return
	}

	if req.Status == "done" && createdBy != userID {
		c.DB.Exec(`
			INSERT INTO notifications (user_id, title, message, notification_type)
			VALUES ($1, $2, $3, 'task')`,
			createdBy,
			"Task Completed ✅",
			assigneeName+" completed: "+title+". Please review and approve.",
		)
	}

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

// GetTask returns a single task by ID
func (c *TaskController) GetTask(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) == 0 {
		utils.BadRequest(w, "missing task id")
		return
	}
	taskID := parts[len(parts)-1]

	var id, title, desc, assigneeID, assigneeName, createdBy, proj, pri, status string
	var dueDate, createdAt interface{}

	if err := c.DB.QueryRow(`
		SELECT t.id, t.title, COALESCE(t.description,''),
		       t.assignee_id, COALESCE(u.name,''),
		       t.created_by,
		       COALESCE(t.project_name,'General'),
		       t.priority, t.status,
		       COALESCE(t.due_date, NOW()),
		       t.created_at
		FROM tasks t
		LEFT JOIN users u ON u.id = t.assignee_id
		WHERE t.id = $1`, taskID,
	).Scan(&id, &title, &desc, &assigneeID, &assigneeName,
		&createdBy, &proj, &pri, &status, &dueDate, &createdAt); err != nil {
		if err == sql.ErrNoRows {
			utils.NotFound(w, "task not found")
			return
		}
		utils.InternalError(w, err)
		return
	}

	utils.OK(w, map[string]interface{}{
		"id":            id,
		"title":         title,
		"description":   desc,
		"assignee_id":   assigneeID,
		"assignee_name": assigneeName,
		"created_by":    createdBy,
		"project_name":  proj,
		"priority":      pri,
		"status":        status,
		"due_date":      dueDate,
		"created_at":    createdAt,
		"is_mine":       assigneeID == userID,
		"i_created":     createdBy == userID,
	})
}
