#!/usr/bin/env python3
"""Generate the matching offline HTML and plain-text notmuch browser guides."""

from __future__ import annotations

import html
from pathlib import Path
from textwrap import dedent


ROOT = Path(__file__).resolve().parents[1]
HTML_PATH = ROOT / "docs" / "NOTMUCH_GO_BROWSER_SERVICE_GUIDE.html"
TEXT_PATH = ROOT / "docs" / "NOTMUCH_GO_BROWSER_SERVICE_GUIDE.txt"


def clean(value: str) -> str:
    return dedent(value).strip()


SECTIONS = [
    {
        "title": "1. Scope, architecture, and safety",
        "body": clean(
            """
            This guide reconstructs the production service accepted on 2026-07-25:
            a Go 1.25+ application using chi v5.3.1, templ v0.3.1020, local HTMX
            2.0.10, and Tailwind CSS 4.3.3 compiled by Bun 1.3.14. Production is
            one stripped Go binary with embedded assets. It needs no Bun, Node,
            npm, templ CLI, Tailwind process, CDN, Alpine, or remote image proxy.

            The HTTP listener is 127.0.0.1:8765. Windows reaches it through an SSH
            local-forward. Browser routes search and view mail and provide
            capability-gated decoded attachment, ZIP, and inline-image responses.
            They never edit Maildir files, notmuch tags, or the notmuch database.
            Evolution remains the application for reply, forward, compose, send,
            tag changes, and mail deletion.

            Routes are GET /, /search, /message, /attachment, /attachments.zip,
            /inline-image, /status, /healthz, and /static/*. POST is rejected.
            Process-lifetime HMAC capabilities bind export purpose, Message-ID,
            selected duplicate, MIME part, filename, and media type. Restarting
            invalidates old capabilities. HTML stays in a sandboxed iframe.
            Embedded and remote images require separate confirmations, and the Go
            service never fetches remote images.

            Default limits are two inline-image operations, one attachment/ZIP
            operation, 64 MiB per inline image, 512 MiB per attachment, 200 ZIP
            entries, 2 GiB decoded ZIP output, two-minute inline timeout, and
            fifteen-minute attachment/ZIP timeout. Temporary files live under
            /mail/AppData/notmuch-browser/download-tmp with private modes and are
            removed after success or failure.
            """
        ),
    },
    {
        "title": "2. Exact validated artifacts and provenance",
        "body": clean(
            """
            Browser build provenance:

            - Clean-build source commit: e6876f2e9a39bb2ad03573af0d615ffbd9e19c24
            - Validated clean-build tar: 2,232,320 bytes, 110 members
            - Clean-build tar SHA256: 4d0b6d9c9e88ad1fab61ffcc2d0ef152c993e67b729f8150c552bed8298347cd
            - Build manifest SHA256: 57d6e3609d426e269550b391411447e666eb7339454c5df6b62cc3c098750d6a
            - Build report SHA256: 7f13bd3d6621237e39f5e6a6afbaee60bfd11dfece845aa0f4188d5c0eb6554c
            - Candidate pointer SHA256: 47a65fdbca38170937f4a18810b9a8eb5644d2dcfdf6ee6dfe05270ca9daf4ad

            Use post-fix source commit a1728127940f0824fb91d3dd97abe636be47690e
            for reconstruction. It contains the identical browser source plus the
            validated antiX session-race repair. A deterministic git archive of
            that commit, with prefix source/, is 2,334,720 bytes, has 114 members,
            and has SHA256
            5e58f63b9ef3eca0b1e8fc2b8b9013f1985aeaae7817424848ae1ed5ccd361a1.

            Installed production artifacts:

            - notmuch-browser: 8,093,961 bytes; SHA256 c7d14e0ee792595cd168a131cb05307214ae1129dc449f982fa48d30aa5bfed9
            - notmuch-browser-control: 10,502 bytes; SHA256 4b8231a2c886dfb1247d4dfa6b3de043e67d230e4fad1bc202b7452936ca04a8
            - notmuch-browser-index-control: 8,620 bytes; SHA256 1ddf93c9c5f9943bcc9b4f744f3e835e6c12f0df83a8a467ac061d2b38f6b007
            - notmuch-browser-runit-setup: 20,308 bytes; SHA256 598762b0f98147460cff3e937b69a47b7aa531e9e4e80807c4f75e540fdc0c77

            Embedded static files include app.css 23,983 bytes, app.js 7,070
            bytes, and htmx.min.js 51,238 bytes. Those three total 82,291 bytes;
            all embedded static files including licenses/icons total 86,332 bytes,
            below the 90 KiB build gate.

            Production paths are ~/.local/bin/notmuch-browser{,-control,
            -index-control,-runit-setup}, ~/.config/notmuch/default/config,
            /mail/SearchIndex/notmuch/default, /mail/Mailstore,
            /mail/AppData/notmuch-browser, /mail/Logs/notmuch-browser, and
            ~/.runit/usersv plus ~/.runit/service.
            """
        ),
    },
    {
        "title": "3. Prerequisites and reconstruction contract",
        "body": clean(
            """
            The target must be antiX with /mail mounted, Go 1.25 or newer
            (validated with Go 1.26.4), notmuch, curl, sha256sum, tar, install,
            runit sv/svlogd, an existing per-user runsvdir supervising
            ~/.runit/service, and an IceWM startup file. Build regeneration also
            needs Bun exactly 1.3.14. package.json and bun.lock pin Tailwind and
            @tailwindcss/cli 4.3.3; go.mod/go.sum pin templ, chi, and x/net.

            Do not create or edit /etc/service. Do not replace
            /etc/user_session.d/runit-user-session.sh. The helper manages only
            ~/.runit/usersv/notmuch-browser, ~/.runit/usersv/notmuch-browser-index,
            and their two links under ~/.runit/service. IceWM runs only the
            bounded session reconciler after login; it does not directly supervise
            either application process.

            Generated templ Go and compiled CSS are committed. A production-only
            machine can install the already verified binary and scripts without
            Bun or templ. Building from source intentionally runs frozen dependency
            preparation and must be done only on a machine where those build
            dependencies are approved.
            """
        ),
    },
    {
        "title": "4. Windows: obtain, verify, and transfer exact post-fix source",
        "body": clean(
            """
            Run from Windows PowerShell. This creates the same deterministic
            uncompressed tar measured above. Replace the antiX address if DHCP
            assigned another address. If Git network access is unavailable, obtain
            the repository through a trusted existing copy, then run the same
            checkout/archive/hash checks before transfer.
            """
        ),
        "label": "Copy Windows source transfer",
        "language": "powershell",
        "code": clean(
            r"""
            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Stop'
            $Commit = 'a1728127940f0824fb91d3dd97abe636be47690e'
            $Expected = '5E58F63B9EF3ECA0B1E8FC2B8B9013F1985AEAAE7817424848AE1ED5CCD361A1'
            $Repo = Join-Path $PWD 'codex_antix-guide-source'
            $Archive = Join-Path $PWD 'notmuch-browser-source-a172812.tar'

            git clone https://github.com/atiqte/codex_antix.git $Repo
            git -C $Repo checkout --detach $Commit
            if ((git -C $Repo rev-parse HEAD) -ne $Commit) { throw 'Wrong commit' }
            if (git -C $Repo status --porcelain) { throw 'Source tree is dirty' }
            git -C $Repo archive --format=tar --prefix=source/ -o $Archive $Commit

            $Item = Get-Item -LiteralPath $Archive
            $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash
            $Members = @(tar -tf $Archive)
            if ($Item.Length -ne 2334720) { throw "Wrong size: $($Item.Length)" }
            if ($Hash -ne $Expected) { throw "Wrong SHA256: $Hash" }
            if ($Members.Count -ne 114) { throw "Wrong member count: $($Members.Count)" }
            if (@($Members | Sort-Object -Unique).Count -ne 114) { throw 'Duplicate member' }

            Test-NetConnection 192.168.254.128 -Port 22
            scp $Archive atiq@192.168.254.128:/home/atiq/
            """
        ),
    },
    {
        "title": "5. antiX: fail-closed prerequisite and safety audit",
        "body": clean(
            """
            Run before extracting, building, backing up, or stopping anything.
            This is read-only. It checks the exact source object, build tools,
            notmuch safety configuration, per-user runit, listener posture, locks,
            and Maildir/download temporary state.
            """
        ),
        "label": "Copy antiX preflight",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            ARCHIVE="$HOME/notmuch-browser-source-a172812.tar"
            CONFIG="$HOME/.config/notmuch/default/config"
            USER_SERVICE="$HOME/.runit/service"

            test -f "$ARCHIVE"
            printf '%s  %s\n' \
              '5e58f63b9ef3eca0b1e8fc2b8b9013f1985aeaae7817424848ae1ed5ccd361a1' \
              "$ARCHIVE" | sha256sum -c -
            test "$(wc -c < "$ARCHIVE" | tr -d ' ')" = 2334720
            test "$(tar -tf "$ARCHIVE" | wc -l | tr -d ' ')" = 114
            test "$(tar -tf "$ARCHIVE" | sort -u | wc -l | tr -d ' ')" = 114
            tar -tf "$ARCHIVE" | awk '
              /^\// || /(^|\/)\.\.($|\/)/ { bad=1 }
              END { exit bad ? 1 : 0 }
            '

            test -r "$CONFIG"
            test "$(notmuch --config="$CONFIG" config get database.path)" = \
              /mail/SearchIndex/notmuch/default
            test "$(notmuch --config="$CONFIG" config get database.mail_root)" = \
              /mail/Mailstore
            test "$(notmuch --config="$CONFIG" config get maildir.synchronize_flags)" = false
            test "$(notmuch --config="$CONFIG" config get index.decrypt)" = false
            awk '$2 == "/mail" { found=1 } END { exit(found ? 0 : 1) }' /proc/mounts

            command -v go
            go version
            test "$(bun --version)" = 1.3.14
            command -v curl
            command -v sv
            command -v svlogd
            test -d "$HOME/.runit/usersv"
            test -d "$USER_SERVICE"
            pgrep -u "$(id -u)" -f "runsvdir -P $USER_SERVICE"
            test -f "$HOME/.icewm/startup"

            test ! -d /mail/AppData/isync/provider-live-loop/lock
            test ! -d /mail/AppData/notmuch-browser/index-refresh.lock
            find /mail/Mailstore -type f -path '*/tmp/*' -print -quit |
              grep -q . && { echo 'Maildir tmp is not empty'; exit 1; } || true
            find /mail/AppData/notmuch-browser/download-tmp -maxdepth 1 \
              -type f -name 'nmb-*' -print -quit 2>/dev/null |
              grep -q . && { echo 'download temp is not empty'; exit 1; } || true

            ss -ltnp | grep '127.0.0.1:8765' || true
            curl -fsS --max-time 15 http://127.0.0.1:8765/healthz || true
            echo status=preflight_complete
            """
        ),
    },
    {
        "title": "6. antiX: extract and reproduce the build",
        "body": clean(
            """
            Extract into a new empty directory. The all target performs frozen Bun
            preparation, Go module download/verification, templ and Tailwind
            generation twice for reproducibility, Go tests/vet/race, shell syntax,
            the full Python suite, asset budget, and stripped build. The validated
            suite at the repaired source had 49 Python tests. Production remains
            untouched because output is written inside the staging directory.
            """
        ),
        "label": "Copy source build",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            ARCHIVE="$HOME/notmuch-browser-source-a172812.tar"
            WORK="$HOME/notmuch-browser-rebuild-a172812"
            test ! -e "$WORK"
            install -d -m 700 "$WORK"
            tar -xf "$ARCHIVE" -C "$WORK"
            cd "$WORK/source"

            scripts/notmuch_browser_build.sh all

            test "$(wc -c < notmuch-browser | tr -d ' ')" = 8093961
            printf '%s  %s\n' \
              'c7d14e0ee792595cd168a131cb05307214ae1129dc449f982fa48d30aa5bfed9' \
              notmuch-browser | sha256sum -c -
            printf '%s\n' \
              '4b8231a2c886dfb1247d4dfa6b3de043e67d230e4fad1bc202b7452936ca04a8  scripts/notmuch_browser_control.sh' \
              '1ddf93c9c5f9943bcc9b4f744f3e835e6c12f0df83a8a467ac061d2b38f6b007  scripts/notmuch_browser_index_control.sh' \
              '598762b0f98147460cff3e937b69a47b7aa531e9e4e80807c4f75e540fdc0c77  scripts/notmuch_browser_runit_setup.sh' |
              sha256sum -c -
            test "$(find internal/notmuchbrowser/static -maxdepth 1 -type f \
              -exec wc -c {} + | awk 'END { print $1 }')" = 86332
            echo status=build_reproduced
            """
        ),
    },
    {
        "title": "7. Back up the prior installation before replacement",
        "body": clean(
            """
            On an upgrade, preserve the currently installed browser, controls,
            config, and IceWM startup before replacing files. The validated
            production rollout retained a preinstall pointer under
            /mail/AppData/notmuch-browser and a backup containing
            backup-inventory.sha256 plus rollback-browser.sh. Those are the
            validated names; do not substitute rollback.sh or SHA256SUMS.

            The following creates a private inventory backup. If this is a genuinely
            fresh VM, absent application files are recorded as absent. Keep this
            backup until the new service passes GUI, read-only, restart, and reboot
            checks. Its executable rollback-browser.sh verifies the exact backup
            and pointer, rolls back supervision first when active, stops the direct
            replacement, restores or removes only the four inventoried application
            paths, restores config/startup, and restarts only a retained prior
            browser/control pair. Review its resolved backup target before use.
            """
        ),
        "label": "Copy preinstall backup",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            RUN_ID="$(date +%Y%m%d-%H%M%S)"
            BACKUP="/mail/Backups/notmuch-browser/${RUN_ID}-before-templ-runit"
            POINTER="/mail/AppData/notmuch-browser/templ-runit-preinstall-rollback-current"
            test ! -e "$BACKUP"
            install -d -m 700 "$BACKUP"
            install -d -m 700 /mail/AppData/notmuch-browser

            for name in notmuch-browser notmuch-browser-control \
              notmuch-browser-index-control notmuch-browser-runit-setup; do
              if [ -e "$HOME/.local/bin/$name" ]; then
                cp -p "$HOME/.local/bin/$name" "$BACKUP/$name"
              else
                printf '%s\n' "$name" >> "$BACKUP/absent-before.txt"
              fi
            done
            cp -p "$HOME/.config/notmuch/default/config" "$BACKUP/notmuch-config"
            cp -p "$HOME/.icewm/startup" "$BACKUP/icewm-startup"

            cat > "$BACKUP/rollback-browser.sh" <<'ROLLBACK'
            #!/bin/sh
            set -eu
            BACKUP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
            PREINSTALL_POINTER=/mail/AppData/notmuch-browser/templ-runit-preinstall-rollback-current
            RUNIT_POINTER=/mail/AppData/notmuch-browser/user-runit-rollback-current
            BIN_DIR="$HOME/.local/bin"

            test -s "$PREINSTALL_POINTER"
            test "$(sed -n '1p' "$PREINSTALL_POINTER")" = "$BACKUP_DIR"
            case "$BACKUP_DIR" in
              /mail/Backups/notmuch-browser/*) ;;
              *) echo 'Refusing backup outside approved root' >&2; exit 1 ;;
            esac
            (cd "$BACKUP_DIR" && sha256sum -c backup-inventory.sha256)

            if [ -s "$RUNIT_POINTER" ]; then
              test -x "$BIN_DIR/notmuch-browser-runit-setup"
              "$BIN_DIR/notmuch-browser-runit-setup" rollback
            elif [ -L "$HOME/.runit/service/notmuch-browser" ] ||
                 [ -L "$HOME/.runit/service/notmuch-browser-index" ]; then
              echo 'Refusing active runit links without rollback pointer' >&2
              exit 1
            fi

            if [ -x "$BIN_DIR/notmuch-browser-index-control" ]; then
              "$BIN_DIR/notmuch-browser-index-control" stop || true
            fi
            if [ -x "$BIN_DIR/notmuch-browser-control" ]; then
              "$BIN_DIR/notmuch-browser-control" stop || true
            fi

            restore_or_remove() {
              name=$1
              mode=$2
              target="$BIN_DIR/$name"
              if [ -f "$BACKUP_DIR/$name" ]; then
                install -m "$mode" "$BACKUP_DIR/$name" "$target"
              elif [ -f "$BACKUP_DIR/absent-before.txt" ] &&
                   grep -Fxq "$name" "$BACKUP_DIR/absent-before.txt"; then
                [ ! -e "$target" ] || unlink "$target"
              else
                echo "Missing inventory decision for $name" >&2
                exit 1
              fi
            }

            restore_or_remove notmuch-browser 755
            restore_or_remove notmuch-browser-control 700
            restore_or_remove notmuch-browser-index-control 700
            restore_or_remove notmuch-browser-runit-setup 700
            cp -p "$BACKUP_DIR/notmuch-config" \
              "$HOME/.config/notmuch/default/config"
            cp -p "$BACKUP_DIR/icewm-startup" "$HOME/.icewm/startup"

            if [ -x "$BIN_DIR/notmuch-browser" ] &&
               [ -x "$BIN_DIR/notmuch-browser-control" ]; then
              "$BIN_DIR/notmuch-browser-control" start
            fi
            if [ -x "$BIN_DIR/notmuch-browser-index-control" ]; then
              "$BIN_DIR/notmuch-browser-index-control" start
            fi
            echo status=preinstall_artifacts_restored
            ROLLBACK
            chmod 700 "$BACKUP/rollback-browser.sh"
            sh -n "$BACKUP/rollback-browser.sh"
            (
              cd "$BACKUP"
              find . -maxdepth 1 -type f \
                ! -name backup-inventory.sha256 -printf '%P\0' |
                sort -z | xargs -0 sha256sum > backup-inventory.sha256
            )
            chmod 600 "$BACKUP"/*
            chmod 700 "$BACKUP/rollback-browser.sh"
            printf '%s\n' "$BACKUP" > "$POINTER"
            chmod 600 "$POINTER"
            (cd "$BACKUP" && sha256sum -c backup-inventory.sha256)
            echo "rollback_backup=$BACKUP"
            """
        ),
    },
    {
        "title": "8. Install artifacts, stage disabled runit services, and activate",
        "body": clean(
            """
            Pause the provider-live loop before an upgrade if its control reports
            active synchronization; wait for its lock to disappear. The block below
            installs exact files atomically enough for a user-local reconstruction,
            stages both definitions with down markers, inspects them, and activates.
            Activation creates its own checksummed supervision rollback backup,
            stops the legacy direct processes, attaches runsv, validates health,
            removes only the two legacy direct IceWM blocks, and installs one
            session-reconciliation block.

            Do not run stage if unmanaged definitions or active links already occupy
            the target names. Inspect and resolve that ownership question first.
            """
        ),
        "label": "Copy install and runit activation",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            SOURCE="$HOME/notmuch-browser-rebuild-a172812/source"
            install -d -m 700 "$HOME/.local/bin"
            install -m 755 "$SOURCE/notmuch-browser" \
              "$HOME/.local/bin/notmuch-browser"
            install -m 700 "$SOURCE/scripts/notmuch_browser_control.sh" \
              "$HOME/.local/bin/notmuch-browser-control"
            install -m 700 "$SOURCE/scripts/notmuch_browser_index_control.sh" \
              "$HOME/.local/bin/notmuch-browser-index-control"
            install -m 700 "$SOURCE/scripts/notmuch_browser_runit_setup.sh" \
              "$HOME/.local/bin/notmuch-browser-runit-setup"

            printf '%s\n' \
              'c7d14e0ee792595cd168a131cb05307214ae1129dc449f982fa48d30aa5bfed9  '"$HOME"'/.local/bin/notmuch-browser' \
              '4b8231a2c886dfb1247d4dfa6b3de043e67d230e4fad1bc202b7452936ca04a8  '"$HOME"'/.local/bin/notmuch-browser-control' \
              '1ddf93c9c5f9943bcc9b4f744f3e835e6c12f0df83a8a467ac061d2b38f6b007  '"$HOME"'/.local/bin/notmuch-browser-index-control' \
              '598762b0f98147460cff3e937b69a47b7aa531e9e4e80807c4f75e540fdc0c77  '"$HOME"'/.local/bin/notmuch-browser-runit-setup' |
              sha256sum -c -
            sh -n "$HOME/.local/bin/notmuch-browser-control"
            sh -n "$HOME/.local/bin/notmuch-browser-index-control"
            sh -n "$HOME/.local/bin/notmuch-browser-runit-setup"

            "$HOME/.local/bin/notmuch-browser-runit-setup" inspect
            "$HOME/.local/bin/notmuch-browser-runit-setup" stage
            "$HOME/.local/bin/notmuch-browser-runit-setup" inspect
            "$HOME/.local/bin/notmuch-browser-runit-setup" activate
            echo status=templ_runit_activated
            """
        ),
    },
    {
        "title": "9. Runtime, listener, route, and reconciliation validation",
        "body": clean(
            """
            The health response must contain ok=true, read_only=true, and
            mail_mutation=false. The listener must be loopback-only. Exactly one
            reconciliation marker pair and zero legacy direct browser/index marker
            pairs must remain. The helper requires both services continuously
            healthy for 60 seconds within a bounded 180-second window after login.
            """
        ),
        "label": "Copy runtime validation",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            "$HOME/.local/bin/notmuch-browser-runit-setup" validate
            "$HOME/.local/bin/notmuch-browser-control" status
            "$HOME/.local/bin/notmuch-browser-index-control" status
            sv status "$HOME/.runit/service/notmuch-browser"
            sv status "$HOME/.runit/service/notmuch-browser-index"

            HEALTH="$(curl -fsS --max-time 15 http://127.0.0.1:8765/healthz)"
            printf '%s\n' "$HEALTH" | grep -F '"ok":true'
            printf '%s\n' "$HEALTH" | grep -F '"read_only":true'
            printf '%s\n' "$HEALTH" | grep -F '"mail_mutation":false'
            test "$(curl -sS -o /dev/null -w '%{http_code}' \
              http://127.0.0.1:8765/)" = 200
            test "$(curl -sS -o /dev/null -w '%{http_code}' \
              'http://127.0.0.1:8765/search?q=tag%3Ainbox')" = 200
            test "$(curl -sS -o /dev/null -w '%{http_code}' \
              http://127.0.0.1:8765/status)" = 200

            ss -ltnp | grep '127.0.0.1:8765'
            ! ss -ltnp | grep -E '(^|[[:space:]])(0\.0\.0\.0|\[::\]):8765'
            test "$(grep -Fxc '# BEGIN NOTMUCH BROWSER USER RUNIT SESSION RECONCILE' \
              "$HOME/.icewm/startup")" = 1
            test "$(grep -Fxc '# END NOTMUCH BROWSER USER RUNIT SESSION RECONCILE' \
              "$HOME/.icewm/startup")" = 1
            test "$(grep -Fxc '# BEGIN NOTMUCH BROWSER SERVICE' \
              "$HOME/.icewm/startup" || true)" = 0
            test "$(grep -Fxc '# BEGIN NOTMUCH BROWSER INDEX REFRESH SERVICE' \
              "$HOME/.icewm/startup" || true)" = 0
            echo status=runtime_validation_passed
            """
        ),
    },
    {
        "title": "10. Manual antiX GUI acceptance",
        "body": clean(
            """
            Open http://127.0.0.1:8765/ on antiX. Confirm search, counts/range,
            fixed Previous/Next controls, responsive result rows, the horizontal
            desktop result/message splitter, metadata including Cc and copy buttons,
            Readable/Original/plain display, duplicate selection, individual
            attachment and Save All, embedded-image confirmation, separate remote
            image confirmation, permission reset on message/duplicate change,
            status, narrow layout, keyboard/pointer splitter behavior, and no
            clipping or unexpected popup.

            The owner completed this checklist against the isolated candidate and
            reported "antiX candidate GUI: PASS". That manual acceptance complements
            automated route and exact-byte checks; it does not replace them.
            """
        ),
    },
    {
        "title": "11. Windows SSH tunnel and GUI acceptance",
        "body": clean(
            """
            Keep the service on loopback. Run this from Windows PowerShell, leave
            the SSH process open, then browse http://127.0.0.1:8765/. If local port
            8765 is already occupied on Windows, use 8876 on the left side and
            browse http://127.0.0.1:8876/. The validated candidate used local 8876;
            production normally uses local 8765.
            """
        ),
        "label": "Copy Windows tunnel",
        "language": "powershell",
        "code": clean(
            r"""
            Test-NetConnection 192.168.254.128 -Port 22
            ssh -N -L 8765:127.0.0.1:8765 atiq@192.168.254.128
            """
        ),
    },
    {
        "title": "12. Read-only, exact-byte, capability, and ZIP proof",
        "body": clean(
            """
            For a production proof, first pause provider-live and stop only the
            index refresh loop so background writers cannot be confused with a
            browser mutation. Capture sorted indexed paths, indexed content hashes,
            tags, Mailstore metadata, counts, config/artifact identities, locks, and
            temporary-file state before and after representative traffic. Always
            restore the index/provider state in a trap.

            The accepted strict gate used scripts/notmuch_browser_strict_validator.py.
            It proved root/search/message/status responses, POST 405, invalid,
            tampered, and wrong-purpose capability 403 responses, selected-duplicate
            isolation, an exact 162,241-byte attachment with SHA256
            92afdde3d5a99c7b780b8da6977ff9c7b25ad220d4a74e4be2242be92cab02cc,
            an exact 4,078-byte inline image with SHA256
            4814092beac5a9e50e3e57b156e8cfcb7fc55e688f361c20268c5c1e0a61d3bd,
            CSP/reset behavior, and two safe three-entry Store ZIPs. The before and
            after stable snapshot SHA256 was identical:
            7f0312e7bd0c0602aeb04d7a4876c7214883547002005de8872c33b9a58d7a37.
            Counts at that bounded proof were 1,635 messages, 2,834 indexed files,
            and 1,635 tagged message records; normal mail later increased them.

            Use the retained operator runner for another formal mailbox proof rather
            than copying only fragments of the old gate. For a quick non-mutating
            daily audit, use the block below.
            """
        ),
        "label": "Copy read-only quick audit",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            CONFIG="$HOME/.config/notmuch/default/config"
            BEFORE="$(mktemp)"
            AFTER="$(mktemp)"
            notmuch --config="$CONFIG" search --format=text0 --output=files '*' |
              sort -z | sha256sum > "$BEFORE"

            curl -fsS -o /dev/null http://127.0.0.1:8765/
            curl -fsS -o /dev/null \
              'http://127.0.0.1:8765/search?q=tag%3Ainbox'
            curl -fsS -o /dev/null http://127.0.0.1:8765/status

            notmuch --config="$CONFIG" search --format=text0 --output=files '*' |
              sort -z | sha256sum > "$AFTER"
            cmp "$BEFORE" "$AFTER"
            test ! -d /mail/AppData/notmuch-browser/index-refresh.lock
            find /mail/AppData/notmuch-browser/download-tmp -maxdepth 1 \
              -type f -name 'nmb-*' -print -quit 2>/dev/null |
              grep -q . && exit 1 || true
            echo status=quick_read_only_audit_passed
            """
        ),
    },
    {
        "title": "13. Resource, restart, and repaired reboot evidence",
        "body": clean(
            """
            The bounded resource gate completed 90 of 90 HTTP requests with status
            200. Browser peaks were 25,520 KiB RSS, 15 threads, and 55 file
            descriptors, below gates of 65,536 KiB, 64 threads, and 128 descriptors.
            The controlled runit-aware restart rotated browser and index identities,
            logged graceful browser shutdown, rejected an old capability with 403,
            returned identical bytes through a fresh capability, and restored the
            provider unpaused with last exit 0.

            The first changed-boot attempt exposed an antiX session-hook race:
            overlapping /etc/user_session.d wrappers stopped normally-up services
            after the surviving runsvdir started. The repair deliberately leaves
            that distro file unchanged. One IceWM block launches
            notmuch-browser-runit-setup session-reconcile, which waits for
            prerequisites, reasserts only the two managed services, and requires
            60 continuous healthy seconds within 180 seconds.

            Final proof log
            notmuch-browser-operator-20260725-203802-977.log has SHA256
            fe18ec8f19796607d7d45c621c2e6e92e5608b0a0086aaab82b3871d913e8202.
            Boot changed to 5c996053-b1ab-4904-aa41-a0fbd1420fa5. The current-boot
            reconciliation log recorded three repairs then stable_seconds=60.
            Fresh runsv ancestry, loopback-only listener, routes, read-only health,
            exact attachment bytes, provider state, locks, and zero temp passed.
            The eleven-file evidence manifest SHA256 is
            4af19fb2dca62622be0b3d6b79e233b698acc0acc53c7d05e1fe32b145182325.
            """
        ),
        "label": "Copy post-login reconciliation proof",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            LOG=/tmp/notmuch-browser-user-runit-session-reconcile.log
            test -s "$LOG"
            grep -F 'status=user_runit_session_reconciled' "$LOG"
            grep -E 'stable_seconds=60|stable_seconds=[6-9][0-9]' "$LOG"
            "$HOME/.local/bin/notmuch-browser-runit-setup" validate
            pgrep -u "$(id -u)" -af "runsvdir -P $HOME/.runit/service"
            sv status "$HOME/.runit/service/notmuch-browser"
            sv status "$HOME/.runit/service/notmuch-browser-index"
            curl -fsS http://127.0.0.1:8765/healthz
            ss -ltnp | grep '127.0.0.1:8765'
            test ! -d /mail/AppData/isync/provider-live-loop/lock
            test ! -d /mail/AppData/notmuch-browser/index-refresh.lock
            echo status=post_login_reconciliation_healthy
            """
        ),
    },
    {
        "title": "14. Rollback",
        "body": clean(
            """
            Roll back only after resolving the exact target and verifying the
            pointer. The runit helper rollback verifies its activation backup,
            brings down only the two managed services, removes only their exact
            links, restores the saved IceWM startup, archives the pointer, and
            restarts the legacy direct controls. It does not restore a separately
            replaced binary. For an upgrade, verify and use the retained preinstall
            backup and its reviewed rollback-browser.sh after the supervision
            rollback.

            On the validated VM, the activation pointer is
            /mail/AppData/notmuch-browser/user-runit-rollback-current. Its backup
            inventory is artifacts.sha256. The earlier full preinstall package
            uses rollback-browser.sh and backup-inventory.sha256. Never guess a
            backup directory, never point outside /mail/Backups/notmuch-browser,
            and do not delete retained evidence as part of rollback.
            """
        ),
        "label": "Copy guarded runit rollback",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            POINTER=/mail/AppData/notmuch-browser/user-runit-rollback-current
            test -s "$POINTER"
            BACKUP="$(sed -n '1p' "$POINTER")"
            case "$BACKUP" in
              /mail/Backups/notmuch-browser/*) ;;
              *) echo 'Refusing pointer outside backup root' >&2; exit 1 ;;
            esac
            test -d "$BACKUP"
            (cd "$BACKUP" && sha256sum -c artifacts.sha256)
            printf 'Verified rollback target: %s\n' "$BACKUP"

            "$HOME/.local/bin/notmuch-browser-runit-setup" rollback
            "$HOME/.local/bin/notmuch-browser-control" status
            "$HOME/.local/bin/notmuch-browser-index-control" status
            curl -fsS http://127.0.0.1:8765/healthz
            echo status=user_runit_rollback_verified
            """
        ),
    },
    {
        "title": "15. Daily operations and stale-index repair",
        "body": clean(
            """
            Use the runit-aware controls; they delegate lifecycle, status, and logs
            to runit whenever the managed links are active. Search may briefly lag
            during mbsync or before the next 60-second index pass. A missing indexed
            Maildir path normally repairs on the next safe refresh. The refresh
            command refuses unsafe notmuch configuration and coordinates the mbsync
            and notmuch lock directories.

            Do not manually start a second browser, index loop, or runsvdir. Do not
            edit the generated service run files directly; update the source helper,
            test it, then restage through a separately reviewed change.
            """
        ),
        "label": "Copy daily operations",
        "language": "sh",
        "code": clean(
            r"""
            "$HOME/.local/bin/notmuch-browser-control" status
            "$HOME/.local/bin/notmuch-browser-index-control" status
            "$HOME/.local/bin/notmuch-browser-control" logs
            "$HOME/.local/bin/notmuch-browser-index-control" logs
            "$HOME/.local/bin/notmuch-browser-control" refresh-index
            "$HOME/.local/bin/notmuch-browser-runit-setup" inspect
            "$HOME/.local/bin/notmuch-browser-runit-setup" validate
            """
        ),
    },
    {
        "title": "16. Completion checklist",
        "body": clean(
            """
            Completion requires all of the following: exact artifact hashes; Go,
            Python, shell, deterministic generation, asset, and stripped-size
            gates; managed user-runit links and runsv ancestry; one reconciliation
            marker pair and no legacy direct blocks; loopback-only 8765; health
            reporting OK/read-only/non-mutating; root/search/message/status/static
            behavior; antiX GUI PASS; Windows tunnel GUI PASS; strict stable
            before/after proof; exact attachment/image/ZIP and capability rejection;
            resource peaks below limits; graceful restart and stale-capability
            rejection; changed-boot current-session reconciliation; provider-live
            restored; absent locks; empty Maildir/download temp; and retained,
            verified rollback evidence.

            The 2026-07-25 migration passed every item. Mailbox counts and process
            IDs in historical evidence are observations, not permanent assertions.
            Artifact, source, log, pointer, and evidence hashes are the durable
            identities.
            """
        ),
    },
]


def render_text() -> str:
    parts = [
        "# NOTMUCH BROWSER SERVICE - Validated templ/HTMX/Tailwind/chi + user-runit Guide",
        "",
        "Updated: 2026-07-25",
        "Validated platform: antiX Linux runit edition with zzzFM/IceWM",
        "Host access: Windows 11 through an SSH local-forward tunnel",
        "",
        "This guide supersedes the 2026-07-14 direct-IceWM reconstruction guide.",
        "It documents the fully accepted combined migration and repaired reboot path.",
    ]
    for section in SECTIONS:
        parts.extend(["", "-" * 79, section["title"], "-" * 79, "", section["body"]])
        if code := section.get("code"):
            parts.extend(["", f"```{section['language']}", code, "```"])
    return "\n".join(parts) + "\n"


def render_html() -> str:
    cards = []
    command_index = 0
    for section in SECTIONS:
        body = "\n".join(
            f"<p>{html.escape(paragraph).replace(chr(10), ' ')}</p>"
            for paragraph in section["body"].split("\n\n")
        )
        command = ""
        if code := section.get("code"):
            command_index += 1
            target = f"cmd-{command_index:02d}"
            command = (
                '<div class="codebox">'
                f'<button type="button" data-copy-target="{target}">'
                f'{html.escape(section["label"])}</button>'
                f'<pre id="{target}"><code>{html.escape(code)}</code></pre>'
                "</div>"
            )
        cards.append(
            f'<section id="section-{len(cards) + 1}">'
            f"<h2>{html.escape(section['title'])}</h2>{body}{command}</section>"
        )

    return clean(
        f"""
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>NOTMUCH BROWSER SERVICE - Validated Reconstruction Guide</title>
          <style>
            :root {{ color-scheme: light; --ink:#172033; --muted:#5b667a;
              --line:#d7e0ec; --blue:#176b87; --panel:#f7fafc; --code:#111827; }}
            * {{ box-sizing:border-box; }}
            body {{ margin:0; color:var(--ink); background:#edf4f8;
              font:16px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif; }}
            header,main,footer {{ width:min(1080px,calc(100% - 28px)); margin:auto; }}
            header {{ padding:42px 0 22px; }}
            h1 {{ margin:0 0 8px; font-size:clamp(1.8rem,4vw,3rem); line-height:1.08; }}
            .lede {{ color:var(--muted); max-width:78ch; }}
            nav {{ display:flex; flex-wrap:wrap; gap:8px; margin-top:18px; }}
            nav a {{ color:var(--blue); background:white; border:1px solid var(--line);
              border-radius:999px; padding:5px 10px; text-decoration:none; }}
            section {{ background:white; border:1px solid var(--line); border-radius:14px;
              padding:clamp(18px,3vw,30px); margin:0 0 18px;
              box-shadow:0 8px 26px rgba(23,32,51,.05); }}
            h2 {{ margin-top:0; line-height:1.2; }}
            p {{ white-space:pre-line; }}
            .codebox {{ position:relative; margin-top:18px; }}
            button {{ border:0; border-radius:8px; color:white; background:var(--blue);
              padding:9px 13px; font-weight:700; cursor:pointer; margin-bottom:8px; }}
            button.copied {{ background:#247a48; }}
            pre {{ margin:0; overflow:auto; color:#edf5ff; background:var(--code);
              border-radius:10px; padding:18px; tab-size:2; }}
            pre code {{ color:inherit; background:transparent; padding:0;
              font:13px/1.55 ui-monospace,SFMono-Regular,Consolas,monospace; }}
            footer {{ color:var(--muted); padding:12px 0 36px; }}
            @media print {{ body {{ background:white; }} section {{ box-shadow:none; }}
              button,nav {{ display:none; }} header,main,footer {{ width:100%; }} }}
          </style>
        </head>
        <body>
          <header>
            <h1>NOTMUCH BROWSER SERVICE</h1>
            <p class="lede">Validated templ/HTMX/Tailwind/chi browser and repaired
            per-user runit reconstruction guide for antiX, with Windows SSH access.</p>
            <p><strong>Updated:</strong> 2026-07-25</p>
            <nav aria-label="Guide sections">
              {''.join(f'<a href="#section-{i}">{i}</a>' for i in range(1, len(SECTIONS) + 1))}
            </nav>
          </header>
          <main>
            {''.join(cards)}
          </main>
          <footer>
            Offline document. All styling and copy behavior are embedded locally.
            The plain-text companion contains the same command blocks.
          </footer>
          <script>
            async function copyText(value) {{
              if (navigator.clipboard && window.isSecureContext) {{
                await navigator.clipboard.writeText(value);
                return;
              }}
              const area = document.createElement("textarea");
              area.value = value;
              area.setAttribute("readonly", "");
              area.style.position = "fixed";
              area.style.opacity = "0";
              document.body.appendChild(area);
              area.select();
              const copied = document.execCommand("copy");
              area.remove();
              if (!copied) throw new Error("copy command was rejected");
            }}
            document.addEventListener("click", async (event) => {{
              const button = event.target.closest("[data-copy-target]");
              if (!button) return;
              const target = document.getElementById(button.dataset.copyTarget);
              if (!target) return;
              const previous = button.textContent;
              try {{
                await copyText(target.textContent);
                button.textContent = "Copied";
                button.classList.add("copied");
              }} catch (error) {{
                button.textContent = "Copy failed";
              }}
              setTimeout(() => {{
                button.textContent = previous;
                button.classList.remove("copied");
              }}, 1400);
            }});
          </script>
        </body>
        </html>
        """
    ) + "\n"


# The original audited reconstruction content above is retained as historical
# source context. Fresh installs now use the beginner-first v2 content module.
# Load it by path so this generator also works when imported directly by tests.
import importlib.util


_V2_PATH = ROOT / "scripts" / "notmuch_browser_service_guide_v2.py"
_V2_SPEC = importlib.util.spec_from_file_location(
    "notmuch_browser_service_guide_v2", _V2_PATH
)
if _V2_SPEC is None or _V2_SPEC.loader is None:  # pragma: no cover
    raise RuntimeError(f"cannot load guide content: {_V2_PATH}")
_V2 = importlib.util.module_from_spec(_V2_SPEC)
_V2_SPEC.loader.exec_module(_V2)
SECTIONS = _V2.SECTIONS
render_text = _V2.render_text
render_html = _V2.render_html


def main() -> None:
    TEXT_PATH.write_text(render_text(), encoding="ascii")
    HTML_PATH.write_text(render_html(), encoding="ascii")
    print(f"generated={TEXT_PATH.relative_to(ROOT)}")
    print(f"generated={HTML_PATH.relative_to(ROOT)}")
    print(f"command_blocks={sum('code' in section for section in SECTIONS)}")


if __name__ == "__main__":
    main()
