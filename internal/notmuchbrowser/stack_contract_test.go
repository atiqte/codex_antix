package notmuchbrowser

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPinnedFrontendRuntimeContract(t *testing.T) {
	htmx, err := staticFiles.ReadFile("static/htmx.min.js")
	if err != nil {
		t.Fatalf("read embedded HTMX: %v", err)
	}
	if !strings.Contains(string(htmx), `version:"2.0.10"`) {
		t.Fatal("embedded HTMX is not the approved 2.0.10 release")
	}

	packageJSON, err := os.ReadFile(filepath.Join("..", "..", "package.json"))
	if err != nil {
		t.Fatalf("read package.json: %v", err)
	}
	for _, pin := range []string{
		`"tailwindcss": "4.3.3"`,
		`"@tailwindcss/cli": "4.3.3"`,
	} {
		if !strings.Contains(string(packageJSON), pin) {
			t.Fatalf("package.json is missing exact pin %s", pin)
		}
	}
}

func TestUserRunitHelperSafetyContract(t *testing.T) {
	script, err := os.ReadFile(filepath.Join("..", "..", "scripts", "notmuch_browser_runit_setup.sh"))
	if err != nil {
		t.Fatalf("read user runit helper: %v", err)
	}
	source := string(script)
	for _, want := range []string{
		`"$HOME/.runit/usersv"`,
		`"$HOME/.runit/service"`,
		`user-runit-rollback-current`,
		`mail_mutation`,
		`rollback_activation`,
	} {
		if !strings.Contains(source, want) {
			t.Fatalf("user runit helper is missing safety contract %q", want)
		}
	}
	for _, forbidden := range []string{
		`USER_SERVICE_ROOT="/etc`,
		`ACTIVE_SERVICE_ROOT="/etc`,
		"rm -rf",
		"kill -9",
	} {
		if strings.Contains(source, forbidden) {
			t.Fatalf("user runit helper contains forbidden operation %q", forbidden)
		}
	}
}
