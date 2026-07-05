package notmuchbrowser

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

type fakeRunner struct {
	outputs map[string]string
	errs    map[string]error
	calls   [][]string
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
	if got.Subject != "Quarterly update" || got.From != "A User <a@example.test>" {
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
	if !strings.Contains(got.HTMLSrcdoc, "Content-Security-Policy") {
		t.Fatalf("expected iframe srcdoc CSP")
	}
	if len(got.Attachments) != 1 || got.Attachments[0] != "invoice.pdf" {
		t.Fatalf("unexpected attachments: %#v", got.Attachments)
	}
}

func TestSearchCommandConstruction(t *testing.T) {
	cfg := testConfig()
	runner := &fakeRunner{
		outputs: map[string]string{
			"count\x00tag:inbox":                                                                 "1\n",
			"count\x00--output=files\x00tag:inbox":                                                "2\n",
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
			"search\x00--output=files\x00id:abc@example.test":                                                              "/mail/a\n/mail/b\n",
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
				ID:       "evil@example.test",
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
