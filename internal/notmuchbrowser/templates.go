package notmuchbrowser

import (
	"embed"
	"html/template"
	"net/http"
	"net/url"
	"strconv"
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
	Error  string
	Detail MessageDetail
}

type statusView struct {
	Error      string
	Status     Status
	TunnelHint string
}

var templates = template.Must(template.New("notmuch-browser").Funcs(template.FuncMap{
	"add":             func(a, b int) int { return a + b },
	"displayLimit":    displayLimit,
	"firstShown":      firstShown,
	"hasNext":         hasNext,
	"hasPrev":         hasPrev,
	"nextOffset":      nextOffset,
	"prevOffset":      prevOffset,
	"searchURL":       searchURL,
	"messageURL":      messageURL,
	"selectedDup":     selectedDup,
	"formatFileCount": formatFileCount,
	"dictTitle":       func(title string) pageView { return pageView{Title: title} },
}).ParseFS(templateFiles, "templates/*.html", "templates/partials/*.html"))

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
	values := url.Values{}
	values.Set("id", id)
	if duplicate > 0 {
		values.Set("dup", strconv.Itoa(duplicate))
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
