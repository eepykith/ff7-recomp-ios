from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import __version__
from .install import build_ipa, install
from .validate import validate_game_dir


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="ff7recomp-mac",
        description=(
            "Mac companion for FF7Recomp on iOS. iOS cannot compile code on the phone, so this "
            "builds the game from the iPhone's ff7_en.exe and installs it there."
        ),
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    p_inst = sub.add_parser("install", help="Build the game for the connected iPhone and install it")
    where = p_inst.add_mutually_exclusive_group()
    where.add_argument("--device", help="the iPhone's name or identifier (default: the one paired iPhone)")
    where.add_argument("--simulator", metavar="UDID", help="a simulator instead (UDID, or 'booted')")
    p_inst.add_argument("--exe", type=Path, help="use this ff7_en (ff7/resources/ff7_1.02/ff7_en) "
                        "instead of the iPhone's copy")
    p_inst.add_argument("--team", help="Apple developer team ID (default: the Apple ID in Xcode)")
    p_inst.add_argument("--profile", type=Path, help="sign with this development .mobileprovision and its "
                        "certificate (import the .p12 into your keychain first) instead of Xcode's Apple ID; "
                        "the app takes the profile's app ID")
    p_inst.add_argument("--relift", action="store_true", help="lift the exe again")

    p_ipa = sub.add_parser("ipa", help="Build an unsigned FF7Recomp.ipa with the game in it (sign it yourself)")
    p_ipa.add_argument("-o", "--output", type=Path, help="where to write it (default: build-ios-ipa/FF7Recomp.ipa)")
    p_ipa.add_argument("--exe", type=Path, help="the ff7_en to lift (default: this Mac's Steam install)")
    p_ipa.add_argument("--relift", action="store_true", help="lift the exe again")

    p_val = sub.add_parser("validate", help="Check a Steam FF7 install folder")
    p_val.add_argument("game_dir", type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "install":
        return install(device=args.device, simulator=args.simulator, exe=args.exe,
                       team=args.team, relift=args.relift, profile_path=args.profile)

    if args.command == "ipa":
        return build_ipa(exe=args.exe, relift=args.relift, out=args.output)

    if args.command == "validate":
        result = validate_game_dir(args.game_dir)
        for line in result.messages:
            print(line)
        return 0 if result.ok else 1

    parser.error(f"unknown command {args.command}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
