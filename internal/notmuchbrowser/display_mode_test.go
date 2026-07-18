package notmuchbrowser

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

func TestMessageViewURLPreservesOnlyApprovedState(t *testing.T) {
	tests := []struct {
		name      string
		raw       string
		duplicate string
		images    string
		display   string
	}{
		{
			name: "default readable blocked",
			raw:  messageViewURL("abc@example.test", 0, imagesBlocked, displayReadable),
		},
		{
			name:      "original embedded duplicate",
			raw:       messageViewURL("abc@example.test", 2, imagesEmbedded, displayOriginal),
			duplicate: "2",
			images:    "embedded",
			display:   "original",
		},
		{
			name:   "invalid display becomes readable",
			raw:    messageViewURL("abc@example.test", 0, imagesRemote, displayMode("invalid")),
			images: "remote",
		},
		{
			name:      "duplicate keeps original and blocks images",
			raw:       messageDuplicateURL("abc@example.test", 1, displayOriginal),
			duplicate: "1",
			display:   "original",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parsed, err := url.Parse(tt.raw)
			if err != nil {
				t.Fatal(err)
			}
			if parsed.Path != "/message" {
				t.Fatalf("path=%q", parsed.Path)
			}
			query := parsed.Query()
			if query.Get("id") != "abc@example.test" || query.Get("dup") != tt.duplicate || query.Get("images") != tt.images || query.Get("display") != tt.display {
				t.Fatalf("query=%v", query)
			}
		})
	}
}

func TestMessageDisplayControlAndLinksPreserveState(t *testing.T) {
	view := messageView{
		Detail: MessageDetail{
			Summary: MessageSummary{ID: "abc@example.test", Subject: "Office message"},
			Files:   []string{"/mail/a", "/mail/b"}, SelectedDup: 1,
			HTMLBody: `<p class="MsoNormal">Office</p>`, BodyKind: "html",
			DuplicateNote: "2 duplicate/copy files share this Message-ID",
		},
		ImageMode: imagesEmbedded, DisplayMode: displayOriginal,
	}
	out := executeTemplateForTest(t, "messageFragment", view)
	for _, want := range []string{
		`class="display-mode-switch" role="group" aria-label="Message display"`,
		`<span class="is-active" aria-current="true">Original</span>`,
		`title="Use normalized Outlook typography"`,
		`href="/message?dup=1&amp;id=abc%40example.test&amp;images=embedded"`,
		`href="/message?display=original&amp;id=abc%40example.test"`,
		`href="/message?display=original&amp;dup=1&amp;id=abc%40example.test&amp;images=remote"`,
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("Original display output missing %q: %s", want, out)
		}
	}

	view.DisplayMode = displayReadable
	out = executeTemplateForTest(t, "messageFragment", view)
	if !strings.Contains(out, `<span class="is-active" aria-current="true">Readable</span>`) {
		t.Fatalf("Readable display is not active: %s", out)
	}
	if strings.Contains(out, `display=readable`) {
		t.Fatalf("default readable mode should not add a query parameter: %s", out)
	}
}

func TestDisplayModeSurvivesFullPageWhileImagesReset(t *testing.T) {
	server := newHTTPTestServer(t)
	path := "/message?id=abc%40example.test&images=remote&display=original"

	full := httptest.NewRecorder()
	server.ServeHTTP(full, httptest.NewRequest(http.MethodGet, path, nil))
	if full.Code != http.StatusOK || !strings.Contains(full.Body.String(), "Images blocked") || !strings.Contains(full.Body.String(), `aria-current="true">Original</span>`) {
		t.Fatalf("full-page display/image state mismatch: status=%d body=%s", full.Code, full.Body.String())
	}
	if strings.Contains(full.Body.String(), "Remote images allowed") {
		t.Fatalf("full-page reload retained remote image permission")
	}

	htmxRequest := httptest.NewRequest(http.MethodGet, path, nil)
	htmxRequest.Header.Set("HX-Request", "true")
	fragment := httptest.NewRecorder()
	server.ServeHTTP(fragment, htmxRequest)
	if fragment.Code != http.StatusOK || !strings.Contains(fragment.Body.String(), "Remote images allowed") || !strings.Contains(fragment.Body.String(), `aria-current="true">Original</span>`) {
		t.Fatalf("HTMX display/image state mismatch: status=%d body=%s", fragment.Code, fragment.Body.String())
	}

	invalid := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/message?id=abc%40example.test&display=invalid", nil)
	request.Header.Set("HX-Request", "true")
	server.ServeHTTP(invalid, request)
	if invalid.Code != http.StatusOK || !strings.Contains(invalid.Body.String(), `aria-current="true">Readable</span>`) {
		t.Fatalf("invalid display did not default to readable: status=%d body=%s", invalid.Code, invalid.Body.String())
	}
}
