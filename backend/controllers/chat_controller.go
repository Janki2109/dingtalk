package controllers

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"dingtalk/config"
	"dingtalk/models"
	"dingtalk/utils"
)

type ChatController struct{ DB *sql.DB }

func NewChatController(db *sql.DB) *ChatController { return &ChatController{DB: db} }

func (c *ChatController) GetChats(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	fmt.Println("DEBUG GetChats userID:", userID)
	rows, err := c.DB.Query(`
		SELECT
			c.id,
			CASE 
				WHEN c.is_group THEN COALESCE(c.name,'')
				ELSE COALESCE((
					SELECT u.name FROM chat_members cm
					JOIN users u ON u.id = cm.user_id
					WHERE cm.chat_id = c.id AND cm.user_id != $1
					LIMIT 1
				), COALESCE(c.name,''))
			END as name,
			c.is_group,
			CASE
				WHEN c.is_group THEN COALESCE(c.avatar_url,'')
				ELSE COALESCE((
					SELECT u.avatar_url FROM chat_members cm
					JOIN users u ON u.id = cm.user_id
					WHERE cm.chat_id = c.id AND cm.user_id != $1
					LIMIT 1
				), '')
			END as avatar_url,
			COALESCE(c.created_by::text,'') as created_by,
			COALESCE(c.is_pinned, false) as is_pinned,
			COALESCE(c.is_muted, false) as is_muted,
			COALESCE(
				(SELECT content FROM messages WHERE chat_id=c.id ORDER BY created_at DESC LIMIT 1),
				''
			) as last_message,
			COALESCE(
				(SELECT created_at FROM messages WHERE chat_id=c.id ORDER BY created_at DESC LIMIT 1),
				c.created_at
			) as last_time,
			(
				SELECT COUNT(*) FROM messages
				WHERE chat_id=c.id AND sender_id!=$1 AND is_read=false
			) as unread_count
		FROM chats c
		JOIN chat_members cm ON cm.chat_id = c.id AND cm.user_id = $1
		ORDER BY last_time DESC`, userID)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer rows.Close()
	var chats []models.Chat
	for rows.Next() {
		var ch models.Chat
		err := rows.Scan(
			&ch.ID, &ch.Name, &ch.IsGroup, &ch.AvatarURL,
			&ch.CreatedBy, &ch.IsPinned, &ch.IsMuted,
			&ch.LastMessage, &ch.LastTime, &ch.UnreadCount,
		)
		if err != nil {
			continue
		}
		chats = append(chats, ch)
	}
	if chats == nil {
		chats = []models.Chat{}
	}
	utils.OK(w, chats)
}

func (c *ChatController) CreateChat(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var req models.CreateChatRequest
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}
	if !req.IsGroup && len(req.MemberIDs) == 1 {
		otherID := req.MemberIDs[0]
		var existingID string
		err := c.DB.QueryRow(`
			SELECT c.id FROM chats c
			JOIN chat_members cm1 ON cm1.chat_id=c.id AND cm1.user_id=$1
			JOIN chat_members cm2 ON cm2.chat_id=c.id AND cm2.user_id=$2
			WHERE c.is_group=false LIMIT 1`,
			userID, otherID).Scan(&existingID)
		if err == nil && existingID != "" {
			utils.OK(w, map[string]string{"id": existingID})
			return
		}
	}
	name := req.Name
	if !req.IsGroup && len(req.MemberIDs) == 1 {
		c.DB.QueryRow(`SELECT name FROM users WHERE id=$1`, req.MemberIDs[0]).Scan(&name)
	}
	var chatID string
	err := c.DB.QueryRow(`
		INSERT INTO chats (name, is_group, created_by)
		VALUES ($1, $2, $3) RETURNING id`,
		name, req.IsGroup, userID).Scan(&chatID)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	c.DB.Exec(`INSERT INTO chat_members (chat_id, user_id) VALUES ($1, $2)`, chatID, userID)
	for _, mID := range req.MemberIDs {
		if mID != userID {
			c.DB.Exec(`INSERT INTO chat_members (chat_id, user_id) VALUES ($1, $2)`, chatID, mID)
		}
	}
	utils.Created(w, map[string]string{"id": chatID})
}

func (c *ChatController) GetMessages(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	chatID := ""
	for i, p := range parts {
		if p == "chats" && i+1 < len(parts) {
			chatID = parts[i+1]
			break
		}
	}
	if chatID == "" {
		utils.BadRequest(w, "missing chat id")
		return
	}

	// Mark messages as read
	c.DB.Exec(`
		UPDATE messages SET is_read=true
		WHERE chat_id=$1 AND sender_id!=$2 AND is_read=false`,
		chatID, userID)

	rows, err := c.DB.Query(`
		SELECT
			m.id,
			m.chat_id,
			m.sender_id,
			COALESCE(u.name, 'Unknown') as sender_name,
			COALESCE(u.avatar_url, '') as sender_avatar,
			m.content,
			COALESCE(m.message_type, 'text') as message_type,
			COALESCE(m.file_url, '') as file_url,
			COALESCE(m.file_name, '') as file_name,
			COALESCE(m.reply_to_id::text, '') as reply_to_id,
			m.is_read,
			m.created_at
		FROM messages m
		LEFT JOIN users u ON u.id = m.sender_id
		WHERE m.chat_id = $1
		ORDER BY m.created_at ASC
		LIMIT 200`, chatID)
	if err != nil {
		utils.InternalError(w, err)
		return
	}
	defer rows.Close()

	var messages []models.Message
	for rows.Next() {
		var msg models.Message
		var senderAvatar string
		err := rows.Scan(
			&msg.ID, &msg.ChatID, &msg.SenderID, &msg.SenderName, &senderAvatar,
			&msg.Content, &msg.MessageType, &msg.FileURL, &msg.FileName,
			&msg.ReplyToID, &msg.IsRead, &msg.CreatedAt,
		)
		if err != nil {
			continue
		}
		messages = append(messages, msg)
	}
	if messages == nil {
		messages = []models.Message{}
	}
	utils.OK(w, messages)
}

func (c *ChatController) SendMessage(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	chatID := ""
	for i, p := range parts {
		if p == "chats" && i+1 < len(parts) {
			chatID = parts[i+1]
			break
		}
	}
	if chatID == "" {
		utils.BadRequest(w, "missing chat id")
		return
	}

	var req models.SendMessageRequest
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}
	msgType := req.MessageType
	if msgType == "" {
		msgType = "text"
	}

	// ✅ FIX: save file_url and file_name
	// ✅ REPLACE WITH:
	fileURL := req.FileURL
	fileName := req.FileName

	var msg models.Message
	err := c.DB.QueryRow(`
		INSERT INTO messages (chat_id, sender_id, content, message_type, file_url, file_name, is_read)
		VALUES ($1, $2, $3, $4, $5, $6, false)
		RETURNING id, chat_id, sender_id, content, message_type,
		          COALESCE(file_url,''), COALESCE(file_name,''), is_read, created_at`,
		chatID, userID, req.Content, msgType, fileURL, fileName,
	).Scan(&msg.ID, &msg.ChatID, &msg.SenderID, &msg.Content,
		&msg.MessageType, &msg.FileURL, &msg.FileName, &msg.IsRead, &msg.CreatedAt)
	if err != nil {
		utils.InternalError(w, err)
		return
	}

	// Get sender's real name
	c.DB.QueryRow(`SELECT name FROM users WHERE id=$1`, userID).Scan(&msg.SenderName)
	c.DB.Exec(`UPDATE chats SET updated_at=NOW() WHERE id=$1`, chatID)

	utils.Created(w, msg)
}

func (c *ChatController) MarkChatRead(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	chatID := ""
	for i, p := range parts {
		if p == "chats" && i+1 < len(parts) {
			chatID = parts[i+1]
			break
		}
	}
	c.DB.Exec(`
		UPDATE messages SET is_read=true
		WHERE chat_id=$1 AND sender_id!=$2 AND is_read=false`,
		chatID, userID)
	utils.OK(w, map[string]string{"message": "marked read"})
}

func (c *ChatController) AIChat(w http.ResponseWriter, r *http.Request) {
	var req models.AIChatRequest
	if err := utils.Decode(r, &req); err != nil {
		utils.BadRequest(w, "invalid body")
		return
	}
	if req.Message == "" {
		utils.BadRequest(w, "message required")
		return
	}

	apiKey := config.App.GeminiAPIKey
	if apiKey == "" {
		utils.Error(w, http.StatusInternalServerError, "Gemini API key not configured")
		return
	}

	geminiURL := "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=" + apiKey
	prompt := "You are a smart, friendly AI assistant built into a workplace app. Respond conversationally and helpfully — like ChatGPT or Gemini would. Be clear and concise. Use bullet points or numbered lists when it makes the answer easier to read. Help with anything the user asks: emails, coding, questions, brainstorming, summaries, planning, and more. Do not mention that you are Gemini or any specific AI model — just call yourself 'AI Assistant'.\n\nUser: " + req.Message

	payload := map[string]interface{}{
		"contents": []map[string]interface{}{
			{"parts": []map[string]interface{}{{"text": prompt}}},
		},
		"generationConfig": map[string]interface{}{"temperature": 0.9, "maxOutputTokens": 2048},
	}
	bodyBytes, _ := json.Marshal(payload)
	httpResp, err := http.Post(geminiURL, "application/json", bytes.NewBuffer(bodyBytes))
	if err != nil {
		utils.Error(w, http.StatusInternalServerError, "Gemini unreachable: "+err.Error())
		return
	}
	defer httpResp.Body.Close()

	var result map[string]interface{}
	json.NewDecoder(httpResp.Body).Decode(&result)

	if errObj, ok := result["error"]; ok {
		if errMap, ok := errObj.(map[string]interface{}); ok {
			utils.Error(w, http.StatusBadGateway, fmt.Sprintf("Gemini: %v", errMap["message"]))
			return
		}
	}

	reply := "I couldn't process that. Please try again."
	if candidates, ok := result["candidates"].([]interface{}); ok && len(candidates) > 0 {
		if c0, ok := candidates[0].(map[string]interface{}); ok {
			if content, ok := c0["content"].(map[string]interface{}); ok {
				if pts, ok := content["parts"].([]interface{}); ok && len(pts) > 0 {
					if pt, ok := pts[0].(map[string]interface{}); ok {
						if txt, ok := pt["text"].(string); ok && txt != "" {
							reply = txt
						}
					}
				}
			}
		}
	}
	utils.OK(w, models.AIChatResponse{Reply: reply})
}

func (c *ChatController) DeleteChat(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	chatID := ""
	for i, p := range parts {
		if p == "chats" && i+1 < len(parts) {
			chatID = parts[i+1]
			break
		}
	}
	if chatID == "" {
		utils.BadRequest(w, "missing chat id")
		return
	}

	var userRole string
	c.DB.QueryRow(`SELECT COALESCE(user_role,'employee') FROM users WHERE id=$1`, userID).Scan(&userRole)

	var memberCount int
	c.DB.QueryRow(`SELECT COUNT(*) FROM chat_members WHERE chat_id=$1 AND user_id=$2`, chatID, userID).Scan(&memberCount)

	if memberCount == 0 && userRole != "admin" {
		utils.Error(w, http.StatusForbidden, "not authorized to delete this chat")
		return
	}

	c.DB.Exec(`DELETE FROM messages WHERE chat_id=$1`, chatID)
	c.DB.Exec(`DELETE FROM chat_members WHERE chat_id=$1`, chatID)
	c.DB.Exec(`DELETE FROM chats WHERE id=$1`, chatID)

	utils.OK(w, map[string]string{"message": "chat deleted"})
}

func formatChatTime(t time.Time) string { return t.Format("2006-01-02 15:04:05") }
