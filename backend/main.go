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

	// Init realtime signaling hub
	wsig.GlobalSigHub = wsig.NewSigHub(db)
	// ✅ ADD THIS LINE:
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
