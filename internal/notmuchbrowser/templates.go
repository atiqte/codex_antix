package notmuchbrowser

import (
	"embed"
	"html/template"
	"net/http"
	"net/mail"
	"net/url"
	"strconv"
	"strings"
	"time"
)

//go:embed templates/*.html templates/partials/*.html
var templateFiles embed.FS

type pageView struct {
	Title      string
	Query      string
	Error      string
	SearchPage SearchPage
}

type messageView struct {
	Error       string
	BodyError   string
	Detail      MessageDetail
	ImageMode   imageMode
	DisplayMode displayMode
	HTMLSrcdoc  string
	SaveAllURL  string
}

type statusView struct {
	Error         string
	Status        Status
	TunnelHint    string
	TempFileCount int
	TempFileBytes int64
}

var templates = template.Must(template.New("notmuch-browser").Funcs(template.FuncMap{
	"add":                 func(a, b int) int { return a + b },
	"displayLimit":        displayLimit,
	"firstShown":          firstShown,
	"hasNext":             hasNext,
	"hasPrev":             hasPrev,
	"nextOffset":          nextOffset,
	"prevOffset":          prevOffset,
	"searchURL":           searchURL,
	"messageURL":          messageURL,
	"messageImageURL":     messageImageURL,
	"messageViewURL":      messageViewURL,
	"messageDuplicateURL": messageDuplicateURL,
	"selectedDup":         selectedDup,
	"formatFileCount":     formatFileCount,
	"formatBytes":         formatBytes,
	"formatReaderDate":    formatReaderDate,
	"formatResultDate":    formatResultDate,
	"icon":                icon,
	"isBlocked":           func(mode imageMode) bool { return mode == imagesBlocked || mode == "" },
	"isEmbedded":          func(mode imageMode) bool { return mode == imagesEmbedded },
	"imagesAllowed":       func(mode imageMode) bool { return mode == imagesEmbedded || mode == imagesRemote },
	"isReadableDisplay":   func(mode displayMode) bool { return mode == displayReadable || mode == "" },
	"isOriginalDisplay":   func(mode displayMode) bool { return mode == displayOriginal },
	"dictTitle":           func(title string) pageView { return pageView{Title: title} },
}).ParseFS(templateFiles, "templates/*.html", "templates/partials/*.html"))

var lucideIconBodies = map[string]string{
	"activity":         `<path d="M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.49 12H2"/>`,
	"archive":          `<rect width="20" height="5" x="2" y="3" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/>`,
	"check":            `<path d="M20 6 9 17l-5-5"/>`,
	"chevron-left":     `<path d="m15 18-6-6 6-6"/>`,
	"chevron-right":    `<path d="m9 18 6-6-6-6"/>`,
	"copy":             `<rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>`,
	"download":         `<path d="M12 15V3"/><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/>`,
	"image":            `<rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/>`,
	"inbox":            `<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>`,
	"mail":             `<path d="m22 7-8.991 5.727a2 2 0 0 1-2.009 0L2 7"/><rect x="2" y="4" width="20" height="16" rx="2"/>`,
	"mail-open":        `<path d="M21.2 8.4c.5.38.8.97.8 1.6v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V10a2 2 0 0 1 .8-1.6l8-6a2 2 0 0 1 2.4 0l8 6Z"/><path d="m22 10-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 10"/>`,
	"menu":             `<path d="M4 5h16"/><path d="M4 12h16"/><path d="M4 19h16"/>`,
	"panel-left-close": `<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 3v18"/><path d="m16 15-3-3 3-3"/>`,
	"panel-left-open":  `<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 3v18"/><path d="m14 9 3 3-3 3"/>`,
	"paperclip":        `<path d="m16 6-8.414 8.586a2 2 0 0 0 2.829 2.829l8.414-8.586a4 4 0 1 0-5.657-5.657l-8.379 8.551a6 6 0 1 0 8.485 8.485l8.379-8.551"/>`,
	"search":           `<path d="m21 21-4.34-4.34"/><circle cx="11" cy="11" r="8"/>`,
	"shield-check":     `<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/>`,
	"x":                `<path d="M18 6 6 18"/><path d="m6 6 12 12"/>`,
}

func icon(name string) template.HTML {
	body, ok := lucideIconBodies[name]
	if !ok {
		return ""
	}
	return template.HTML(`<svg class="icon" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">` + body + `</svg>`)
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

func (s *Server) renderMessageFragment(w http.ResponseWriter, status int, view messageView) {
	writeTemplate(w, status, "messageFragment", view)
}

func (s *Server) renderStatus(w http.ResponseWriter, status int, view statusView) {
	writeTemplate(w, status, "statusPage", view)
}

func writeTemplate(w http.ResponseWriter, status int, name string, data any) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(status)
	if err := templates.ExecuteTemplate(w, name, data); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func displayLimit(page SearchPage) int {
	if page.Limit > 0 {
		return page.Limit
	}
	return 50
}

func firstShown(page SearchPage) int {
	if len(page.Results) == 0 {
		return 0
	}
	return page.Offset + 1
}

func nextOffset(page SearchPage) int {
	return page.Offset + len(page.Results)
}

func prevOffset(page SearchPage) int {
	limit := displayLimit(page)
	offset := page.Offset - limit
	if offset < 0 {
		return 0
	}
	return offset
}

func hasPrev(page SearchPage) bool {
	return page.Offset > 0
}

func hasNext(page SearchPage) bool {
	return nextOffset(page) < page.Counts.Messages
}

func searchURL(query string, offset int, limit int) string {
	values := url.Values{}
	values.Set("q", query)
	values.Set("offset", strconv.Itoa(offset))
	values.Set("limit", strconv.Itoa(limit))
	return "/search?" + values.Encode()
}

func messageURL(id string, duplicate int) string {
	return messageViewURL(id, duplicate, imagesBlocked, displayReadable)
}

func messageImageURL(id string, duplicate int, mode imageMode) string {
	return messageViewURL(id, duplicate, mode, displayReadable)
}

func messageDuplicateURL(id string, duplicate int, display displayMode) string {
	return messageViewURL(id, duplicate, imagesBlocked, display)
}

func messageViewURL(id string, duplicate int, mode imageMode, display displayMode) string {
	values := url.Values{}
	values.Set("id", id)
	if duplicate > 0 {
		values.Set("dup", strconv.Itoa(duplicate))
	}
	if mode != imagesBlocked {
		values.Set("images", string(mode))
	}
	if parseDisplayMode(string(display)) == displayOriginal {
		values.Set("display", string(displayOriginal))
	}
	return "/message?" + values.Encode()
}

func selectedDup(current int, expected int) bool {
	return current == expected
}

func formatFileCount(count int) string {
	if count <= 0 {
		return "?"
	}
	return strconv.Itoa(count)
}

func formatBytes(size int64) string {
	const unit = int64(1024)
	if size < unit {
		return strconv.FormatInt(size, 10) + " B"
	}
	if size < unit*unit {
		return strconv.FormatInt((size+unit/2)/unit, 10) + " KiB"
	}
	return strconv.FormatInt((size+unit*unit/2)/(unit*unit), 10) + " MiB"
}

func formatReaderDate(raw string) string {
	return formatDateInLocation(raw, "Mon, 02 Jan 2006, 03:04:05 PM", time.Local)
}

func formatResultDate(relative string, raw string) string {
	relative = strings.TrimSpace(relative)
	if relative == "" {
		return formatDateInLocation(raw, "02 Jan 2006, 03:04 PM", time.Local)
	}

	fields := strings.Fields(relative)
	last := fields[len(fields)-1]
	parsed, err := time.Parse("15:04", last)
	if err != nil {
		return relative
	}
	prefix := strings.TrimSpace(strings.TrimSuffix(relative, last))
	if prefix == "" {
		return parsed.Format("03:04 PM")
	}
	return prefix + " " + parsed.Format("03:04 PM")
}

func formatDateInLocation(raw string, layout string, location *time.Location) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	parsed, err := mail.ParseDate(raw)
	if err != nil {
		return raw
	}
	if location == nil {
		location = time.Local
	}
	return parsed.In(location).Format(layout)
}
