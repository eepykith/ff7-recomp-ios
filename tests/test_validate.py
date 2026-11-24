from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "mac"))

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

    def test_finds_exe(self) -> None:
        game = ROOT / "tests" / "_fake_game"
        game.mkdir(exist_ok=True)
        exe = game / "ff7_en.exe"
        exe.write_bytes(b"MZ-fake-for-tests-only")
        try:
            result = validate_game_dir(game)
            self.assertTrue(result.ok)
            self.assertEqual(result.exe_path, exe)
        finally:
            exe.unlink(missing_ok=True)
            game.rmdir()


if __name__ == "__main__":
    unittest.main()


class InstallTests(unittest.TestCase):
    def test_no_apple_id_stops_before_building(self) -> None:
        from ff7recomp_mac import install as inst
        target = inst.Target("device", "x", "test iPhone")
        orig = (inst.pick_target, inst.xcode_team, inst.build_app)
        built = []
        inst.pick_target = lambda d, s: target
        inst.xcode_team = lambda: None
        inst.build_app = lambda t, team: built.append(1)
        try:
            self.assertEqual(inst.install(), 1)
            self.assertEqual(built, [])
        finally:
            inst.pick_target, inst.xcode_team, inst.build_app = orig
