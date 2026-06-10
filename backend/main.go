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
	// Load config
	config.Load()
	cfg := config.App

	// Connect to PostgreSQL
	db, err := sql.Open("postgres", cfg.DBDSN())
	if err != nil {
		log.Fatal("❌ Cannot open database:", err)
	}
	if err := db.Ping(); err != nil {
		log.Fatal("❌ Cannot connect to database:", err)
	}
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	log.Println("✅ Connected to PostgreSQL:", cfg.DBName)

	// ✅ Auto-create all missing tables
	migrate(db)

	// Init realtime signaling hub
	wsig.GlobalSigHub = wsig.NewSigHub(db)
	wsig.DB = db

	// Setup routes
	handler := routes.Setup(db)

	addr := fmt.Sprintf(":%s", cfg.Port)
	log.Printf("🚀 WorkSpace Pro API running on http://localhost%s", addr)
	log.Printf("📋 Health check: http://localhost%s/health", addr)
	if err := http.ListenAndServe(addr, handler); err != nil {
		log.Fatal("Server error:", err)
	}
}

func migrate(db *sql.DB) {
	queries := []string{
		// Fix user_role for existing users
		`UPDATE users SET user_role='employee' WHERE user_role IS NULL OR user_role=''`,

		// Tasks table
		`CREATE TABLE IF NOT EXISTS tasks (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			title VARCHAR(500) NOT NULL,
			description TEXT DEFAULT '',
			assignee_id UUID,
			created_by UUID,
			project_name VARCHAR(200) DEFAULT 'General',
			due_date TIMESTAMP DEFAULT NOW() + INTERVAL '7 days',
			priority VARCHAR(20) DEFAULT 'medium',
			status VARCHAR(20) DEFAULT 'todo',
			created_at TIMESTAMP DEFAULT NOW(),
			updated_at TIMESTAMP DEFAULT NOW()
		)`,

		// Notifications table
		`CREATE TABLE IF NOT EXISTS notifications (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			user_id UUID NOT NULL,
			title VARCHAR(500) DEFAULT '',
			body TEXT DEFAULT '',
			message TEXT DEFAULT '',
			notification_type VARCHAR(50) DEFAULT 'system',
			action_id VARCHAR(200) DEFAULT '',
			is_read BOOLEAN DEFAULT false,
			created_at TIMESTAMP DEFAULT NOW()
		)`,

		// Approvals table
		`CREATE TABLE IF NOT EXISTS approvals (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			title VARCHAR(500) NOT NULL,
			approval_type VARCHAR(100) DEFAULT 'general',
			requester_id UUID NOT NULL,
			approver_id UUID,
			description TEXT DEFAULT '',
			status VARCHAR(20) DEFAULT 'pending',
			created_at TIMESTAMP DEFAULT NOW(),
			updated_at TIMESTAMP DEFAULT NOW()
		)`,

		// Meeting rooms table
		`CREATE TABLE IF NOT EXISTS meeting_rooms (
			id TEXT PRIMARY KEY,
			title TEXT,
			host_id TEXT,
			host_name TEXT,
			is_active BOOLEAN DEFAULT true,
			created_at TIMESTAMPTZ DEFAULT NOW()
		)`,

		// Room waiting table
		`CREATE TABLE IF NOT EXISTS room_waiting (
			room_id TEXT,
			user_id TEXT,
			user_name TEXT,
			asked_at TIMESTAMPTZ DEFAULT NOW(),
			PRIMARY KEY (room_id, user_id)
		)`,

		// Room participants table
		`CREATE TABLE IF NOT EXISTS room_participants (
			room_id TEXT,
			user_id TEXT,
			user_name TEXT,
			is_host BOOLEAN DEFAULT false,
			joined_at TIMESTAMPTZ DEFAULT NOW(),
			PRIMARY KEY (room_id, user_id)
		)`,

		// Add missing columns safely
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS user_role VARCHAR(20) DEFAULT 'employee'`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS bio TEXT DEFAULT ''`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen TIMESTAMP`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(50) DEFAULT ''`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT DEFAULT ''`,
		`ALTER TABLE notifications ADD COLUMN IF NOT EXISTS body TEXT DEFAULT ''`,
		`ALTER TABLE notifications ADD COLUMN IF NOT EXISTS action_id VARCHAR(200) DEFAULT ''`,
	}

	for _, q := range queries {
		if _, err := db.Exec(q); err != nil {
			log.Println("⚠️ Migration warning:", err)
		}
	}
	log.Println("✅ Database migrations done")
}
