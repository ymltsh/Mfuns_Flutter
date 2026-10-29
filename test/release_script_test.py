import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("mfuns_release", Path(__file__).resolve().parents[1] / "release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseScriptTest(unittest.TestCase):
    def test_four_part_hotfix_keeps_legal_pub_version(self):
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / "pubspec.yaml"
            config = Path(directory) / "app_config.dart"
            pubspec.write_text("version: 1.6.9+65\n", encoding="utf-8")
            config.write_text("static const appVersion = '1.6.9';\nstatic const appBuild = 65;", encoding="utf-8")
            with patch.object(release, "PUBSPEC", str(pubspec)), patch.object(release, "APP_CONFIG", str(config)):
                release.bump_pubspec("1.6.9.1", 66)
                release.bump_app_config("1.6.9.1", 66)
                self.assertEqual(release.current_version(), (1, 6, 9, 66))
            self.assertEqual(pubspec.read_text(encoding="utf-8").strip(), "version: 1.6.9+66")
            self.assertIn("appVersion = '1.6.9.1'", config.read_text(encoding="utf-8"))

    def test_split_apks_have_exactly_one_correct_abi(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(release, "APK_DIR", directory):
            paths = release.android_apk_paths()
            for abi, path in paths.items():
                with zipfile.ZipFile(path, "w") as apk:
                    apk.writestr(f"lib/{abi}/libapp.so", b"test")
                    apk.writestr(f"lib/{abi}/libflutter.so", b"test")
            self.assertEqual(release.validate_android_apks(), paths)
            with zipfile.ZipFile(paths["arm64-v8a"], "a") as apk:
                apk.writestr("lib/x86_64/libflutter.so", b"wrong ABI")
            with self.assertRaises(SystemExit):
                release.validate_android_apks()

    def test_missing_apk_stops_release(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(release, "APK_DIR", directory):
            with self.assertRaises(SystemExit):
                release.validate_android_apks()

    def test_manifest_defaults_legacy_clients_to_arm64(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "version.json"
            path.write_text(json.dumps({"latest": {"version": "1.6.7"}}), encoding="utf-8")
            with patch.object(release, "VERSION_JSON", str(path)), patch.dict(release._ARGS, repo="owner/repo", asset="1.6.8"):
                release.update_version_json("1.6.8", 64, "title", "notes", "v1.6.8", "https://example.test/release")
            manifest = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(manifest["latest"]["urls"]["android"], manifest["latest"]["urls"]["android_abis"]["arm64-v8a"])
            self.assertEqual(set(manifest["latest"]["urls"]["android_abis"]), set(release.ANDROID_ABIS))
            self.assertTrue(manifest["latest"]["urls"]["android_abis"]["arm64-v8a"].endswith("mfuns-flutter-1.6.8-arm64-v8a.apk"))
            self.assertEqual(manifest["history"][0]["version"], "1.6.7")

    def test_release_starts_as_draft(self):
        with patch.object(release, "api_request", return_value={"html_url": "https://example.test"}) as api:
            release.create_release("test-credential", "owner/repo", "v2", "title", "notes", False)
            self.assertTrue(api.call_args.kwargs["body"]["draft"])

    def test_hotfix_release_targets_pushed_source_branch(self):
        with patch.dict(release._ARGS, release_ref="codex/hotfix-test"), patch.object(release, "api_request", return_value={"html_url": "https://example.test"}) as api:
            release.create_release("test-credential", "owner/repo", "v2", "title", "notes", False)
            self.assertEqual(api.call_args.kwargs["body"]["target_commitish"], "codex/hotfix-test")

    def test_publish_only_after_five_uploads_and_manifest_after_publish(self):
        events = []
        with contextlib.ExitStack() as stack:
            replacements = {
                "current_version": (1, 6, 7, 63), "repo_from_remote": "owner/repo",
                "find_flutter": "flutter", "github_token": "test-credential",
                "bump_pubspec": None, "bump_app_config": None,
                "validate_android_apks": {abi: abi + ".apk" for abi in release.ANDROID_ABIS},
                "create_release": {"id": 1},
            }
            for name, value in replacements.items():
                stack.enter_context(patch.object(release, name, return_value=value))
            stack.enter_context(patch.object(release.os.path, "isfile", return_value=True))
            stack.enter_context(patch.object(release, "upload_asset", side_effect=lambda *args: events.append("upload:" + args[-1])))
            stack.enter_context(patch.object(release, "publish_release", side_effect=lambda *args: events.append("publish")))
            stack.enter_context(patch.object(release, "update_version_json", side_effect=lambda *args: events.append("manifest")))
            stack.enter_context(patch("sys.argv", ["release.py", "--version", "1.6.8", "--build", "64", "--skip-build", "--skip-checks", "--no-push"]))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            release.main()
        self.assertEqual(len(events), 7)
        self.assertTrue(all(event.startswith("upload:") for event in events[:5]))
        self.assertEqual(events[-2:], ["publish", "manifest"])


if __name__ == "__main__":
    unittest.main()
