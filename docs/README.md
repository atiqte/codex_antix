# Documentation Index

This folder contains project memory and operational guides for the approved
Betterbird mail migration utilities.

## Start Here

- `PROJECT_STATE.md`: current repository state and next actions.
- `TODO.md`: active work checklist.
- `DECISIONS.md`: accepted project and workflow decisions.
- `WORKFLOW.md`: Git and session workflow.
- `CHANGELOG.md`: meaningful repository changes.

## Betterbird Mail Migration Guides

- `BETTERBIRD_PROFILE_TRANSPORT_GUIDE.html`: offline browser guide with copy buttons for the Fedora-to-antiX profile transport and post-restore conversion flow.
- `BETTERBIRD_PROFILE_TRANSPORT_GUIDE.txt`: terminal-friendly plain text version of the same guide.
- `MAILDIRPP_ARCHIVE_TRANSPORT_GUIDE.html`: offline browser guide with copy buttons for transporting the already-converted Fedora Maildir++ archive to antiX.
- `MAILDIRPP_ARCHIVE_TRANSPORT_GUIDE.txt`: terminal-friendly plain text version of the converted Maildir++ archive transport guide.
- `EVOLUTION_FLATPAK_ANTIX_GUIDE.html`: offline browser guide with copy buttons for installing and validating Evolution Flatpak 3.60.2 on antiX runit/IceWM.
- `EVOLUTION_FLATPAK_ANTIX_GUIDE.txt`: terminal-friendly plain text version of the Evolution Flatpak guide.
- `MBSYNC_ANTIX_GUIDE.html`: offline browser guide with copy buttons for the first deletion-safe mbsync INBOX test on antiX.
- `MBSYNC_ANTIX_GUIDE.txt`: terminal-friendly plain text version of the mbsync antiX guide.

## antiX Desktop Helpers

- `../scripts/evolution_flatpak_icewm_launcher_setup.sh`: user-level helper for adding Evolution Flatpak to the IceWM Personal menu and taskbar toolbar while starting `gnome-keyring-daemon` at login.
- `../scripts/mbsync_provider_inbox_setup.sh`: antiX helper for installing isync/mbsync, creating the isolated `/mail` test layout, writing a pull-only INBOX config, dry-running, and pulling once.

For transport commands, `--manifest` always points to `manifest.json`.
`inventory.jsonl` must stay beside it and is read automatically by the
transport script.
