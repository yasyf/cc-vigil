#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unicodedata
from urllib.parse import quote
import zipfile


REPOSITORY = "yasyf/cc-vigil"
TEAM_ID = "SXKCTF23Q2"
TEMPLATE_PATH = ".github/cask/cc-vigil.rb.tmpl"
SEMVER_RE = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce",
    b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf",
    b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe",
    b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xba\xbf",
    b"\xbf\xba\xfe\xca",
}
EXPECTED_MACHOS = {
    "Contents/MacOS/CCVigil",
    "Contents/Library/LaunchAgents/CCVigilDaemon",
    "Contents/Library/LaunchDaemons/CCVigilHelper",
    "Contents/Helpers/cc-vigil",
}
MAX_ENTRIES = 4096
MAX_EXPANDED_BYTES = 512 * 1024 * 1024


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def required_env(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        fail(f"{name} is required")
    return value


def gh_bytes(*args: str) -> bytes:
    result = subprocess.run(
        ["gh", "api", *args], check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        fail(f"GitHub API request failed: {detail}")
    return result.stdout


def gh_json(endpoint: str) -> object:
    raw = gh_bytes(endpoint)
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"GitHub API returned invalid JSON for {endpoint}: {exc}")


def validate_release(value: object, release_id: int, tag: str, label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        fail(f"{label} release response is not an object")
    if value.get("id") != release_id:
        fail(f"{label} release ID does not equal {release_id}")
    if value.get("tag_name") != tag:
        fail(f"{label} release tag does not equal {tag!r}")
    if value.get("draft") is not False:
        fail(f"release {release_id} is not public")
    if value.get("prerelease") is not False:
        fail(f"release {release_id} is a prerelease")
    node_id = value.get("node_id")
    if not isinstance(node_id, str) or not node_id:
        fail(f"{label} release has no immutable node ID")
    return value


def peel_tag(tag: str) -> str:
    ref = gh_json(f"repos/{REPOSITORY}/git/ref/tags/{quote(tag, safe='')}")
    if not isinstance(ref, dict) or not isinstance(ref.get("object"), dict):
        fail(f"tag ref {tag!r} is malformed")
    current = ref["object"]
    seen: set[str] = set()
    for _ in range(16):
        object_type = current.get("type")
        object_sha = current.get("sha")
        if not isinstance(object_sha, str) or not SHA_RE.fullmatch(object_sha):
            fail(f"tag {tag!r} contains an invalid Git object SHA")
        if object_type == "commit":
            return object_sha
        if object_type != "tag":
            fail(f"tag {tag!r} resolves to unsupported Git object type {object_type!r}")
        if object_sha in seen:
            fail(f"tag {tag!r} contains an annotated-tag cycle")
        seen.add(object_sha)
        annotated = gh_json(f"repos/{REPOSITORY}/git/tags/{object_sha}")
        if not isinstance(annotated, dict) or not isinstance(annotated.get("object"), dict):
            fail(f"annotated tag object {object_sha} is malformed")
        current = annotated["object"]
    fail(f"tag {tag!r} exceeds the annotated-tag peel limit")


def release_assets(
    release: dict[str, object], expected_sha: dict[str, str]
) -> dict[str, dict[str, object]]:
    rows = release.get("assets")
    if not isinstance(rows, list):
        fail("public release assets are malformed")
    result: dict[str, dict[str, object]] = {}
    for row in rows:
        if not isinstance(row, dict):
            fail("public release contains a malformed asset")
        name = row.get("name")
        if not isinstance(name, str) or name in result:
            fail(f"public release contains an invalid or duplicate asset name: {name!r}")
        result[name] = row
    if set(result) != set(expected_sha):
        missing = sorted(set(expected_sha) - set(result))
        extra = sorted(set(result) - set(expected_sha))
        fail(f"public asset set is not exact; missing={missing}, extra={extra}")
    for name, row in result.items():
        asset_id = row.get("id")
        size = row.get("size")
        if not isinstance(asset_id, int) or asset_id <= 0:
            fail(f"public release asset {name!r} has an invalid ID")
        if not isinstance(size, int) or size <= 0:
            fail(f"public release asset {name!r} has an invalid size")
        if row.get("state") != "uploaded":
            fail(f"public release asset {name!r} is not uploaded")
        if row.get("digest") != f"sha256:{expected_sha[name]}":
            fail(f"public release asset {name!r} does not have the exact GitHub digest")
    return result


def download_assets(
    rows: dict[str, dict[str, object]], expected_sha: dict[str, str], destination: Path
) -> None:
    destination.mkdir()
    for name in sorted(rows):
        payload = gh_bytes(
            "-H",
            "Accept: application/octet-stream",
            f"repos/{REPOSITORY}/releases/assets/{rows[name]['id']}",
        )
        if len(payload) != rows[name]["size"]:
            fail(f"downloaded asset {name!r} has the wrong size")
        actual = hashlib.sha256(payload).hexdigest()
        if actual != expected_sha[name]:
            fail(f"downloaded asset {name!r} has SHA-256 {actual}, expected {expected_sha[name]}")
        (destination / name).write_bytes(payload)


def verify_sidecar(sidecar: Path, zip_name: str, zip_sha: str) -> None:
    try:
        content = sidecar.read_text(encoding="ascii")
    except UnicodeDecodeError as exc:
        fail(f"checksum sidecar is not ASCII: {exc}")
    expected = f"{zip_sha}  {zip_name}\n"
    if content != expected:
        fail("checksum sidecar does not exactly bind the app archive basename and SHA-256")


def safe_extract_zip(archive: Path, destination: Path) -> Path:
    destination.mkdir()
    seen: set[PurePosixPath] = set()
    seen_platform_paths: set[str] = set()
    expanded = 0
    try:
        bundle = zipfile.ZipFile(archive)
    except (zipfile.BadZipFile, OSError) as exc:
        fail(f"app archive is not a valid zip: {exc}")
    with bundle:
        entries = bundle.infolist()
        if not entries or len(entries) > MAX_ENTRIES:
            fail("app archive has an invalid entry count")
        for entry in entries:
            raw_name = entry.filename[:-1] if entry.is_dir() and entry.filename.endswith("/") else entry.filename
            parts = raw_name.split("/")
            if (
                not raw_name
                or raw_name.startswith("/")
                or "\\" in raw_name
                or any(part in ("", ".", "..") for part in parts)
            ):
                fail(f"app archive contains unsafe path {entry.filename!r}")
            relative = PurePosixPath(*parts)
            if relative.parts[0] != "CCVigil.app":
                fail(f"app archive contains a second top-level object: {entry.filename!r}")
            if relative in seen:
                fail(f"app archive repeats path {entry.filename!r}")
            seen.add(relative)
            platform_path = unicodedata.normalize("NFD", relative.as_posix()).casefold()
            if platform_path in seen_platform_paths:
                fail(f"app archive contains platform-aliased path {entry.filename!r}")
            seen_platform_paths.add(platform_path)
            mode = entry.external_attr >> 16
            if entry.flag_bits & 1:
                fail(f"app archive contains encrypted entry {entry.filename!r}")
            if entry.is_dir():
                if mode and not stat.S_ISDIR(mode):
                    fail(f"app archive directory has an invalid file type: {entry.filename!r}")
                (destination / Path(*relative.parts)).mkdir(parents=True, exist_ok=True)
                continue
            if mode and not stat.S_ISREG(mode):
                fail(f"app archive contains non-regular entry {entry.filename!r}")
            expanded += entry.file_size
            if expanded > MAX_EXPANDED_BYTES:
                fail("app archive exceeds the expanded-size limit")
            target = destination / Path(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            with bundle.open(entry) as source, target.open("xb") as handle:
                shutil.copyfileobj(source, handle)
            os.chmod(target, mode & 0o777 if mode else 0o644)
    app = destination / "CCVigil.app"
    if not app.is_dir() or list(destination.iterdir()) != [app]:
        fail("app archive must contain exactly one CCVigil.app bundle")
    return app


def command(*args: str) -> str:
    result = subprocess.run(args, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        detail = (result.stdout + result.stderr).strip()
        fail(f"command {' '.join(args[:3])} failed: {detail}")
    return result.stdout + result.stderr


def is_macho(path: Path) -> bool:
    with path.open("rb") as handle:
        return handle.read(4) in MACHO_MAGICS


def verify_macho(path: Path) -> None:
    command("codesign", "--verify", "--strict", "--verbose=4", str(path))
    details = command("codesign", "-d", "--verbose=4", str(path))
    if not re.search(rf"^TeamIdentifier={TEAM_ID}$", details, re.MULTILINE):
        fail(f"Mach-O {path.name!r} is not signed by TeamIdentifier {TEAM_ID}")
    authorities = re.findall(r"^Authority=(.+)$", details, re.MULTILINE)
    if not any(value.startswith("Developer ID Application:") and f"({TEAM_ID})" in value for value in authorities):
        fail(f"Mach-O {path.name!r} has no Developer ID Application authority for {TEAM_ID}")
    if not re.search(r"\bflags=.*\bruntime\b", details):
        fail(f"Mach-O {path.name!r} does not enable hardened runtime")
    arches = command("lipo", "-archs", str(path)).strip().split()
    if arches != ["arm64"]:
        fail(f"Mach-O {path.name!r} architectures {arches} do not equal ['arm64']")


def verify_app(app: Path, version: str) -> None:
    files = [path for path in app.rglob("*") if path.is_file()]
    macho_paths = {path.relative_to(app).as_posix() for path in files if is_macho(path)}
    if macho_paths != EXPECTED_MACHOS:
        fail(
            "app bundle Mach-O set is not exact; "
            f"missing={sorted(EXPECTED_MACHOS - macho_paths)}, extra={sorted(macho_paths - EXPECTED_MACHOS)}"
        )
    for path in files:
        relative = path.relative_to(app).as_posix()
        if relative not in macho_paths and path.stat().st_mode & 0o111:
            fail(f"app bundle contains executable non-Mach-O file {relative!r}")
    for relative in sorted(macho_paths):
        verify_macho(app / relative)
    command("codesign", "--verify", "--deep", "--strict", "--verbose=4", str(app))
    command("xcrun", "stapler", "validate", str(app))
    command("spctl", "--assess", "--type", "execute", "--verbose=4", str(app))
    actual_version = command(
        "plutil", "-extract", "CFBundleShortVersionString", "raw", "-o", "-", str(app / "Contents/Info.plist")
    ).strip()
    if actual_version != version:
        fail(f"app bundle version {actual_version!r} does not equal release version {version!r}")


def fetch_template(source_sha: str, destination: Path) -> None:
    payload = gh_bytes(
        "--method",
        "GET",
        "-H",
        "Accept: application/vnd.github.raw+json",
        f"repos/{REPOSITORY}/contents/{TEMPLATE_PATH}",
        "-f",
        f"ref={source_sha}",
    )
    if not payload:
        fail("tagged cask template is empty")
    destination.write_bytes(payload)


def render_cask(template: Path, output: Path, version: str, zip_sha: str) -> None:
    try:
        content = template.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        fail(f"tagged cask template is not UTF-8: {exc}")
    if content.count("__VERSION__") != 1 or content.count("__SHA_APP__") != 1:
        fail("tagged cask template does not contain the exact placeholder set")
    content = content.replace("__VERSION__", version).replace("__SHA_APP__", zip_sha)
    if re.search(r"__[A-Z0-9_]+__", content):
        fail("rendered cask contains an unresolved placeholder")
    expected_url = (
        f'url "https://github.com/yasyf/cc-vigil/releases/download/v#{{version}}/'
        f'cc-vigil-v#{{version}}-darwin.zip"'
    )
    if expected_url not in content:
        fail("tagged cask template does not bind the cc-vigil public release archive")
    output.parent.mkdir(parents=True)
    output.write_text(content, encoding="utf-8")
    command("ruby", "-c", str(output))


def main() -> None:
    release_id_raw = required_env("RELEASE_ID")
    tag = required_env("RELEASE_TAG")
    source_sha = required_env("TAGGED_SOURCE_SHA")
    zip_sha = required_env("ZIP_SHA256")
    sidecar_sha = required_env("SIDECAR_SHA256")
    if not re.fullmatch(r"[1-9][0-9]*", release_id_raw):
        fail("release-id must be a positive decimal integer")
    release_id = int(release_id_raw)
    if not SEMVER_RE.fullmatch(tag):
        fail("tag must be an exact stable v-prefixed SemVer tag")
    if not SHA_RE.fullmatch(source_sha):
        fail("tagged-source-sha must be a lowercase 40-character commit SHA")
    if not SHA256_RE.fullmatch(zip_sha) or not SHA256_RE.fullmatch(sidecar_sha):
        fail("asset SHA-256 inputs must be lowercase 64-character values")

    version = tag[1:]
    zip_name = f"cc-vigil-{tag}-darwin.zip"
    sidecar_name = f"{zip_name}.sha256"
    expected_sha = {zip_name: zip_sha, sidecar_name: sidecar_sha}
    by_id = validate_release(
        gh_json(f"repos/{REPOSITORY}/releases/{release_id}"), release_id, tag, "ID-selected"
    )
    by_tag = validate_release(
        gh_json(f"repos/{REPOSITORY}/releases/tags/{quote(tag, safe='')}"),
        release_id,
        tag,
        "tag-selected",
    )
    if by_id["node_id"] != by_tag["node_id"]:
        fail("release ID and tag do not select the same public release object")
    rows = release_assets(by_id, expected_sha)
    peeled_sha = peel_tag(tag)
    if peeled_sha != source_sha:
        fail(f"tag {tag!r} peels to {peeled_sha}, expected {source_sha}")

    work = Path(tempfile.mkdtemp(prefix="cc-vigil-public-tap-", dir=os.environ.get("RUNNER_TEMP")))
    assets = work / "assets"
    download_assets(rows, expected_sha, assets)
    verify_sidecar(assets / sidecar_name, zip_name, zip_sha)
    app = safe_extract_zip(assets / zip_name, work / "unpacked")
    verify_app(app, version)
    template = work / "cc-vigil.rb.tmpl"
    fetch_template(source_sha, template)
    staging = work / "tap-staging"
    output = staging / "Casks/cc-vigil.rb"
    render_cask(template, output, version, zip_sha)
    files = [path for path in staging.rglob("*") if path.is_file()]
    if files != [output]:
        fail("tap staging must contain exactly one rendered cask")

    with open(required_env("GITHUB_OUTPUT"), "a", encoding="utf-8") as handle:
        handle.write(f"staging-dir={staging}\n")
        handle.write("file=Casks/cc-vigil.rb\n")
        handle.write(f"message=cc-vigil {tag}\n")
    print(f"verified public release {release_id} ({tag}) at {source_sha}")


if __name__ == "__main__":
    main()
