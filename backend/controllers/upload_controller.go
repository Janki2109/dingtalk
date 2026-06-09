package controllers

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"dingtalk/utils"
)

type UploadController struct{}

func NewUploadController() *UploadController {
	os.MkdirAll("uploads", 0755)
	return &UploadController{}
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

	ext := filepath.Ext(header.Filename)
	uniqueName := fmt.Sprintf("%d%s", time.Now().UnixNano(), ext)
	dstPath := filepath.Join("uploads", uniqueName)

	dst, err := os.Create(dstPath)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer dst.Close()

	size, err := io.Copy(dst, file)
	if err != nil {
		utils.InternalError(w, err)
		return
	}

	utils.OK(w, map[string]interface{}{
		"url":      "/uploads/" + uniqueName,
		"name":     header.Filename,
		"size":     size,
		"size_str": formatSize(size),
	})
}
