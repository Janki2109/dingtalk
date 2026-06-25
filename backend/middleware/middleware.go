package middleware

import (
	"errors"
	"log"
	"net/http"
	"net/netip"
	"strings"
	"sync"
	"time"

	"dingtalk/config"

	"github.com/golang-jwt/jwt/v5"
)

// ── CORS ──────────────────────────────────────────────────────────────────────
func CORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type,Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// ── Logger ────────────────────────────────────────────────────────────────────
func Logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		println("["+time.Now().Format("15:04:05")+"]", r.Method, r.URL.Path, time.Since(start).String())
	})
}

// ── Auth ──────────────────────────────────────────────────────────────────────
type Claims struct {
	UserID string `json:"user_id"`
	Email  string `json:"email"`
	jwt.RegisteredClaims
}

// FIX BUG #37: use config.App.JWTSecret — consistent with rest of app config
func getJWTSecret() []byte {
	if config.App.JWTSecret == "" {
		log.Fatal("FATAL: JWT_SECRET is not configured")
	}
	return []byte(config.App.JWTSecret)
}

func GenerateToken(userID, email string) (string, error) {
	claims := Claims{
		UserID: userID,
		Email:  email,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(72 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(getJWTSecret())
}

func ValidateToken(tokenStr string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		// Enforce HMAC algorithm — reject alg:none attacks
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return getJWTSecret(), nil
	})
	if err != nil || !token.Valid {
		return nil, errors.New("invalid or expired token")
	}
	claims, ok := token.Claims.(*Claims)
	if !ok {
		return nil, errors.New("invalid token claims")
	}
	return claims, nil
}

func Auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		claims, err := ValidateToken(strings.TrimPrefix(authHeader, "Bearer "))
		if err != nil {
			http.Error(w, `{"error":"invalid token"}`, http.StatusUnauthorized)
			return
		}
		r.Header.Set("X-User-ID", claims.UserID)
		r.Header.Set("X-User-Email", claims.Email)
		next.ServeHTTP(w, r)
	})
}

// ── Rate Limiter ──────────────────────────────────────────────────────────────
type rateLimiter struct {
	mu       sync.Mutex
	attempts map[string][]time.Time
	limit    int
	window   time.Duration
}

var loginLimiter = &rateLimiter{
	attempts: make(map[string][]time.Time),
	limit:    10,
	window:   time.Minute,
}

func init() {
	// FIX BUG #6: periodically evict old IPs to prevent memory leak
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			loginLimiter.mu.Lock()
			cutoff := time.Now().Add(-loginLimiter.window)
			for ip, times := range loginLimiter.attempts {
				var recent []time.Time
				for _, t := range times {
					if t.After(cutoff) {
						recent = append(recent, t)
					}
				}
				if len(recent) == 0 {
					// FIX BUG #6: delete IPs with no recent attempts
					delete(loginLimiter.attempts, ip)
				} else {
					loginLimiter.attempts[ip] = recent
				}
			}
			loginLimiter.mu.Unlock()
		}
	}()
}

func (rl *rateLimiter) allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	now := time.Now()
	cutoff := now.Add(-rl.window)
	var recent []time.Time
	for _, t := range rl.attempts[ip] {
		if t.After(cutoff) {
			recent = append(recent, t)
		}
	}
	recent = append(recent, now)
	rl.attempts[ip] = recent
	return len(recent) <= rl.limit
}

// FIX BUG #7: validate X-Forwarded-For instead of blindly trusting it
func getIP(r *http.Request) string {
	forwarded := r.Header.Get("X-Forwarded-For")
	if forwarded != "" {
		// Take first IP and validate it is a real IP
		candidate := strings.TrimSpace(strings.Split(forwarded, ",")[0])
		if _, err := netip.ParseAddr(candidate); err == nil {
			return candidate
		}
	}
	// Fall back to RemoteAddr (strip port)
	addr := r.RemoteAddr
	if host, _, err := splitHostPort(addr); err == nil {
		return host
	}
	return addr
}

func splitHostPort(addr string) (string, string, error) {
	// handles both IPv4 and IPv6
	lastColon := strings.LastIndex(addr, ":")
	if lastColon < 0 {
		return addr, "", nil
	}
	host := addr[:lastColon]
	port := addr[lastColon+1:]
	// IPv6 addresses are wrapped in brackets
	host = strings.Trim(host, "[]")
	return host, port, nil
}

// RateLimit wraps a handler — use on /auth/login route
func RateLimit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := getIP(r)
		if !loginLimiter.allow(ip) {
			http.Error(w, `{"error":"too many requests — please wait 1 minute"}`, http.StatusTooManyRequests)
			return
		}
		next.ServeHTTP(w, r)
	})
}
