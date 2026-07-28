"""One-command, release-pinned source for matching notmuch browser guides."""

from __future__ import annotations

import html
from textwrap import dedent


RELEASE_TAG = "notmuch-browser-antix-v1.0.0"
RECOVERY_SET_SHA256 = (
    "6858d5050a1cfe958d43ed0dc838e4c4b4a2c495afa709ffce796327599ef9d2"
)
RELEASE_STATUS = (
    "Release-candidate preparation: the stable tag is published only after the "
    "blank-VM antiX and Windows pilot passes."
)


def clean(value: str) -> str:
    return dedent(value).strip()


SECTIONS = [
    {
        "title": "1. Result and current release status",
        "body": clean(
            f"""
            This guide reconstructs the accepted read-only notmuch browser on a
            new x86_64 antiX Linux runit VM with zzzFM/IceWM on a Windows 11
            VMware host. No prior Linux, Go, Bun, notmuch, Tailwind, templ, chi,
            HTMX, or runit knowledge is assumed.

            The completed service listens only on 127.0.0.1:8765 and Windows
            reaches it through SSH. It provides the six approved search sources,
            single-message newest-first results, precise local dates, the sticky
            sidebar, mailto and raw-address copy controls, Readable/Original/plain
            views, duplicate selection, signed attachments, Save All ZIP, and
            separately confirmed embedded and remote images. Browser routes never
            change Maildir, notmuch tags, or the search database.

            {RELEASE_STATUS}
            """
        ),
    },
    {
        "title": "2. What is automatic and what is deliberately manual",
        "body": clean(
            """
            After /mail is safely mounted, one resumable guided-install command
            verifies the pinned release and recovery set, installs packages plus
            exact Go 1.26.5 and Bun 1.3.14, securely configures mbsync and notmuch,
            restores approved sources, runs the large index, reproduces templ and
            Tailwind CSS 4.3.3 from locked dependencies, builds and installs the
            Go/chi application with local HTMX 2.0.10, enables per-user runit, and
            validates localhost health.

            Disk partitioning remains separate because blindly formatting a disk
            is unsafe. The script never formats disks, deletes mail, invents
            credentials, restores into unexpected nonempty folders, or copies an
            old notmuch database. Secure prompts collect the IMAP host, username,
            app password, and notmuch identity. The password is hidden, stored
            mode 600, and excluded from setup logs.

            The go1.26.5 linux-amd64 archive SHA256 is
            5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053.
            The Bun linux-x64 ZIP SHA256 is
            951ee2aee855f08595aeec6225226a298d3fea83a3dcd6465c09cbccdf7e848f.
            Downloads are verified before extraction; no remote script is piped
            directly into a shell.
            """
        ),
    },
    {
        "title": "3. Prepare and verify the dedicated /mail disk",
        "body": clean(
            """
            Install antiX runit normally and add a separate virtual disk of at
            least 250 GB. Follow the repository XFS disk guide, identifying the
            new empty disk by its real size/model. Never copy a /dev/sdb example
            without proving that it is the intended empty virtual disk.

            The main installer begins only after /mail is a dedicated writable
            XFS mount. Keep at least 80 GiB free before indexing; 100 GiB is
            preferred. This verification is read-only except for a harmless
            create/remove write test.
            """
        ),
        "label": "Copy /mail verification",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            findmnt --target /mail
            test "$(findmnt -n -o FSTYPE --target /mail)" = xfs
            test "$(findmnt -n -o TARGET --target /mail)" = /mail
            df -h /mail
            test "$(df -Pk /mail | awk 'NR == 2 { print $4 }')" -ge 83886080
            touch /mail/.notmuch-browser-write-test
            unlink /mail/.notmuch-browser-write-test
            """
        ),
    },
    {
        "title": "4. Attach the private validated recovery set",
        "body": clean(
            f"""
            Git never contains private mail. Attach or copy the external
            notmuch-browser-recovery-v1 folder to the VM. It contains the pristine
            48,720-message, 62,430,783,277-byte historical package and the
            canonical 247-message Betterbird delta package. Its mode-600
            recovery-set.env binds both split archives, inventories, counts,
            bytes, and destinations.

            provider-inbox-test is created by the guarded IMAP test pull;
            provider-live comes from the production pull; provider-live-archive
            starts as an empty Maildir; and test-maildir contains four
            deterministic example.test fixtures. The recovery set contains no
            credentials, provider-live snapshot, notmuch database, or logs.
            Replace only the recovery-root path below. The exact validated
            recovery-set.env SHA256 is {RECOVERY_SET_SHA256}.
            """
        ),
        "label": "Copy recovery verification",
        "language": "sh",
        "code": clean(
            f"""
            set -eu
            RECOVERY_ROOT=/REPLACE/WITH/notmuch-browser-recovery-v1
            test -f "$RECOVERY_ROOT/recovery-set.env"
            chmod 600 "$RECOVERY_ROOT/recovery-set.env"
            printf '%s  %s\\n' \\
              {RECOVERY_SET_SHA256} \\
              "$RECOVERY_ROOT/recovery-set.env" | sha256sum -c -
            """
        ),
    },
    {
        "title": "5. Clone main and fetch the pinned stable release",
        "body": clean(
            f"""
            Install only Git, Python 3, and CA certificates for the initial
            clone. Python verifies the private recovery-set metadata before the
            guided installer installs the remaining packages. The
            repository stays on main so future documentation can use
            git pull --ff-only. The installer itself exports and re-executes the
            exact {RELEASE_TAG} tag from a private release-source directory.

            Stop if the tag is unavailable, the repository is dirty, or the
            branch is not main. Until the stable tag is published after the real
            blank-VM pilot, this block intentionally stops at the tag check.
            """
        ),
        "label": "Copy Git clone and release check",
        "language": "sh",
        "code": clean(
            f"""
            set -eu
            sudo apt update
            sudo apt install -y git ca-certificates python3
            cd "$HOME"
            test ! -e codex_antix
            git clone https://github.com/atiqte/codex_antix.git codex_antix
            cd "$HOME/codex_antix"
            test "$(git branch --show-current)" = main
            git pull --ff-only origin main
            git fetch --tags origin
            git rev-parse --verify "{RELEASE_TAG}^{{commit}}"
            test -z "$(git status --porcelain)"
            """
        ),
    },
    {
        "title": "6. Run the one resumable installer",
        "body": clean(
            f"""
            Run this one command from the clean main clone. Replace only
            RECOVERY_ROOT. Read each prompt. The IMAP app-password prompt is
            hidden. Normal folders are receive-only; only the dedicated Sent
            channel permits PushNew.

            A stage prints already_ready when a prior verified result can be
            reused. On BLOCKED or failure, correct the stated reason and rerun the
            identical command. It resumes safely after interruption, logout, or
            power loss. Initial indexing may take a long time.
            """
        ),
        "label": "Copy guided installer",
        "language": "sh",
        "code": clean(
            f"""
            set -eu
            cd "$HOME/codex_antix"
            RECOVERY_ROOT=/REPLACE/WITH/notmuch-browser-recovery-v1
            ./scripts/notmuch_browser_fresh_vm_setup.sh guided-install \\
              --release {RELEASE_TAG} \\
              --recovery-root "$RECOVERY_ROOT"
            """
        ),
    },
    {
        "title": "7. Understand the indexing and source result",
        "body": clean(
            """
            notmuch new is necessary because mbsync receives Maildir files while
            notmuch maintains a separate search database. The first pass indexes
            every approved source. Later passes are incremental and normally run
            every 60 seconds, waiting while mbsync is active. The browser does not
            restart when mail arrives.

            Success requires exact prefix-filtered path parity for local-maildir,
            the Betterbird delta, provider-inbox-test, provider-live, the empty
            provider archive, and the four test fixtures. new.ignore contains
            only betterbird-post-main-archive-maildirpp-20260704-205827. Results
            are never thread-grouped and are always newest first. Unique-message
            counts can be smaller than file counts because duplicate Message-IDs
            are valid, and live counts naturally change.
            """
        ),
    },
    {
        "title": "8. Run full validation and prove automatic new-mail indexing",
        "body": clean(
            """
            Full validation checks read-only health, the six-source catalog, all
            four deterministic fixture results, From/To/Cc/Bcc mailto and copy
            behavior, 2.2-second copied feedback, and attachment presentation.

            The new-mail proof prints a harmless unique subject. Send one message
            with exactly that subject to the configured account, press Enter, and
            allow up to seven minutes. PASS proves mbsync delivery plus automatic
            notmuch indexing without a browser restart.
            """
        ),
        "label": "Copy full and new-mail validation",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh validate --full
            ./scripts/notmuch_browser_fresh_vm_setup.sh prove-new-mail-indexing
            """
        ),
    },
    {
        "title": "9. Open the Windows 11 SSH tunnel",
        "body": clean(
            """
            On antiX, enable and verify SSH, run hostname -I, and confirm the
            browser listens only on 127.0.0.1:8765. In Windows PowerShell replace
            the user and VM address, keep the window open, and browse to
            http://127.0.0.1:8765/.

            Manually check source selection, newest-first rows, nonoverlapping
            dates, the fixed sidebar while scrolling, address links/copy feedback,
            Readable/Original/plain modes, attachments/ZIP, image confirmations,
            narrow layout, and status.
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
        "title": "10. Prove reboot recovery",
        "body": clean(
            """
            Reboot antiX, log back into IceWM, wait one minute, and run the
            post-reboot command. It refuses to pass until the boot ID differs from
            the guided-install completion boot. It then repeats full browser,
            index, source, fixture, and mbsync-loop validation.
            """
        ),
        "label": "Copy post-reboot validation",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh validate --post-reboot
            """
        ),
    },
    {
        "title": "11. Safe release updates",
        "body": clean(
            """
            Updates remain explicit and release-pinned. The main clone is pulled
            only for current documentation and installer logic. The update command
            fetches the requested approved tag, builds that exact tag in an
            isolated release source, backs up installed files and the install
            marker, stops only the two supervised services, installs, validates,
            and restores the prior version automatically on failure.

            Replace the example tag only when the guide names a newer approved
            release. Never run go get -u, bun update, or an untagged update.
            """
        ),
        "label": "Copy safe release update",
        "language": "sh",
        "code": clean(
            f"""
            set -eu
            cd "$HOME/codex_antix"
            git pull --ff-only origin main
            ./scripts/notmuch_browser_fresh_vm_setup.sh update \\
              --release {RELEASE_TAG}
            """
        ),
    },
    {
        "title": "12. Troubleshooting and completion",
        "body": clean(
            """
            Run status first. Never delete local-maildir, an active lock, setup
            state, a backup, or a partial first index. The verified Maildir is the
            irreplaceable source; the notmuch database is a resumable sidecar.
            support-report writes a private credential-free report and prints its
            SHA256. Share only that reviewed report, never raw configs or mail.

            Complete means: recovery archives verified; 48,720 historical and 247
            delta paths plus all dynamic/fixture paths indexed; exactly one ignore
            value; six GUI sources; individual newest-first results; the complete
            local date contract; accepted sidebar/address/attachment/image
            behavior; localhost-only 8765; full validation; automatic new-mail
            indexing; antiX and Windows GUI PASS; and changed-boot recovery PASS.
            """
        ),
        "label": "Copy safe support report",
        "language": "sh",
        "code": clean(
            r"""
            set -eu
            cd "$HOME/codex_antix"
            ./scripts/notmuch_browser_fresh_vm_setup.sh status
            ./scripts/notmuch_browser_fresh_vm_setup.sh support-report
            """
        ),
    },
]


def render_text() -> str:
    parts = [
        "# NOTMUCH GO BROWSER SERVICE - One-Command Fresh antiX Guide",
        "",
        "Updated: 2026-07-28",
        "Target: antiX Linux runit edition with zzzFM/IceWM on Windows 11 VMware",
        f"Stable application release: {RELEASE_TAG}",
        f"Release status: {RELEASE_STATUS}",
        "",
        "Follow the sections in order and stop whenever a check reports failure.",
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
          <title>One-Command Fresh antiX Notmuch Browser Guide</title>
          <style>
            :root {{ color-scheme:light; --ink:#172033; --muted:#556176;
              --line:#cfdbe7; --blue:#126782; --green:#276749; --amber:#945d0b;
              --code:#111827; }}
            * {{ box-sizing:border-box; }}
            body {{ margin:0; color:var(--ink); background:#eef5f8;
              font:16px/1.58 system-ui,-apple-system,"Segoe UI",sans-serif; }}
            header,main,footer {{ width:min(1080px,calc(100% - 28px)); margin:auto; }}
            header {{ padding:40px 0 22px; }}
            h1 {{ margin:0 0 10px; font-size:clamp(1.8rem,4vw,3rem); line-height:1.08; }}
            .lede {{ max-width:78ch; color:var(--muted); }}
            .notice {{ border-left:5px solid var(--amber); background:#fff8e8;
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
            <h1>One-Command Fresh antiX Setup</h1>
            <p class="lede">Release-pinned, resumable reconstruction of the full
            Go/chi/templ/HTMX/Tailwind notmuch browser and verified private mail
            recovery set.</p>
            <p class="notice"><strong>Release status:</strong>
            {html.escape(RELEASE_STATUS)} Do not bypass a failed tag, recovery,
            disk, index, service, or reboot check.</p>
            <p><strong>Updated:</strong> 2026-07-28</p>
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
