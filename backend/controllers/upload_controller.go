package controllers

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"dingtalk/utils"
)

type UploadController struct{}

func NewUploadController() *UploadController {
	os.MkdirAll("uploads", 0755)
	return &UploadController{}
}

// FIX BUG #39: strict allowed file types — executables and malware blocked
var allowedExtensions = map[string]bool{
	// Images
	".jpg": true, ".jpeg": true, ".png": true,
	".gif": true, ".webp": true, ".svg": true,
	// Documents
	".pdf": true, ".doc": true, ".docx": true,
	".xls": true, ".xlsx": true, ".ppt": true,
	".pptx": true, ".txt": true, ".csv": true,
	// Audio / Video
	".mp3": true, ".mp4": true, ".wav": true,
	".ogg": true, ".webm": true,
	// Archives
	".zip": true, ".rar": true,
}

// Allowed MIME type prefixes for double-checking
var allowedMIMEPrefixes = []string{
	"image/",
	"video/",
	"audio/",
	"application/pdf",
	"application/msword",
	"application/vnd.openxmlformats",
	"application/vnd.ms-",
	"text/plain",
	"text/csv",
	"application/zip",
	"application/x-rar",
	"application/octet-stream", // some mobile clients send this for all files
}

func isAllowedMIME(mime string) bool {
	mime = strings.ToLower(mime)
	for _, prefix := range allowedMIMEPrefixes {
		if strings.HasPrefix(mime, prefix) {
			return true
		}
	}
	return false
}

func (c *UploadController) Upload(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(50 << 20); err != nil {
		utils.BadRequest(w, "file too large (max 50 MB)")
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		utils.BadRequest(w, "file field required")
		return
	}
	defer file.Close()

	// FIX BUG #39: validate file extension
	ext := strings.ToLower(filepath.Ext(header.Filename))
	if ext == "" {
		utils.Error(w, http.StatusBadRequest, "file must have an extension")
		return
	}
	if !allowedExtensions[ext] {
		utils.Error(w, http.StatusBadRequest,
			fmt.Sprintf("file type '%s' is not allowed. Allowed types: images, pdf, office documents, audio, video, zip", ext))
		return
	}

	// FIX BUG #39: validate MIME type from Content-Type header
	contentType := header.Header.Get("Content-Type")
	if contentType != "" && !isAllowedMIME(contentType) {
		utils.Error(w, http.StatusBadRequest,
			fmt.Sprintf("MIME type '%s' is not allowed", contentType))
		return
	}

	// FIX BUG #39: read first 512 bytes to detect real file type
	buf := make([]byte, 512)
	n, _ := file.Read(buf)
	detectedMIME := http.DetectContentType(buf[:n])
	if !isAllowedMIME(detectedMIME) {
		utils.Error(w, http.StatusBadRequest,
			fmt.Sprintf("detected file type '%s' is not allowed", detectedMIME))
		return
	}

	// Safe unique filename — strip original name to avoid path traversal
	uniqueName := fmt.Sprintf("%d%s", time.Now().UnixNano(), ext)
	dstPath := filepath.Join("uploads", uniqueName)

	dst, err := os.Create(dstPath)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer dst.Close()

	// Write the already-read bytes first, then copy the rest
	if _, err := dst.Write(buf[:n]); err != nil {
		utils.InternalError(w, err)
		return
	}
	remaining, err := io.Copy(dst, file)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	size := int64(n) + remaining

	utils.OK(w, map[string]interface{}{
		"url":      "/uploads/" + uniqueName,
		"name":     header.Filename,
		"size":     size,
		"size_str": formatSize(size),
	})
}
