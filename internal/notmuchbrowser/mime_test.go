package notmuchbrowser

import (
	"strings"
	"testing"
)

func TestMIMEParsingPreservesPartsAndExcludesBodyAndCIDOnlyResources(t *testing.T) {
	details, err := ParseMessageDetails([]byte(complexMIMEJSON))
	if err != nil {
		t.Fatal(err)
	}
	if len(details) != 1 {
		t.Fatalf("expected one message, got %d", len(details))
	}
	detail := details[0]
	if detail.BodyKind != "html" || !strings.Contains(detail.HTMLBody, "cid:logo@example.test") {
		t.Fatalf("unexpected selected body: kind=%q body=%q", detail.BodyKind, detail.HTMLBody)
	}
	if len(detail.Parts) != 9 {
		t.Fatalf("expected 9 MIME parts, got %d: %#v", len(detail.Parts), detail.Parts)
	}
	if len(detail.Attachments) != 4 {
		t.Fatalf("expected 4 downloadable attachments, got %d: %#v", len(detail.Attachments), detail.Attachments)
	}
	want := map[string]struct {
		part        int
		previewable bool
	}{
		"photo.png":             {part: 5, previewable: true},
		"scan.tiff":             {part: 6, previewable: false},
		"attachment-part-7.eml": {part: 7, previewable: false},
		"notes.txt":             {part: 9, previewable: false},
	}
	for _, attachment := range detail.Attachments {
		expected, ok := want[attachment.FileName]
		if !ok || attachment.PartID != expected.part || attachment.Previewable != expected.previewable {
			t.Fatalf("unexpected attachment: %#v", attachment)
		}
		delete(want, attachment.FileName)
	}
	if len(want) != 0 {
		t.Fatalf("missing attachments: %#v", want)
	}
}

func TestHTMLFileAttachmentIsNotSelectedAsBody(t *testing.T) {
	input := strings.Replace(complexMIMEJSON,
		`{"id": 3, "content-type": "text/html", "content": "<p><img src=\"cid:logo@example.test\"></p>"},`,
		`{"id": 3, "content-type": "text/html", "content-disposition": "attachment", "filename": "saved.html", "content": "<p>attachment</p>"},`,
		1,
	)
	details, err := ParseMessageDetails([]byte(input))
	if err != nil {
		t.Fatal(err)
	}
	if details[0].BodyKind != "plain" || details[0].PlainBody != "outer plain body" {
		t.Fatalf("HTML attachment became body: %#v", details[0])
	}
}

func TestReferencedBodyImagesAreSeparatedFromGenuineAttachments(t *testing.T) {
	details, err := ParseMessageDetails([]byte(embeddedResourceMIMEJSON))
	if err != nil {
		t.Fatal(err)
	}
	if len(details) != 1 {
		t.Fatalf("expected one message, got %d", len(details))
	}
	detail := details[0]
	if detail.BodyKind != "html" || len(detail.Parts) != 9 {
		t.Fatalf("unexpected detail: kind=%q parts=%d", detail.BodyKind, len(detail.Parts))
	}
	want := map[int]string{
		5: "download.png",
		6: "orphan.png",
		7: "duplicate.png",
		8: "duplicate.png",
		9: "escape.png",
	}
	for _, attachment := range detail.Attachments {
		name, ok := want[attachment.PartID]
		if !ok || attachment.FileName != name {
			t.Fatalf("unexpected attachment: %#v", attachment)
		}
		delete(want, attachment.PartID)
	}
	if len(want) != 0 {
		t.Fatalf("missing genuine attachments: %#v; got %#v", want, detail.Attachments)
	}
	for _, bodyOnlyPart := range []int{3, 4} {
		for _, attachment := range detail.Attachments {
			if attachment.PartID == bodyOnlyPart {
				t.Fatalf("body resource part %d leaked into attachments", bodyOnlyPart)
			}
		}
	}
}

func TestParseMediaTypeRejectsHeaderInjection(t *testing.T) {
	if got := parseMediaType("image/png\r\nX-Evil: yes"); got != "application/octet-stream" {
		t.Fatalf("unsafe media type was retained: %q", got)
	}
	if got := parseMediaType("image/png; broken-param"); got != "image/png" {
		t.Fatalf("valid base media type was lost: %q", got)
	}
}

const complexMIMEJSON = `[
  [[{
    "id": "mime@example.test",
    "match": true,
    "filename": "/mail/one",
    "tags": ["inbox", "attachment"],
    "headers": {"Subject":"MIME fixture","From":"a@example.test","To":"b@example.test","Date":"Today"},
    "body": [
      {"id": 1, "content-type": "multipart/mixed", "content": [
        {"id": "2", "content-type": "text/plain; charset=utf-8", "content": "outer plain body"},
        {"id": 3, "content-type": "text/html", "content": "<p><img src=\"cid:logo@example.test\"></p>"},
        {"id": 4, "content-type": "image/png", "content-id": "<logo@example.test>", "content-disposition": "inline"},
        {"id": 5, "content-type": "image/png", "content-id": "photo@example.test", "content-disposition": "inline; size=1", "filename": "photo.png"},
        {"id": 6, "content-type": "image/tiff", "content-disposition": "attachment", "filename": "scan.tiff"},
        {"id": 7, "content-type": "message/rfc822", "content-disposition": "attachment", "content": [
          {"id": 8, "content-type": "text/plain", "content-disposition": "attachment", "filename": "nested.txt", "content": "nested body"}
        ]},
        {"id": 9, "content-type": "text/plain", "content-disposition": "attachment", "filename": "../notes.txt", "content": "attachment text"}
      ]}
    ]
  }, []]]
]`

const embeddedResourceMIMEJSON = `[
  [[{
    "id": "resources@example.test",
    "match": true,
    "filename": "/mail/resources",
    "tags": ["inbox", "attachment"],
    "headers": {"Subject":"Resources","From":"a@example.test","To":"b@example.test","Date":"Today"},
    "body": [
      {"id": 1, "content-type": "multipart/related", "content": [
        {"id": 2, "content-type": "text/html", "content": "<img src=\"cid:logo@example.test\"><img src=\"images/photo.png\"><img src=\"cid:download@example.test\"><img src=\"duplicate.png\"><img src=\"../escape.png\"><img src=\"data:image/png;base64,AA==\">"},
        {"id": 3, "content-type": "image/png", "content-id": "<logo@example.test>", "content-disposition": "inline", "filename": "logo.png"},
        {"id": 4, "content-type": "image/png", "content-disposition": "inline", "filename": "photo.png"},
        {"id": 5, "content-type": "image/png", "content-id": "download@example.test", "content-disposition": "attachment", "filename": "download.png"},
        {"id": 6, "content-type": "image/png", "content-disposition": "inline", "filename": "orphan.png"},
        {"id": 7, "content-type": "image/png", "content-disposition": "inline", "filename": "duplicate.png"},
        {"id": 8, "content-type": "image/png", "content-disposition": "inline", "filename": "duplicate.png"},
        {"id": 9, "content-type": "image/png", "content-disposition": "inline", "filename": "escape.png"}
      ]}
    ]
  }, []]]
]`
