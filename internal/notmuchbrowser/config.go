package notmuchbrowser

import (
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	defaultAddr             = "127.0.0.1:8765"
	defaultDatabasePath     = "/mail/SearchIndex/notmuch/default"
	defaultMailRoot         = "/mail/Mailstore"
	defaultMbsyncLock       = "/mail/AppData/isync/provider-live-loop/lock"
	defaultCommandTimeout   = 30 * time.Second
	defaultShowTimeout      = 75 * time.Second
	defaultRefreshTimeout   = 10 * time.Minute
	defaultMaxResults       = 200
	defaultMaxQueryBytes    = 4096
	defaultMaxMessageIDSize = 998
)

// Config contains every tunable for the read-only browser service.
type Config struct {
	Addr                  string
	NotmuchConfig         string
	ExpectedDatabasePath  string
	ExpectedMailRoot      string
	ExpectedSyncFlags     string
	ExpectedIndexDecrypt  string
	MbsyncLockDir         string
	CommandTimeout        time.Duration
	ShowTimeout           time.Duration
	RefreshTimeout        time.Duration
	MaxResults            int
	MaxQueryBytes         int
	MaxMessageIDBytes     int
	SkipStartupSafety     bool
	RequireLocalhostBind  bool
	AllowExternalLoopback bool
}

// DefaultConfig returns conservative defaults for the validated antiX pilot.
func DefaultConfig() Config {
	home, _ := os.UserHomeDir()
	return Config{
		Addr:                 envString("NOTMUCH_BROWSER_ADDR", defaultAddr),
		NotmuchConfig:        envString("NOTMUCH_BROWSER_CONFIG", filepath.Join(home, ".config", "notmuch", "default", "config")),
		ExpectedDatabasePath: envString("NOTMUCH_BROWSER_EXPECTED_DB", defaultDatabasePath),
		ExpectedMailRoot:     envString("NOTMUCH_BROWSER_EXPECTED_MAIL_ROOT", defaultMailRoot),
		ExpectedSyncFlags:    envString("NOTMUCH_BROWSER_EXPECTED_SYNC_FLAGS", "false"),
		ExpectedIndexDecrypt: envString("NOTMUCH_BROWSER_EXPECTED_INDEX_DECRYPT", "false"),
		MbsyncLockDir:        envString("NOTMUCH_BROWSER_MBSYNC_LOCK", defaultMbsyncLock),
		CommandTimeout:       envDuration("NOTMUCH_BROWSER_COMMAND_TIMEOUT_SECONDS", defaultCommandTimeout),
		ShowTimeout:          envDuration("NOTMUCH_BROWSER_SHOW_TIMEOUT_SECONDS", defaultShowTimeout),
		RefreshTimeout:       envDuration("NOTMUCH_BROWSER_REFRESH_TIMEOUT_SECONDS", defaultRefreshTimeout),
		MaxResults:           envInt("NOTMUCH_BROWSER_MAX_RESULTS", defaultMaxResults),
		MaxQueryBytes:        defaultMaxQueryBytes,
		MaxMessageIDBytes:    defaultMaxMessageIDSize,
		RequireLocalhostBind: true,
	}
}

// ParseConfig applies command-line flags over environment/default values.
func ParseConfig(args []string) (Config, error) {
	cfg := DefaultConfig()
	fs := flag.NewFlagSet("notmuch-browser", flag.ContinueOnError)
	fs.StringVar(&cfg.Addr, "addr", cfg.Addr, "listen address; must be localhost unless explicitly overridden")
	fs.StringVar(&cfg.NotmuchConfig, "config", cfg.NotmuchConfig, "notmuch config path")
	fs.StringVar(&cfg.ExpectedDatabasePath, "expected-db", cfg.ExpectedDatabasePath, "required notmuch database.path")
	fs.StringVar(&cfg.ExpectedMailRoot, "expected-mail-root", cfg.ExpectedMailRoot, "required notmuch database.mail_root")
	fs.StringVar(&cfg.MbsyncLockDir, "mbsync-lock", cfg.MbsyncLockDir, "mbsync provider-live lock directory")
	fs.DurationVar(&cfg.CommandTimeout, "command-timeout", cfg.CommandTimeout, "timeout for small notmuch commands")
	fs.DurationVar(&cfg.ShowTimeout, "show-timeout", cfg.ShowTimeout, "timeout for notmuch show commands")
	fs.IntVar(&cfg.MaxResults, "max-results", cfg.MaxResults, "maximum search results per request")
	fs.BoolVar(&cfg.SkipStartupSafety, "skip-startup-safety", cfg.SkipStartupSafety, "skip startup notmuch config safety checks")
	fs.BoolVar(&cfg.AllowExternalLoopback, "allow-non-localhost-bind", cfg.AllowExternalLoopback, "allow binding outside localhost")

	if err := fs.Parse(args); err != nil {
		return Config{}, err
	}
	if cfg.MaxResults < 1 || cfg.MaxResults > 1000 {
		return Config{}, fmt.Errorf("max-results must be between 1 and 1000")
	}
	if cfg.CommandTimeout <= 0 || cfg.ShowTimeout <= 0 {
		return Config{}, fmt.Errorf("timeouts must be positive")
	}
	if err := cfg.ValidateBind(); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func (cfg Config) ValidateBind() error {
	host, _, err := net.SplitHostPort(cfg.Addr)
	if err != nil {
		return fmt.Errorf("invalid listen address %q: %w", cfg.Addr, err)
	}
	if !cfg.RequireLocalhostBind || cfg.AllowExternalLoopback {
		return nil
	}
	ip := net.ParseIP(host)
	if host == "localhost" || ip != nil && ip.IsLoopback() {
		return nil
	}
	return fmt.Errorf("refusing non-localhost bind %q; use SSH tunnel to reach antiX from Win11", cfg.Addr)
}

func (cfg Config) ValidateQuery(q string) error {
	if strings.TrimSpace(q) == "" {
		return errors.New("query is empty")
	}
	if strings.ContainsRune(q, '\x00') {
		return errors.New("query contains NUL")
	}
	if len(q) > cfg.MaxQueryBytes {
		return fmt.Errorf("query exceeds %d bytes", cfg.MaxQueryBytes)
	}
	return nil
}

func (cfg Config) ValidateMessageID(id string) error {
	if strings.TrimSpace(id) == "" {
		return errors.New("message id is empty")
	}
	if strings.ContainsRune(id, '\x00') {
		return errors.New("message id contains NUL")
	}
	if len(id) > cfg.MaxMessageIDBytes {
		return fmt.Errorf("message id exceeds %d bytes", cfg.MaxMessageIDBytes)
	}
	return nil
}

func envString(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func envInt(key string, fallback int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	value, err := strconv.Atoi(raw)
	if err != nil {
		return fallback
	}
	return value
}

func envDuration(key string, fallback time.Duration) time.Duration {
	seconds := envInt(key, 0)
	if seconds <= 0 {
		return fallback
	}
	return time.Duration(seconds) * time.Second
}
