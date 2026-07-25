#!/usr/bin/env python3
"""Validate production attachment/image capabilities without mutating mail state."""

import base64
import hashlib
from html.parser import HTMLParser
import html
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile


MAX_SMALL = 128 * 1024 * 1024
MAX_ZIP = 2 * 1024 * 1024 * 1024 + 1024
NOTMUCH_CONFIG = os.environ.get(
    "NOTMUCH_CONFIG",
    "/home/atiq/.config/notmuch/default/config",
)


class Collector(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.urls = []
        self.srcdocs = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        for key in ("href", "src"):
            value = values.get(key)
            if value:
                self.urls.append(value)
        if tag == "iframe" and values.get("srcdoc"):
            self.srcdocs.append(values["srcdoc"])


def request_bytes(base, path, headers=None, method="GET", limit=MAX_SMALL):
    url = urllib.parse.urljoin(base, path)
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "notmuch-browser-strict-validator", **(headers or {})},
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            body = response.read(limit + 1)
            if len(body) > limit:
                raise RuntimeError(f"response exceeded validation limit: {url}")
            return response.status, response.headers, body
    except urllib.error.HTTPError as exc:
        return exc.code, exc.headers, exc.read(1024 * 1024)


def request_file(base, path, destination):
    url = urllib.parse.urljoin(base, path)
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "notmuch-browser-strict-validator"},
    )
    try:
        with urllib.request.urlopen(request, timeout=900) as response:
            total = 0
            digest = hashlib.sha256()
            with destination.open("wb") as handle:
                os.chmod(destination, 0o600)
                while True:
                    block = response.read(1024 * 1024)
                    if not block:
                        break
                    total += len(block)
                    if total > MAX_ZIP:
                        raise RuntimeError("ZIP exceeded configured validation limit")
                    digest.update(block)
                    handle.write(block)
            return response.status, response.headers, total, digest.hexdigest()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.headers, 0, ""


def parse_page(raw):
    text = raw.decode("utf-8", "replace")
    parser = Collector()
    parser.feed(text)
    urls = list(parser.urls)
    srcdocs = []
    for value in parser.srcdocs:
        for _ in range(3):
            value = html.unescape(value)
        srcdocs.append(value)
        srcdoc_parser = Collector()
        srcdoc_parser.feed(value)
        urls.extend(srcdoc_parser.urls)
    return text, urls, srcdocs


def capability_payload(base, url):
    full = urllib.parse.urljoin(base, url)
    query = urllib.parse.parse_qs(urllib.parse.urlsplit(full).query)
    token = query.get("cap", [""])[0]
    encoded = token.split(".", 1)[0]
    if not encoded:
        raise RuntimeError("capability token missing")
    encoded += "=" * (-len(encoded) % 4)
    return json.loads(base64.urlsafe_b64decode(encoded))


def capability_urls(base, urls, purpose, duplicate, part=None):
    matches = []
    for url in urls:
        try:
            payload = capability_payload(base, url)
        except Exception:
            continue
        if payload.get("p") != purpose or payload.get("d") != duplicate:
            continue
        if part is not None and payload.get("n") != part:
            continue
        matches.append(url)
    return list(dict.fromkeys(matches))


def attachment_parts(base, urls, duplicate):
    parts = {}
    for url in urls:
        try:
            payload = capability_payload(base, url)
        except Exception:
            continue
        if payload.get("p") != "attachment" or payload.get("d") != duplicate:
            continue
        part = payload.get("n")
        if not isinstance(part, int):
            continue
        parts.setdefault(part, []).append(url)
    return {part: list(dict.fromkeys(matches)) for part, matches in parts.items()}


def direct_part(message_id, duplicate, part):
    result = subprocess.run(
        [
            "/usr/bin/notmuch",
            f"--config={NOTMUCH_CONFIG}",
            "show",
            "--format=raw",
            f"--part={part}",
            f"--duplicate={duplicate}",
            "--decrypt=false",
            "id:" + message_id,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "direct notmuch part failed: "
            + result.stderr.decode("utf-8", "replace")[:500]
        )
    return result.stdout


def assert_csp(srcdocs, expected):
    if not srcdocs:
        raise RuntimeError("sandboxed iframe srcdoc missing")
    combined = "\n".join(srcdocs)
    if expected not in combined:
        raise RuntimeError(f"expected iframe CSP fragment missing: {expected}")


def tamper_url(base, url):
    full = urllib.parse.urljoin(base, url)
    parts = urllib.parse.urlsplit(full)
    query = urllib.parse.parse_qs(parts.query)
    token = query["cap"][0]
    replacement = "A" if token[-1] != "A" else "B"
    query["cap"] = [token[:-1] + replacement]
    return urllib.parse.urlunsplit(
        (
            parts.scheme,
            parts.netloc,
            parts.path,
            urllib.parse.urlencode(query, doseq=True),
            "",
        )
    )


def inspect_zip(path, expected_attachment_hash):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("ZIP CRC validation failed")
        entries = archive.infolist()
        if not entries:
            raise RuntimeError("ZIP contained no attachments")

        lowered = []
        hashes = []
        decoded_bytes = 0

        for entry in entries:
            name = entry.filename
            pure = PurePosixPath(name)
            if pure.is_absolute() or ".." in pure.parts or len(pure.parts) != 1:
                raise RuntimeError("unsafe ZIP entry path")
            lowered.append(name.lower())

            if entry.compress_type != zipfile.ZIP_STORED:
                raise RuntimeError("ZIP entry did not use Store mode")

            digest = hashlib.sha256()
            with archive.open(entry) as source:
                while True:
                    block = source.read(1024 * 1024)
                    if not block:
                        break
                    decoded_bytes += len(block)
                    digest.update(block)
            hashes.append(digest.hexdigest())

        if len(lowered) != len(set(lowered)):
            raise RuntimeError("ZIP entry names collide case-insensitively")
        if expected_attachment_hash not in hashes:
            raise RuntimeError("ZIP did not contain the selected decoded attachment")

        return len(entries), decoded_bytes


def main():
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: notmuch_browser_strict_validator.py BASE AUDIT_PATH RUN_DIR"
        )

    base = sys.argv[1]
    audit_path = Path(sys.argv[2])
    run_dir = Path(sys.argv[3])

    with audit_path.open(encoding="utf-8") as handle:
        audit = json.load(handle)

    probe = audit["raw_part_probe"]
    candidate = probe["candidate"]
    message_id = candidate["message_id"]
    inline_part = int(candidate["part"])
    inline_expected_bytes = int(probe["bytes"])
    inline_expected_hash = probe["sha256"]

    if candidate.get("file_count", 0) < 2:
        raise SystemExit("selected production sample has no duplicate 2")

    message_id_hash = hashlib.sha256(
        message_id.encode("utf-8", "surrogateescape")
    ).hexdigest()[:16]
    query0 = urllib.parse.urlencode({"id": message_id})
    query1 = urllib.parse.urlencode({"id": message_id, "dup": 1})

    status, _, blocked_raw = request_bytes(base, "/message?" + query0)
    if status != 200:
        raise RuntimeError(f"blocked message request returned {status}")
    blocked_text, blocked_urls, blocked_srcdocs = parse_page(blocked_raw)

    for marker in (
        "Images blocked",
        "Duplicate file selection",
        "Attachments",
        "Save All",
        "No external server will be contacted",
    ):
        if marker not in blocked_text:
            raise RuntimeError(f"blocked message marker missing: {marker}")
    assert_csp(blocked_srcdocs, "img-src 'none'")
    if "about:blank#blocked-image" not in "\n".join(blocked_srcdocs):
        raise RuntimeError("CID image was not blocked in initial mode")

    status, _, duplicate_raw = request_bytes(base, "/message?" + query1)
    if status != 200:
        raise RuntimeError(f"duplicate 2 message returned {status}")
    duplicate_text, duplicate_urls, duplicate_srcdocs = parse_page(duplicate_raw)

    if "from duplicate 2" not in duplicate_text:
        raise RuntimeError("duplicate 2 attachment marker missing")
    if "Images blocked" not in duplicate_text:
        raise RuntimeError("duplicate switch did not reset images")
    assert_csp(duplicate_srcdocs, "img-src 'none'")

    attachment_parts0 = attachment_parts(base, blocked_urls, 0)
    attachment_parts1 = attachment_parts(base, duplicate_urls, 1)
    common_parts = sorted(set(attachment_parts0) & set(attachment_parts1))
    if not common_parts:
        raise RuntimeError("duplicates had no common genuine attachment part")
    attachment_part = common_parts[0]

    attachment0 = attachment_parts0[attachment_part]
    attachment1 = attachment_parts1[attachment_part]
    archive0 = capability_urls(base, blocked_urls, "attachments-zip", 0)
    archive1 = capability_urls(base, duplicate_urls, "attachments-zip", 1)
    if any(len(matches) != 1 for matches in (attachment0, attachment1, archive0, archive1)):
        raise RuntimeError("selected attachment/archive capabilities were not unique")

    direct_attachment0 = direct_part(message_id, 1, attachment_part)
    direct_attachment1 = direct_part(message_id, 2, attachment_part)
    attachment_hash0 = hashlib.sha256(direct_attachment0).hexdigest()
    attachment_hash1 = hashlib.sha256(direct_attachment1).hexdigest()

    status, attachment_headers0, downloaded0 = request_bytes(base, attachment0[0])
    if status != 200:
        raise RuntimeError(f"attachment duplicate 1 returned {status}")
    if downloaded0 != direct_attachment0:
        raise RuntimeError("attachment duplicate 1 differs from direct notmuch bytes")
    if "attachment" not in attachment_headers0.get("Content-Disposition", "").lower():
        raise RuntimeError("attachment disposition missing")

    wrong_purpose = urllib.parse.urlsplit(urllib.parse.urljoin(base, attachment0[0]))
    wrong_inline = urllib.parse.urlunsplit(
        (
            wrong_purpose.scheme,
            wrong_purpose.netloc,
            "/inline-image",
            wrong_purpose.query,
            "",
        )
    )
    if request_bytes(base, tamper_url(base, attachment0[0]))[0] != 403:
        raise RuntimeError("tampered capability was not rejected")
    if request_bytes(base, wrong_inline)[0] != 403:
        raise RuntimeError("wrong-purpose capability was not rejected")

    status, _, downloaded1 = request_bytes(base, attachment1[0])
    if status != 200:
        raise RuntimeError(f"attachment duplicate 2 returned {status}")
    if downloaded1 != direct_attachment1:
        raise RuntimeError("attachment duplicate 2 differs from direct notmuch bytes")

    status, _, embedded_raw = request_bytes(
        base,
        "/message?" + query0 + "&images=embedded",
        headers={"HX-Request": "true"},
    )
    if status != 200:
        raise RuntimeError(f"embedded mode returned {status}")
    embedded_text, embedded_urls, embedded_srcdocs = parse_page(embedded_raw)

    if "Embedded images shown" not in embedded_text:
        raise RuntimeError("embedded mode marker missing")
    if "Remote servers may learn your IP address" not in embedded_text:
        raise RuntimeError("remote-image warning missing")
    assert_csp(embedded_srcdocs, "img-src http://127.0.0.1:8765 data:")

    inline0 = capability_urls(
        base,
        embedded_urls,
        "inline-image",
        0,
        inline_part,
    )
    if len(inline0) != 1:
        raise RuntimeError("selected inline-image capability was not unique")

    direct_inline0 = direct_part(message_id, 1, inline_part)
    if (
        len(direct_inline0) != inline_expected_bytes
        or hashlib.sha256(direct_inline0).hexdigest() != inline_expected_hash
    ):
        raise RuntimeError("direct inline part differs from audit baseline")

    status, inline_headers, inline_bytes = request_bytes(base, inline0[0])
    if status != 200:
        raise RuntimeError(f"inline image returned {status}")
    if inline_bytes != direct_inline0:
        raise RuntimeError("inline image differs from direct notmuch bytes")
    if not inline_headers.get("Content-Type", "").startswith("image/png"):
        raise RuntimeError("inline image content type is not PNG")
    if "inline" not in inline_headers.get("Content-Disposition", "").lower():
        raise RuntimeError("inline image disposition missing")

    status, _, remote_raw = request_bytes(
        base,
        "/message?" + query0 + "&images=remote",
        headers={"HX-Request": "true"},
    )
    if status != 200:
        raise RuntimeError(f"remote mode returned {status}")
    remote_text, _, remote_srcdocs = parse_page(remote_raw)
    if "Remote images allowed" not in remote_text:
        raise RuntimeError("remote mode marker missing")
    assert_csp(
        remote_srcdocs,
        "img-src http://127.0.0.1:8765 data: http: https:",
    )

    status, _, forced_full_raw = request_bytes(
        base,
        "/message?" + query0 + "&images=remote",
    )
    if status != 200:
        raise RuntimeError("full-page image reset request failed")
    forced_text, _, forced_srcdocs = parse_page(forced_full_raw)
    if "Images blocked" not in forced_text or "Remote images allowed" in forced_text:
        raise RuntimeError("full-page request did not reset image permission")
    assert_csp(forced_srcdocs, "img-src 'none'")

    with tempfile.TemporaryDirectory(dir=run_dir, prefix="client-download-") as temp:
        os.chmod(temp, 0o700)
        zip0 = Path(temp) / "duplicate-1.zip"
        zip1 = Path(temp) / "duplicate-2.zip"

        status0, zip_headers0, zip_bytes0, zip_hash0 = request_file(
            base,
            archive0[0],
            zip0,
        )
        status1, zip_headers1, zip_bytes1, zip_hash1 = request_file(
            base,
            archive1[0],
            zip1,
        )
        if status0 != 200 or status1 != 200:
            raise RuntimeError(
                f"ZIP status mismatch: duplicate1={status0}, duplicate2={status1}"
            )
        if not zip_headers0.get("Content-Type", "").startswith("application/zip"):
            raise RuntimeError("duplicate 1 ZIP content type missing")
        if not zip_headers1.get("Content-Type", "").startswith("application/zip"):
            raise RuntimeError("duplicate 2 ZIP content type missing")

        zip0_entries, zip0_decoded = inspect_zip(zip0, attachment_hash0)
        zip1_entries, zip1_decoded = inspect_zip(zip1, attachment_hash1)

    print(f"message_id_hash={message_id_hash}")
    print(f"selected_attachment_part={attachment_part}")
    print(f"selected_inline_part={inline_part}")
    print(f"selected_duplicate_files={candidate.get('file_count')}")
    print(f"attachment_duplicate_1_bytes={len(downloaded0)}")
    print(f"attachment_duplicate_1_sha256={attachment_hash0}")
    print(f"attachment_duplicate_2_bytes={len(downloaded1)}")
    print(f"attachment_duplicate_2_sha256={attachment_hash1}")
    print(f"inline_image_bytes={len(inline_bytes)}")
    print(f"inline_image_sha256={inline_expected_hash}")
    print("duplicate_1_exact_bytes=verified")
    print("duplicate_2_exact_bytes=verified")
    print("tampered_capability_http=403")
    print("wrong_purpose_capability_http=403")
    print("blocked_csp=verified")
    print("embedded_csp=verified")
    print("remote_csp=verified")
    print("full_page_permission_reset=verified")
    print("inline_image_exact_bytes=verified")
    print(f"zip_duplicate_1_entries={zip0_entries}")
    print(f"zip_duplicate_1_bytes={zip_bytes0}")
    print(f"zip_duplicate_1_decoded_bytes={zip0_decoded}")
    print(f"zip_duplicate_1_sha256={zip_hash0}")
    print(f"zip_duplicate_2_entries={zip1_entries}")
    print(f"zip_duplicate_2_bytes={zip_bytes1}")
    print(f"zip_duplicate_2_decoded_bytes={zip1_decoded}")
    print(f"zip_duplicate_2_sha256={zip_hash1}")
    print("zip_integrity_store_names_and_selected_attachment=verified")
    print("status=python_capability_validation_complete")


if __name__ == "__main__":
    main()
