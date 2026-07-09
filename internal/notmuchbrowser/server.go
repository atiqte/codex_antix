package notmuchbrowser

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

//go:embed static/*
var staticFiles embed.FS

type Server struct {
	Config Config
	Client NotmuchClient
	Router http.Handler
}

func Main(args []string) error {
	cfg, err := ParseConfig(args)
	if err != nil {
		return err
	}
	client := NewNotmuchClient(cfg)
	ctx, cancel := context.WithTimeout(context.Background(), cfg.CommandTimeout)
	defer cancel()
	if err := client.CheckStartupSafety(ctx); err != nil {
		return err
	}
	server := NewServer(cfg, client)
	httpServer := &http.Server{
		Addr:              cfg.Addr,
		Handler:           server,
		ReadHeaderTimeout: 5 * time.Second,
	}
	fmt.Printf("notmuch_browser_url=http://%s/\n", cfg.Addr)
	fmt.Println("viewer_mode=single_email_go")
	fmt.Println("read_only=yes")
	return httpServer.ListenAndServe()
}

func NewServer(cfg Config, client NotmuchClient) *Server {
	s := &Server{Config: cfg, Client: client}
	s.Router = s.newRouter()
	return s
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.Router.ServeHTTP(w, r)
}

func (s *Server) newRouter() http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.Recoverer)
	r.Use(securityHeaders)

	static, err := fs.Sub(staticFiles, "static")
	if err != nil {
		panic(err)
	}
	staticHandler := http.StripPrefix("/static/", http.FileServer(http.FS(static)))
	r.Handle("/static/*", requireGetHandler(staticHandler))

	r.HandleFunc("/", s.handleRoot)
	r.HandleFunc("/search", s.handleSearch)
	r.HandleFunc("/message", s.handleMessage)
	r.HandleFunc("/status", s.handleStatus)
	r.HandleFunc("/healthz", s.handleHealthz)
	return r
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data: cid:; style-src 'self'; script-src 'self'; frame-src 'self' about:; object-src 'none'; base-uri 'none'; form-action 'self'")
		next.ServeHTTP(w, r)
	})
}

func requireGetHandler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !requireGet(w, r) {
			return
		}
		next.ServeHTTP(w, r)
	})
}

func requireGet(w http.ResponseWriter, r *http.Request) bool {
	if r.Method == http.MethodGet || r.Method == http.MethodHead {
		return true
	}
	w.Header().Set("Allow", http.MethodGet)
	http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	return false
}

func isHTMX(r *http.Request) bool {
	return strings.EqualFold(r.Header.Get("HX-Request"), "true")
}

func parseNonNegative(raw string, fallback int) int {
	value, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || value < 0 {
		return fallback
	}
	return value
}

func parseLimit(raw string, fallback int, max int) int {
	value, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || value < 1 {
		return fallback
	}
	if value > max {
		return max
	}
	return value
}

func defaultLimit(cfg Config) int {
	if cfg.MaxResults < 50 {
		return cfg.MaxResults
	}
	return 50
}

func tunnelHint(addr string) string {
	_, port, err := splitAddr(addr)
	if err != nil || port == "" {
		port = "8765"
	}
	return fmt.Sprintf("ssh -N -L %s:127.0.0.1:%s atiq@ANTI_X_VM_IP", port, port)
}

func splitAddr(addr string) (string, string, error) {
	parts := strings.Split(addr, ":")
	if len(parts) < 2 {
		return "", "", fmt.Errorf("missing port")
	}
	port := parts[len(parts)-1]
	host := strings.TrimSuffix(addr, ":"+port)
	return host, port, nil
}
