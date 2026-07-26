package notmuchbrowser

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
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
	catalog, err := s.Client.SearchFolderCatalog(r.Context())
	if err != nil {
		s.renderPage(r.Context(), w, http.StatusOK, "Search", pageView{
			Query: query,
			Error: err.Error(),
		})
		return
	}
	folder, ok := catalog.Resolve(r.URL.Query().Get("folder"))
	if !ok {
		s.renderPage(r.Context(), w, http.StatusOK, "Search", pageView{
			Query:      query,
			Error:      "Unknown mail folder selection.",
			SearchPage: SearchPage{FolderCatalog: catalog, Folder: catalog.All},
		})
		return
	}
	page, err := s.Client.Search(r.Context(), query, folder, 0, defaultLimit(s.Config))
	page.FolderCatalog = catalog
	if err != nil {
		s.renderPage(r.Context(), w, http.StatusOK, "Search", pageView{
			Query:      query,
			Error:      err.Error(),
			SearchPage: page,
		})
		return
	}
	s.renderPage(r.Context(), w, http.StatusOK, "Search", pageView{
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
	catalog, err := s.Client.SearchFolderCatalog(r.Context())
	if err != nil {
		view := pageView{Query: query, Error: err.Error()}
		if isHTMX(r) {
			w.Header().Set("Vary", "HX-Request")
			s.renderResults(r.Context(), w, http.StatusOK, view)
			return
		}
		s.renderPage(r.Context(), w, http.StatusOK, "Search", view)
		return
	}
	folder, ok := catalog.Resolve(r.URL.Query().Get("folder"))
	if !ok {
		view := pageView{
			Query:      query,
			Error:      "Unknown mail folder selection.",
			SearchPage: SearchPage{FolderCatalog: catalog, Folder: catalog.All},
		}
		if isHTMX(r) {
			w.Header().Set("Vary", "HX-Request")
			s.renderResults(r.Context(), w, http.StatusOK, view)
			return
		}
		s.renderPage(r.Context(), w, http.StatusOK, "Search", view)
		return
	}
	page, err := s.Client.Search(r.Context(), query, folder, offset, limit)
	page.FolderCatalog = catalog
	view := pageView{Query: query, SearchPage: page}
	if err != nil {
		view.Error = err.Error()
	}
	if isHTMX(r) {
		w.Header().Set("Vary", "HX-Request")
		s.renderResults(r.Context(), w, http.StatusOK, view)
		return
	}
	s.renderPage(r.Context(), w, http.StatusOK, "Search", view)
}

func (s *Server) handleMessage(w http.ResponseWriter, r *http.Request) {
	if !requireGet(w, r) {
		return
	}
	id := r.URL.Query().Get("id")
	dup := parseNonNegative(r.URL.Query().Get("dup"), 0)
	detail, err := s.Client.Message(r.Context(), id, dup)
	mode := imagesBlocked
	if isHTMX(r) {
		mode = parseImageMode(r.URL.Query().Get("images"))
	}
	view := messageView{
		Detail:      detail,
		ImageMode:   mode,
		DisplayMode: parseDisplayMode(r.URL.Query().Get("display")),
	}
	if err != nil {
		view.Error = err.Error()
	} else if err := s.prepareMessageView(r, &view); err != nil {
		view.BodyError = err.Error()
	}
	if isHTMX(r) {
		w.Header().Set("Vary", "HX-Request")
		s.renderMessageFragment(r.Context(), w, http.StatusOK, view)
		return
	}
	s.renderMessage(r.Context(), w, http.StatusOK, view)
}

func (s *Server) prepareMessageView(r *http.Request, view *messageView) error {
	detail := &view.Detail
	origin := requestOrigin(r, s.Config.Addr)
	inlineURLs := make(map[int]string)
	cidURLs := make(map[string]string)
	nameURLs := make(map[string]string)
	for _, part := range detail.Parts {
		if part.ID <= 0 || part.NestedInAttachment || !browserImageType(part.MediaType) {
			continue
		}
		name := attachmentName(part)
		token, err := s.Signer.Sign(capabilityPayload{
			Purpose:   purposeInline,
			MessageID: detail.Summary.ID,
			Duplicate: detail.SelectedDup,
			Part:      part.ID,
			FileName:  name,
			MediaType: part.MediaType,
		})
		if err != nil {
			return fmt.Errorf("create inline image capability: %w", err)
		}
		path := signedRoute("/inline-image", token)
		inlineURLs[part.ID] = path
	}
	imageParts := embeddedImageParts(detail.Parts)
	for cid, partID := range imageParts.CIDs {
		if path := inlineURLs[partID]; path != "" {
			cidURLs[strings.ToLower(cid)] = origin + path
		}
	}
	for name, partID := range imageParts.Names {
		if path := inlineURLs[partID]; path != "" {
			nameURLs[name] = origin + path
		}
	}
	for i := range detail.Attachments {
		attachment := &detail.Attachments[i]
		token, err := s.Signer.Sign(capabilityPayload{
			Purpose:   purposeAttachment,
			MessageID: detail.Summary.ID,
			Duplicate: detail.SelectedDup,
			Part:      attachment.PartID,
			FileName:  attachment.FileName,
			MediaType: attachment.MediaType,
		})
		if err != nil {
			return fmt.Errorf("create attachment capability: %w", err)
		}
		attachment.DownloadURL = signedRoute("/attachment", token)
		attachment.InlineURL = inlineURLs[attachment.PartID]
	}
	if len(detail.Attachments) > 0 {
		token, err := s.Signer.Sign(capabilityPayload{
			Purpose:   purposeArchive,
			MessageID: detail.Summary.ID,
			Duplicate: detail.SelectedDup,
		})
		if err != nil {
			return fmt.Errorf("create archive capability: %w", err)
		}
		view.SaveAllURL = signedRoute("/attachments.zip", token)
	}
	if detail.BodyKind == "html" {
		srcdoc, err := sanitizeEmailHTMLForDisplay(detail.HTMLBody, view.ImageMode, view.DisplayMode, origin, cidURLs, nameURLs)
		if err != nil {
			return fmt.Errorf("email HTML cannot be rendered safely: %w", err)
		}
		view.HTMLSrcdoc = srcdoc
	}
	return nil
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
	view.TempFileCount, view.TempFileBytes = temporaryFileStats(s.Config.DownloadTempDir)
	if err != nil {
		view.Error = err.Error()
	}
	s.renderStatus(r.Context(), w, http.StatusOK, view)
}

func (s *Server) handleHealthz(w http.ResponseWriter, r *http.Request) {
	if !requireGet(w, r) {
		return
	}
	status, err := s.Client.Status(r.Context())
	ok := err == nil && status.DatabasePath == s.Config.ExpectedDatabasePath && status.MailRoot == s.Config.ExpectedMailRoot && status.MaildirSyncFlags == s.Config.ExpectedSyncFlags && status.IndexDecrypt == s.Config.ExpectedIndexDecrypt
	payload := map[string]any{
		"ok":                       ok,
		"read_only":                true,
		"viewer_mode":              "single_email_go",
		"addr":                     s.Config.Addr,
		"config":                   s.Config.NotmuchConfig,
		"mbsync_lock_present":      status.MbsyncLockPresent,
		"mail_mutation":            false,
		"downloads_enabled":        true,
		"temporary_download_files": true,
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
