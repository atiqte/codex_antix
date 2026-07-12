package notmuchbrowser

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/iotest"
	"time"
)

func TestCapabilityRoundTripAndPurpose(t *testing.T) {
	signer, err := newCapabilitySignerWithKey(bytes.Repeat([]byte{0x11}, capabilityKeyBytes))
	if err != nil {
		t.Fatal(err)
	}
	want := capabilityPayload{
		Purpose:   purposeAttachment,
		MessageID: "message@example.test",
		Duplicate: 2,
		Part:      7,
		FileName:  "report.pdf",
		MediaType: "application/pdf",
	}
	token, err := signer.Sign(want)
	if err != nil {
		t.Fatalf("Sign: %v", err)
	}
	got, err := signer.Verify(token, purposeAttachment)
	if err != nil {
		t.Fatalf("Verify: %v", err)
	}
	if got.MessageID != want.MessageID || got.Duplicate != want.Duplicate || got.Part != want.Part || got.FileName != want.FileName {
		t.Fatalf("unexpected verified payload: %#v", got)
	}
	if _, err := signer.Verify(token, purposeInline); !errors.Is(err, errInvalidCapability) {
		t.Fatalf("expected purpose mismatch rejection, got %v", err)
	}
}

func TestCapabilityTamperAndRestartRejection(t *testing.T) {
	first, _ := newCapabilitySignerWithKey(bytes.Repeat([]byte{0x21}, capabilityKeyBytes))
	second, _ := newCapabilitySignerWithKey(bytes.Repeat([]byte{0x22}, capabilityKeyBytes))
	token, err := first.Sign(capabilityPayload{
		Purpose: purposeInline, MessageID: "m@example.test", Part: 3, MediaType: "image/png",
	})
	if err != nil {
		t.Fatal(err)
	}
	parts := strings.Split(token, ".")
	raw, _ := base64.RawURLEncoding.DecodeString(parts[0])
	var payload capabilityPayload
	_ = json.Unmarshal(raw, &payload)
	payload.Part = 4
	tampered, _ := json.Marshal(payload)
	tamperedToken := base64.RawURLEncoding.EncodeToString(tampered) + "." + parts[1]
	if _, err := first.Verify(tamperedToken, purposeInline); !errors.Is(err, errInvalidCapability) {
		t.Fatalf("expected payload tamper rejection, got %v", err)
	}
	if _, err := second.Verify(token, purposeInline); !errors.Is(err, errInvalidCapability) {
		t.Fatalf("expected startup-key rejection, got %v", err)
	}
}

func TestCapabilityKeyGenerationFailsClosed(t *testing.T) {
	if _, err := newCapabilitySignerFrom(iotest.ErrReader(errors.New("entropy unavailable"))); err == nil || !strings.Contains(err.Error(), "entropy unavailable") {
		t.Fatalf("expected entropy failure, got %v", err)
	}
	if _, err := newCapabilitySignerWithKey(make([]byte, capabilityKeyBytes-1)); err == nil {
		t.Fatal("expected short capability key rejection")
	}
}

func TestFilenameSanitizationAndZIPCollisions(t *testing.T) {
	if got := sanitizeFilename("../../dir\\evil\r\nname.pdf"); got != "evilname.pdf" {
		t.Fatalf("unexpected sanitized filename %q", got)
	}
	if got := sanitizeFilename("CON:<report>?.txt"); got != "CON__report__.txt" {
		t.Fatalf("unexpected portable filename %q", got)
	}
	if got := sanitizeFilename("NUL.txt"); got != "_NUL.txt" {
		t.Fatalf("reserved Windows filename was retained: %q", got)
	}
	used := map[string]int{}
	got := []string{
		uniqueArchiveName("report.pdf", used),
		uniqueArchiveName("report.pdf", used),
		uniqueArchiveName("REPORT.PDF", used),
	}
	want := []string{"report.pdf", "report (2).pdf", "REPORT (3).PDF"}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("collision %d: got %q want %q", i, got[i], want[i])
		}
	}
}

func TestLimitWriterStopsAtConfiguredBytes(t *testing.T) {
	var output bytes.Buffer
	limited := &limitWriter{writer: &output, max: 4}
	n, err := limited.Write([]byte("123456"))
	if n != 4 || !errors.Is(err, errOutputTooLarge) || output.String() != "1234" || limited.wrote != 4 {
		t.Fatalf("unexpected limited write: n=%d err=%v output=%q wrote=%d", n, err, output.String(), limited.wrote)
	}
}

func TestStartupCleanupRemovesOnlyOldOwnedTempFiles(t *testing.T) {
	dir := t.TempDir()
	oldPath := filepath.Join(dir, tempFilePrefix+"old")
	freshPath := filepath.Join(dir, tempFilePrefix+"fresh")
	unrelated := filepath.Join(dir, "keep.txt")
	for _, path := range []string{oldPath, freshPath, unrelated} {
		if err := os.WriteFile(path, []byte("x"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	old := time.Now().Add(-25 * time.Hour)
	if err := os.Chtimes(oldPath, old, old); err != nil {
		t.Fatal(err)
	}
	if err := cleanupDownloadTempDir(dir, time.Now().Add(-24*time.Hour)); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(oldPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("old owned temp file still exists: %v", err)
	}
	for _, path := range []string{freshPath, unrelated} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("expected %s to remain: %v", path, err)
		}
	}
}
