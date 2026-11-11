from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "mac"))

from ff7recomp_mac.package import build_package  # noqa: E402
from ff7recomp_mac.validate import validate_game_dir  # noqa: E402


class ValidateTests(unittest.TestCase):
    def test_missing_dir(self) -> None:
        result = validate_game_dir(ROOT / "nope-does-not-exist")
        self.assertFalse(result.ok)

    def test_empty_dir(self) -> None:
        empty = ROOT / "tests" / "_empty_game"
        empty.mkdir(exist_ok=True)
        result = validate_game_dir(empty)
        self.assertFalse(result.ok)
        empty.rmdir()

    def test_finds_exe_and_packages(self) -> None:
        game = ROOT / "tests" / "_fake_game"
        game.mkdir(exist_ok=True)
        exe = game / "ff7_en.exe"
        exe.write_bytes(b"MZ-fake-for-tests-only")
        try:
            result = validate_game_dir(game)
            self.assertTrue(result.ok)
            self.assertEqual(result.exe_path, exe)

            out = ROOT / "tests" / "_out.ff7pkg"
            written = build_package(game, out)
            self.assertTrue(written.exists())
            self.assertEqual(written.suffix, ".ff7pkg")
            written.unlink()
        finally:
            exe.unlink(missing_ok=True)
            game.rmdir()


if __name__ == "__main__":
    unittest.main()
