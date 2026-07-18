package notmuchbrowser

import (
	"archive/zip"
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode"
)

const tempFilePrefix = "nmb-"

var errOutputTooLarge = errors.New("decoded MIME part exceeds configured limit")

type limitWriter struct {
	writer io.Writer
	max    int64
	wrote  int64
}

func (w *limitWriter) Write(data []byte) (int, error) {
	remaining := w.max - w.wrote
	if remaining <= 0 {
		return 0, errOutputTooLarge
	}
	if int64(len(data)) > remaining {
		n, err := w.writer.Write(data[:remaining])
		w.wrote += int64(n)
		if err != nil {
			return n, err
		}
		return n, errOutputTooLarge
	}
	n, err := w.writer.Write(data)
	w.wrote += int64(n)
	return n, err
}

func prepareDownloadTempDir(cfg Config) error {
	path := filepath.Clean(cfg.DownloadTempDir)
	if !filepath.IsAbs(path) {
		return errors.New("download temporary directory must be absolute")
	}
	if pathWithin(path, cfg.ExpectedMailRoot) || pathWithin(path, cfg.ExpectedDatabasePath) {
		return fmt.Errorf("download temporary directory %q must remain outside mail and index trees", path)
	}
	if info, err := os.Lstat(path); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("download temporary directory %q must not be a symlink", path)
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err := os.MkdirAll(path, 0o700); err != nil {
		return fmt.Errorf("create download temporary directory: %w", err)
	}
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return fmt.Errorf("resolve download temporary directory: %w", err)
	}
	if pathWithin(resolved, cfg.ExpectedMailRoot) || pathWithin(resolved, cfg.ExpectedDatabasePath) {
		return fmt.Errorf("resolved download temporary directory %q must remain outside mail and index trees", resolved)
	}
	if err := os.Chmod(path, 0o700); err != nil {
		return fmt.Errorf("secure download temporary directory: %w", err)
	}
	return cleanupDownloadTempDir(path, time.Now().Add(-24*time.Hour))
}

func cleanupDownloadTempDir(path string, olderThan time.Time) error {
	entries, err := os.ReadDir(path)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasPrefix(entry.Name(), tempFilePrefix) {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		if info.Mode().IsRegular() && info.ModTime().Before(olderThan) {
			if err := os.Remove(filepath.Join(path, entry.Name())); err != nil && !errors.Is(err, os.ErrNotExist) {
				return err
			}
		}
	}
	return nil
}

func pathWithin(path string, parent string) bool {
	if strings.TrimSpace(parent) == "" {
		return false
	}
	rel, err := filepath.Rel(filepath.Clean(parent), filepath.Clean(path))
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func (s *Server) handleAttachment(w http.ResponseWriter, r *http.Request) {
	if !requireGet(w, r) {
		return
	}
	payload, err := s.Signer.Verify(r.URL.Query().Get("cap"), purposeAttachment)
	if err != nil {
		http.Error(w, "invalid or expired download capability; refresh the message", http.StatusForbidden)
		return
	}
	if !tryAcquire(s.downloadSlots) {
		w.Header().Set("Retry-After", "2")
		http.Error(w, "another download is being prepared", http.StatusTooManyRequests)
		return
	}
	defer release(s.downloadSlots)

	ctx, cancel := context.WithTimeout(r.Context(), s.Config.DownloadTimeout)
	defer cancel()
	path, size, err := s.preparePart(ctx, payload, s.Config.MaxAttachmentBytes, s.Config.DownloadTimeout)
	if err != nil {
		writeDownloadError(w, err)
		return
	}
	defer os.Remove(path)
	name := sanitizeFilename(payload.FileName)
	if name == "" {
		name = fmt.Sprintf("attachment-part-%d%s", payload.Part, extensionForMediaType(payload.MediaType))
	}
	w.Header().Set("Content-Type", contentTypeOrBinary(payload.MediaType))
	w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": name}))
	w.Header().Set("Cache-Control", "private, no-store")
	servePreparedFile(w, r, path, name, size)
}

func (s *Server) handleInlineImage(w http.ResponseWriter, r *http.Request) {
	if !requireGet(w, r) {
		return
	}
	payload, err := s.Signer.Verify(r.URL.Query().Get("cap"), purposeInline)
	if err != nil {
		http.Error(w, "invalid or expired image capability; refresh the message", http.StatusForbidden)
		return
	}
	if !browserImageType(payload.MediaType) {
		http.Error(w, "image type is download-only", http.StatusNotFound)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), s.Config.InlineImageTimeout)
	defer cancel()
	select {
	case s.inlineSlots <- struct{}{}:
		defer release(s.inlineSlots)
	case <-ctx.Done():
		writeDownloadError(w, ctx.Err())
		return
	}
	path, size, err := s.preparePart(ctx, payload, s.Config.MaxInlineImageBytes, s.Config.InlineImageTimeout)
	if err != nil {
		writeDownloadError(w, err)
		return
	}
	defer os.Remove(path)
	name := sanitizeFilename(payload.FileName)
	if name == "" {
		name = fmt.Sprintf("inline-part-%d%s", payload.Part, extensionForMediaType(payload.MediaType))
	}
	w.Header().Set("Content-Type", payload.MediaType)
	w.Header().Set("Content-Disposition", mime.FormatMediaType("inline", map[string]string{"filename": name}))
	w.Header().Set("Cache-Control", "private, no-store")
	if payload.MediaType == "image/svg+xml" {
		w.Header().Set("Cross-Origin-Resource-Policy", "same-origin")
		w.Header().Set("Content-Security-Policy", "sandbox; default-src 'none'; style-src 'unsafe-inline'")
	}
	servePreparedFile(w, r, path, name, size)
}

func (s *Server) handleAttachmentsZIP(w http.ResponseWriter, r *http.Request) {
	if !requireGet(w, r) {
		return
	}
	payload, err := s.Signer.Verify(r.URL.Query().Get("cap"), purposeArchive)
	if err != nil {
		http.Error(w, "invalid or expired archive capability; refresh the message", http.StatusForbidden)
		return
	}
	if !tryAcquire(s.downloadSlots) {
		w.Header().Set("Retry-After", "2")
		http.Error(w, "another download is being prepared", http.StatusTooManyRequests)
		return
	}
	defer release(s.downloadSlots)

	ctx, cancel := context.WithTimeout(r.Context(), s.Config.DownloadTimeout)
	defer cancel()
	detail, err := s.Client.Message(ctx, payload.MessageID, payload.Duplicate)
	if err != nil {
		writeDownloadError(w, err)
		return
	}
	if len(detail.Attachments) == 0 {
		http.Error(w, "selected duplicate has no downloadable attachments", http.StatusNotFound)
		return
	}
	if len(detail.Attachments) > s.Config.MaxZIPAttachments {
		http.Error(w, "selected duplicate has too many attachments", http.StatusRequestEntityTooLarge)
		return
	}
	path, size, err := s.prepareZIP(ctx, detail)
	if err != nil {
		writeDownloadError(w, err)
		return
	}
	defer os.Remove(path)
	w.Header().Set("Content-Type", "application/zip")
	w.Header().Set("Content-Disposition", `attachment; filename="attachments.zip"`)
	w.Header().Set("Cache-Control", "private, no-store")
	servePreparedFile(w, r, path, "attachments.zip", size)
}

func (s *Server) preparePart(ctx context.Context, payload capabilityPayload, limit int64, timeout time.Duration) (string, int64, error) {
	file, err := os.CreateTemp(s.Config.DownloadTempDir, tempFilePrefix+"part-")
	if err != nil {
		return "", 0, fmt.Errorf("create temporary file: %w", err)
	}
	path := file.Name()
	remove := true
	defer func() {
		_ = file.Close()
		if remove {
			_ = os.Remove(path)
		}
	}()
	if err := file.Chmod(0o600); err != nil {
		return "", 0, err
	}
	limited := &limitWriter{writer: file, max: limit}
	if err := s.Client.WritePart(ctx, payload.MessageID, payload.Duplicate, payload.Part, limited, timeout); err != nil {
		return "", 0, err
	}
	if err := file.Close(); err != nil {
		return "", 0, err
	}
	remove = false
	return path, limited.wrote, nil
}

func (s *Server) prepareZIP(ctx context.Context, detail MessageDetail) (string, int64, error) {
	file, err := os.CreateTemp(s.Config.DownloadTempDir, tempFilePrefix+"attachments-")
	if err != nil {
		return "", 0, fmt.Errorf("create ZIP temporary file: %w", err)
	}
	path := file.Name()
	remove := true
	defer func() {
		_ = file.Close()
		if remove {
			_ = os.Remove(path)
		}
	}()
	if err := file.Chmod(0o600); err != nil {
		return "", 0, err
	}
	archive := zip.NewWriter(file)
	usedNames := map[string]int{}
	var total int64
	for _, attachment := range detail.Attachments {
		remaining := s.Config.MaxZIPDecodedBytes - total
		if remaining <= 0 {
			return "", 0, errOutputTooLarge
		}
		partLimit := min(s.Config.MaxAttachmentBytes, remaining)
		name := uniqueArchiveName(sanitizeFilename(attachment.FileName), usedNames)
		header := &zip.FileHeader{Name: name, Method: zip.Store}
		header.SetMode(0o600)
		entry, err := archive.CreateHeader(header)
		if err != nil {
			return "", 0, err
		}
		limited := &limitWriter{writer: entry, max: partLimit}
		if err := s.Client.WritePart(ctx, detail.Summary.ID, detail.SelectedDup, attachment.PartID, limited, s.Config.DownloadTimeout); err != nil {
			return "", 0, err
		}
		total += limited.wrote
	}
	if err := archive.Close(); err != nil {
		return "", 0, err
	}
	if err := file.Close(); err != nil {
		return "", 0, err
	}
	info, err := os.Stat(path)
	if err != nil {
		return "", 0, err
	}
	remove = false
	return path, info.Size(), nil
}

func servePreparedFile(w http.ResponseWriter, r *http.Request, path string, name string, size int64) {
	file, err := os.Open(path)
	if err != nil {
		http.Error(w, "prepared file is unavailable", http.StatusInternalServerError)
		return
	}
	defer file.Close()
	w.Header().Set("Content-Length", fmt.Sprintf("%d", size))
	http.ServeContent(w, r, name, time.Time{}, file)
}

func writeDownloadError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, errOutputTooLarge):
		http.Error(w, "decoded output exceeds the configured limit", http.StatusRequestEntityTooLarge)
	case errors.Is(err, context.DeadlineExceeded), errors.Is(err, context.Canceled):
		http.Error(w, "notmuch decoding timed out", http.StatusGatewayTimeout)
	default:
		http.Error(w, "notmuch could not decode the selected MIME part", http.StatusBadGateway)
	}
}

func tryAcquire(slots chan struct{}) bool {
	select {
	case slots <- struct{}{}:
		return true
	default:
		return false
	}
}

func release(slots chan struct{}) {
	<-slots
}

func signedRoute(path string, token string) string {
	values := url.Values{}
	values.Set("cap", token)
	return path + "?" + values.Encode()
}

func sanitizeFilename(name string) string {
	name = strings.ReplaceAll(name, "\\", "/")
	name = filepath.Base(name)
	var cleaned []rune
	for _, r := range strings.TrimSpace(name) {
		if unicode.IsControl(r) || unicode.Is(unicode.Cf, r) || r == '/' || r == '\\' {
			continue
		}
		if strings.ContainsRune(`<>:"|?*`, r) {
			r = '_'
		}
		cleaned = append(cleaned, r)
		if len(cleaned) >= 180 {
			break
		}
	}
	name = strings.Trim(strings.TrimSpace(string(cleaned)), ".")
	if name == "" || name == "." || name == ".." {
		return ""
	}
	base := strings.ToUpper(strings.TrimSuffix(name, filepath.Ext(name)))
	if base == "CON" || base == "PRN" || base == "AUX" || base == "NUL" || len(base) == 4 && (strings.HasPrefix(base, "COM") || strings.HasPrefix(base, "LPT")) && base[3] >= '1' && base[3] <= '9' {
		name = "_" + name
	}
	return name
}

func uniqueArchiveName(name string, used map[string]int) string {
	if name == "" {
		name = "attachment"
	}
	key := strings.ToLower(name)
	used[key]++
	if used[key] == 1 {
		return name
	}
	ext := filepath.Ext(name)
	base := strings.TrimSuffix(name, ext)
	for n := used[key]; ; n++ {
		candidate := fmt.Sprintf("%s (%d)%s", base, n, ext)
		candidateKey := strings.ToLower(candidate)
		if used[candidateKey] == 0 {
			used[candidateKey] = 1
			used[key] = n
			return candidate
		}
	}
}

func extensionForMediaType(mediaType string) string {
	switch strings.ToLower(mediaType) {
	case "image/png":
		return ".png"
	case "image/jpeg":
		return ".jpg"
	case "image/gif":
		return ".gif"
	case "image/webp":
		return ".webp"
	case "image/bmp":
		return ".bmp"
	case "image/svg+xml":
		return ".svg"
	case "application/pdf":
		return ".pdf"
	case "message/rfc822":
		return ".eml"
	case "text/plain":
		return ".txt"
	default:
		return ""
	}
}

func contentTypeOrBinary(mediaType string) string {
	mediaType = strings.TrimSpace(mediaType)
	if mediaType == "" {
		return "application/octet-stream"
	}
	return mediaType
}

func temporaryFileStats(path string) (int, int64) {
	entries, err := os.ReadDir(path)
	if err != nil {
		return 0, 0
	}
	var count int
	var size int64
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasPrefix(entry.Name(), tempFilePrefix) {
			continue
		}
		if info, err := entry.Info(); err == nil && info.Mode().IsRegular() {
			count++
			size += info.Size()
		}
	}
	return count, size
}
