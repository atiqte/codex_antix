package notmuchbrowser

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestSearchFolderCatalogIncludesApprovedEmptySourceAndNonemptySubfolder(t *testing.T) {
	root := t.TempDir()
	local := filepath.Join(root, "evolution", "local-maildir")
	inbox := filepath.Join(local, ".Account.Inbox")
	for _, path := range []string{
		filepath.Join(local, "cur"),
		filepath.Join(local, "new"),
		filepath.Join(local, "tmp"),
		filepath.Join(inbox, "cur"),
		filepath.Join(inbox, "new"),
		filepath.Join(inbox, "tmp"),
		filepath.Join(root, "evolution", "provider-live-archive"),
	} {
		if err := os.MkdirAll(path, 0o700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(inbox, "cur", "message:2,S"), []byte("mail"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(inbox, filepath.Join(local, ".unsafe-link")); err != nil {
		t.Fatal(err)
	}

	cfg := testConfig()
	cfg.ExpectedMailRoot = root
	runner := &fakeRunner{outputs: map[string]string{
		"count\x00*": "1\n",
		"count\x00path:\"evolution/local-maildir/**\"":         "1\n",
		"count\x00path:\"evolution/provider-live-archive/**\"": "0\n",
	}, errs: map[string]error{}}
	client := NotmuchClient{Config: cfg, Runner: runner}
	catalog, err := client.SearchFolderCatalog(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if catalog.All.Messages != 1 {
		t.Fatalf("all count=%d", catalog.All.Messages)
	}
	if len(catalog.Groups) != 2 {
		t.Fatalf("groups=%#v", catalog.Groups)
	}
	localScope, ok := catalog.Resolve("evolution/local-maildir/.Account.Inbox")
	if !ok || localScope.Label != "Account / Inbox" {
		t.Fatalf("local subfolder=%#v ok=%v", localScope, ok)
	}
	archive, ok := catalog.Resolve("evolution/provider-live-archive")
	if !ok || archive.Messages != 0 || !archive.ShowCount {
		t.Fatalf("empty archive=%#v ok=%v", archive, ok)
	}
	if _, ok := catalog.Resolve("../private"); ok {
		t.Fatal("traversal scope resolved")
	}
	for _, group := range catalog.Groups {
		for _, option := range group.Options {
			if strings.Contains(option.Value, "unsafe-link") {
				t.Fatalf("symlink appeared in catalog: %#v", option)
			}
		}
	}
}

func TestSearchUsesStrictMessageOrderAndSelectedFolderDuplicate(t *testing.T) {
	cfg := testConfig()
	cfg.ExpectedMailRoot = "/mail/Mailstore"
	folder := SearchFolder{
		Value:        "evolution/local-maildir",
		Label:        "All folders",
		RelativePath: "evolution/local-maildir",
	}
	scoped := `(tag:inbox) and path:"evolution/local-maildir/**"`
	metadataQuery := `(id:"new@example.test" or id:"old@example.test")`
	metadata := `[
	  [[{"id":"old@example.test","timestamp":100,"filename":["/mail/Mailstore/mbsync/provider-live/cur/old","/mail/Mailstore/evolution/local-maildir/.Archive/cur/old"],"tags":["inbox"],"match":true,"headers":{"Subject":"Old","From":"Old","Date":"Thu, 01 Jan 1970 12:01:40 AM +0000"}}]],
	  [[{"id":"new@example.test","timestamp":200,"filename":["/mail/Mailstore/evolution/local-maildir/.Inbox/cur/new"],"tags":["historical-archive"],"match":true,"headers":{"Subject":"New","From":"New","Date":"Thu, 01 Jan 1970 12:03:20 AM +0000"}}]]
	]`
	runner := &fakeRunner{outputs: map[string]string{
		"count\x00" + scoped:                   "2\n",
		"count\x00--output=files\x00" + scoped: "3\n",
		"search\x00--format=text0\x00--output=messages\x00--sort=newest-first\x00--offset=0\x00--limit=50\x00" + scoped: "id:new@example.test\x00id:old@example.test\x00",
		"show\x00--format=json\x00--entire-thread=false\x00--body=false\x00--sort=newest-first\x00" + metadataQuery:     metadata,
	}, errs: map[string]error{}}
	client := NotmuchClient{Config: cfg, Runner: runner}
	page, err := client.Search(context.Background(), "tag:inbox", folder, 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Results) != 2 || page.Results[0].ID != "new@example.test" || page.Results[1].ID != "old@example.test" {
		t.Fatalf("ordered results=%#v", page.Results)
	}
	if page.Results[0].SelectedDup != 0 || page.Results[1].SelectedDup != 1 {
		t.Fatalf("selected duplicates=%d,%d", page.Results[0].SelectedDup, page.Results[1].SelectedDup)
	}
	if page.Results[0].Timestamp < page.Results[1].Timestamp {
		t.Fatalf("timestamps are not newest first: %#v", page.Results)
	}
}

func TestResultDateBoundaries(t *testing.T) {
	location := time.FixedZone("Asia/Dhaka", 6*60*60)
	previous := time.Local
	time.Local = location
	t.Cleanup(func() { time.Local = previous })
	now := time.Date(2026, 7, 26, 12, 0, 0, 0, location)
	tests := []struct {
		age  time.Duration
		want string
	}{
		{age: 0, want: "Now"},
		{age: 59 * time.Second, want: "Now"},
		{age: time.Minute, want: "1 min ago"},
		{age: 5*time.Minute + 59*time.Second, want: "5 min ago"},
		{age: 59*time.Minute + 59*time.Second, want: "59 min ago"},
		{age: time.Hour, want: "1 hour ago"},
		{age: 119*time.Minute + 59*time.Second, want: "1 hour ago"},
		{age: 2 * time.Hour, want: "Today 10:00:00 AM"},
	}
	for _, test := range tests {
		if got := formatResultDate(now.Add(-test.age).Unix(), "", now); got != test.want {
			t.Fatalf("age=%s got=%q want=%q", test.age, got, test.want)
		}
	}
}
