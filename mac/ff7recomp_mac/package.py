from __future__ import annotations

import hashlib
import json
import zipfile
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

from . import __version__
from .validate import ValidationResult, validate_game_dir

# Core ABI the package is built against; the iOS app accepts packages whose core version
# has the same major (and, for 0.x, minor) as its own ff7_host_version().
CORE_VERSION = "0.2.0"


@dataclass
class PackageManifest:
    format: str
    tool_version: str
    created_at: str
    exe_name: str
    exe_sha256: str
    exe_size: int
    language: str
    build_id: str
    core_version: str
    platform: str
    notes: str
    # Package layout: every file besides manifest.json, with its SHA-256 (the iOS app
    # verifies each). Empty for stub packages; libff7.dylib lands here in P3.
    files: list


def exe_language(exe_name: str) -> str:
    """ff7_en.exe / ff7_fr / ... -> 'en' / 'fr'; plain ff7.exe is the English release."""
    stem = exe_name.lower().removesuffix(".exe")
    if stem.startswith("ff7_") and len(stem) == 6:
        return stem[4:]
    return "en"


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
    exe_sha = sha256_file(exe)
    now = datetime.now(timezone.utc)
    manifest = PackageManifest(
        format="ff7pkg-v1",
        tool_version=__version__,
        created_at=now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        exe_name=exe.name,
        exe_sha256=exe_sha,
        exe_size=exe.stat().st_size,
        language=exe_language(exe.name),
        build_id=f"{exe_sha[:12]}-{now.strftime('%Y%m%d%H%M%S')}",
        core_version=CORE_VERSION,
        platform="ios-arm64",
        notes=(
            "P0 stub package: contains manifest + exe hash only. "
            "No lifted code or game assets. Real dylib lands in P3."
        ),
        files=[],
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
