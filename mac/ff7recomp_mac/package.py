from __future__ import annotations

import hashlib
import json
import zipfile
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

from . import __version__
from .validate import ValidationResult, validate_game_dir


@dataclass
class PackageManifest:
    format: str
    tool_version: str
    created_at: str
    exe_name: str
    exe_sha256: str
    exe_size: int
    platform: str
    notes: str


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def build_package(game_dir: Path, output: Path) -> Path:
    result: ValidationResult = validate_game_dir(game_dir)
    if not result.ok or result.exe_path is None:
        raise SystemExit("validate failed:\n  " + "\n  ".join(result.messages))

    exe = result.exe_path
    manifest = PackageManifest(
        format="ff7pkg-v1",
        tool_version=__version__,
        created_at=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        exe_name=exe.name,
        exe_sha256=sha256_file(exe),
        exe_size=exe.stat().st_size,
        platform="ios-arm64",
        notes=(
            "P0 stub package: contains manifest + exe hash only. "
            "No lifted code or game assets. Real dylib lands in P3."
        ),
    )

    output = output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.suffix != ".ff7pkg":
        output = output.with_suffix(".ff7pkg")

    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("manifest.json", json.dumps(asdict(manifest), indent=2) + "\n")
        # Fingerprint only — never pack game binaries into redistributable trees.
        zf.writestr(
            "fingerprint.txt",
            f"{manifest.exe_name}\n{manifest.exe_sha256}\n{manifest.exe_size}\n",
        )

    return output
