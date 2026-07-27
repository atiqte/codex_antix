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
			Date:    "unparseable date preserved",
		},
		PlainBody: "body",
		BodyKind:  "plain",
	}}
	out := executeTemplateForTest(t, "messageFragment", view)
	for _, want := range []string{
		`<dt>Cc</dt><dd>C User &lt;c@example.test&gt;, D User &lt;d@example.test&gt;</dd>`,
		`data-copy-text="Quarterly &amp; Special"`,
		`data-copy-text="Message-ID: abc@example.test"`,
		`unparseable date preserved`,
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("annotated reader output missing %q: %s", want, out)
		}
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
	out = executeTemplateForTest(t, "messageFragment", view)
	if strings.Contains(out, "<dt>Cc</dt>") {
		t.Fatalf("empty Cc row was rendered: %s", out)
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
