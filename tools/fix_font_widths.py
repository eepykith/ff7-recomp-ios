#!/usr/bin/env python3
"""Fix the dialog font widths in the 2026 Steam files (run with `python3 -I`).

The current Steam release's data/lang-{en,fr,de,es}/kernel/window.bin gives the letters
M, W, m and w a width of 8 pixels where the font image draws them 11 wide, so the classic text
renderer runs them into the next letter ("C'mon newcomer" shows as "newcom≡r"). This sets those
widths back to 11, as in the classic table and this release's Japanese file.

M, W, m and w drawn 11 pixels wide in the font but given a width of 8 (the same fix as the
Android app's fixFontWidths()). Patches the files in
place and is idempotent: a file that is already fixed is left untouched.

    python3 -I tools/fix_font_widths.py [game_dir]      # default: ./game
    python3 -I tools/fix_font_widths.py --check [game_dir]
"""
import gzip
import os
import struct
import sys

LANGS = ("en", "fr", "de", "es")
WIDE = (0x2D, 0x37, 0x4D, 0x57)  # M, W, m, w (FF7 text codes)


def patch(data):
    """Return the patched window.bin bytes, or None when nothing needs to change."""
    # Sections: u16 compressed size, u16 size, u16 type, then gzip data. Widths are the 3rd.
    at = 0
    for _ in range(2):
        if at + 6 > len(data):
            return None
        at += 6 + struct.unpack_from("<H", data, at)[0]
    if at + 6 > len(data):
        return None
    csize = struct.unpack_from("<H", data, at)[0]
    if at + 6 + csize > len(data):
        return None
    widths = bytearray(gzip.decompress(data[at + 6:at + 6 + csize]))
    if max(WIDE) >= len(widths):
        return None
    changed = False
    for c in WIDE:
        if widths[c] & 31 == 8:
            widths[c] = (widths[c] & 0xE0) | 11
            changed = True
    if not changed:
        return None
    packed = gzip.compress(bytes(widths), compresslevel=9, mtime=0)
    if len(packed) > 0xFFFF:
        return None
    return (data[:at] + struct.pack("<H", len(packed)) + data[at + 2:at + 6] + packed
            + data[at + 6 + csize:])


def main(argv):
    check = "--check" in argv
    args = [a for a in argv if a != "--check"]
    game = args[0] if args else "game"
    if not os.path.isdir(os.path.join(game, "data")):
        print(f"fix_font_widths: no data/ folder in {game}", file=sys.stderr)
        return 2
    pending = 0
    for lang in LANGS:
        path = os.path.join(game, "data", f"lang-{lang}", "kernel", "window.bin")
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as f:
            data = f.read()
        out = patch(data)
        if out is None:
            print(f"{lang}: ok")
            continue
        pending += 1
        if check:
            print(f"{lang}: needs the fix")
            continue
        tmp = path + ".new"
        with open(tmp, "wb") as f:
            f.write(out)
        os.replace(tmp, path)
        print(f"{lang}: fixed M/W/m/w widths")
    return 1 if check and pending else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
