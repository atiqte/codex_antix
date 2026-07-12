package notmuchbrowser

import (
	"context"
	"net"
	"net/http"
	"os"
	"testing"
	"time"
)

func TestVisualPreviewServer(t *testing.T) {
	if os.Getenv("NOTMUCH_BROWSER_VISUAL_PREVIEW") != "1" {
		t.Skip("set NOTMUCH_BROWSER_VISUAL_PREVIEW=1 for the localhost visual fixture")
	}
	listener, err := net.Listen("tcp", "127.0.0.1:8876")
	if err != nil {
		t.Fatalf("listen for visual fixture: %v", err)
	}
	server := &http.Server{
		Handler:           newHTTPTestServer(t),
		ReadHeaderTimeout: 5 * time.Second,
	}
	done := make(chan error, 1)
	go func() {
		done <- server.Serve(listener)
	}()
	t.Log("visual fixture: http://127.0.0.1:8876/")

	timer := time.NewTimer(3 * time.Minute)
	defer timer.Stop()
	select {
	case err := <-done:
		if err != nil && err != http.ErrServerClosed {
			t.Fatalf("visual fixture failed: %v", err)
		}
	case <-timer.C:
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(ctx)
	}
}
