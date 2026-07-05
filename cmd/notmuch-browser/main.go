package main

import (
	"fmt"
	"os"

	"antix-vm-laptop/internal/notmuchbrowser"
)

func main() {
	if err := notmuchbrowser.Main(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "notmuch-browser: %v\n", err)
		os.Exit(1)
	}
}
