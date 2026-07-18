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

func TestEmailPageDefaultsPreserveSenderElementStyles(t *testing.T) {
	body := `<html style="margin:70.85pt"><body style="margin:1in"><p style="font-family:Courier New;font-size:18px;line-height:2;margin:20px"><img src="data:image/png;base64,AA==" style="width:41px;height:25px">Sender text</p></body></html>`
	got, err := sanitizeEmailHTML(body, imagesEmbedded, "http://127.0.0.1:8765", nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		`html{margin:0!important;padding:0!important}`,
		`body{margin:0!important;padding:8px!important}`,
		`font-family:Courier New;font-size:18px;line-height:2;margin:20px`,
		`width:41px;height:25px`,
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("sanitized HTML missing %q: %s", want, got)
		}
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

func TestCollectImageReferencesCoversCIDRelativeSrcsetAndCSS(t *testing.T) {
	body := `<style>.hero{background:url("assets/Badge%20One.png?cache=1")}.data{background:url(data:image/svg+xml,%3Csvg%3Ecid:not-a-part%3C/svg%3E)}</style><img src="cid:%3Clogo%40example.test%3E" srcset="photo.png 1x, images/photo@2x.png 2x"><table background="marks/seal.svg"></table><img src="../escape.png"><a href="ordinary.png">link</a>`
	references := collectImageReferences(body)
	if !references.CIDs["logo@example.test"] || references.CIDs["not-a-part%3c/svg%3e"] {
		t.Fatalf("unexpected CID references: %#v", references.CIDs)
	}
	for _, name := range []string{"badge one.png", "photo.png", "photo@2x.png", "seal.svg"} {
		if !references.Names[name] {
			t.Fatalf("missing relative image reference %q: %#v", name, references.Names)
		}
	}
	for _, name := range []string{"escape.png", "ordinary.png"} {
		if references.Names[name] {
			t.Fatalf("unsafe or non-image reference was collected: %q", name)
		}
	}
}

func TestSanitizeEmailHTMLRewritesRelativeResourcesByMode(t *testing.T) {
	body := `<style>.logo{background-image:url(images/logo.png)}</style><img src="logo.png" srcset="small.png 1x, images/large.png 2x"><img src="../escape.png"><img src="data:image/png;base64,AA=="><img src="https://remote.example/pixel.png">`
	nameURLs := map[string]string{
		"logo.png":  "http://127.0.0.1:8765/inline-image?cap=logo",
		"small.png": "http://127.0.0.1:8765/inline-image?cap=small",
		"large.png": "http://127.0.0.1:8765/inline-image?cap=large",
	}

	blocked, err := sanitizeEmailHTMLWithResources(body, imagesBlocked, "http://127.0.0.1:8765", nil, nameURLs)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(blocked, "/inline-image?") {
		t.Fatalf("blocked output retained a signed image URL: %s", blocked)
	}
	if count := strings.Count(blocked, "about:blank#blocked-image"); count != 5 {
		t.Fatalf("blocked relative resource count=%d want=5: %s", count, blocked)
	}

	embedded, err := sanitizeEmailHTMLWithResources(body, imagesEmbedded, "http://127.0.0.1:8765", nil, nameURLs)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"cap=logo", "cap=small", "cap=large", "about:blank#missing-inline-image", "data:image/png", "https://remote.example/pixel.png"} {
		if !strings.Contains(embedded, want) {
			t.Fatalf("embedded output missing %q: %s", want, embedded)
		}
	}
	for _, want := range []string{
		`font-family:Aptos,"Segoe UI",Carlito,Arial,sans-serif;font-size:10pt;line-height:1.35`,
		`html{margin:0!important;padding:0!important}`,
		`body{margin:0!important;padding:8px!important}`,
		`p{margin-top:.55em;margin-bottom:.55em}`,
		`img{max-width:100%;height:auto}`,
	} {
		if !strings.Contains(embedded, want) {
			t.Fatalf("safe HTML defaults missing %q: %s", want, embedded)
		}
	}
	if !strings.Contains(embedded, "font-src &#39;none&#39;") && !strings.Contains(embedded, "font-src 'none'") {
		t.Fatalf("iframe CSP no longer blocks downloaded fonts: %s", embedded)
	}
}

func TestEmbeddedImagePartLookupIsDeterministic(t *testing.T) {
	parts := []MIMEPart{
		{ID: 1, MediaType: "image/png", ContentID: "same@example.test", FileName: "duplicate.png", Disposition: "attachment"},
		{ID: 2, MediaType: "image/png", ContentID: "same@example.test", FileName: "duplicate.png", Disposition: "inline"},
		{ID: 3, MediaType: "image/png", FileName: "unique.png", Disposition: "inline"},
		{ID: 4, MediaType: "image/tiff", ContentID: "unsupported@example.test", FileName: "scan.tiff", Disposition: "inline"},
	}
	lookup := embeddedImageParts(parts)
	if lookup.CIDs["same@example.test"] != 2 {
		t.Fatalf("CID did not prefer the non-attachment part: %#v", lookup.CIDs)
	}
	if _, ok := lookup.Names["duplicate.png"]; ok {
		t.Fatalf("ambiguous filename should not be mapped: %#v", lookup.Names)
	}
	if lookup.Names["unique.png"] != 3 {
		t.Fatalf("unique filename missing: %#v", lookup.Names)
	}
	if _, ok := lookup.CIDs["unsupported@example.test"]; ok {
		t.Fatalf("unsupported browser image type was mapped: %#v", lookup.CIDs)
	}
}
