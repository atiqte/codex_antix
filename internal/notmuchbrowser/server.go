package notmuchbrowser

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"net"
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
	Config        Config
	Client        NotmuchClient
	Router        http.Handler
	Signer        capabilitySigner
	inlineSlots   chan struct{}
	downloadSlots chan struct{}
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
	server, err := NewServer(cfg, client)
	if err != nil {
		return err
	}
	httpServer := &http.Server{
		Addr:              cfg.Addr,
		Handler:           server,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}
	fmt.Printf("notmuch_browser_url=http://%s/\n", cfg.Addr)
	fmt.Println("viewer_mode=single_email_go")
	fmt.Println("read_only=yes")
	return httpServer.ListenAndServe()
}

func NewServer(cfg Config, client NotmuchClient) (*Server, error) {
	signer, err := newCapabilitySigner()
	if err != nil {
		return nil, err
	}
	return newServerWithSigner(cfg, client, signer)
}

func newServerWithSigner(cfg Config, client NotmuchClient, signer capabilitySigner) (*Server, error) {
	if err := prepareDownloadTempDir(cfg); err != nil {
		return nil, err
	}
	s := &Server{
		Config:        cfg,
		Client:        client,
		Signer:        signer,
		inlineSlots:   make(chan struct{}, 2),
		downloadSlots: make(chan struct{}, 1),
	}
	s.Router = s.newRouter()
	return s, nil
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
	r.HandleFunc("/attachment", s.handleAttachment)
	r.HandleFunc("/attachments.zip", s.handleAttachmentsZIP)
	r.HandleFunc("/inline-image", s.handleInlineImage)
	r.HandleFunc("/status", s.handleStatus)
	r.HandleFunc("/healthz", s.handleHealthz)
	return r
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; frame-src 'self' about:; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'")
		if strings.HasPrefix(r.URL.Path, "/static/") {
			w.Header().Set("Cache-Control", "public, max-age=0, must-revalidate")
		} else {
			w.Header().Set("Cache-Control", "private, no-store")
		}
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

func requestOrigin(r *http.Request, fallbackAddr string) string {
	host := strings.TrimSpace(r.Host)
	if isLoopbackHostPort(host) {
		return "http://" + host
	}
	return "http://" + fallbackAddr
}

func isLoopbackHostPort(hostPort string) bool {
	host, _, err := net.SplitHostPort(hostPort)
	if err != nil {
		return false
	}
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}
