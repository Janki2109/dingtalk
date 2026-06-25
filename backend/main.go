package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"

	"dingtalk/config"
	"dingtalk/routes"
	wsig "dingtalk/websocket"

	_ "github.com/lib/pq"
)

func main() {
	config.Load()
	cfg := config.App

	db, err := sql.Open("postgres", cfg.DBDSN())
	if err != nil {
		log.Fatal("Cannot open database:", err)
	}
	if err := db.Ping(); err != nil {
		log.Fatal("Cannot connect to database:", err)
	}
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	log.Println("Connected to PostgreSQL:", cfg.DBName)

	migrate(db)

	wsig.GlobalSigHub = wsig.NewSigHub(db)
	wsig.DB = db

	handler := routes.Setup(db)

	addr := fmt.Sprintf(":%s", cfg.Port)
	log.Printf("WorkSpace Pro API running on http://localhost%s", addr)
	if err := http.ListenAndServe(addr, handler); err != nil {
		log.Fatal("Server error:", err)
	}
}

// execOrLog runs a DB statement and logs any error instead of silently ignoring it
// FIX BUG #2: all migration errors now logged
func execOrLog(db *sql.DB, label, query string) {
	if _, err := db.Exec(query); err != nil {
		log.Printf("Migration warning [%s]: %v", label, err)
	}
}

func migrate(db *sql.DB) {
	log.Println("Running migrations...")

	// FIX BUG #1: ALTER TABLE must run BEFORE UPDATE that uses the column
	execOrLog(db, "add user_role column", "ALTER TABLE users ADD COLUMN IF NOT EXISTS user_role VARCHAR(20) DEFAULT 'employee'")
	execOrLog(db, "add bio column", "ALTER TABLE users ADD COLUMN IF NOT EXISTS bio TEXT DEFAULT ''")
	execOrLog(db, "add last_seen column", "ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen TIMESTAMP")
	execOrLog(db, "add phone column", "ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(50) DEFAULT ''")
	execOrLog(db, "add avatar_url column", "ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT DEFAULT ''")

	// Now safe to UPDATE because column exists
	execOrLog(db, "fix user roles", "UPDATE users SET user_role='employee' WHERE user_role IS NULL OR user_role=''")

	// Create chat tables
	execOrLog(db, "create chats", `CREATE TABLE IF NOT EXISTS chats (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		name VARCHAR(200) DEFAULT '',
		is_group BOOLEAN DEFAULT false,
		avatar_url TEXT DEFAULT '',
		created_by UUID,
		is_pinned BOOLEAN DEFAULT false,
		is_muted BOOLEAN DEFAULT false,
		created_at TIMESTAMP DEFAULT NOW(),
		updated_at TIMESTAMP DEFAULT NOW()
	)`)

	execOrLog(db, "create chat_members", `CREATE TABLE IF NOT EXISTS chat_members (
		chat_id UUID,
		user_id UUID,
		PRIMARY KEY (chat_id, user_id)
	)`)

	execOrLog(db, "create messages", `CREATE TABLE IF NOT EXISTS messages (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		chat_id UUID,
		sender_id UUID,
		content TEXT DEFAULT '',
		message_type VARCHAR(50) DEFAULT 'text',
		file_url TEXT DEFAULT '',
		file_name TEXT DEFAULT '',
		reply_to_id UUID,
		is_read BOOLEAN DEFAULT false,
		created_at TIMESTAMP DEFAULT NOW()
	)`)

	// FIX BUG #3: create meeting_chat_messages table that signaling.go inserts into
	execOrLog(db, "create meeting_chat_messages", `CREATE TABLE IF NOT EXISTS meeting_chat_messages (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		meeting_id TEXT NOT NULL,
		sender_id TEXT NOT NULL,
		content TEXT DEFAULT '',
		created_at TIMESTAMP DEFAULT NOW()
	)`)

	execOrLog(db, "add messages.file_url", "ALTER TABLE messages ADD COLUMN IF NOT EXISTS file_url TEXT DEFAULT ''")
	execOrLog(db, "add messages.file_name", "ALTER TABLE messages ADD COLUMN IF NOT EXISTS file_name TEXT DEFAULT ''")
	execOrLog(db, "add messages.reply_to_id", "ALTER TABLE messages ADD COLUMN IF NOT EXISTS reply_to_id UUID")

	execOrLog(db, "add chats.is_pinned", "ALTER TABLE chats ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false")
	execOrLog(db, "add chats.is_muted", "ALTER TABLE chats ADD COLUMN IF NOT EXISTS is_muted BOOLEAN DEFAULT false")
	execOrLog(db, "add chats.avatar_url", "ALTER TABLE chats ADD COLUMN IF NOT EXISTS avatar_url TEXT DEFAULT ''")
	execOrLog(db, "add chats.updated_at", "ALTER TABLE chats ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW()")

	execOrLog(db, "add tasks.created_at", "ALTER TABLE tasks ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT NOW()")
	execOrLog(db, "add tasks.updated_at", "ALTER TABLE tasks ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW()")
	execOrLog(db, "add tasks.assignee_id", "ALTER TABLE tasks ADD COLUMN IF NOT EXISTS assignee_id UUID")
	execOrLog(db, "add tasks.created_by", "ALTER TABLE tasks ADD COLUMN IF NOT EXISTS created_by UUID")
	execOrLog(db, "add tasks.project_name", "ALTER TABLE tasks ADD COLUMN IF NOT EXISTS project_name VARCHAR(200) DEFAULT 'General'")
	execOrLog(db, "add tasks.due_date", "ALTER TABLE tasks ADD COLUMN IF NOT EXISTS due_date TIMESTAMP DEFAULT NOW()")
	execOrLog(db, "add tasks.priority", "ALTER TABLE tasks ADD COLUMN IF NOT EXISTS priority VARCHAR(20) DEFAULT 'medium'")
	execOrLog(db, "add tasks.description", "ALTER TABLE tasks ADD COLUMN IF NOT EXISTS description TEXT DEFAULT ''")
	execOrLog(db, "add tasks.status", "ALTER TABLE tasks ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'todo'")
	execOrLog(db, "add tasks.title", "ALTER TABLE tasks ADD COLUMN IF NOT EXISTS title VARCHAR(500)")

	execOrLog(db, "create tasks", `CREATE TABLE IF NOT EXISTS tasks (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		title VARCHAR(500) NOT NULL,
		description TEXT DEFAULT '',
		assignee_id UUID,
		created_by UUID,
		project_name VARCHAR(200) DEFAULT 'General',
		due_date TIMESTAMP DEFAULT NOW(),
		priority VARCHAR(20) DEFAULT 'medium',
		status VARCHAR(20) DEFAULT 'todo',
		created_at TIMESTAMP DEFAULT NOW(),
		updated_at TIMESTAMP DEFAULT NOW()
	)`)

	execOrLog(db, "create notifications", `CREATE TABLE IF NOT EXISTS notifications (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		user_id UUID NOT NULL,
		title VARCHAR(500) DEFAULT '',
		body TEXT DEFAULT '',
		message TEXT DEFAULT '',
		notification_type VARCHAR(50) DEFAULT 'system',
		action_id VARCHAR(200) DEFAULT '',
		is_read BOOLEAN DEFAULT false,
		created_at TIMESTAMP DEFAULT NOW()
	)`)

	execOrLog(db, "add notifications.body", "ALTER TABLE notifications ADD COLUMN IF NOT EXISTS body TEXT DEFAULT ''")
	execOrLog(db, "add notifications.action_id", "ALTER TABLE notifications ADD COLUMN IF NOT EXISTS action_id VARCHAR(200) DEFAULT ''")
	execOrLog(db, "add notifications.message", "ALTER TABLE notifications ADD COLUMN IF NOT EXISTS message TEXT DEFAULT ''")

	execOrLog(db, "create approvals", `CREATE TABLE IF NOT EXISTS approvals (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		title VARCHAR(500) NOT NULL,
		approval_type VARCHAR(100) DEFAULT 'general',
		requester_id UUID NOT NULL,
		approver_id UUID,
		description TEXT DEFAULT '',
		status VARCHAR(20) DEFAULT 'pending',
		created_at TIMESTAMP DEFAULT NOW(),
		updated_at TIMESTAMP DEFAULT NOW()
	)`)

	execOrLog(db, "create meeting_rooms", `CREATE TABLE IF NOT EXISTS meeting_rooms (
		id TEXT PRIMARY KEY,
		title TEXT,
		host_id TEXT,
		host_name TEXT,
		is_active BOOLEAN DEFAULT true,
		created_at TIMESTAMPTZ DEFAULT NOW()
	)`)

	execOrLog(db, "create room_waiting", `CREATE TABLE IF NOT EXISTS room_waiting (
		room_id TEXT,
		user_id TEXT,
		user_name TEXT,
		asked_at TIMESTAMPTZ DEFAULT NOW(),
		PRIMARY KEY (room_id, user_id)
	)`)

	execOrLog(db, "create room_participants", `CREATE TABLE IF NOT EXISTS room_participants (
		room_id TEXT,
		user_id TEXT,
		user_name TEXT,
		is_host BOOLEAN DEFAULT false,
		joined_at TIMESTAMPTZ DEFAULT NOW(),
		PRIMARY KEY (room_id, user_id)
	)`)

	// FIX BUG #8: domain column is used by auth_controller for tenant isolation
	execOrLog(db, "add domain column", "ALTER TABLE users ADD COLUMN IF NOT EXISTS domain VARCHAR(255) DEFAULT ''")

	// FIX BUG #42: signaling.go inserts into meeting_attendance on every WS connect
	execOrLog(db, "create meeting_attendance", `CREATE TABLE IF NOT EXISTS meeting_attendance (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		meeting_id TEXT NOT NULL,
		user_id TEXT NOT NULL,
		joined_at TIMESTAMPTZ DEFAULT NOW(),
		left_at TIMESTAMPTZ,
		status VARCHAR(20) DEFAULT 'attended',
		UNIQUE (meeting_id, user_id)
	)`)

	log.Println("Migrations done!")
}
