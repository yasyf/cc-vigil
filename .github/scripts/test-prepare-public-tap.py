#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import io
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock
import zipfile


SCRIPT_DIR = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("prepare_public_tap", SCRIPT_DIR / "prepare-public-tap.py")
assert SPEC is not None and SPEC.loader is not None
delivery = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(delivery)

SHA_A = "a" * 64
SHA_B = "b" * 64


class FailureAssertions(unittest.TestCase):
    def assert_fails(self, expected: str, function, *args, **kwargs) -> None:
        with self.assertRaises(SystemExit), mock.patch("sys.stderr", new=io.StringIO()) as stderr:
            function(*args, **kwargs)
        self.assertIn(expected, stderr.getvalue())


class ReleaseContractTests(FailureAssertions):
    def release(self) -> dict[str, object]:
        return {
            "id": 41,
            "tag_name": "v0.8.1",
            "draft": False,
            "prerelease": False,
            "node_id": "release-node",
        }

    def test_release_identity_is_exact_public_and_immutable(self) -> None:
        value = self.release()
        self.assertEqual(delivery.validate_release(value, 41, "v0.8.1", "test"), value)
        for field, replacement in (
            ("id", 42),
            ("tag_name", "v0.8.2"),
            ("draft", True),
            ("prerelease", True),
            ("node_id", ""),
        ):
            changed = self.release()
            changed[field] = replacement
            self.assert_fails("release", delivery.validate_release, changed, 41, "v0.8.1", "test")

    def test_release_assets_require_exact_set_digest_state_and_size(self) -> None:
        expected = {"app.zip": SHA_A, "app.zip.sha256": SHA_B}
        release = self.release()
        release["assets"] = [
            {"name": name, "id": index, "size": 1, "state": "uploaded", "digest": f"sha256:{sha}"}
            for index, (name, sha) in enumerate(expected.items(), start=1)
        ]
        self.assertEqual(set(delivery.release_assets(release, expected)), set(expected))
        release["assets"].append(
            {"name": "extra", "id": 3, "size": 1, "state": "uploaded", "digest": f"sha256:{SHA_A}"}
        )
        self.assert_fails("asset set is not exact", delivery.release_assets, release, expected)
        release["assets"] = [
            {"name": name, "id": index, "size": 1, "state": "new", "digest": f"sha256:{sha}"}
            for index, (name, sha) in enumerate(expected.items(), start=1)
        ]
        self.assert_fails("is not uploaded", delivery.release_assets, release, expected)

    def test_download_is_bound_to_asset_id_size_and_sha(self) -> None:
        payload = b"immutable"
        sha = hashlib.sha256(payload).hexdigest()
        rows = {"app.zip": {"id": 91, "size": len(payload)}}
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            with mock.patch.object(delivery, "gh_bytes", return_value=payload) as gh:
                delivery.download_assets(rows, {"app.zip": sha}, root / "assets")
            gh.assert_called_once_with(
                "-H", "Accept: application/octet-stream", "repos/yasyf/cc-vigil/releases/assets/91"
            )
            self.assertEqual((root / "assets/app.zip").read_bytes(), payload)
        with tempfile.TemporaryDirectory() as raw, mock.patch.object(delivery, "gh_bytes", return_value=b"wrong"):
            self.assert_fails(
                "wrong size", delivery.download_assets, rows, {"app.zip": sha}, Path(raw) / "assets"
            )

    def test_sidecar_must_be_the_exact_single_basename_record(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            sidecar = Path(raw) / "app.zip.sha256"
            sidecar.write_text(f"{SHA_A}  app.zip\n", encoding="ascii")
            delivery.verify_sidecar(sidecar, "app.zip", SHA_A)
            sidecar.write_text(f"{SHA_A} *app.zip\n", encoding="ascii")
            self.assert_fails("does not exactly bind", delivery.verify_sidecar, sidecar, "app.zip", SHA_A)


class ZipContractTests(FailureAssertions):
    def make_zip(self, path: Path, entries: list[tuple[zipfile.ZipInfo, bytes]]) -> None:
        with zipfile.ZipFile(path, "w") as archive:
            for info, payload in entries:
                archive.writestr(info, payload)

    def regular(self, name: str, mode: int = 0o644) -> zipfile.ZipInfo:
        info = zipfile.ZipInfo(name)
        info.external_attr = (stat.S_IFREG | mode) << 16
        return info

    def test_zip_rejects_traversal_links_and_second_top_level(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            for name, expected in (
                ("../escape", "unsafe path"),
                ("Other.app/file", "second top-level"),
            ):
                archive = root / f"{len(name)}.zip"
                self.make_zip(archive, [(self.regular(name), b"x")])
                self.assert_fails(expected, delivery.safe_extract_zip, archive, root / f"out-{len(name)}")
            link = zipfile.ZipInfo("CCVigil.app/link")
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive = root / "link.zip"
            self.make_zip(archive, [(link, b"/tmp/escape")])
            self.assert_fails("non-regular", delivery.safe_extract_zip, archive, root / "out-link")

    def test_zip_rejects_casefolded_and_unicode_platform_aliases(self) -> None:
        for first, second in (("Payload", "payload"), ("caf\u00e9", "cafe\u0301")):
            with tempfile.TemporaryDirectory() as raw:
                root = Path(raw)
                archive = root / "alias.zip"
                self.make_zip(
                    archive,
                    [
                        (self.regular(f"CCVigil.app/{first}"), b"one"),
                        (self.regular(f"CCVigil.app/{second}"), b"two"),
                    ],
                )
                self.assert_fails("platform-aliased", delivery.safe_extract_zip, archive, root / "out")

    def test_zip_extracts_regular_bundle_without_aliasing(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            archive = root / "app.zip"
            self.make_zip(archive, [(self.regular("CCVigil.app/Contents/file"), b"body")])
            app = delivery.safe_extract_zip(archive, root / "out")
            self.assertEqual((app / "Contents/file").read_bytes(), b"body")


class SignatureContractTests(FailureAssertions):
    DETAILS = "\n".join(
        (
            "Authority=Developer ID Application: Example (SXKCTF23Q2)",
            "TeamIdentifier=SXKCTF23Q2",
            "CodeDirectory v=20500 size=123 flags=0x10000(runtime) hashes=2+7 location=embedded",
        )
    )

    def valid_command(self, *args: str) -> str:
        if args[:2] == ("codesign", "-d"):
            return self.DETAILS
        if args[0] == "lipo":
            return "arm64\n"
        return ""

    def test_macho_requires_team_authority_runtime_and_exact_arm64(self) -> None:
        with mock.patch.object(delivery, "command", side_effect=self.valid_command):
            delivery.verify_macho(Path("CCVigil"))
        with mock.patch.object(
            delivery,
            "command",
            side_effect=lambda *args: "x86_64 arm64\n" if args[0] == "lipo" else self.DETAILS,
        ):
            self.assert_fails("do not equal", delivery.verify_macho, Path("CCVigil"))
        with mock.patch.object(delivery, "command", return_value="arm64\n"):
            self.assert_fails("TeamIdentifier", delivery.verify_macho, Path("CCVigil"))

    def test_app_requires_the_exact_complete_macho_set(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            app = Path(raw) / "CCVigil.app"
            for relative in delivery.EXPECTED_MACHOS:
                path = app / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"\xcf\xfa\xed\xfe")
                path.chmod(0o755)
            plist = app / "Contents/Info.plist"
            plist.write_text("plist", encoding="utf-8")

            def command(*args: str) -> str:
                return "0.8.1\n" if args[0] == "plutil" else ""

            with mock.patch.object(delivery, "verify_macho") as verify, mock.patch.object(
                delivery, "command", side_effect=command
            ):
                delivery.verify_app(app, "0.8.1")
            self.assertEqual(verify.call_count, 4)
            extra = app / "Contents/Helpers/extra"
            extra.write_bytes(b"\xcf\xfa\xed\xfe")
            with mock.patch.object(delivery, "command", side_effect=command):
                self.assert_fails("Mach-O set is not exact", delivery.verify_app, app, "0.8.1")


class RenderContractTests(FailureAssertions):
    def test_tagged_template_renders_only_exact_version_and_archive_sha(self) -> None:
        template = Path(__file__).resolve().parents[1] / "cask/cc-vigil.rb.tmpl"
        with tempfile.TemporaryDirectory() as raw:
            output = Path(raw) / "Casks/cc-vigil.rb"
            delivery.render_cask(template, output, "0.8.1", SHA_A)
            content = output.read_text(encoding="utf-8")
            self.assertIn('version "0.8.1"', content)
            self.assertIn(f'sha256 "{SHA_A}"', content)
            self.assertNotIn("__VERSION__", content)
            self.assertNotIn("__SHA_APP__", content)
        with tempfile.TemporaryDirectory() as raw:
            broken = Path(raw) / "broken.tmpl"
            broken.write_text("__VERSION__ __VERSION__ __SHA_APP__", encoding="utf-8")
            self.assert_fails(
                "exact placeholder set",
                delivery.render_cask,
                broken,
                Path(raw) / "out.rb",
                "0.8.1",
                SHA_A,
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
