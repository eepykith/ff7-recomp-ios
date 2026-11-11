from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import __version__
from .package import build_package
from .validate import validate_game_dir


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="ff7recomp-mac",
        description=(
            "Mac companion for FF7Recomp iOS. Validates your Steam FF7 folder "
            "and builds a GamePackage stub for the iOS app to import."
        ),
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    p_val = sub.add_parser("validate", help="Check a Steam FF7 install folder")
    p_val.add_argument("game_dir", type=Path)

    p_pkg = sub.add_parser(
        "build-package",
        help="Write a .ff7pkg stub (manifest + exe fingerprint; no game data)",
    )
    p_pkg.add_argument("game_dir", type=Path)
    p_pkg.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("GamePackage.ff7pkg"),
        help="Output .ff7pkg path (default: ./GamePackage.ff7pkg)",
    )

    p_lift = sub.add_parser(
        "lift",
        help="Lift ff7_en.exe with pcrecomp (not wired in P0)",
    )
    p_lift.add_argument("game_dir", type=Path)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "validate":
        result = validate_game_dir(args.game_dir)
        for line in result.messages:
            print(line)
        return 0 if result.ok else 1

    if args.command == "build-package":
        out = build_package(args.game_dir, args.output)
        print(f"wrote {out}")
        return 0

    if args.command == "lift":
        result = validate_game_dir(args.game_dir)
        for line in result.messages:
            print(line)
        if not result.ok:
            return 1
        print(
            "lift is not wired in P0 — next: vendor pcrecomp tools from "
            "ff7-recomp-android and emit arm64-apple-ios objects"
        )
        return 2

    parser.error(f"unknown command {args.command}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
