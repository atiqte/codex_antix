package notmuchbrowser

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type fakeRunner struct {
	outputs    map[string]string
	rawOutputs map[string][]byte
	errs       map[string]error
	calls      [][]string
}

func (f *fakeRunner) RunRaw(ctx context.Context, timeout time.Duration, output io.Writer, args ...string) (string, error) {
	f.calls = append(f.calls, append([]string(nil), args...))
	key := strings.Join(args, "\x00")
	if err := f.errs[key]; err != nil {
		return "fake stderr", err
	}
	data := f.rawOutputs[key]
	if data == nil {
		data = []byte(f.outputs[key])
	}
	_, err := output.Write(data)
	return "", err
}

func (f *fakeRunner) Run(ctx context.Context, timeout time.Duration, args ...string) (string, string, error) {
	f.calls = append(f.calls, append([]string(nil), args...))
	key := strings.Join(args, "\x00")
	if err := f.errs[key]; err != nil {
		return "", "fake stderr", err
	}
	return f.outputs[key], "", nil
}

func testConfig() Config {
	cfg := DefaultConfig()
	cfg.NotmuchConfig = "/home/atiq/.config/notmuch/default/config"
	cfg.CommandTimeout = time.Second
	cfg.ShowTimeout = time.Second
	cfg.MaxResults = 200
	return cfg
}

func TestConfigValidation(t *testing.T) {
	cfg := testConfig()
	if err := cfg.ValidateQuery("tag:inbox"); err != nil {
		t.Fatalf("expected valid query: %v", err)
	}
	if err := cfg.ValidateQuery("bad\x00query"); err == nil {
		t.Fatalf("expected NUL query to be rejected")
	}
	if err := cfg.ValidateMessageID("abc@example.test"); err != nil {
		t.Fatalf("expected valid message id: %v", err)
	}
	if err := cfg.ValidateMessageID("bad\x00id"); err == nil {
		t.Fatalf("expected NUL message id to be rejected")
	}
	cfg.Addr = "0.0.0.0:8765"
	if err := cfg.ValidateBind(); err == nil {
		t.Fatalf("expected non-localhost bind refusal")
	}
	cfg.Addr = ":8765"
	if err := cfg.ValidateBind(); err == nil {
		t.Fatalf("expected all-interface bind refusal")
	}
}

func TestParseSummaries(t *testing.T) {
	summaries, err := ParseSummaries([]byte(sampleNotmuchJSON))
	if err != nil {
		t.Fatalf("ParseSummaries returned error: %v", err)
	}
	if len(summaries) != 1 {
		t.Fatalf("expected 1 summary, got %d", len(summaries))
	}
	got := summaries[0]
	if got.ID != "abc@example.test" {
		t.Fatalf("unexpected id: %q", got.ID)
	}
	if got.Subject != "Quarterly update" || got.From != "A User <a@example.test>" || got.Cc != "C User <c@example.test>" {
		t.Fatalf("unexpected headers: %#v", got)
	}
	if got.FileCount != 2 {
		t.Fatalf("expected duplicate file count 2, got %d", got.FileCount)
	}
	if len(got.Tags) != 2 || got.Tags[0] != "inbox" || got.Tags[1] != "unread" {
		t.Fatalf("unexpected tags: %#v", got.Tags)
	}
}

func TestParseMessageDetailsPrefersHTMLAndAttachments(t *testing.T) {
	details, err := ParseMessageDetails([]byte(sampleNotmuchJSON))
	if err != nil {
		t.Fatalf("ParseMessageDetails returned error: %v", err)
	}
	if len(details) != 1 {
		t.Fatalf("expected 1 detail, got %d", len(details))
	}
	got := details[0]
	if got.BodyKind != "html" {
		t.Fatalf("expected html body, got %q", got.BodyKind)
	}
	if len(got.Attachments) != 1 || got.Attachments[0].FileName != "invoice.pdf" || got.Attachments[0].PartID != 3 {
		t.Fatalf("unexpected attachments: %#v", got.Attachments)
	}
}

func TestSearchCommandConstruction(t *testing.T) {
	cfg := testConfig()
	runner := &fakeRunner{
		outputs: map[string]string{
			"count\x00tag:inbox":                   "1\n",
			"count\x00--output=files\x00tag:inbox": "2\n",
			"show\x00--format=json\x00--entire-thread=false\x00--body=false\x00--offset=10\x00--limit=25\x00tag:inbox": sampleNotmuchJSON,
		},
		errs: map[string]error{},
	}
	client := NotmuchClient{Config: cfg, Runner: runner}
	page, err := client.Search(context.Background(), "tag:inbox", 10, 25)
	if err != nil {
		t.Fatalf("Search returned error: %v", err)
	}
	if page.Counts.Messages != 1 || page.Counts.Files != 2 {
		t.Fatalf("unexpected counts: %#v", page.Counts)
	}
	if len(runner.calls) != 3 {
		t.Fatalf("expected 3 notmuch calls, got %d", len(runner.calls))
	}
	show := strings.Join(runner.calls[2], " ")
	for _, want := range []string{"show", "--format=json", "--entire-thread=false", "--body=false", "--offset=10", "--limit=25", "tag:inbox"} {
		if !strings.Contains(show, want) {
			t.Fatalf("show command missing %q: %s", want, show)
		}
	}
}

func TestMessageCommandConstructionUsesDuplicate(t *testing.T) {
	cfg := testConfig()
	runner := &fakeRunner{
		outputs: map[string]string{
			"search\x00--output=files\x00id:abc@example.test": "/mail/a\n/mail/b\n",
			"show\x00--format=json\x00--entire-thread=false\x00--include-html\x00--decrypt=false\x00--duplicate=2\x00id:abc@example.test": sampleNotmuchJSON,
		},
		errs: map[string]error{},
	}
	client := NotmuchClient{Config: cfg, Runner: runner}
	detail, err := client.Message(context.Background(), "abc@example.test", 1)
	if err != nil {
		t.Fatalf("Message returned error: %v", err)
	}
	if detail.SelectedFile != "/mail/b" {
		t.Fatalf("expected selected duplicate file /mail/b, got %q", detail.SelectedFile)
	}
	if len(runner.calls) != 2 {
		t.Fatalf("expected 2 notmuch calls, got %d", len(runner.calls))
	}
	show := strings.Join(runner.calls[1], " ")
	if !strings.Contains(show, "--duplicate=2") || !strings.Contains(show, "--decrypt=false") {
		t.Fatalf("message command missing safety flags: %s", show)
	}
}

func TestRunnerErrorPropagates(t *testing.T) {
	cfg := testConfig()
	runner := &fakeRunner{
		outputs: map[string]string{},
		errs: map[string]error{
			"count\x00tag:inbox": errors.New("boom"),
		},
	}
	client := NotmuchClient{Config: cfg, Runner: runner}
	_, err := client.Search(context.Background(), "tag:inbox", 0, 10)
	if err == nil {
		t.Fatalf("expected search error")
	}
}

func TestTemplateEscapesSearchResults(t *testing.T) {
	view := pageView{
		Query: "tag:inbox",
		SearchPage: SearchPage{
			Query:  "tag:inbox",
			Limit:  50,
			Counts: Counts{Messages: 1, Files: 1},
			Results: []MessageSummary{{
				ID:      "evil@example.test",
				Subject: `<script>alert("x")</script>`,
				From:    "Tester",
				Tags:    []string{"inbox"},
			}},
		},
	}
	var buf bytes.Buffer
	if err := templates.ExecuteTemplate(&buf, "results", view); err != nil {
		t.Fatalf("template render failed: %v", err)
	}
	out := buf.String()
	if strings.Contains(out, `<script>alert("x")</script>`) {
		t.Fatalf("raw script was not escaped: %s", out)
	}
	if !strings.Contains(out, "&lt;script&gt;") {
		t.Fatalf("escaped script marker missing: %s", out)
	}
}

func TestRouteRejectsPost(t *testing.T) {
	server := newHTTPTestServer(t)
	req := httptest.NewRequest(http.MethodPost, "/search", nil)
	res := httptest.NewRecorder()
	server.ServeHTTP(res, req)
	if res.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", res.Code)
	}
	if got := res.Header().Get("Allow"); got != http.MethodGet {
		t.Fatalf("expected Allow GET, got %q", got)
	}
}

func TestSecurityHeadersAndHTMXFragment(t *testing.T) {
	server := newHTTPTestServer(t)
	req := httptest.NewRequest(http.MethodGet, "/search?q=tag%3Ainbox", nil)
	req.Header.Set("HX-Request", "true")
	res := httptest.NewRecorder()
	server.ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", res.Code, res.Body.String())
	}
	if got := res.Header().Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("missing security header, got %q", got)
	}
	if got := res.Header().Get("Vary"); got != "HX-Request" {
		t.Fatalf("expected HTMX vary header, got %q", got)
	}
	if csp := res.Header().Get("Content-Security-Policy"); strings.Contains(csp, "cid:") || !strings.Contains(csp, "frame-ancestors 'none'") {
		t.Fatalf("unexpected parent CSP: %q", csp)
	}
	out := res.Body.String()
	if strings.Contains(out, "<!doctype html>") {
		t.Fatalf("HTMX fragment included full page shell: %s", out)
	}
	if !strings.Contains(out, `id="result-toolbar-slot" hx-swap-oob="innerHTML"`) {
		t.Fatalf("HTMX fragment missing OOB toolbar update: %s", out)
	}
	if strings.Contains(out, `class="result-toolbar"`) {
		t.Fatalf("HTMX fragment retained dedicated result-toolbar band: %s", out)
	}
}

func TestStaticAssetServedLocally(t *testing.T) {
	server := newHTTPTestServer(t)
	req := httptest.NewRequest(http.MethodGet, "/static/app.css", nil)
	res := httptest.NewRecorder()
	server.ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", res.Code)
	}
	css := res.Body.String()
	if !strings.Contains(css, "tailwindcss") || !strings.Contains(css, ".app-sidebar") {
		t.Fatalf("static CSS did not look like compiled local Tailwind output")
	}
	for _, want := range []string{"--result-pane-height:35%", "grid-template-rows:minmax(160px, var(--result-pane-height)) 7px minmax(260px, 1fr)", "cursor:row-resize", ".app-mobilebar{display:none}", ".search-subbar{", "grid-template-columns:minmax(0,1fr) auto", ".result-toolbar-slot{min-width:0}", ".result-pagination{", "grid-template-columns:repeat(2,30px)", ".mini-copy-button{width:22px", ".result-subject-line .subject,.result-id-line .path,.reader-heading-title h1,.message-id-line .path{overflow-wrap:anywhere;min-width:0;display:inline}", "align-items:baseline", "text-align:right", "white-space:nowrap", "@media (max-width:860px)", ".search-subbar{grid-template-columns:minmax(0,1fr);align-items:stretch}"} {
		if !strings.Contains(css, want) {
			t.Fatalf("compiled CSS missing GUI rule %q", want)
		}
	}
	for _, unwanted := range []string{".app-topbar{", ".mode-indicator{", ".pager{", ".result-toolbar{"} {
		if strings.Contains(css, unwanted) {
			t.Fatalf("compiled CSS retained removed GUI rule %q", unwanted)
		}
	}
}

func TestApplicationJavaScriptServedLocally(t *testing.T) {
	server := newHTTPTestServer(t)
	res := httptest.NewRecorder()
	server.ServeHTTP(res, httptest.NewRequest(http.MethodGet, "/static/app.js", nil))
	if res.Code != http.StatusOK {
		t.Fatalf("local application JavaScript missing: status=%d body=%s", res.Code, res.Body.String())
	}
	js := res.Body.String()
	for _, want := range []string{"data-pane-divider", "notmuch-browser.result-pane-height-percent", "event.clientY", "bounds.height", "ArrowUp", "ArrowDown", "[data-copy-target], [data-copy-text]", "button.dataset.copyText"} {
		if !strings.Contains(js, want) {
			t.Fatalf("local application JavaScript missing horizontal splitter behavior %q", want)
		}
	}
	for _, unwanted := range []string{"notmuch-browser.result-pane-percent", "event.clientX", "bounds.width", "ArrowLeft", "ArrowRight"} {
		if strings.Contains(js, unwanted) {
			t.Fatalf("local application JavaScript retained vertical splitter behavior %q", unwanted)
		}
	}
}

func TestSearchShellIncludesReusableEmptyReaderState(t *testing.T) {
	server := newHTTPTestServer(t)
	res := httptest.NewRecorder()
	server.ServeHTTP(res, httptest.NewRequest(http.MethodGet, "/", nil))
	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `<template id="reader-empty-template">`) || strings.Count(res.Body.String(), "No message selected") != 2 {
		t.Fatalf("search shell reader reset template missing: status=%d body=%s", res.Code, res.Body.String())
	}
}

func TestSearchShellUsesHorizontalSplitter(t *testing.T) {
	server := newHTTPTestServer(t)
	res := httptest.NewRecorder()
	server.ServeHTTP(res, httptest.NewRequest(http.MethodGet, "/", nil))
	if res.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", res.Code)
	}
	out := res.Body.String()
	for _, want := range []string{`aria-orientation="horizontal"`, `aria-valuemin="25"`, `aria-valuemax="70"`, `aria-valuenow="35"`, `id="results"`, `id="reading-pane-content"`} {
		if !strings.Contains(out, want) {
			t.Fatalf("search shell missing horizontal splitter contract %q", want)
		}
	}
	if strings.Contains(out, `aria-orientation="vertical"`) {
		t.Fatalf("search shell retained vertical splitter orientation")
	}
}

func TestMessageHTMXFragmentHasBlockedImagesAndSignedDownloads(t *testing.T) {
	server := newHTTPTestServer(t)
	req := httptest.NewRequest(http.MethodGet, "/message?id=abc%40example.test", nil)
	req.Header.Set("HX-Request", "true")
	res := httptest.NewRecorder()
	server.ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("message status=%d body=%s", res.Code, res.Body.String())
	}
	out := res.Body.String()
	if strings.Contains(out, "<!doctype html>") || !strings.Contains(out, "Images blocked") {
		t.Fatalf("unexpected message fragment shell/state: %s", out)
	}
	for _, want := range []string{"/attachment?cap=", "/attachments.zip?cap=", "img-src &amp;#39;none&amp;#39;", `<iframe sandbox referrerpolicy="no-referrer"`, "No external server will be contacted"} {
		if !strings.Contains(out, want) {
			t.Fatalf("message fragment missing %q: %s", want, out)
		}
	}
}

func TestImagePermissionResetsOnFullPageReload(t *testing.T) {
	server := newHTTPTestServer(t)
	path := "/message?id=abc%40example.test&images=remote"
	full := httptest.NewRecorder()
	server.ServeHTTP(full, httptest.NewRequest(http.MethodGet, path, nil))
	if full.Code != http.StatusOK || !strings.Contains(full.Body.String(), "Images blocked") || strings.Contains(full.Body.String(), "Remote images allowed") {
		t.Fatalf("full-page reload did not reset image permission: status=%d body=%s", full.Code, full.Body.String())
	}
	htmxRequest := httptest.NewRequest(http.MethodGet, path, nil)
	htmxRequest.Header.Set("HX-Request", "true")
	fragment := httptest.NewRecorder()
	server.ServeHTTP(fragment, htmxRequest)
	if fragment.Code != http.StatusOK || !strings.Contains(fragment.Body.String(), "Remote images allowed") {
		t.Fatalf("HTMX confirmation state missing: status=%d body=%s", fragment.Code, fragment.Body.String())
	}
}

func TestHealthReportsDownloadReadOnlyContract(t *testing.T) {
	server := newHTTPTestServer(t)
	res := httptest.NewRecorder()
	server.ServeHTTP(res, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if res.Code != http.StatusOK {
		t.Fatalf("health status=%d body=%s", res.Code, res.Body.String())
	}
	out := res.Body.String()
	for _, want := range []string{`"read_only":true`, `"mail_mutation":false`, `"downloads_enabled":true`, `"temporary_download_files":true`} {
		if !strings.Contains(out, want) {
			t.Fatalf("health payload missing %s: %s", want, out)
		}
	}
}

func TestTemplateRendersDuplicateSelector(t *testing.T) {
	view := messageView{
		Detail: MessageDetail{
			Summary: MessageSummary{
				ID:      "abc@example.test",
				Subject: "Duplicate test",
				Tags:    []string{"inbox"},
			},
			Files:         []string{"/mail/a", "/mail/b"},
			SelectedDup:   1,
			SelectedFile:  "/mail/b",
			PlainBody:     "plain body",
			BodyKind:      "plain",
			DuplicateNote: "2 duplicate/copy files share this Message-ID",
		},
	}
	var buf bytes.Buffer
	if err := templates.ExecuteTemplate(&buf, "messagePage", view); err != nil {
		t.Fatalf("template render failed: %v", err)
	}
	out := buf.String()
	if !strings.Contains(out, "2 duplicate/copy files") {
		t.Fatalf("duplicate note missing: %s", out)
	}
	if !strings.Contains(out, `<strong title="/mail/b">2</strong>`) {
		t.Fatalf("selected duplicate marker missing: %s", out)
	}
	if !strings.Contains(out, `href="/message?id=abc%40example.test"`) {
		t.Fatalf("duplicate navigation link missing: %s", out)
	}
}

func newHTTPTestServer(t *testing.T) *Server {
	t.Helper()
	cfg := testConfig()
	cfg.DownloadTempDir = filepath.Join(t.TempDir(), "download-tmp")
	runner := &fakeRunner{
		outputs: map[string]string{
			"count\x00tag:inbox":                   "1\n",
			"count\x00--output=files\x00tag:inbox": "2\n",
			"show\x00--format=json\x00--entire-thread=false\x00--body=false\x00--offset=0\x00--limit=50\x00tag:inbox": sampleNotmuchJSON,
			"count\x00tag:attachment":                   "1\n",
			"count\x00--output=files\x00tag:attachment": "2\n",
			"show\x00--format=json\x00--entire-thread=false\x00--body=false\x00--offset=0\x00--limit=50\x00tag:attachment": sampleNotmuchJSON,
			"count\x00*":                   "1\n",
			"count\x00--output=files\x00*": "2\n",
			"show\x00--format=json\x00--entire-thread=false\x00--body=false\x00--offset=0\x00--limit=50\x00*": sampleNotmuchJSON,
			"config\x00get\x00database.path":                  cfg.ExpectedDatabasePath + "\n",
			"config\x00get\x00database.mail_root":             cfg.ExpectedMailRoot + "\n",
			"config\x00get\x00maildir.synchronize_flags":      cfg.ExpectedSyncFlags + "\n",
			"config\x00get\x00index.decrypt":                  cfg.ExpectedIndexDecrypt + "\n",
			"config\x00get\x00new.ignore":                     "evolution/local-maildir\n",
			"--version":                                       "notmuch 0.39\n",
			"search\x00--output=files\x00id:abc@example.test": "/mail/a\n/mail/b\n",
			"show\x00--format=json\x00--entire-thread=false\x00--include-html\x00--decrypt=false\x00--duplicate=1\x00id:abc@example.test": sampleNotmuchJSON,
		},
		errs: map[string]error{},
	}
	signer, err := newCapabilitySignerWithKey(bytes.Repeat([]byte{0x42}, capabilityKeyBytes))
	if err != nil {
		t.Fatalf("create test signer: %v", err)
	}
	server, err := newServerWithSigner(cfg, NotmuchClient{Config: cfg, Runner: runner}, signer)
	if err != nil {
		t.Fatalf("create test server: %v", err)
	}
	return server
}

const sampleNotmuchJSON = `[
  [
    [
      {
        "id": "abc@example.test",
        "match": true,
        "excluded": false,
        "filename": ["/mail/a", "/mail/b"],
        "date_relative": "Today",
        "tags": ["inbox", "unread"],
        "headers": {
          "Subject": "Quarterly update",
          "From": "A User <a@example.test>",
          "To": "B User <b@example.test>",
          "Cc": "C User <c@example.test>",
          "Date": "Mon, 06 Jul 2026 10:00:00 +0600"
        },
        "body": [
          {"id": 1, "content-type": "text/plain", "content": "Plain body"},
          {"id": 2, "content-type": "text/html", "content": "<main><p>HTML body</p></main>"},
          {"id": 3, "content-type": "application/pdf", "content-disposition": "attachment", "filename": "invoice.pdf"}
        ]
      },
      []
    ]
  ]
]`
