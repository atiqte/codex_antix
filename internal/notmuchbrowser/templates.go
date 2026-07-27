package notmuchbrowser

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"net/mail"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/a-h/templ"
)

const htmxConfigJSON = `{"allowEval":false,"allowScriptTags":false,"historyRestoreAsHxRequest":false,"historyCacheSize":0}`

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

type messageAddressView struct {
	Display string
	Address string
	Mailto  string
}

type messageAddressListView struct {
	Addresses []messageAddressView
	Fallback  string
	Parsed    bool
}

func (s *Server) renderPage(ctx context.Context, w http.ResponseWriter, status int, title string, view pageView) {
	view.Title = title
	writeComponent(ctx, w, status, pageComponent(view))
}

func (s *Server) renderResults(ctx context.Context, w http.ResponseWriter, status int, view pageView) {
	writeComponent(ctx, w, status, resultsComponent(view))
}

func (s *Server) renderMessage(ctx context.Context, w http.ResponseWriter, status int, view messageView) {
	writeComponent(ctx, w, status, messagePageComponent(view))
}

func (s *Server) renderMessageFragment(ctx context.Context, w http.ResponseWriter, status int, view messageView) {
	writeComponent(ctx, w, status, messageFragmentComponent(view))
}

func (s *Server) renderStatus(ctx context.Context, w http.ResponseWriter, status int, view statusView) {
	writeComponent(ctx, w, status, statusPageComponent(view))
}

func writeComponent(ctx context.Context, w http.ResponseWriter, status int, component templ.Component) {
	var buf bytes.Buffer
	if err := component.Render(ctx, &buf); err != nil {
		http.Error(w, "page rendering failed", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(status)
	_, _ = buf.WriteTo(w)
}

func namedComponent(name string, data any) (templ.Component, error) {
	switch name {
	case "page":
		view, ok := data.(pageView)
		if !ok {
			return nil, fmt.Errorf("page component requires pageView")
		}
		return pageComponent(view), nil
	case "results":
		view, ok := data.(pageView)
		if !ok {
			return nil, fmt.Errorf("results component requires pageView")
		}
		return resultsComponent(view), nil
	case "messagePage":
		view, ok := data.(messageView)
		if !ok {
			return nil, fmt.Errorf("messagePage component requires messageView")
		}
		return messagePageComponent(view), nil
	case "messageFragment":
		view, ok := data.(messageView)
		if !ok {
			return nil, fmt.Errorf("messageFragment component requires messageView")
		}
		return messageFragmentComponent(view), nil
	case "statusPage":
		view, ok := data.(statusView)
		if !ok {
			return nil, fmt.Errorf("statusPage component requires statusView")
		}
		return statusPageComponent(view), nil
	default:
		return nil, fmt.Errorf("unknown component %q", name)
	}
}

func isBlocked(mode imageMode) bool {
	return mode == imagesBlocked || mode == ""
}

func isEmbedded(mode imageMode) bool {
	return mode == imagesEmbedded
}

func imagesAllowed(mode imageMode) bool {
	return mode == imagesEmbedded || mode == imagesRemote
}

func isReadableDisplay(mode displayMode) bool {
	return mode == displayReadable || mode == ""
}

func isOriginalDisplay(mode displayMode) bool {
	return mode == displayOriginal
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

func searchURL(query string, folder string, offset int, limit int) string {
	values := url.Values{}
	values.Set("q", query)
	if folder != "" && folder != "all" {
		values.Set("folder", folder)
	}
	values.Set("offset", strconv.Itoa(offset))
	values.Set("limit", strconv.Itoa(limit))
	return "/search?" + values.Encode()
}

func searchShortcutURL(query string, folder string) string {
	return searchURL(query, folder, 0, 50)
}

func folderSelected(current string, candidate string) bool {
	if current == "" {
		current = "all"
	}
	return current == candidate
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

func messageAddressList(raw string) messageAddressListView {
	raw = strings.TrimSpace(raw)
	view := messageAddressListView{Fallback: raw}
	if raw == "" {
		return view
	}

	parsed, err := mail.ParseAddressList(raw)
	if err != nil || len(parsed) == 0 {
		return view
	}
	view.Addresses = make([]messageAddressView, 0, len(parsed))
	for _, address := range parsed {
		if address == nil {
			return messageAddressListView{Fallback: raw}
		}
		email := strings.TrimSpace(address.Address)
		if email == "" || containsControlCharacter(email) {
			return messageAddressListView{Fallback: raw}
		}
		display := email
		if name := strings.TrimSpace(address.Name); name != "" {
			display = name + " <" + email + ">"
		}
		view.Addresses = append(view.Addresses, messageAddressView{
			Display: display,
			Address: email,
			Mailto:  (&url.URL{Scheme: "mailto", Opaque: url.PathEscape(email)}).String(),
		})
	}
	view.Parsed = true
	return view
}

func containsControlCharacter(value string) bool {
	for _, character := range value {
		if character < 0x20 || character == 0x7f {
			return true
		}
	}
	return false
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

func formatResultDate(timestamp int64, raw string, now time.Time) string {
	parsed, ok := resultDate(timestamp, raw)
	if !ok {
		return strings.TrimSpace(raw)
	}
	if now.IsZero() {
		now = time.Now()
	}
	parsed = parsed.In(time.Local)
	now = now.In(time.Local)
	if parsed.After(now) {
		return parsed.Format("Mon, 02 Jan 2006, 03:04:05 PM")
	}
	age := now.Sub(parsed)
	switch {
	case age < time.Minute:
		return "Now"
	case age < time.Hour:
		return strconv.Itoa(int(age/time.Minute)) + " min ago"
	case age < 2*time.Hour:
		return "1 hour ago"
	case sameCalendarDay(parsed, now):
		return "Today " + parsed.Format("03:04:05 PM")
	case sameCalendarDay(parsed, now.AddDate(0, 0, -1)):
		return "Yesterday " + parsed.Format("03:04:05 PM")
	default:
		return parsed.Format("Mon, 02 Jan 2006, 03:04:05 PM")
	}
}

func resultDateTime(timestamp int64, raw string) string {
	parsed, ok := resultDate(timestamp, raw)
	if !ok {
		return ""
	}
	return parsed.In(time.Local).Format(time.RFC3339)
}

func resultDateTitle(timestamp int64, raw string) string {
	parsed, ok := resultDate(timestamp, raw)
	if !ok {
		return strings.TrimSpace(raw)
	}
	return parsed.In(time.Local).Format("Mon, 02 Jan 2006, 03:04:05 PM MST")
}

func resultDate(timestamp int64, raw string) (time.Time, bool) {
	if timestamp > 0 {
		return time.Unix(timestamp, 0), true
	}
	parsed, err := mail.ParseDate(strings.TrimSpace(raw))
	if err != nil {
		return time.Time{}, false
	}
	return parsed, true
}

func sameCalendarDay(a time.Time, b time.Time) bool {
	ay, am, ad := a.Date()
	by, bm, bd := b.Date()
	return ay == by && am == bm && ad == bd
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
