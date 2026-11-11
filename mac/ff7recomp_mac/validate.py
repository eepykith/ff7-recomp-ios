from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

# Steam FF7 layout signals used by the Android importer. Keep this list in sync
# when wiring the real shared validator from the Android tools.
REQUIRED_MARKERS = (
    "ff7_en.exe",
    "ff7.exe",
)


@dataclass
class ValidationResult:
    ok: bool
    game_dir: Path
    exe_path: Path | None
    messages: list[str]


def find_exe(game_dir: Path) -> Path | None:
    for name in REQUIRED_MARKERS:
        candidate = game_dir / name
        if candidate.is_file():
            return candidate
        nested = game_dir / "ff7" / name
        if nested.is_file():
            return nested
    # Search one level for common Steam folder layouts.
    for child in game_dir.iterdir() if game_dir.is_dir() else []:
        if not child.is_dir():
            continue
        for name in REQUIRED_MARKERS:
            candidate = child / name
            if candidate.is_file():
                return candidate
    return None


def validate_game_dir(path: Path) -> ValidationResult:
    game_dir = path.expanduser().resolve()
    messages: list[str] = []
    if not game_dir.exists():
        return ValidationResult(False, game_dir, None, [f"path does not exist: {game_dir}"])
    if not game_dir.is_dir():
        return ValidationResult(False, game_dir, None, [f"not a directory: {game_dir}"])

    exe = find_exe(game_dir)
    if exe is None:
        messages.append(
            "could not find ff7_en.exe / ff7.exe — pick the Steam install folder "
            "(FINAL FANTASY VII Steam Edition)"
        )
        return ValidationResult(False, game_dir, None, messages)

    size = exe.stat().st_size
    messages.append(f"found {exe.name} ({size} bytes)")
    messages.append("P0 validate only — lift/link runs in a later milestone")
    return ValidationResult(True, game_dir, exe, messages)
