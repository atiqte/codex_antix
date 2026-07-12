package notmuchbrowser

import (
	"strings"
	"testing"
)

func TestSanitizeEmailHTMLBlockedMode(t *testing.T) {
	body := `<meta http-equiv="refresh" content="0;url=https://bad.test"><base href="https://bad.test/"><script>alert(1)</script><form action="https://bad.test"><input></form><iframe src="https://bad.test"></iframe><object data="https://bad.test"></object><img src="cid:%3Clogo%40example.test%3E" onerror="alert(1)"><svg onload="alert(1)"><script>alert(2)</script><foreignObject><iframe src="https://bad.test"></iframe></foreignObject><circle cx="2" cy="2" r="1"/></svg>`
	got, err := sanitizeEmailHTML(body, imagesBlocked, "http://127.0.0.1:8765", map[string]string{"logo@example.test": "http://127.0.0.1:8765/inline-image?cap=signed"})
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{"alert(1)", "<form", "<iframe", "<object", "onerror", "<base", "http-equiv=\"refresh\"", "cid:"} {
		if strings.Contains(strings.ToLower(got), strings.ToLower(forbidden)) {
			t.Fatalf("blocked output retained %q: %s", forbidden, got)
		}
	}
	if !strings.Contains(got, "img-src &#39;none&#39;") && !strings.Contains(got, "img-src 'none'") {
		t.Fatalf("blocked CSP missing: %s", got)
	}
	if !strings.Contains(got, "embedded SVG blocked") {
		t.Fatalf("blocked SVG placeholder missing: %s", got)
	}
}

func TestSanitizeEmailHTMLEmbeddedAndRemoteModes(t *testing.T) {
	body := `<style>.logo{background-image:url(cid:logo@example.test)}</style><div background="cid:logo@example.test" style="background:url(cid:logo@example.test)"><img src="cid:%3Clogo@example.test%3E" srcset="cid:logo@example.test 1x"><img src="data:image/png;base64,AA=="><img src="https://tracker.example/pixel.png"><svg><image xlink:href="cid:logo@example.test"/><foreignObject><p>drop me</p></foreignObject></svg></div>`
	cidURLs := map[string]string{"logo@example.test": "http://127.0.0.1:8765/inline-image?cap=signed"}
	embedded, err := sanitizeEmailHTML(body, imagesEmbedded, "http://127.0.0.1:8765", cidURLs)
	if err != nil {
		t.Fatal(err)
	}
	if count := strings.Count(embedded, "/inline-image?cap=signed"); count != 6 {
		t.Fatalf("expected six CID rewrites, got %d: %s", count, embedded)
	}
	if !strings.Contains(embedded, "data:") || strings.Contains(strings.ToLower(embedded), "foreignobject") {
		t.Fatalf("embedded sanitization mismatch: %s", embedded)
	}
	cspEnd := strings.Index(embedded, `">`)
	if cspEnd < 0 || strings.Contains(embedded[:cspEnd], "https:") {
		t.Fatalf("embedded CSP unexpectedly permits HTTPS: %s", embedded[:cspEnd+2])
	}

	remote, err := sanitizeEmailHTML(body, imagesRemote, "http://127.0.0.1:8765", cidURLs)
	if err != nil {
		t.Fatal(err)
	}
	cspEnd = strings.Index(remote, `">`)
	if cspEnd < 0 || !strings.Contains(remote[:cspEnd], "http: https:") {
		t.Fatalf("remote CSP does not permit remote images: %s", remote[:cspEnd+2])
	}
}

func TestSanitizeEmailHTMLRejectsOversizeBodyAndToken(t *testing.T) {
	if _, err := sanitizeEmailHTML(strings.Repeat("x", maxEmailHTMLBytes+1), imagesBlocked, "http://127.0.0.1:8765", nil); err == nil {
		t.Fatal("expected oversized HTML body rejection")
	}
	largeToken := `<div title="` + strings.Repeat("x", maxHTMLTokenBytes+1) + `">ok</div>`
	if _, err := sanitizeEmailHTML(largeToken, imagesBlocked, "http://127.0.0.1:8765", nil); err == nil {
		t.Fatal("expected oversized tokenizer buffer rejection")
	}
}

func TestSanitizeEmailHTMLHandlesMalformedMarkup(t *testing.T) {
	got, err := sanitizeEmailHTML(`<table><tr><td><img src="cid:broken@example.test"><script>never closes`, imagesEmbedded, "http://127.0.0.1:8765", map[string]string{"broken@example.test": "http://127.0.0.1:8765/inline-image?cap=ok"})
	if err != nil {
		t.Fatalf("malformed HTML should be safely reserialized: %v", err)
	}
	if !strings.Contains(got, "/inline-image?cap=ok") || strings.Contains(got, "never closes") {
		t.Fatalf("malformed HTML sanitization mismatch: %s", got)
	}
}

func TestNormalizeContentID(t *testing.T) {
	for input, want := range map[string]string{
		"<logo@example.test>":           "logo@example.test",
		"cid:logo@example.test":         "logo@example.test",
		"cid:%3Clogo%40example.test%3E": "logo@example.test",
	} {
		if got := normalizeContentID(input); got != want {
			t.Fatalf("normalizeContentID(%q)=%q want %q", input, got, want)
		}
	}
}

func TestCIDRewriteDoesNotCorruptDataImagePayload(t *testing.T) {
	dataImage := `data:image/svg+xml,%3Csvg%3Ecid:visible-text%3C/svg%3E`
	if got := rewriteCIDReferences(dataImage, imagesEmbedded, map[string]string{"visible-text%3c/svg%3e": "/wrong"}); got != dataImage {
		t.Fatalf("data image payload was rewritten: %q", got)
	}
}
