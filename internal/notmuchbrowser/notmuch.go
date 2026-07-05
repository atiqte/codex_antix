package notmuchbrowser

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// Runner executes notmuch with a fixed config.
type Runner interface {
	Run(ctx context.Context, timeout time.Duration, args ...string) (stdout string, stderr string, err error)
}

// ExecRunner invokes the notmuch CLI without a shell.
type ExecRunner struct {
	ConfigPath string
}

func (r ExecRunner) Run(ctx context.Context, timeout time.Duration, args ...string) (string, string, error) {
	if strings.TrimSpace(r.ConfigPath) == "" {
		return "", "", errors.New("missing notmuch config path")
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	fullArgs := append([]string{"--config", r.ConfigPath}, args...)
	cmd := exec.CommandContext(ctx, "notmuch", fullArgs...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if ctx.Err() != nil {
		return stdout.String(), stderr.String(), fmt.Errorf("notmuch command timed out: %w", ctx.Err())
	}
	if err != nil {
		return stdout.String(), stderr.String(), fmt.Errorf("notmuch %s failed: %w: %s", strings.Join(args, " "), err, trimOutput(stderr.String(), 2048))
	}
	return stdout.String(), stderr.String(), nil
}

// NotmuchClient is the read-only notmuch access layer used by HTTP handlers.
type NotmuchClient struct {
	Config Config
	Runner Runner
}

type Counts struct {
	Messages int
	Files    int
}

type SearchPage struct {
	Query   string
	Offset  int
	Limit   int
	Counts  Counts
	Results []MessageSummary
}

type MessageSummary struct {
	ID           string
	Subject      string
	From         string
	To           string
	Date         string
	DateRelative string
	Tags         []string
	FileCount    int
	Matched      bool
	Excluded     bool
	Error        string
}

type MessageDetail struct {
	Summary       MessageSummary
	Files         []string
	SelectedDup   int
	SelectedFile  string
	PlainBody     string
	HTMLBody      string
	HTMLSrcdoc    string
	BodyKind      string
	Attachments   []string
	HasBody       bool
	DuplicateNote string
}

type Status struct {
	ConfigPath           string
	DatabasePath         string
	MailRoot             string
	MaildirSyncFlags     string
	IndexDecrypt         string
	NewIgnore            string
	NotmuchVersion       string
	Counts               Counts
	MbsyncLockPresent    bool
	StartupSafetySkipped bool
}

func NewNotmuchClient(cfg Config) NotmuchClient {
	return NotmuchClient{
		Config: cfg,
		Runner: ExecRunner{ConfigPath: cfg.NotmuchConfig},
	}
}

func (c NotmuchClient) Count(ctx context.Context, query string) (Counts, error) {
	if err := c.Config.ValidateQuery(query); err != nil {
		return Counts{}, err
	}
	messages, err := c.countOne(ctx, query)
	if err != nil {
		return Counts{}, err
	}
	files, err := c.countOne(ctx, "--output=files", query)
	if err != nil {
		return Counts{}, err
	}
	return Counts{Messages: messages, Files: files}, nil
}

func (c NotmuchClient) Search(ctx context.Context, query string, offset int, limit int) (SearchPage, error) {
	query = normalizeQuery(query)
	if err := c.Config.ValidateQuery(query); err != nil {
		return SearchPage{}, err
	}
	if offset < 0 {
		offset = 0
	}
	if limit < 1 || limit > c.Config.MaxResults {
		limit = c.Config.MaxResults
	}

	counts, err := c.Count(ctx, query)
	if err != nil {
		return SearchPage{}, err
	}

	stdout, _, err := c.Runner.Run(
		ctx,
		c.Config.ShowTimeout,
		"show",
		"--format=json",
		"--entire-thread=false",
		"--body=false",
		"--offset="+strconv.Itoa(offset),
		"--limit="+strconv.Itoa(limit),
		query,
	)
	if err != nil {
		return SearchPage{}, err
	}
	summaries, err := ParseSummaries([]byte(stdout))
	if err != nil {
		return SearchPage{}, err
	}
	return SearchPage{
		Query:   query,
		Offset:  offset,
		Limit:   limit,
		Counts:  counts,
		Results: summaries,
	}, nil
}

func (c NotmuchClient) Message(ctx context.Context, id string, duplicate int) (MessageDetail, error) {
	id = normalizeMessageID(id)
	if err := c.Config.ValidateMessageID(id); err != nil {
		return MessageDetail{}, err
	}
	files, err := c.FilesFor(ctx, id)
	if err != nil {
		return MessageDetail{}, err
	}
	if duplicate < 0 || duplicate >= len(files) {
		duplicate = 0
	}

	args := []string{
		"show",
		"--format=json",
		"--entire-thread=false",
		"--include-html",
		"--decrypt=false",
		"--duplicate=" + strconv.Itoa(duplicate+1),
		"id:" + id,
	}
	stdout, _, err := c.Runner.Run(ctx, c.Config.ShowTimeout, args...)
	if err != nil {
		return MessageDetail{}, err
	}
	messages, err := ParseMessageDetails([]byte(stdout))
	if err != nil {
		return MessageDetail{}, err
	}
	if len(messages) == 0 {
		return MessageDetail{}, fmt.Errorf("notmuch returned no message for id:%s", id)
	}
	detail := messages[0]
	detail.Files = files
	detail.SelectedDup = duplicate
	if duplicate >= 0 && duplicate < len(files) {
		detail.SelectedFile = files[duplicate]
	}
	if len(files) > 1 {
		detail.DuplicateNote = fmt.Sprintf("%d duplicate/copy files share this Message-ID", len(files))
	}
	return detail, nil
}

func (c NotmuchClient) FilesFor(ctx context.Context, id string) ([]string, error) {
	id = normalizeMessageID(id)
	if err := c.Config.ValidateMessageID(id); err != nil {
		return nil, err
	}
	stdout, _, err := c.Runner.Run(ctx, c.Config.CommandTimeout, "search", "--output=files", "id:"+id)
	if err != nil {
		return nil, err
	}
	files := make([]string, 0)
	seen := make(map[string]bool)
	for _, line := range strings.Split(stdout, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || seen[line] {
			continue
		}
		seen[line] = true
		files = append(files, line)
	}
	return files, nil
}

func (c NotmuchClient) Status(ctx context.Context) (Status, error) {
	counts, err := c.Count(ctx, "*")
	if err != nil {
		return Status{}, err
	}
	databasePath, _ := c.ConfigValue(ctx, "database.path")
	mailRoot, _ := c.ConfigValue(ctx, "database.mail_root")
	syncFlags, _ := c.ConfigValue(ctx, "maildir.synchronize_flags")
	indexDecrypt, _ := c.ConfigValue(ctx, "index.decrypt")
	newIgnore, _ := c.ConfigValue(ctx, "new.ignore")
	version, _ := c.version(ctx)
	return Status{
		ConfigPath:           c.Config.NotmuchConfig,
		DatabasePath:         databasePath,
		MailRoot:             mailRoot,
		MaildirSyncFlags:     syncFlags,
		IndexDecrypt:         indexDecrypt,
		NewIgnore:            newIgnore,
		NotmuchVersion:       version,
		Counts:               counts,
		MbsyncLockPresent:    dirExists(c.Config.MbsyncLockDir),
		StartupSafetySkipped: c.Config.SkipStartupSafety,
	}, nil
}

func (c NotmuchClient) CheckStartupSafety(ctx context.Context) error {
	if c.Config.SkipStartupSafety {
		return nil
	}
	checks := []struct {
		key      string
		expected string
	}{
		{"database.path", c.Config.ExpectedDatabasePath},
		{"database.mail_root", c.Config.ExpectedMailRoot},
		{"maildir.synchronize_flags", c.Config.ExpectedSyncFlags},
		{"index.decrypt", c.Config.ExpectedIndexDecrypt},
	}
	for _, check := range checks {
		actual, err := c.ConfigValue(ctx, check.key)
		if err != nil {
			return err
		}
		if actual != check.expected {
			return fmt.Errorf("unsafe notmuch config: %s=%q, expected %q", check.key, actual, check.expected)
		}
	}
	return nil
}

func (c NotmuchClient) ConfigValue(ctx context.Context, key string) (string, error) {
	stdout, _, err := c.Runner.Run(ctx, c.Config.CommandTimeout, "config", "get", key)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(stdout), nil
}

func (c NotmuchClient) countOne(ctx context.Context, args ...string) (int, error) {
	stdout, _, err := c.Runner.Run(ctx, c.Config.CommandTimeout, append([]string{"count"}, args...)...)
	if err != nil {
		return 0, err
	}
	value, err := strconv.Atoi(strings.TrimSpace(stdout))
	if err != nil {
		return 0, fmt.Errorf("cannot parse notmuch count %q: %w", stdout, err)
	}
	return value, nil
}

func (c NotmuchClient) version(ctx context.Context) (string, error) {
	stdout, _, err := c.Runner.Run(ctx, c.Config.CommandTimeout, "--version")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(stdout), nil
}

func ParseSummaries(data []byte) ([]MessageSummary, error) {
	objects, err := messageObjects(data)
	if err != nil {
		return nil, err
	}
	out := make([]MessageSummary, 0, len(objects))
	seen := make(map[string]bool)
	for _, obj := range objects {
		summary := summaryFromMap(obj)
		if summary.ID == "" || seen[summary.ID] {
			continue
		}
		seen[summary.ID] = true
		out = append(out, summary)
	}
	return out, nil
}

func ParseMessageDetails(data []byte) ([]MessageDetail, error) {
	objects, err := messageObjects(data)
	if err != nil {
		return nil, err
	}
	out := make([]MessageDetail, 0, len(objects))
	seen := make(map[string]bool)
	for _, obj := range objects {
		summary := summaryFromMap(obj)
		if summary.ID == "" || seen[summary.ID] {
			continue
		}
		seen[summary.ID] = true
		detail := MessageDetail{Summary: summary}
		parts := collectBodyParts(obj["body"])
		for _, part := range parts {
			if part.FileName != "" {
				detail.Attachments = appendUnique(detail.Attachments, part.FileName)
			}
			if strings.EqualFold(part.Disposition, "attachment") && part.FileName == "" {
				detail.Attachments = appendUnique(detail.Attachments, part.ContentType)
			}
		}
		if htmlPart := firstPart(parts, "text/html"); htmlPart.Content != "" {
			detail.HTMLBody = htmlPart.Content
			detail.HTMLSrcdoc = htmlSrcdoc(htmlPart.Content)
			detail.BodyKind = "html"
			detail.HasBody = true
		} else if plainPart := firstPart(parts, "text/plain"); plainPart.Content != "" {
			detail.PlainBody = plainPart.Content
			detail.BodyKind = "plain"
			detail.HasBody = true
		}
		out = append(out, detail)
	}
	return out, nil
}

func messageObjects(data []byte) ([]map[string]any, error) {
	var root any
	if err := json.Unmarshal(data, &root); err != nil {
		return nil, err
	}
	var out []map[string]any
	var walk func(any)
	walk = func(v any) {
		switch x := v.(type) {
		case []any:
			for _, item := range x {
				walk(item)
			}
		case map[string]any:
			if isMessageObject(x) {
				out = append(out, x)
			}
			for _, item := range x {
				walk(item)
			}
		}
	}
	walk(root)
	return out, nil
}

func isMessageObject(m map[string]any) bool {
	if _, ok := m["headers"].(map[string]any); !ok {
		return false
	}
	id, ok := m["id"].(string)
	if !ok || id == "" {
		return false
	}
	_, hasTags := m["tags"]
	_, hasMatch := m["match"]
	_, hasFilename := m["filename"]
	return hasTags || hasMatch || hasFilename
}

func summaryFromMap(m map[string]any) MessageSummary {
	headers, _ := m["headers"].(map[string]any)
	summary := MessageSummary{
		ID:           stringValue(m["id"]),
		Subject:      headerValue(headers, "Subject"),
		From:         headerValue(headers, "From"),
		To:           headerValue(headers, "To"),
		Date:         headerValue(headers, "Date"),
		DateRelative: stringValue(m["date_relative"]),
		Tags:         stringSlice(m["tags"]),
		FileCount:    filenameCount(m["filename"]),
		Matched:      boolValue(m["match"]),
		Excluded:     boolValue(m["excluded"]),
	}
	if summary.Subject == "" {
		summary.Subject = "(no subject)"
	}
	return summary
}

type bodyPart struct {
	ContentType string
	Content     string
	FileName    string
	Disposition string
}

func collectBodyParts(root any) []bodyPart {
	var out []bodyPart
	var walk func(any)
	walk = func(v any) {
		switch x := v.(type) {
		case []any:
			for _, item := range x {
				walk(item)
			}
		case map[string]any:
			part := bodyPart{
				ContentType: stringValue(x["content-type"]),
				Content:     stringValue(x["content"]),
				FileName:    stringValue(x["filename"]),
				Disposition: stringValue(x["content-disposition"]),
			}
			if part.ContentType != "" || part.Content != "" || part.FileName != "" || part.Disposition != "" {
				out = append(out, part)
			}
			walk(x["content"])
			walk(x["body"])
		}
	}
	walk(root)
	return out
}

func firstPart(parts []bodyPart, contentType string) bodyPart {
	for _, part := range parts {
		if strings.EqualFold(part.ContentType, contentType) && part.Content != "" {
			return part
		}
	}
	return bodyPart{}
}

func htmlSrcdoc(body string) string {
	return `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: cid:; style-src 'unsafe-inline'; font-src 'none'; script-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">` + body
}

func normalizeQuery(q string) string {
	q = strings.TrimSpace(q)
	if q == "" {
		return "tag:inbox"
	}
	return q
}

func normalizeMessageID(id string) string {
	id = strings.TrimSpace(id)
	id = strings.TrimPrefix(id, "id:")
	return strings.TrimSpace(id)
}

func stringValue(v any) string {
	switch x := v.(type) {
	case string:
		return x
	case fmt.Stringer:
		return x.String()
	default:
		return ""
	}
}

func headerValue(headers map[string]any, name string) string {
	if headers == nil {
		return ""
	}
	return stringValue(headers[name])
}

func boolValue(v any) bool {
	value, _ := v.(bool)
	return value
}

func stringSlice(v any) []string {
	items, ok := v.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(items))
	for _, item := range items {
		if s := stringValue(item); s != "" {
			out = append(out, s)
		}
	}
	return out
}

func filenameCount(v any) int {
	switch x := v.(type) {
	case string:
		if x == "" {
			return 0
		}
		return 1
	case []any:
		count := 0
		for _, item := range x {
			if stringValue(item) != "" {
				count++
			}
		}
		return count
	default:
		return 0
	}
}

func appendUnique(items []string, value string) []string {
	value = strings.TrimSpace(value)
	if value == "" {
		return items
	}
	for _, item := range items {
		if item == value {
			return items
		}
	}
	return append(items, value)
}

func trimOutput(s string, max int) string {
	s = strings.TrimSpace(s)
	if len(s) <= max {
		return s
	}
	return s[:max] + "...(truncated)"
}

func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}
