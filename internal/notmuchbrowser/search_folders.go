package notmuchbrowser

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type approvedSearchSource struct {
	Path  string
	Label string
}

var approvedSearchSources = []approvedSearchSource{
	{Path: "mbsync/provider-live", Label: "Live provider"},
	{Path: "mbsync/provider-inbox-test", Label: "Provider inbox test"},
	{Path: "evolution/local-maildir", Label: "Historical local archive"},
	{Path: "evolution/betterbird-delta-maildirpp-20260704", Label: "Betterbird delta"},
	{Path: "evolution/provider-live-archive", Label: "Provider live archive"},
	{Path: "evolution/test-maildir", Label: "Evolution test mail"},
}

func allMailFolder() SearchFolder {
	return SearchFolder{Value: "all", Label: "All Mail", ShowCount: true}
}

func (catalog SearchFolderCatalog) Resolve(value string) (SearchFolder, bool) {
	value = strings.TrimSpace(value)
	if value == "" || value == "all" {
		return catalog.All, true
	}
	for _, group := range catalog.Groups {
		for _, option := range group.Options {
			if option.Value == value {
				return option, true
			}
		}
	}
	return SearchFolder{}, false
}

func (c NotmuchClient) SearchFolderCatalog(ctx context.Context) (SearchFolderCatalog, error) {
	all := allMailFolder()
	allMessages, err := c.countOne(ctx, "*")
	if err != nil {
		return SearchFolderCatalog{}, err
	}
	all.Messages = allMessages
	catalog := SearchFolderCatalog{All: all}

	root := filepath.Clean(c.Config.ExpectedMailRoot)
	for _, source := range approvedSearchSources {
		sourceRoot := filepath.Join(root, filepath.FromSlash(source.Path))
		info, err := os.Lstat(sourceRoot)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return SearchFolderCatalog{}, fmt.Errorf("inspect search source %s: %w", source.Path, err)
		}
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			continue
		}

		sourceFolder := SearchFolder{
			Value:        source.Path,
			Label:        "All folders",
			RelativePath: source.Path,
			ShowCount:    true,
		}
		sourceFolder.Messages, err = c.countOne(ctx, scopedPathTerm(source.Path))
		if err != nil {
			return SearchFolderCatalog{}, err
		}
		group := SearchFolderGroup{Label: source.Label, Options: []SearchFolder{sourceFolder}}
		subfolders, err := discoverMaildirSubfolders(sourceRoot, source.Path)
		if err != nil {
			return SearchFolderCatalog{}, err
		}
		group.Options = append(group.Options, subfolders...)
		catalog.Groups = append(catalog.Groups, group)
	}
	return catalog, nil
}

func discoverMaildirSubfolders(sourceRoot string, sourceRelative string) ([]SearchFolder, error) {
	var folders []SearchFolder
	err := filepath.WalkDir(sourceRoot, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.Type()&os.ModeSymlink != 0 {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if !entry.IsDir() {
			return nil
		}
		if path != sourceRoot {
			switch entry.Name() {
			case "cur", "new", "tmp":
				return filepath.SkipDir
			}
		}
		if path == sourceRoot || !isNonemptyMaildir(path) {
			return nil
		}
		withinSource, err := filepath.Rel(sourceRoot, path)
		if err != nil {
			return err
		}
		relative := filepath.ToSlash(filepath.Join(filepath.FromSlash(sourceRelative), withinSource))
		folders = append(folders, SearchFolder{
			Value:        relative,
			Label:        maildirFolderLabel(filepath.ToSlash(withinSource)),
			RelativePath: relative,
		})
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("discover Maildir folders under %s: %w", sourceRoot, err)
	}
	return folders, nil
}

func isNonemptyMaildir(path string) bool {
	for _, leaf := range []string{"cur", "new"} {
		dir := filepath.Join(path, leaf)
		handle, err := os.Open(dir)
		if err != nil {
			continue
		}
		for {
			entries, readErr := handle.ReadDir(32)
			for _, entry := range entries {
				if entry.Type().IsRegular() {
					_ = handle.Close()
					return true
				}
			}
			if readErr != nil {
				break
			}
		}
		_ = handle.Close()
	}
	return false
}

func maildirFolderLabel(relative string) string {
	label := strings.TrimPrefix(relative, ".")
	label = strings.ReplaceAll(label, "_", " ")
	label = strings.ReplaceAll(label, ".", " / ")
	label = strings.ReplaceAll(label, "/", " / ")
	for strings.Contains(label, "  ") {
		label = strings.ReplaceAll(label, "  ", " ")
	}
	return strings.TrimSpace(label)
}

func scopedSearchQuery(query string, folder SearchFolder) (string, error) {
	query = normalizeQuery(query)
	if folder.Value == "" || folder.Value == "all" {
		return query, nil
	}
	if folder.RelativePath == "" || folder.Value != folder.RelativePath {
		return "", fmt.Errorf("invalid search folder")
	}
	clean := filepath.ToSlash(filepath.Clean(filepath.FromSlash(folder.RelativePath)))
	if clean != folder.RelativePath || clean == "." || strings.HasPrefix(clean, "../") || filepath.IsAbs(filepath.FromSlash(clean)) {
		return "", fmt.Errorf("invalid search folder path")
	}
	return "(" + query + ") and " + scopedPathTerm(clean), nil
}

func scopedPathTerm(relative string) string {
	return "path:" + quoteNotmuchValue(relative+"/**")
}

func quoteNotmuchValue(value string) string {
	value = strings.ReplaceAll(value, `\`, `\\`)
	value = strings.ReplaceAll(value, `"`, `\"`)
	return `"` + value + `"`
}

func parseMessageIDOutput(output string) ([]string, error) {
	if output == "" {
		return nil, nil
	}
	parts := strings.Split(output, "\x00")
	ids := make([]string, 0, len(parts))
	seen := make(map[string]bool)
	for _, part := range parts {
		if part == "" {
			continue
		}
		if !strings.HasPrefix(part, "id:") {
			return nil, fmt.Errorf("unexpected notmuch message output")
		}
		id := strings.TrimPrefix(part, "id:")
		if id == "" || strings.ContainsRune(id, '\x00') {
			return nil, fmt.Errorf("invalid notmuch message id")
		}
		if seen[id] {
			return nil, fmt.Errorf("duplicate message id in ordered search output")
		}
		seen[id] = true
		ids = append(ids, id)
	}
	return ids, nil
}

func selectedDuplicateForFolder(paths []string, folder SearchFolder, mailRoot string) int {
	if folder.RelativePath == "" {
		return 0
	}
	prefix := filepath.Join(mailRoot, filepath.FromSlash(folder.RelativePath)) + string(os.PathSeparator)
	for index, path := range paths {
		clean := filepath.Clean(path)
		if strings.HasPrefix(clean, prefix) {
			return index
		}
	}
	return 0
}

func folderOptionLabel(folder SearchFolder) string {
	if folder.Label == "" {
		folder.Label = "All Mail"
	}
	if folder.ShowCount {
		return folder.Label + " (" + strconv.Itoa(folder.Messages) + ")"
	}
	return folder.Label
}
