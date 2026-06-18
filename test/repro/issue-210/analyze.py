#!/usr/bin/env python3
"""Ground-truth blank-vs-content verdict for a captured carbonyl ANSI stream.

carbonyl paints every terminal cell as a colored half-block, so counting
non-space characters cannot distinguish a rendered page from a blank one --
both fill the screen. The distinguishing signal is COLOR DIVERSITY of the final
screen buffer: a genuinely blank page collapses to ~1-3 distinct (fg,bg) pairs;
a rendered page has many, including real text colors (e.g. black-on-white).

Replays the raw capture through a real terminal emulator (pyte) and inspects the
final screen.

Usage:  analyze.py raw.bin [--cols 120 --rows 40 --blank-threshold 3]
Requires: pip install pyte
"""
import argparse, sys

try:
    import pyte
except ImportError:
    sys.exit("pyte not installed -- run: pip install pyte")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("--cols", type=int, default=120)
    ap.add_argument("--rows", type=int, default=40)
    ap.add_argument("--blank-threshold", type=int, default=3,
                    help="<= this many distinct colors => screen is blank")
    args = ap.parse_args()

    raw = open(args.raw, "rb").read()
    screen = pyte.Screen(args.cols, args.rows)
    stream = pyte.ByteStream(screen)
    stream.feed(raw)

    pairs: dict[tuple, int] = {}
    for y in range(args.rows):
        for x in range(args.cols):
            ch = screen.buffer[y][x]
            pairs[(ch.fg, ch.bg)] = pairs.get((ch.fg, ch.bg), 0) + 1

    distinct = len(pairs)
    top = sorted(pairs.items(), key=lambda kv: -kv[1])[:6]
    blank = distinct <= args.blank_threshold

    print(f"raw bytes        : {len(raw)}")
    print(f"distinct colors  : {distinct}")
    print("top (fg,bg) pairs:")
    for (fg, bg), cnt in top:
        print(f"  fg={fg} bg={bg}  cells={cnt}")
    print(f"VERDICT          : {'BLANK (bug reproduced)' if blank else 'CONTENT (not reproduced)'}")
    sys.exit(1 if blank else 0)


if __name__ == "__main__":
    main()
