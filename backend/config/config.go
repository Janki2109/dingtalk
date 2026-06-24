package config

import (
	"fmt"
	"log"
	"os"

	"github.com/joho/godotenv"
)

type Config struct {
	Port           string
	DBHost         string
	DBPort         string
	DBUser         string
	DBPassword     string
	DBName         string
	DBSSLMode      string
	JWTSecret      string
	JWTExpiryHours string
	GeminiAPIKey   string
	DingTalkAppKey string
	DingTalkSecret string
	AllowedOrigins string
}

var App *Config

func Load() {
	if err := godotenv.Load(); err != nil {
		log.Println("⚠️  No .env file found, using system environment variables")
	} else {
		log.Println("✅ .env file loaded successfully")
	}

	App = &Config{
		Port:       getEnv("PORT", "8080"),
		DBHost:     getEnv("DB_HOST", "localhost"),
		DBPort:     getEnv("DB_PORT", "5432"),
		DBUser:     getEnv("DB_USER", "postgres"),
		DBPassword: getEnv("DB_PASSWORD", "postgres"),
		DBName:     getEnv("DB_NAME", "dingtalk"),
		DBSSLMode:  getEnv("DB_SSLMODE", "disable"),

		// FIX BUG 28: JWT secret must be set — crash at startup if missing
		JWTSecret: getEnvRequired("JWT_SECRET"),

		JWTExpiryHours: getEnv("JWT_EXPIRY_HOURS", "72"),
		GeminiAPIKey:   getEnv("GEMINI_API_KEY", ""),
		DingTalkAppKey: getEnv("DINGTALK_APP_KEY", ""),
		DingTalkSecret: getEnv("DINGTALK_APP_SECRET", ""),
		AllowedOrigins: getEnv("ALLOWED_ORIGINS", "*"),
	}

	if App.GeminiAPIKey != "" {
		log.Println("✅ Gemini API key loaded")
	} else {
		log.Println("❌ Gemini API key NOT found — AI will not work!")
	}
}

func (c *Config) DBDSN() string {
	return fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		c.DBHost, c.DBPort, c.DBUser,
		c.DBPassword, c.DBName, c.DBSSLMode,
	)
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// FIX BUG 28: crash at startup if a required env var is missing
func getEnvRequired(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("FATAL: required environment variable %q is not set. Server cannot start safely.", key)
	}
	return v
}
