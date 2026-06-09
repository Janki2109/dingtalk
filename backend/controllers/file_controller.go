package controllers

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"dingtalk/utils"
)

type FileController struct{ DB *sql.DB }

func NewFileController(db *sql.DB) *FileController {
	return &FileController{DB: db}
}

type FileRecord struct {
	ID         string    `json:"id"`
	Name       string    `json:"name"`
	FileType   string    `json:"file_type"`
	SizeBytes  int64     `json:"size_bytes"`
	SizeStr    string    `json:"size_str"`
	URL        string    `json:"url"`
	UploadedBy string    `json:"uploaded_by"`
	UploadedAt time.Time `json:"uploaded_at"`
	FromChat   bool      `json:"from_chat"`
}

func (c *FileController) GetFiles(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	rows, err := c.DB.Query(`
		SELECT f.id, f.name, COALESCE(f.file_type,''),
		       f.size_bytes, COALESCE(u.name,'You'),
		       f.uploaded_at,
		       COALESCE(f.url,''),
		       CASE WHEN f.chat_id IS NOT NULL THEN true ELSE false END
		FROM files f
		LEFT JOIN users u ON u.id = f.uploaded_by
		WHERE f.uploaded_by = $1
		ORDER BY f.uploaded_at DESC`, userID)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer rows.Close()

	var files []FileRecord
	for rows.Next() {
		var f FileRecord
		var sizeBytes int64
		rows.Scan(&f.ID, &f.Name, &f.FileType,
			&sizeBytes, &f.UploadedBy, &f.UploadedAt, &f.URL, &f.FromChat)
		f.SizeBytes = sizeBytes
		f.SizeStr = formatSize(sizeBytes)
		files = append(files, f)
	}
	if files == nil {
		files = []FileRecord{}
	}
	utils.OK(w, files)
}

func (c *FileController) UploadFile(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var req struct {
		Name     string `json:"name"`
		FileType string `json:"file_type"`
		Size     int64  `json:"size"`
		URL      string `json:"url"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	if req.Name == "" {
		utils.BadRequest(w, "file name required")
		return
	}

	ext := req.FileType
	if ext == "" && strings.Contains(req.Name, ".") {
		parts := strings.Split(req.Name, ".")
		ext = parts[len(parts)-1]
	}

	var f FileRecord
	err := c.DB.QueryRow(`
		INSERT INTO files (name, file_type, size_bytes, url, uploaded_by)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, name, file_type, size_bytes, COALESCE(url,''), uploaded_at`,
		req.Name, ext, req.Size, req.URL, userID,
	).Scan(&f.ID, &f.Name, &f.FileType, &f.SizeBytes, &f.URL, &f.UploadedAt)

	if err != nil {
		utils.InternalError(w, err)
		return
	}
	f.SizeStr = formatSize(f.SizeBytes)
	f.UploadedBy = "You"
	f.FromChat = false

	utils.Created(w, f)
}

func (c *FileController) DeleteFile(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	fileID := ""
	for i, p := range parts {
		if p == "files" && i+1 < len(parts) {
			fileID = parts[i+1]
			break
		}
	}
	c.DB.Exec(`DELETE FROM files WHERE id=$1 AND uploaded_by=$2`,
		fileID, userID)
	utils.OK(w, map[string]string{"status": "deleted"})
}

func formatSize(bytes int64) string {
	if bytes == 0 {
		return "0 KB"
	}
	kb := float64(bytes) / 1024
	if kb < 1024 {
		return fmt.Sprintf("%.0f KB", kb)
	}
	mb := kb / 1024
	if mb < 1024 {
		return fmt.Sprintf("%.1f MB", mb)
	}
	return fmt.Sprintf("%.1f GB", mb/1024)
}
