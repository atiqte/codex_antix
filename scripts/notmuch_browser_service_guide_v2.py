"""Beginner-first source for the matching notmuch browser HTML/TXT guides."""

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
        "title": "1. What this guide creates",
        "body": clean(
            """
            This is the from-scratch guide for a new x86_64 antiX Linux runit VM
            with zzzFM/IceWM on a Windows 11 VMware host. No prior Linux, Go,
            notmuch, Bun, Tailwind, or runit knowledge is assumed.

            At the end, the VM has the complete accepted Go browser: chi routing,
            templ views, local HTMX 2.0.10, Tailwind CSS 4.3.3 built with Bun,
            search and message reading, Readable/Original/plain modes, duplicate
            selection, signed individual attachments, Save All ZIP, confirmed
            embedded/remote images, and status/health pages.

            The browser listens only on 127.0.0.1:8765. Windows accesses it through
            an SSH tunnel. Browser routes never change Maildir files, tags, or the
            notmuch database. Evolution remains the compose/reply/send client.
            """
        ),
    },
    {
        "title": "2. Understand the three moving parts",
        "body": clean(
            """
            Git copies the application source, helper scripts, tests, and this
            guide. Git does not copy email, passwords, the restored archive, local
            logs, or the notmuch search database.

            mbsync receives new provider mail into Maildir. Its normal loop waits
            about 180 seconds after a sync. notmuch does not receive mail: it builds
            and refreshes a separate search database. Its normal loop checks about
            every 60 seconds and waits if mbsync is busy.

            Therefore notmuch new is necessary. After the first large index it is
            incremental. A newly received message normally becomes searchable
            after mbsync delivers it plus at most one index interval. The browser
            does not need to restart.
            """
        ),
    },
    {
        "title": "3. Before starting",
        "body": clean(
            """
            You need: a Windows 11 computer; VMware; an antiX runit ISO; internet;
            sudo permission in antiX; GitHub repository access; and the verified
            historical split-archive folder.

            Give the VM enough CPU/RAM for a Go build. Add a separate virtual disk
            of at least 250 GB for /mail. After restoring the 59 GB archive, at
            least 80 GiB free is mandatory before initial indexing; 100 GiB free
            is preferred. Take a VMware snapshot before disk work.

            Never paste disk commands until you have identified the new empty
            virtual disk. The setup assistant deliberately never partitions,
            formats, edits fstab, deletes mail, or creates credentials.
            """
        ),
    },
    {
        "title": "4. Install antiX and clone the main branch",
        "body": clean(
            """
            Install antiX runit with zzzFM/IceWM normally, log in as your regular
            user, open a terminal, and run this block. GitHub may ask for your
            username and a personal access token if the repository is private.

            Expected final lines: branch main, an origin URL, and no changed files.
            Stop if clone or checkout fails.
            """
        ),
        "label": "Copy first clone",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            sudo apt update
            sudo apt install git ca-certificates
            cd "$HOME"
            test ! -e codex_antix
            git clone --branch main https://github.com/atiqte/codex_antix.git codex_antix
            cd "$HOME/codex_antix"
            git branch --show-current
            git remote -v
            git status --short --branch
            """
        ),
    },
    {
        "title": "5. Start the one-step-at-a-time assistant",
        "body": clean(
            """
            Stay in the repository directory. inspect and status are read-only.
            next prints only the next required stage; it does not silently install
            packages, write credentials, or start the long index.

            Run next again after every completed step. If it reports a different
            stage than expected, stop and read its status output.
            """
        ),
        "label": "Copy assistant start",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh inspect
            ./scripts/notmuch_browser_fresh_vm_setup.sh next
            """
        ),
    },
    {
        "title": "6. Create the dedicated XFS /mail disk",
        "body": clean(
            """
            Open existing_DIY-Guide/antiX_VM_XFS_Maildir_Disk_Setup_Guide.html
            from the cloned repository and follow it carefully. That guide covers
            identifying the second VMware disk, creating XFS, mounting /mail, and
            making the mount persistent. Do not guess the device name.

            Run this read-only verification afterward. Expected: TARGET is /mail,
            FSTYPE is xfs, and SIZE is approximately the virtual disk size. If
            /mail resolves to the antiX root filesystem, stop.
            """
        ),
        "label": "Copy XFS verification",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            findmnt --target /mail
            test "$(findmnt -n -o FSTYPE --target /mail)" = xfs
            df -h /mail
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh next
            """
        ),
    },
    {
        "title": "7. Install antiX operating-system packages",
        "body": clean(
            """
            This installs the command-line tools, notmuch, mbsync/isync, SSH,
            build tools, and antiX runit integration. It does not install Go or
            Bun. Answer yes if apt asks for confirmation.

            Expected: every command -v line prints a path and sv --help runs.
            """
        ),
        "label": "Copy OS package install",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            sudo apt update
            sudo apt install git curl ca-certificates unzip xz-utils rsync python3 \
              notmuch isync libsasl2-modules runit-antix runit-service-ssh iproute2 \
              openssh-client openssh-server build-essential
            for tool in git curl python3 rsync notmuch mbsync sv svlogd ssh ss unzip tar sha256sum findmnt; do
              command -v "$tool"
            done
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh next
            """
        ),
    },
    {
        "title": "8. Install verified Go 1.26.5",
        "body": clean(
            """
            This uses the official linux-amd64 archive and verifies its SHA256.
            The command refuses to replace an existing /usr/local/go directory.
            If that directory already exists, stop and review it instead of
            deleting it.

            Expected: go version go1.26.5 linux/amd64.
            """
        ),
        "label": "Copy Go install",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            GO_ARCHIVE=/tmp/go1.26.5.linux-amd64.tar.gz
            curl -fL https://go.dev/dl/go1.26.5.linux-amd64.tar.gz -o "$GO_ARCHIVE"
            printf '%s  %s\n' \
              5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053 \
              "$GO_ARCHIVE" | sha256sum -c -
            test ! -e /usr/local/go
            sudo tar -C /usr/local -xzf "$GO_ARCHIVE"
            grep -Fqx 'export PATH=/usr/local/go/bin:$PATH' "$HOME/.profile" 2>/dev/null ||
              printf '%s\n' 'export PATH=/usr/local/go/bin:$PATH' >> "$HOME/.profile"
            export PATH=/usr/local/go/bin:$PATH
            go version
            test "$(go version | awk '{print $3}')" = go1.26.5
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh next
            """
        ),
    },
    {
        "title": "9. Install verified Bun 1.3.14",
        "body": clean(
            """
            Bun is used only to reproduce the Tailwind build. Production runs one
            Go binary and does not need a Bun process. The repository lockfile
            keeps Tailwind and @tailwindcss/cli at 4.3.3.

            Expected: bun --version prints 1.3.14. Do not run bun update.
            """
        ),
        "label": "Copy Bun install",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            curl -fsSL https://bun.com/install | bash -s "bun-v1.3.14"
            export BUN_INSTALL="$HOME/.bun"
            export PATH="$BUN_INSTALL/bin:/usr/local/go/bin:$PATH"
            test "$(bun --version)" = 1.3.14
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh next
            """
        ),
    },
    {
        "title": "10. Configure live mail reception with mbsync",
        "body": clean(
            """
            The first write-config command is interactive. Enter your provider
            IMAP server, login, and password-command details. The generated normal
            folders are receive-only: PullNew, Remove None, Expunge None. Only the
            dedicated Sent channel permits PushNew.

            Read each result before continuing. list must show the expected remote
            folders. The first real sync can take time. autosync-validate finishes
            with the 180-second loop running and no stale lock.
            """
        ),
        "label": "Copy mbsync setup",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            cd "$HOME/codex_antix"
            ./scripts/mbsync_provider_inbox_setup.sh create-layout
            ./scripts/mbsync_provider_inbox_setup.sh write-config
            ./scripts/mbsync_provider_inbox_setup.sh list
            ./scripts/mbsync_provider_inbox_setup.sh dry-run
            ./scripts/mbsync_provider_inbox_setup.sh sync-once
            ./scripts/mbsync_provider_inbox_setup.sh production-layout
            ./scripts/mbsync_provider_inbox_setup.sh write-production-config
            ./scripts/mbsync_provider_inbox_setup.sh production-list
            ./scripts/mbsync_provider_inbox_setup.sh production-sync
            ./scripts/mbsync_provider_inbox_setup.sh write-autosync
            ./scripts/mbsync_provider_inbox_setup.sh install-autosync-startup
            ./scripts/mbsync_provider_inbox_setup.sh autosync-validate
            ./scripts/notmuch_browser_fresh_vm_setup.sh next
            """
        ),
    },
    {
        "title": "11. Restore the exact historical local-maildir archive",
        "body": clean(
            """
            Copy the complete verified export folder to the exact staging path
            below. It contains manifest.json, inventory.jsonl, and 21 unchanged
            part files. Use the separate Maildir++ transport guide for USB or
            VMware shared-folder transfer.

            The destination must be absent or completely empty. Never restore over
            another tree. Expected verification: archive status ok; 48,720 cur;
            zero new/tmp; one metadata file; 62,430,783,277 regular bytes; no
            symlinks or special files.

            Do not copy the drifted 48,564-file tree from the older VM.
            """
        ),
        "label": "Copy archive restore",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            cd "$HOME/codex_antix"
            MANIFEST=/mail/import-staging/maildirpp-archive-export-20260701-215204/manifest.json
            DEST=/mail/Mailstore/evolution/local-maildir
            test -f "$MANIFEST"
            if [ -e "$DEST" ]; then
              test -d "$DEST"
              test -z "$(find "$DEST" -mindepth 1 -print -quit)"
            fi
            python3 src/maildirpp_transport.py verify-archive --manifest "$MANIFEST"
            python3 src/maildirpp_transport.py unpack --manifest "$MANIFEST" --dest "$DEST"
            python3 src/maildirpp_transport.py verify-tree --manifest "$MANIFEST" --dest "$DEST"
            python3 src/maildirpp_transport.py inspect --source "$DEST"
            df -h /mail
            """
        ),
    },
    {
        "title": "12. Reverify and acknowledge the archive gate",
        "body": clean(
            """
            This intentionally verifies the large package and restored tree again.
            It rejects the wrong archive hashes, wrong counts, links/special files,
            or less than 80 GiB free. Only then does it write a small private
            acknowledgement marker.

            Expected: status=archive_restore_acknowledged and the next stage is
            notmuch-config.
            """
        ),
        "label": "Copy archive acknowledgement",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh acknowledge archives-restored
            ./scripts/notmuch_browser_fresh_vm_setup.sh next
            """
        ),
    },
    {
        "title": "13. Create the safe notmuch configuration",
        "body": clean(
            """
            Replace the example name and email. This is identity metadata, not a
            password. The database lives under /mail/SearchIndex and scans the
            real /mail/Mailstore tree.

            local-maildir is deliberately not in new.ignore, so the full historical
            archive will be indexed. Only the named test/secondary archive folders
            remain ignored. synchronize_flags=false prevents notmuch flag/tag
            synchronization from altering Maildir filenames; index.decrypt=false
            disables automatic decryption.
            """
        ),
        "label": "Copy notmuch configuration",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh configure-notmuch \
              "REPLACE WITH YOUR NAME" "replace-with-your-email@example.com"
            notmuch --config="$HOME/.config/notmuch/default/config" config get new.ignore
            ./scripts/notmuch_browser_fresh_vm_setup.sh next
            """
        ),
    },
    {
        "title": "14. Run the first large historical index",
        "body": clean(
            """
            This is the long step. It pauses active mbsync/index loops, backs up
            existing config/tags/database state, and runs notmuch new without the
            normal 600-second refresh timeout. Output is saved under
            /mail/Logs/notmuch-browser/fresh-vm-setup.

            You may safely rerun the same command after power loss or interruption;
            notmuch continues incrementally. Success requires exact path parity for
            all 48,720 restored messages. Unique message count may be smaller
            because duplicate Message-IDs are valid; file-path parity is the gate.
            """
        ),
        "label": "Copy initial historical index",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh initial-index
            ./scripts/notmuch_browser_fresh_vm_setup.sh next
            """
        ),
    },
    {
        "title": "15. Build and install the complete browser",
        "body": clean(
            """
            This performs a frozen Bun install, Go module verification, templ and
            Tailwind generation, reproducibility checks, Go tests/vet/race, Python
            tests, shell syntax checks, the embedded-asset budget, and a stripped
            binary build. It then installs the browser and control helpers under
            ~/.local/bin, backing up any prior application files.

            Go dependencies remain pinned by go.mod/go.sum. Tailwind dependencies
            remain pinned by package.json/bun.lock. Do not run go get -u or bun
            update as part of reconstruction.
            """
        ),
        "label": "Copy browser build and install",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            export PATH="$HOME/.bun/bin:/usr/local/go/bin:$PATH"
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh build-install
            ./scripts/notmuch_browser_fresh_vm_setup.sh next
            """
        ),
    },
    {
        "title": "16. Enable repaired per-user runit supervision",
        "body": clean(
            """
            antiX should already run a per-user runsvdir for ~/.runit/service.
            These checks create only the two empty user directories if absent;
            they never write /etc/service. If pgrep prints nothing, log out of
            IceWM and log back in, then retry. Do not create a second runsvdir.

            enable-services stages disabled definitions, activates them, installs
            the bounded IceWM session reconciler, and validates browser and index
            health. The initial 48,720-file gate must pass first.
            """
        ),
        "label": "Copy user-runit enablement",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            mkdir -p "$HOME/.runit/usersv" "$HOME/.runit/service"
            pgrep -a -u "$(id -u)" -f "runsvdir -P $HOME/.runit/service"
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh enable-services
            ./scripts/notmuch_browser_fresh_vm_setup.sh validate
            """
        ),
    },
    {
        "title": "17. Enable SSH and connect from Windows 11",
        "body": clean(
            """
            On antiX, confirm SSH is supervised and find the VM address. The
            browser must remain bound only to 127.0.0.1:8765.
            """
        ),
        "label": "Copy antiX SSH checks",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            sudo sv up /etc/service/ssh
            sudo sv status /etc/service/ssh
            hostname -I
            ss -ltn | grep '127.0.0.1:8765'
            curl -fsS http://127.0.0.1:8765/healthz
            """
        ),
    },
    {
        "title": "18. Open the Windows SSH tunnel",
        "body": clean(
            """
            Run this in Windows PowerShell and replace both placeholders. Keep the
            PowerShell window open. Then browse to http://127.0.0.1:8765/ on
            Windows. The -N option opens only the tunnel; it does not open a remote
            shell.
            """
        ),
        "label": "Copy Windows tunnel",
        "language": "powershell",
        "code": clean(
            r"""
            ssh -N -L 8765:127.0.0.1:8765 REPLACE_WITH_ANTIX_USER@REPLACE_WITH_VM_IP
            """
        ),
    },
    {
        "title": "19. Manual browser acceptance",
        "body": clean(
            """
            Search for a known historical message and a recent live message. Open
            both. Check Readable, Original, and plain display modes; duplicate
            selection; individual attachment download; Save All ZIP; embedded
            image confirmation; remote image confirmation/reset; narrow-window
            layout; and the Status page.

            Health must say ok=true, read_only=true, and mail_mutation=false.
            Confirm there are no overlapping controls, error popups, or files left
            under Maildir tmp or the browser download-temp directory.
            """
        ),
    },
    {
        "title": "20. Prove automatic new-mail indexing",
        "body": clean(
            """
            Send a test message to the configured account. The first status shows
            current service state. Wait for the next mbsync and notmuch cycles, then
            search for a distinctive subject. This is the real proof that mail
            reception and incremental indexing both work.

            mbsync normally waits 180 seconds after each sync and the index loop
            normally waits 60 seconds. Exact arrival time depends on where each
            loop is in its cycle. No browser restart is required.
            """
        ),
        "label": "Copy automatic-index proof",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            "$HOME/.local/bin/mbsync-provider-live-control" status
            "$HOME/.local/bin/notmuch-browser-index-control" status
            "$HOME/.local/bin/notmuch-browser-control" status
            echo "After sending the test email, wait up to about five minutes."
            notmuch --config="$HOME/.config/notmuch/default/config" \
              search 'subject:"REPLACE WITH DISTINCTIVE TEST SUBJECT"'
            """
        ),
    },
    {
        "title": "21. Reboot proof",
        "body": clean(
            """
            Reboot antiX, log back into IceWM, wait one minute, and run this block.
            Expected: both runit services are running, health passes, mbsync is
            active, and local-maildir remains absent from new.ignore.
            """
        ),
        "label": "Copy post-reboot checks",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh validate
            "$HOME/.local/bin/mbsync-provider-live-control" status
            "$HOME/.local/bin/notmuch-browser-runit-setup" inspect
            notmuch --config="$HOME/.config/notmuch/default/config" config get new.ignore
            """
        ),
    },
    {
        "title": "22. Daily use and safe GitHub updates",
        "body": clean(
            """
            Normally you only open the Windows tunnel and use the browser. Use
            status if mail looks stale. refresh-index requests one immediate,
            lock-protected incremental notmuch new.

            For a repository update, use the update command from a clean main
            branch. It performs git pull --ff-only, rebuilds locked assets, backs
            up installed application files, restarts both runit services, validates
            health, and restores the prior application files if validation fails.
            It never replaces Maildir or the notmuch database.
            """
        ),
        "label": "Copy daily and update commands",
        "language": "sh",
        "code": clean(
            r"""
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh status
            "$HOME/.local/bin/notmuch-browser-control" refresh-index

            # Run this only when you intentionally want the newest main branch:
            ./scripts/notmuch_browser_fresh_vm_setup.sh update
            """
        ),
    },
    {
        "title": "23. Troubleshooting and recovery",
        "body": clean(
            """
            Always run status first. If initial-index failed, read its newest log,
            correct the reported problem, confirm at least 80 GiB free, and rerun
            initial-index. A missing completion marker means services cannot be
            enabled.

            If search is stale but both loops are healthy, run one refresh-index.
            If a lock is reported, do not delete it while its PID is alive. If the
            browser update rolled back, status reports the retained backup path;
            keep that backup until the corrected version passes.

            Never solve an indexing problem by deleting local-maildir. notmuch's
            database is a sidecar, while the verified Maildir archive is the
            irreplaceable source.
            """
        ),
        "label": "Copy troubleshooting report",
        "language": "sh",
        "code": clean(
            r"""
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh status
            "$HOME/.local/bin/notmuch-browser-control" logs
            "$HOME/.local/bin/notmuch-browser-index-control" logs
            ls -lt /mail/Logs/notmuch-browser/fresh-vm-setup
            df -h /mail
            """
        ),
    },
    {
        "title": "24. Completion checklist",
        "body": clean(
            """
            Complete means: /mail is XFS; the exact 48,720-file archive passed
            package/tree inspection; at least 80 GiB was free before initial
            indexing; all archive paths are in notmuch; local-maildir is not
            ignored; the full browser feature set passed; browser/index are under
            repaired user runit; 8765 is localhost-only; the Windows tunnel works;
            reboot recovery works; and a newly received test email became
            searchable automatically.

            Keep the verified split archive outside Git as disaster-recovery
            material. Keep credentials mode 600 and never commit them.
            """
        ),
    },
]


def render_text() -> str:
    parts = [
        "# NOTMUCH GO BROWSER SERVICE - Beginner Fresh antiX VM Guide",
        "",
        "Updated: 2026-07-25",
        "Target: antiX Linux runit edition with zzzFM/IceWM on Windows 11 VMware",
        "Repository update branch: main",
        "",
        "Follow the numbered sections in order. Stop when a check fails.",
        "Run the setup assistant's `next` command after each completed stage.",
    ]
    for section in SECTIONS:
        parts.extend(["", "=" * 79, section["title"], "=" * 79, "", section["body"]])
        if code := section.get("code"):
            parts.extend(["", f"```{section['language']}", code, "```"])
    return "\n".join(parts) + "\n"


def render_html() -> str:
    cards = []
    command_index = 0
    for section_index, section in enumerate(SECTIONS, start=1):
        paragraphs = []
        for paragraph in section["body"].split("\n\n"):
            escaped = html.escape(paragraph).replace("\n", "<br>")
            paragraphs.append(f"<p>{escaped}</p>")
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
            f'<section id="section-{section_index}">'
            f"<h2>{html.escape(section['title'])}</h2>"
            f"{''.join(paragraphs)}{command}</section>"
        )

    nav = "".join(
        f'<a href="#section-{index}">{index}</a>'
        for index in range(1, len(SECTIONS) + 1)
    )
    return clean(
        f"""
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Beginner Fresh antiX Notmuch Browser Guide</title>
          <style>
            :root {{ color-scheme:light; --ink:#172033; --muted:#556176;
              --line:#cfdbe7; --blue:#126782; --green:#276749; --code:#111827; }}
            * {{ box-sizing:border-box; }}
            body {{ margin:0; color:var(--ink); background:#eef5f8;
              font:16px/1.58 system-ui,-apple-system,"Segoe UI",sans-serif; }}
            header,main,footer {{ width:min(1080px,calc(100% - 28px)); margin:auto; }}
            header {{ padding:40px 0 22px; }}
            h1 {{ margin:0 0 10px; font-size:clamp(1.8rem,4vw,3rem); line-height:1.08; }}
            .lede {{ max-width:78ch; color:var(--muted); }}
            .notice {{ border-left:5px solid var(--green); background:#f1fff7;
              border-radius:8px; padding:12px 16px; max-width:84ch; }}
            nav {{ display:flex; flex-wrap:wrap; gap:7px; margin-top:18px; }}
            nav a {{ min-width:32px; text-align:center; color:var(--blue); background:white;
              border:1px solid var(--line); border-radius:999px; padding:5px 9px;
              text-decoration:none; }}
            section {{ background:white; border:1px solid var(--line); border-radius:14px;
              padding:clamp(18px,3vw,30px); margin:0 0 18px;
              box-shadow:0 8px 26px rgba(23,32,51,.05); }}
            h2 {{ margin-top:0; line-height:1.22; }}
            p {{ max-width:88ch; }}
            .codebox {{ margin-top:18px; }}
            button {{ border:0; border-radius:8px; color:white; background:var(--blue);
              padding:9px 13px; font-weight:700; cursor:pointer; margin-bottom:8px; }}
            button.copied {{ background:var(--green); }}
            pre {{ margin:0; overflow:auto; color:#edf5ff; background:var(--code);
              border-radius:10px; padding:18px; tab-size:2; }}
            pre code {{ color:inherit; font:13px/1.55 ui-monospace,SFMono-Regular,Consolas,monospace; }}
            footer {{ color:var(--muted); padding:12px 0 36px; }}
            @media print {{ body {{ background:white; }} section {{ box-shadow:none; }}
              button,nav {{ display:none; }} header,main,footer {{ width:100%; }} }}
          </style>
        </head>
        <body>
          <header>
            <h1>Fresh antiX Notmuch Browser Setup</h1>
            <p class="lede">A from-scratch, beginner-friendly reconstruction of the
            complete Go/chi/templ/HTMX/Tailwind browser, including the verified
            48,720-file historical archive and automatic new-mail indexing.</p>
            <p class="notice"><strong>Safety rule:</strong> follow the steps in order
            and stop whenever an expected check fails. The assistant never formats
            a disk or invents credentials.</p>
            <p><strong>Updated:</strong> 2026-07-25</p>
            <nav aria-label="Guide sections">{nav}</nav>
          </header>
          <main>{''.join(cards)}</main>
          <footer>Offline guide. Styling and copy controls are embedded; the TXT
          companion contains the same commands.</footer>
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


def main() -> None:
    TEXT_PATH.write_text(render_text(), encoding="ascii")
    HTML_PATH.write_text(render_html(), encoding="ascii")
    print(f"generated={TEXT_PATH.relative_to(ROOT)}")
    print(f"generated={HTML_PATH.relative_to(ROOT)}")
