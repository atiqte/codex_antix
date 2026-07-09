package notmuchbrowser

import (
	"encoding/json"
	"net/http"
)

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
