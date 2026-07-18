package notmuchbrowser

import (
	"archive/zip"
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestWritePartBuildsExactRawDuplicateCommand(t *testing.T) {
	cfg := testConfig()
	runner := &fakeRunner{outputs: map[string]string{}, rawOutputs: map[string][]byte{}, errs: map[string]error{}}
	key := rawPartKey("part@example.test", 1, 7)
	runner.rawOutputs[key] = []byte{0x00, 0x01, 0xff}
	client := NotmuchClient{Config: cfg, Runner: runner}
	var output bytes.Buffer
	if err := client.WritePart(context.Background(), "part@example.test", 1, 7, &output, time.Second); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(output.Bytes(), []byte{0x00, 0x01, 0xff}) {
		t.Fatalf("raw bytes changed: %x", output.Bytes())
	}
	if len(runner.calls) != 1 || strings.Join(runner.calls[0], "\x00") != key {
		t.Fatalf("unexpected raw command: %#v", runner.calls)
	}
}

func TestAttachmentHandlerReturnsExactBytesAndCleansTemp(t *testing.T) {
	server, runner := newDownloadTestServer(t)
	payload := capabilityPayload{
		Purpose: purposeAttachment, MessageID: "download@example.test", Duplicate: 1, Part: 3, FileName: "invoice.pdf", MediaType: "application/pdf",
	}
	token, _ := server.Signer.Sign(payload)
	runner.rawOutputs[rawPartKey(payload.MessageID, payload.Duplicate, payload.Part)] = []byte("decoded-pdf-bytes")
	request := httptest.NewRequest(http.MethodGet, signedRoute("/attachment", token), nil)
	response := httptest.NewRecorder()
	server.ServeHTTP(response, request)
	if response.Code != http.StatusOK || response.Body.String() != "decoded-pdf-bytes" {
		t.Fatalf("unexpected download response: status=%d body=%q", response.Code, response.Body.String())
	}
	if got := response.Header().Get("Content-Disposition"); !strings.Contains(got, "attachment") || !strings.Contains(got, "invoice.pdf") {
		t.Fatalf("unexpected Content-Disposition: %q", got)
	}
	if count, size := temporaryFileStats(server.Config.DownloadTempDir); count != 0 || size != 0 {
		t.Fatalf("temporary files remain: count=%d size=%d", count, size)
	}
}

func TestInlineImageHeadersAndTamperedCapability(t *testing.T) {
	server, runner := newDownloadTestServer(t)
	payload := capabilityPayload{
		Purpose: purposeInline, MessageID: "image@example.test", Part: 4, FileName: "logo.svg", MediaType: "image/svg+xml",
	}
	token, _ := server.Signer.Sign(payload)
	runner.rawOutputs[rawPartKey(payload.MessageID, 0, payload.Part)] = []byte(`<svg xmlns="http://www.w3.org/2000/svg"><rect width="1" height="1"/></svg>`)
	response := httptest.NewRecorder()
	server.ServeHTTP(response, httptest.NewRequest(http.MethodGet, signedRoute("/inline-image", token), nil))
	if response.Code != http.StatusOK || response.Header().Get("Content-Type") != "image/svg+xml" {
		t.Fatalf("unexpected inline image response: status=%d headers=%v", response.Code, response.Header())
	}
	for header, want := range map[string]string{
		"Content-Security-Policy":      "sandbox; default-src 'none'",
		"Cross-Origin-Resource-Policy": "same-origin",
		"X-Content-Type-Options":       "nosniff",
	} {
		if !strings.Contains(response.Header().Get(header), want) {
			t.Fatalf("%s=%q does not contain %q", header, response.Header().Get(header), want)
		}
	}
	replacement := "A"
	if strings.HasSuffix(token, replacement) {
		replacement = "B"
	}
	tampered := token[:len(token)-1] + replacement
	response = httptest.NewRecorder()
	server.ServeHTTP(response, httptest.NewRequest(http.MethodGet, signedRoute("/inline-image", tampered), nil))
	if response.Code != http.StatusForbidden {
		t.Fatalf("expected tampered capability 403, got %d", response.Code)
	}
}

func TestInlineImageWaitsForDecoderSlot(t *testing.T) {
	server, runner := newDownloadTestServer(t)
	server.Config.InlineImageTimeout = time.Second
	server.inlineSlots <- struct{}{}
	server.inlineSlots <- struct{}{}

	payload := capabilityPayload{
		Purpose: purposeInline, MessageID: "burst@example.test", Part: 7, FileName: "logo.png", MediaType: "image/png",
	}
	token, _ := server.Signer.Sign(payload)
	runner.rawOutputs[rawPartKey(payload.MessageID, 0, payload.Part)] = []byte("png-bytes")
	response := httptest.NewRecorder()
	done := make(chan struct{})
	go func() {
		server.ServeHTTP(response, httptest.NewRequest(http.MethodGet, signedRoute("/inline-image", token), nil))
		close(done)
	}()

	select {
	case <-done:
		for len(server.inlineSlots) > 0 {
			<-server.inlineSlots
		}
		t.Fatalf("inline request returned instead of waiting: status=%d body=%q", response.Code, response.Body.String())
	case <-time.After(50 * time.Millisecond):
	}

	<-server.inlineSlots
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("inline request did not resume after a decoder slot became available")
	}
	for len(server.inlineSlots) > 0 {
		<-server.inlineSlots
	}
	if response.Code != http.StatusOK || response.Body.String() != "png-bytes" {
		t.Fatalf("queued inline response: status=%d body=%q", response.Code, response.Body.String())
	}
	if response.Header().Get("Retry-After") != "" {
		t.Fatalf("queued inline response unexpectedly has Retry-After: %v", response.Header())
	}
}

func TestInlineImageSlotWaitUsesExistingTimeout(t *testing.T) {
	server, _ := newDownloadTestServer(t)
	server.Config.InlineImageTimeout = 20 * time.Millisecond
	server.inlineSlots <- struct{}{}
	server.inlineSlots <- struct{}{}

	payload := capabilityPayload{
		Purpose: purposeInline, MessageID: "timeout@example.test", Part: 7, FileName: "logo.png", MediaType: "image/png",
	}
	token, _ := server.Signer.Sign(payload)
	response := httptest.NewRecorder()
	server.ServeHTTP(response, httptest.NewRequest(http.MethodGet, signedRoute("/inline-image", token), nil))
	for len(server.inlineSlots) > 0 {
		<-server.inlineSlots
	}
	if response.Code != http.StatusGatewayTimeout {
		t.Fatalf("slot timeout status=%d want=%d body=%q", response.Code, http.StatusGatewayTimeout, response.Body.String())
	}
}

func TestUnsupportedImageTypeRemainsDownloadOnly(t *testing.T) {
	server, _ := newDownloadTestServer(t)
	token, _ := server.Signer.Sign(capabilityPayload{Purpose: purposeInline, MessageID: "image@example.test", Part: 5, FileName: "scan.tiff", MediaType: "image/tiff"})
	response := httptest.NewRecorder()
	server.ServeHTTP(response, httptest.NewRequest(http.MethodGet, signedRoute("/inline-image", token), nil))
	if response.Code != http.StatusNotFound {
		t.Fatalf("unsupported inline image status=%d want=404", response.Code)
	}
}

func TestSaveAllUsesSelectedDuplicateAndResolvesNames(t *testing.T) {
	server, runner := newDownloadTestServer(t)
	messageID := "zip@example.test"
	runner.outputs["search\x00--output=files\x00id:"+messageID] = "/mail/one\n/mail/two\n"
	runner.outputs["show\x00--format=json\x00--entire-thread=false\x00--include-html\x00--decrypt=false\x00--duplicate=2\x00id:"+messageID] = zipMIMEJSON
	runner.rawOutputs[rawPartKey(messageID, 1, 3)] = []byte("first-copy")
	runner.rawOutputs[rawPartKey(messageID, 1, 4)] = []byte("second-copy")
	token, _ := server.Signer.Sign(capabilityPayload{Purpose: purposeArchive, MessageID: messageID, Duplicate: 1})
	response := httptest.NewRecorder()
	server.ServeHTTP(response, httptest.NewRequest(http.MethodGet, signedRoute("/attachments.zip", token), nil))
	if response.Code != http.StatusOK {
		t.Fatalf("ZIP status=%d body=%s", response.Code, response.Body.String())
	}
	reader, err := zip.NewReader(bytes.NewReader(response.Body.Bytes()), int64(response.Body.Len()))
	if err != nil {
		t.Fatalf("open ZIP: %v", err)
	}
	if len(reader.File) != 2 || reader.File[0].Name != "report.txt" || reader.File[1].Name != "report (2).txt" {
		t.Fatalf("unexpected ZIP entries: %#v", reader.File)
	}
	for i, want := range []string{"first-copy", "second-copy"} {
		file, err := reader.File[i].Open()
		if err != nil {
			t.Fatal(err)
		}
		got, err := io.ReadAll(file)
		_ = file.Close()
		if err != nil || string(got) != want || reader.File[i].Method != zip.Store {
			t.Fatalf("entry %d: bytes=%q method=%d err=%v", i, got, reader.File[i].Method, err)
		}
	}
	if count, size := temporaryFileStats(server.Config.DownloadTempDir); count != 0 || size != 0 {
		t.Fatalf("ZIP temporary files remain: count=%d size=%d", count, size)
	}
}

func TestSaveAllExcludesReferencedInlineBodyResources(t *testing.T) {
	server, runner := newDownloadTestServer(t)
	messageID := "zip-inline@example.test"
	runner.outputs["search\x00--output=files\x00id:"+messageID] = "/mail/one\n"
	runner.outputs["show\x00--format=json\x00--entire-thread=false\x00--include-html\x00--decrypt=false\x00--duplicate=1\x00id:"+messageID] = inlineZIPMIMEJSON
	runner.rawOutputs[rawPartKey(messageID, 0, 4)] = []byte("real attachment")
	token, _ := server.Signer.Sign(capabilityPayload{Purpose: purposeArchive, MessageID: messageID})
	response := httptest.NewRecorder()
	server.ServeHTTP(response, httptest.NewRequest(http.MethodGet, signedRoute("/attachments.zip", token), nil))
	if response.Code != http.StatusOK {
		t.Fatalf("ZIP status=%d body=%s", response.Code, response.Body.String())
	}
	reader, err := zip.NewReader(bytes.NewReader(response.Body.Bytes()), int64(response.Body.Len()))
	if err != nil {
		t.Fatal(err)
	}
	if len(reader.File) != 1 || reader.File[0].Name != "report.pdf" {
		t.Fatalf("body resource leaked into ZIP: %#v", reader.File)
	}
	for _, call := range runner.calls {
		if strings.Contains(strings.Join(call, "\x00"), "--part=3") {
			t.Fatalf("body resource part was decoded for Save All: %#v", call)
		}
	}
}

func TestDownloadFailureStatusesAndCleanup(t *testing.T) {
	tests := []struct {
		name       string
		runnerErr  error
		maxBytes   int64
		body       []byte
		wantStatus int
	}{
		{name: "oversize", maxBytes: 3, body: []byte("1234"), wantStatus: http.StatusRequestEntityTooLarge},
		{name: "timeout", runnerErr: context.DeadlineExceeded, maxBytes: 20, wantStatus: http.StatusGatewayTimeout},
		{name: "notmuch", runnerErr: errors.New("notmuch failed"), maxBytes: 20, wantStatus: http.StatusBadGateway},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			server, runner := newDownloadTestServer(t)
			server.Config.MaxAttachmentBytes = test.maxBytes
			payload := capabilityPayload{Purpose: purposeAttachment, MessageID: "failure@example.test", Part: 3, FileName: "x.bin", MediaType: "application/octet-stream"}
			key := rawPartKey(payload.MessageID, 0, payload.Part)
			runner.rawOutputs[key] = test.body
			if test.runnerErr != nil {
				runner.errs[key] = test.runnerErr
			}
			token, _ := server.Signer.Sign(payload)
			response := httptest.NewRecorder()
			server.ServeHTTP(response, httptest.NewRequest(http.MethodGet, signedRoute("/attachment", token), nil))
			if response.Code != test.wantStatus {
				t.Fatalf("status=%d want=%d body=%s", response.Code, test.wantStatus, response.Body.String())
			}
			if count, size := temporaryFileStats(server.Config.DownloadTempDir); count != 0 || size != 0 {
				t.Fatalf("temporary files remain after failure: count=%d size=%d", count, size)
			}
		})
	}
}

func TestSaveAllLimitsReturn413AndCleanTemp(t *testing.T) {
	for _, test := range []struct {
		name     string
		maxParts int
		maxBytes int64
	}{
		{name: "attachment-count", maxParts: 1, maxBytes: 100},
		{name: "decoded-bytes", maxParts: 10, maxBytes: 5},
	} {
		t.Run(test.name, func(t *testing.T) {
			server, runner := newDownloadTestServer(t)
			server.Config.MaxZIPAttachments = test.maxParts
			server.Config.MaxZIPDecodedBytes = test.maxBytes
			server.Config.MaxAttachmentBytes = 100
			messageID := "zip-limit@example.test"
			runner.outputs["search\x00--output=files\x00id:"+messageID] = "/mail/one\n"
			runner.outputs["show\x00--format=json\x00--entire-thread=false\x00--include-html\x00--decrypt=false\x00--duplicate=1\x00id:"+messageID] = strings.ReplaceAll(zipMIMEJSON, "zip@example.test", messageID)
			runner.rawOutputs[rawPartKey(messageID, 0, 3)] = []byte("1234")
			runner.rawOutputs[rawPartKey(messageID, 0, 4)] = []byte("5678")
			token, _ := server.Signer.Sign(capabilityPayload{Purpose: purposeArchive, MessageID: messageID})
			response := httptest.NewRecorder()
			server.ServeHTTP(response, httptest.NewRequest(http.MethodGet, signedRoute("/attachments.zip", token), nil))
			if response.Code != http.StatusRequestEntityTooLarge {
				t.Fatalf("status=%d want=413 body=%s", response.Code, response.Body.String())
			}
			if count, size := temporaryFileStats(server.Config.DownloadTempDir); count != 0 || size != 0 {
				t.Fatalf("temporary files remain after ZIP limit: count=%d size=%d", count, size)
			}
		})
	}
}

func TestBusyDownloadReturns429(t *testing.T) {
	server, _ := newDownloadTestServer(t)
	server.downloadSlots <- struct{}{}
	defer func() { <-server.downloadSlots }()
	token, _ := server.Signer.Sign(capabilityPayload{Purpose: purposeAttachment, MessageID: "busy@example.test", Part: 1, FileName: "busy.bin", MediaType: "application/octet-stream"})
	response := httptest.NewRecorder()
	server.ServeHTTP(response, httptest.NewRequest(http.MethodGet, signedRoute("/attachment", token), nil))
	if response.Code != http.StatusTooManyRequests || response.Header().Get("Retry-After") == "" {
		t.Fatalf("busy response status=%d headers=%v", response.Code, response.Header())
	}
}

func newDownloadTestServer(t *testing.T) (*Server, *fakeRunner) {
	t.Helper()
	cfg := testConfig()
	cfg.DownloadTempDir = filepath.Join(t.TempDir(), "download-tmp")
	runner := &fakeRunner{outputs: map[string]string{}, rawOutputs: map[string][]byte{}, errs: map[string]error{}}
	signer, err := newCapabilitySignerWithKey(bytes.Repeat([]byte{0x51}, capabilityKeyBytes))
	if err != nil {
		t.Fatal(err)
	}
	server, err := newServerWithSigner(cfg, NotmuchClient{Config: cfg, Runner: runner}, signer)
	if err != nil {
		t.Fatal(err)
	}
	return server, runner
}

func rawPartKey(messageID string, duplicate int, part int) string {
	return strings.Join([]string{
		"show", "--format=raw", "--part=" + strconv.Itoa(part), "--duplicate=" + strconv.Itoa(duplicate+1), "--decrypt=false", "id:" + messageID,
	}, "\x00")
}

const zipMIMEJSON = `[[[{"id":"zip@example.test","match":true,"filename":["/mail/one","/mail/two"],"tags":["attachment"],"headers":{"Subject":"ZIP","From":"a","To":"b","Date":"Today"},"body":[{"id":1,"content-type":"text/plain","content":"body"},{"id":3,"content-type":"text/plain","content-disposition":"attachment","filename":"../report.txt"},{"id":4,"content-type":"text/plain","content-disposition":"attachment","filename":"report.txt"}]} ,[]]]]`

const inlineZIPMIMEJSON = `[[[{"id":"zip-inline@example.test","match":true,"filename":"/mail/one","tags":["attachment"],"headers":{"Subject":"ZIP inline","From":"a","To":"b","Date":"Today"},"body":[{"id":1,"content-type":"multipart/related","content":[{"id":2,"content-type":"text/html","content":"<p>Body<img src=\"cid:logo@example.test\"></p>"},{"id":3,"content-type":"image/png","content-id":"logo@example.test","content-disposition":"inline","filename":"logo.png"},{"id":4,"content-type":"application/pdf","content-disposition":"attachment","filename":"report.pdf"}]}]} ,[]]]]`
