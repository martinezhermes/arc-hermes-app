import importlib.machinery
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "release-version"
loader = importlib.machinery.SourceFileLoader("release_version", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
versioning = importlib.util.module_from_spec(spec)
loader.exec_module(versioning)


class ReleaseVersionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "Config").mkdir()
        (self.root / "ARCHermes.xcodeproj").mkdir()
        self.version_file = self.root / "Config/Version.xcconfig"
        self.version_file.write_text("// preserved comment\nMARKETING_VERSION = 1.9.0\n")
        (self.root / "Config/Shared.xcconfig").write_text('#include "Version.xcconfig"\n')
        (self.root / "ARCHermes.xcodeproj/project.pbxproj").write_text("CURRENT_PROJECT_VERSION = 123;\n")

    def test_bumps_reset_lower_components_and_minor_is_not_decimal(self):
        self.assertEqual(versioning.bumped("1.9.4", "patch"), "1.9.5")
        self.assertEqual(versioning.bumped("1.9.4", "minor"), "1.10.0")
        self.assertEqual(versioning.bumped("1.9.4", "major"), "2.0.0")

    def test_rejects_partial_suffix_or_leading_zero_versions(self):
        for value in ["1.9", "01.9.0", "1.09.0", "1.9.00", "1.9.0-beta.1", "1.9.0+1", "-1.9.0"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                versioning.parse(value)

    def test_dry_run_changes_no_files(self):
        before = self.version_file.read_bytes()
        result = subprocess.run([str(SCRIPT), "major", "--dry-run", "--root", str(self.root)],
                                capture_output=True, text=True, check=True)
        self.assertIn("1.9.0 -> 2.0.0 (dry run)", result.stdout)
        self.assertEqual(self.version_file.read_bytes(), before)

    def test_bump_preserves_comments_and_build_number(self):
        self.assertEqual(versioning.bump(self.root, "patch"), ("1.9.0", "1.9.1"))
        self.assertEqual(self.version_file.read_text(), "// preserved comment\nMARKETING_VERSION = 1.9.1\n")
        self.assertEqual((self.root / "ARCHermes.xcodeproj/project.pbxproj").read_text(),
                         "CURRENT_PROJECT_VERSION = 123;\n")

    def test_rejects_duplicate_release_source(self):
        self.version_file.write_text("MARKETING_VERSION = 1.9.0\nMARKETING_VERSION = 1.9.1\n")
        with self.assertRaisesRegex(ValueError, "exactly once"):
            versioning.check(self.root)

    def test_rejects_target_or_local_overrides_but_ignores_comments(self):
        project = self.root / "ARCHermes.xcodeproj/project.pbxproj"
        project.write_text('"MARKETING_VERSION[sdk=iphoneos*]" = 2.0.0;\n')
        with self.assertRaisesRegex(ValueError, "overrides"):
            versioning.check(self.root)
        project.write_text("CURRENT_PROJECT_VERSION = 123;\n")
        local = self.root / "Config/Local.xcconfig"
        local.write_text("// MARKETING_VERSION = 2.0.0\nDEVELOPMENT_TEAM = OTHER\n")
        self.assertEqual(versioning.check(self.root), "1.9.0")
        local.write_text("MARKETING_VERSION = 2.0.0\n")
        with self.assertRaisesRegex(ValueError, "Local.xcconfig"):
            versioning.check(self.root)

    def test_checks_every_effective_target_and_rejects_missing_or_stale_settings(self):
        settings = self.root / "settings.json"
        entries = [{"target": name, "buildSettings": {"MARKETING_VERSION": "1.9.0"}}
                   for name in sorted(versioning.TARGETS)]
        settings.write_text(json.dumps(entries))
        self.assertEqual(versioning.check(self.root, settings), "1.9.0")
        entries[0]["buildSettings"]["MARKETING_VERSION"] = "1.9"
        settings.write_text(json.dumps(entries))
        with self.assertRaisesRegex(ValueError, "expected 1.9.0"):
            versioning.check(self.root, settings)
        settings.write_text(json.dumps(entries[1:]))
        with self.assertRaisesRegex(ValueError, "Missing"):
            versioning.check(self.root, settings)


if __name__ == "__main__":
    unittest.main()
