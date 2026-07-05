package notmuchbrowser

import (
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"net/http"
	"strconv"
	"strings"
	"time"
)

//go:embed static/*
var staticFiles embed.FS

type Server struct {
	Config Config
	Client NotmuchClient
	Mux    *http.ServeMux
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
	s := &Server{Config: cfg, Client: client, Mux: http.NewServeMux()}
	static, _ := fs.Sub(staticFiles, "static")
	s.Mux.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.FS(static))))
	s.Mux.HandleFunc("/", s.handleRoot)
	s.Mux.HandleFunc("/search", s.handleSearch)
	s.Mux.HandleFunc("/message", s.handleMessage)
	s.Mux.HandleFunc("/status", s.handleStatus)
	s.Mux.HandleFunc("/healthz", s.handleHealthz)
	return s
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data: cid:; style-src 'self'; script-src 'self'; frame-src 'self' about:; object-src 'none'; base-uri 'none'; form-action 'self'")
	s.Mux.ServeHTTP(w, r)
}

func (s *Server) handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	if !requireGet(w, r) {
		return
	}
	query := normalizeQuery(r.URL.Query().Get("q"))
	page, err := s.Client.Search(r.Context(), query, 0, defaultLimit(s.Config))
	if err != nil {
		s.renderPage(w, http.StatusOK, "Search", pageView{
			Query: query,
			Error: err.Error(),
		})
		return
	}
	s.renderPage(w, http.StatusOK, "Search", pageView{
		Query:      query,
		SearchPage: page,
	})
}

func (s *Server) handleSearch(w http.ResponseWriter, r *http.Request) {
	if !requireGet(w, r) {
		return
	}
	query := normalizeQuery(r.URL.Query().Get("q"))
	offset := parseNonNegative(r.URL.Query().Get("offset"), 0)
	limit := parseLimit(r.URL.Query().Get("limit"), defaultLimit(s.Config), s.Config.MaxResults)
	page, err := s.Client.Search(r.Context(), query, offset, limit)
	view := pageView{Query: query, SearchPage: page}
	if err != nil {
		view.Error = err.Error()
	}
	if isHTMX(r) {
		w.Header().Set("Vary", "HX-Request")
		s.renderResults(w, http.StatusOK, view)
		return
	}
	s.renderPage(w, http.StatusOK, "Search", view)
}

func (s *Server) handleMessage(w http.ResponseWriter, r *http.Request) {
	if !requireGet(w, r) {
		return
	}
	id := r.URL.Query().Get("id")
	dup := parseNonNegative(r.URL.Query().Get("dup"), 0)
	detail, err := s.Client.Message(r.Context(), id, dup)
	view := messageView{Detail: detail}
	if err != nil {
		view.Error = err.Error()
	}
	s.renderMessage(w, http.StatusOK, view)
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	if !requireGet(w, r) {
		return
	}
	status, err := s.Client.Status(r.Context())
	view := statusView{
		Status:     status,
		TunnelHint: tunnelHint(s.Config.Addr),
	}
	if err != nil {
		view.Error = err.Error()
	}
	s.renderStatus(w, http.StatusOK, view)
}

func (s *Server) handleHealthz(w http.ResponseWriter, r *http.Request) {
	if !requireGet(w, r) {
		return
	}
	status, err := s.Client.Status(r.Context())
	ok := err == nil && status.DatabasePath == s.Config.ExpectedDatabasePath && status.MailRoot == s.Config.ExpectedMailRoot && status.MaildirSyncFlags == s.Config.ExpectedSyncFlags && status.IndexDecrypt == s.Config.ExpectedIndexDecrypt
	payload := map[string]any{
		"ok":                  ok,
		"read_only":           true,
		"viewer_mode":         "single_email_go",
		"addr":                s.Config.Addr,
		"config":              s.Config.NotmuchConfig,
		"mbsync_lock_present": status.MbsyncLockPresent,
	}
	if err != nil {
		payload["error"] = err.Error()
	} else {
		payload["messages"] = status.Counts.Messages
		payload["files"] = status.Counts.Files
		payload["database_path"] = status.DatabasePath
		payload["mail_root"] = status.MailRoot
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	if !ok {
		w.WriteHeader(http.StatusServiceUnavailable)
	}
	_ = json.NewEncoder(w).Encode(payload)
}

func (s *Server) renderPage(w http.ResponseWriter, status int, title string, view pageView) {
	view.Title = title
	writeTemplate(w, status, "page", view)
}

func (s *Server) renderResults(w http.ResponseWriter, status int, view pageView) {
	writeTemplate(w, status, "results", view)
}

func (s *Server) renderMessage(w http.ResponseWriter, status int, view messageView) {
	writeTemplate(w, status, "messagePage", view)
}

func (s *Server) renderStatus(w http.ResponseWriter, status int, view statusView) {
	writeTemplate(w, status, "statusPage", view)
}

func requireGet(w http.ResponseWriter, r *http.Request) bool {
	if r.Method == http.MethodGet || r.Method == http.MethodHead {
		return true
	}
	w.Header().Set("Allow", http.MethodGet)
	http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	return false
}

func writeTemplate(w http.ResponseWriter, status int, name string, data any) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(status)
	if err := templates.ExecuteTemplate(w, name, data); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
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
