package notmuchbrowser

import (
	"bytes"
	"context"
	"os"
	"strings"
	"testing"
	"time"
)

func TestAnnotatedGUIResultToolbarAndCopyControls(t *testing.T) {
	renderedAt := time.Date(2026, 7, 14, 22, 0, 0, 0, time.Local)
	view := pageView{SearchPage: SearchPage{
		Query:      "tag:inbox",
		Limit:      50,
		Counts:     Counts{Messages: 101, Files: 151},
		RenderedAt: renderedAt,
		Results: []MessageSummary{{
			ID:        "abc@example.test",
			Subject:   `Quarterly "special" <plan>`,
			From:      "A User <a@example.test>",
			Timestamp: renderedAt.AddDate(0, 0, -1).Add(-97 * time.Minute).Unix(),
			FileCount: 2,
		}},
	}}
	out := executeTemplateForTest(t, "results", view)
	if !strings.Contains(out, `id="result-toolbar-slot" hx-swap-oob="innerHTML"`) {
		t.Fatalf("HTMX result fragment is missing the OOB toolbar update: %s", out)
	}

	queryAt := strings.Index(out, `class="result-query"`)
	countsAt := strings.Index(out, `class="result-counts"`)
	pagerAt := strings.Index(out, `class="result-pagination"`)
	if queryAt < 0 || countsAt <= queryAt || pagerAt <= countsAt {
		t.Fatalf("result toolbar order is not query, counts, pager: %s", out)
	}
	if strings.Contains(out, `class="pager"`) || strings.Contains(out, ">Previous<") || strings.Contains(out, ">Next<") {
		t.Fatalf("legacy bottom text pager remains: %s", out)
	}
	if strings.Contains(out, `class="result-toolbar"`) {
		t.Fatalf("dedicated result-toolbar band remains: %s", out)
	}
	for _, want := range []string{
		`data-copy-text="Quarterly &#34;special&#34; &lt;plan&gt;"`,
		`data-copy-text="Message-ID: abc@example.test"`,
		`Yesterday 08:23:00 PM`,
		`aria-label="Previous results"`,
		`aria-label="Next results"`,
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("annotated result output missing %q: %s", want, out)
		}
	}
	subjectEnd := strings.Index(out, `&lt;plan&gt;</a>`)
	subjectCopy := strings.Index(out, `data-copy-text="Quarterly &#34;special&#34; &lt;plan&gt;"`)
	if subjectEnd < 0 || subjectCopy <= subjectEnd || subjectCopy-subjectEnd > 180 {
		t.Fatalf("result subject copy button is not immediately after its text: %s", out)
	}
	idEnd := strings.Index(out, `<span class="path">abc@example.test</span>`)
	idCopy := strings.Index(out, `data-copy-text="Message-ID: abc@example.test"`)
	if idEnd < 0 || idCopy <= idEnd || idCopy-idEnd > 180 {
		t.Fatalf("result Message-ID copy button is not immediately after its text: %s", out)
	}
}

func TestGUI2InitialSearchSubbarOwnsToolbarSlot(t *testing.T) {
	out := executeTemplateForTest(t, "page", pageView{
		Query: "tag:inbox",
		SearchPage: SearchPage{
			Query: "tag:inbox", Limit: 50,
			Counts: Counts{Messages: 101, Files: 151},
		},
	})
	if !strings.Contains(out, `class="search-subbar"`) {
		t.Fatalf("search subbar is missing: %s", out)
	}
	if got := strings.Count(out, `id="result-toolbar-slot"`); got != 1 {
		t.Fatalf("initial toolbar slot count=%d, want 1: %s", got, out)
	}
	shortcutsAt := strings.Index(out, `class="query-shortcuts"`)
	toolbarAt := strings.Index(out, `id="result-toolbar-slot"`)
	resultsAt := strings.Index(out, `id="results"`)
	if shortcutsAt < 0 || toolbarAt <= shortcutsAt || resultsAt <= toolbarAt {
		t.Fatalf("initial layout is not shortcuts, toolbar slot, results: %s", out)
	}
	if strings.Contains(out, `hx-swap-oob=`) || strings.Contains(out, `class="result-toolbar"`) {
		t.Fatalf("initial page contains an OOB marker or dedicated toolbar band: %s", out)
	}
}

func TestAnnotatedGUIPagerKeepsTwoStablePositions(t *testing.T) {
	tests := []struct {
		name         string
		offset       int
		resultCount  int
		disabledWant int
	}{
		{name: "first", offset: 0, resultCount: 50, disabledWant: 1},
		{name: "middle", offset: 50, resultCount: 50, disabledWant: 0},
		{name: "last", offset: 100, resultCount: 1, disabledWant: 1},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			results := make([]MessageSummary, tt.resultCount)
			for i := range results {
				results[i] = MessageSummary{ID: "id@example.test", Subject: "Subject"}
			}
			out := executeTemplateForTest(t, "results", pageView{SearchPage: SearchPage{
				Query: "*", Offset: tt.offset, Limit: 50,
				Counts: Counts{Messages: 101, Files: 151}, Results: results,
			}})
			if got := strings.Count(out, `class="icon-button pagination-button`); got != 2 {
				t.Fatalf("pager positions=%d, want 2: %s", got, out)
			}
			if got := strings.Count(out, `is-disabled`); got != tt.disabledWant {
				t.Fatalf("disabled positions=%d, want %d: %s", got, tt.disabledWant, out)
			}
		})
	}
}

func TestAnnotatedGUIReaderMetadataAndCopyControls(t *testing.T) {
	view := messageView{Detail: MessageDetail{
		Summary: MessageSummary{
			ID:      "abc@example.test",
			Subject: "Quarterly & Special",
			From:    "A User <a@example.test>",
			To:      "B User <b@example.test>",
			Cc:      "C User <c@example.test>, D User <d@example.test>",
			Bcc:     "Hidden User <hidden@example.test>",
			Date:    "unparseable date preserved",
		},
		PlainBody: "body",
		BodyKind:  "plain",
	}}
	out := executeTemplateForTest(t, "messageFragment", view)
	for _, want := range []string{
		`href="mailto:a@example.test"`,
		`href="mailto:b@example.test"`,
		`href="mailto:c@example.test"`,
		`href="mailto:d@example.test"`,
		`<dt>Bcc</dt>`,
		`href="mailto:hidden@example.test"`,
		`data-copy-text="a@example.test"`,
		`data-copy-text="b@example.test"`,
		`data-copy-text="c@example.test"`,
		`data-copy-text="d@example.test"`,
		`data-copy-text="hidden@example.test"`,
		`data-copy-text="Quarterly &amp; Special"`,
		`data-copy-text="Message-ID: abc@example.test"`,
		`unparseable date preserved`,
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("annotated reader output missing %q: %s", want, out)
		}
	}
	if got := strings.Count(out, `href="mailto:`); got != 5 {
		t.Fatalf("reader mailto link count=%d, want 5: %s", got, out)
	}
	subjectEnd := strings.Index(out, `Quarterly &amp; Special</h1>`)
	subjectCopy := strings.Index(out, `data-copy-text="Quarterly &amp; Special"`)
	if subjectEnd < 0 || subjectCopy <= subjectEnd || subjectCopy-subjectEnd > 180 {
		t.Fatalf("reader subject copy button is not immediately after its text: %s", out)
	}
	idEnd := strings.Index(out, `<span class="path">abc@example.test</span>`)
	idCopy := strings.Index(out, `data-copy-text="Message-ID: abc@example.test"`)
	if idEnd < 0 || idCopy <= idEnd || idCopy-idEnd > 180 {
		t.Fatalf("reader Message-ID copy button is not immediately after its text: %s", out)
	}

	view.Detail.Summary.Cc = ""
	view.Detail.Summary.Bcc = ""
	out = executeTemplateForTest(t, "messageFragment", view)
	if strings.Contains(out, "<dt>Cc</dt>") || strings.Contains(out, "<dt>Bcc</dt>") {
		t.Fatalf("empty Cc or Bcc row was rendered: %s", out)
	}
}

func TestAnnotatedGUIMessageAddressParsingAndSafeFallback(t *testing.T) {
	tests := []struct {
		name         string
		raw          string
		wantParsed   bool
		wantDisplays []string
		wantEmails   []string
	}{
		{
			name:         "bare",
			raw:          "person@example.test",
			wantParsed:   true,
			wantDisplays: []string{"person@example.test"},
			wantEmails:   []string{"person@example.test"},
		},
		{
			name:         "multiple quoted and encoded names",
			raw:          `"Family, Ada" <ada@example.test>, =?UTF-8?Q?Ren=C3=A9?= <rene@example.test>`,
			wantParsed:   true,
			wantDisplays: []string{"Family, Ada <ada@example.test>", "René <rene@example.test>"},
			wantEmails:   []string{"ada@example.test", "rene@example.test"},
		},
		{
			name:         "group",
			raw:          "Friends: first@example.test, Second <second@example.test>;",
			wantParsed:   true,
			wantDisplays: []string{"first@example.test", "Second <second@example.test>"},
			wantEmails:   []string{"first@example.test", "second@example.test"},
		},
		{name: "empty group", raw: "undisclosed-recipients:;", wantParsed: false},
		{name: "malformed", raw: "Broken <broken@example.test", wantParsed: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := messageAddressList(tt.raw)
			if got.Parsed != tt.wantParsed {
				t.Fatalf("Parsed=%t, want %t: %#v", got.Parsed, tt.wantParsed, got)
			}
			if len(got.Addresses) != len(tt.wantEmails) {
				t.Fatalf("address count=%d, want %d: %#v", len(got.Addresses), len(tt.wantEmails), got)
			}
			for index := range tt.wantEmails {
				if got.Addresses[index].Display != tt.wantDisplays[index] || got.Addresses[index].Address != tt.wantEmails[index] {
					t.Fatalf("address[%d]=%#v, want display=%q email=%q", index, got.Addresses[index], tt.wantDisplays[index], tt.wantEmails[index])
				}
				if got.Addresses[index].Mailto != "mailto:"+tt.wantEmails[index] {
					t.Fatalf("mailto[%d]=%q", index, got.Addresses[index].Mailto)
				}
			}
		})
	}
}

func TestAnnotatedGUIMessageAddressMailtoCannotInjectQuery(t *testing.T) {
	got := messageAddressList(`"victim?subject=Injected"@example.test`)
	if !got.Parsed || len(got.Addresses) != 1 {
		t.Fatalf("expected quoted address to parse: %#v", got)
	}
	if strings.Contains(got.Addresses[0].Mailto, "?subject=") || !strings.Contains(got.Addresses[0].Mailto, "%3F") {
		t.Fatalf("mailto query delimiter was not encoded: %q", got.Addresses[0].Mailto)
	}

	got = messageAddressList("safe@example.test\r\nBcc: attacker@example.test")
	if got.Parsed {
		t.Fatalf("control-character address field was linked: %#v", got)
	}

	out := executeTemplateForTest(t, "messageFragment", messageView{Detail: MessageDetail{
		Summary:   MessageSummary{ID: "id@example.test", Subject: "Subject", From: "Broken <broken@example.test", To: "valid@example.test"},
		PlainBody: "body",
		BodyKind:  "plain",
	}})
	if !strings.Contains(out, `Broken &lt;broken@example.test`) || strings.Contains(out, `mailto:broken@example.test`) {
		t.Fatalf("malformed From header did not remain escaped plain text: %s", out)
	}
	if !strings.Contains(out, `href="mailto:valid@example.test"`) {
		t.Fatalf("valid To header lost its mailto link: %s", out)
	}
}

func TestAnnotatedGUISearchSenderRemainsPlainText(t *testing.T) {
	out := executeTemplateForTest(t, "results", pageView{SearchPage: SearchPage{
		Query:  "*",
		Limit:  50,
		Counts: Counts{Messages: 1, Files: 1},
		Results: []MessageSummary{{
			ID:      "id@example.test",
			Subject: "Subject",
			From:    "Sender <sender@example.test>",
		}},
	}})
	if !strings.Contains(out, `Sender &lt;sender@example.test&gt;`) {
		t.Fatalf("search sender text is missing: %s", out)
	}
	if strings.Contains(out, `mailto:sender@example.test`) {
		t.Fatalf("search sender unexpectedly became a mailto link: %s", out)
	}
}

func TestAnnotatedGUIDateFormatting(t *testing.T) {
	dhaka := time.FixedZone("Asia/Dhaka", 6*60*60)
	raw := "Tue, 14 Jul 2026 16:23:01 +0200"
	if got := formatDateInLocation(raw, "Mon, 02 Jan 2006, 03:04:05 PM", dhaka); got != "Tue, 14 Jul 2026, 08:23:01 PM" {
		t.Fatalf("reader date=%q", got)
	}
	if got := formatDateInLocation("not a date", "Mon, 02 Jan 2006, 03:04:05 PM", dhaka); got != "not a date" {
		t.Fatalf("invalid date fallback=%q", got)
	}
	previousLocal := time.Local
	time.Local = dhaka
	t.Cleanup(func() { time.Local = previousLocal })
	if got := formatReaderDate(raw); got != "Tue, 14 Jul 2026, 08:23:01 PM" {
		t.Fatalf("formatReaderDate=%q", got)
	}

	now := time.Date(2026, 7, 14, 22, 0, 0, 0, dhaka)
	tests := []struct {
		name string
		when time.Time
		want string
	}{
		{name: "now", when: now.Add(-59 * time.Second), want: "Now"},
		{name: "minutes", when: now.Add(-33 * time.Minute), want: "33 min ago"},
		{name: "one-hour", when: now.Add(-60 * time.Minute), want: "1 hour ago"},
		{name: "today", when: now.Add(-2 * time.Hour), want: "Today 08:00:00 PM"},
		{name: "yesterday", when: time.Date(2026, 7, 13, 20, 23, 1, 0, dhaka), want: "Yesterday 08:23:01 PM"},
		{name: "older", when: time.Date(2026, 7, 12, 20, 23, 1, 0, dhaka), want: "Sun, 12 Jul 2026, 08:23:01 PM"},
	}
	for _, tt := range tests {
		if got := formatResultDate(tt.when.Unix(), "", now); got != tt.want {
			t.Fatalf("%s: formatResultDate=%q, want %q", tt.name, got, tt.want)
		}
	}
}

func TestAnnotatedGUILayoutHeaderContract(t *testing.T) {
	out := executeTemplateForTest(t, "page", pageView{
		Query:      "tag:inbox",
		SearchPage: SearchPage{Query: "tag:inbox", Limit: 50},
	})
	for _, unwanted := range []string{"Mail archive", "localhost only", `class="app-topbar"`} {
		if strings.Contains(out, unwanted) {
			t.Fatalf("removed desktop top-bar content %q remains: %s", unwanted, out)
		}
	}
	for _, want := range []string{`class="app-mobilebar"`, `data-sidebar-open`, `aria-label="Open navigation"`} {
		if !strings.Contains(out, want) {
			t.Fatalf("mobile navigation contract missing %q: %s", want, out)
		}
	}
}

func TestResultTableDateAndSenderResponsiveLayoutContract(t *testing.T) {
	css, err := os.ReadFile("styles/app.tailwind.css")
	if err != nil {
		t.Fatal(err)
	}
	source := string(css)
	for _, want := range []string{
		"width: 218px;",
		"font-variant-numeric: tabular-nums;",
		".result-table thead {",
		".result-table tbody tr {",
		".result-table .sender {",
		"white-space: normal;",
	} {
		if !strings.Contains(source, want) {
			t.Fatalf("responsive result layout is missing %q", want)
		}
	}
	if strings.Contains(source, "width: 122px;") {
		t.Fatal("obsolete overlapping date-column width remains")
	}
}

func TestDesktopSidebarStaysViewportPinnedContract(t *testing.T) {
	css, err := os.ReadFile("styles/app.tailwind.css")
	if err != nil {
		t.Fatal(err)
	}
	source := string(css)
	sidebarStart := strings.Index(source, ".app-sidebar {")
	if sidebarStart < 0 {
		t.Fatal("desktop sidebar rule is missing")
	}
	sidebarEnd := strings.Index(source[sidebarStart:], "}")
	if sidebarEnd < 0 {
		t.Fatal("desktop sidebar rule is unterminated")
	}
	sidebarRule := source[sidebarStart : sidebarStart+sidebarEnd]
	for _, want := range []string{
		"position: sticky;",
		"top: 0;",
		"align-self: start;",
		"height: 100dvh;",
	} {
		if !strings.Contains(sidebarRule, want) {
			t.Fatalf("viewport-pinned sidebar contract is missing %q", want)
		}
	}
	if strings.Contains(sidebarRule, "position: relative;") {
		t.Fatal("obsolete document-scrolling sidebar position remains")
	}
	for _, want := range []string{"position: fixed;", "inset: 0 auto 0 0;"} {
		if !strings.Contains(source, want) {
			t.Fatalf("mobile off-canvas sidebar contract is missing %q", want)
		}
	}
}

func TestMessageAddressCopyButtonCompactNoticeableContract(t *testing.T) {
	css, err := os.ReadFile("styles/app.tailwind.css")
	if err != nil {
		t.Fatal(err)
	}
	source := string(css)
	start := strings.Index(source, ".message-address-entry .mini-copy-button {")
	if start < 0 {
		t.Fatal("address-specific copy-button rule is missing")
	}
	end := strings.Index(source[start:], "}")
	if end < 0 {
		t.Fatal("address-specific copy-button rule is unterminated")
	}
	rule := source[start : start+end]
	for _, want := range []string{
		"width: 18px;",
		"height: 18px;",
		"min-height: 18px;",
		"flex-basis: 18px;",
		"border-color: var(--line);",
		"background: var(--surface-muted);",
		"color: var(--sapphire-dark);",
	} {
		if !strings.Contains(rule, want) {
			t.Fatalf("compact noticeable address copy-button contract is missing %q", want)
		}
	}
	for _, want := range []string{
		".message-address-entry .mini-copy-button:hover,",
		".message-address-entry .mini-copy-button .icon {",
		"width: 11px;",
		".message-address-entry .mini-copy-button.copied {",
		"background: var(--green-bg);",
	} {
		if !strings.Contains(source, want) {
			t.Fatalf("address copy-button interaction contract is missing %q", want)
		}
	}
}

func TestHTMXHardeningAndHistoryContract(t *testing.T) {
	out := executeTemplateForTest(t, "page", pageView{
		Query:      "tag:inbox",
		SearchPage: SearchPage{Query: "tag:inbox", Limit: 50},
	})
	for _, want := range []string{
		`name="htmx-config"`,
		`allowEval`,
		`allowScriptTags`,
		`historyRestoreAsHxRequest`,
		`historyCacheSize`,
		`<body hx-history="false">`,
		`src="/static/htmx.min.js"`,
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("HTMX hardening contract missing %q: %s", want, out)
		}
	}
	for _, unwanted := range []string{
		`"allowEval":true`,
		`"allowScriptTags":true`,
		`unsafe-eval`,
		`alpine`,
	} {
		if strings.Contains(out, unwanted) {
			t.Fatalf("HTMX hardening contract contains %q: %s", unwanted, out)
		}
	}
}

func TestTemplEscapesIframeSrcdocAttribute(t *testing.T) {
	out := executeTemplateForTest(t, "messageFragment", messageView{
		Detail: MessageDetail{
			Summary:  MessageSummary{ID: "id@example.test", Subject: "Subject"},
			HTMLBody: "<p>HTML</p>",
			BodyKind: "html",
		},
		HTMLSrcdoc: `<p title='" onload="alert(1)'>safe</p>`,
	})
	if strings.Contains(out, `srcdoc="<p`) || strings.Contains(out, `" onload="alert(1)`) {
		t.Fatalf("templ emitted an unescaped srcdoc attribute: %s", out)
	}
	if !strings.Contains(out, `srcdoc="&lt;p title=`) {
		t.Fatalf("escaped srcdoc attribute is missing: %s", out)
	}
}

func executeTemplateForTest(t *testing.T, name string, data any) string {
	t.Helper()
	component, err := namedComponent(name, data)
	if err != nil {
		t.Fatalf("resolve component %s: %v", name, err)
	}
	var buf bytes.Buffer
	if err := component.Render(context.Background(), &buf); err != nil {
		t.Fatalf("render component %s: %v", name, err)
	}
	return buf.String()
}
