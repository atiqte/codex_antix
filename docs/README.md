# Documentation Index

This folder contains project memory and operational guides for the approved
mail migration utilities and read-only Go notmuch browser.

## Start Here

- `PROJECT_STATE.md`: current repository state and next actions.
- `TODO.md`: active work checklist.
- `DECISIONS.md`: accepted project and workflow decisions.
- `WORKFLOW.md`: Git and session workflow.
- `CHANGELOG.md`: meaningful repository changes.

## Betterbird Mail Migration Guides

- `BETTERBIRD_PROFILE_TRANSPORT_GUIDE.html`: offline browser guide with copy buttons for the Fedora-to-antiX profile transport and post-restore conversion flow.
- `BETTERBIRD_PROFILE_TRANSPORT_GUIDE.txt`: terminal-friendly plain text version of the same guide.
- `MAILDIRPP_ARCHIVE_TRANSPORT_GUIDE.html`: offline browser guide with copy buttons for transporting the already-converted Fedora Maildir++ archive to antiX, including the verified USB and Win11 host-share transfer workflow.
- `MAILDIRPP_ARCHIVE_TRANSPORT_GUIDE.txt`: terminal-friendly plain text version of the converted Maildir++ archive transport, USB transfer, and Win11 host-share copy guide.
- `EVOLUTION_FLATPAK_ANTIX_GUIDE.html`: offline browser guide with copy buttons for installing and validating Evolution Flatpak 3.60.2 on antiX runit/IceWM.
- `EVOLUTION_FLATPAK_ANTIX_GUIDE.txt`: terminal-friendly plain text version of the Evolution Flatpak guide.
- `MBSYNC_ANTIX_GUIDE.html`: offline browser guide with copy buttons for the first deletion-safe mbsync INBOX test on antiX.
- `MBSYNC_ANTIX_GUIDE.txt`: terminal-friendly plain text version of the mbsync antiX guide.
- `NOTMUCH_GO_BROWSER_SERVICE_GUIDE.html` and `.txt`: the final validated templ/HTMX/Tailwind/chi and repaired per-user-runit production reconstruction guide, including exact source/artifact hashes, rollback, strict non-mutation, resource, Windows tunnel, restart, and reboot evidence.

## antiX Desktop Helpers

- `../scripts/evolution_flatpak_icewm_launcher_setup.sh`: user-level helper for adding Evolution Flatpak to the IceWM Personal menu and taskbar toolbar while starting `gnome-keyring-daemon` at login.
- `../scripts/mbsync_provider_inbox_setup.sh`: antiX helper for installing isync/mbsync, creating the isolated `/mail` test layout, writing a pull-only INBOX config, dry-running, and pulling once.
- `../scripts/notmuch_browser_build.sh`: pinned Bun/Go preparation, templ/Tailwind generation, verification, tests, and stripped browser build.
- `../scripts/notmuch_browser_runit_setup.sh`: fail-closed staging, activation, validation, and rollback for only the existing per-user runit tree.
- `../scripts/generate_notmuch_browser_service_guide.py`: standard-library generator for the matching offline HTML and terminal-friendly text reconstruction guides.

For transport commands, `--manifest` always points to `manifest.json`.
`inventory.jsonl` must stay beside it and is read automatically by the
transport script.
