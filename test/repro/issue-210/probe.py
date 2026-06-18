#!/usr/bin/env python3
"""Run carbonyl inside the GPU-less repro container and capture its ANSI stream.

Captures the raw terminal output (for replay through analyze.py) plus a coarse
per-window timeline. The timeline alone is NOT a reliable blank detector --
carbonyl stops emitting frames when idle, which looks like "blank" but isn't.
Use analyze.py on the raw capture for the ground-truth verdict.

Usage:
  probe.py --bin-dir <prebuilt-dir> --url <url> [--flags "..."] \
           [--duration 12] [--image carbonyl-repro:bullseye] [--out raw.bin]
"""
import argparse, json, os, re, subprocess, time

ANSI = re.compile(rb'\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[PX^_].*?\x1b\\|\x1b\][^\x07]*\x07|\x1b[()][0-9A-Za-z]')


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin-dir", required=True, help="prebuilt dir containing carbonyl + libcarbonyl.so")
    ap.add_argument("--url", required=True)
    ap.add_argument("--flags", default="", help="extra carbonyl flags, space separated")
    ap.add_argument("--duration", type=float, default=12.0)
    ap.add_argument("--image", default="carbonyl-repro:bullseye")
    ap.add_argument("--cols", type=int, default=120)
    ap.add_argument("--rows", type=int, default=40)
    ap.add_argument("--out", default="raw.bin", help="path to write the raw capture")
    args = ap.parse_args()

    bin_dir = os.path.abspath(args.bin_dir)
    extra = args.flags.split() if args.flags else []
    name = f"cbprobe-{int(time.time())}"
    cmd = [
        "docker", "run", "--rm", "-t", "--name", name,
        "-v", f"{bin_dir}:/carbonyl:ro",
        "-e", f"COLUMNS={args.cols}", "-e", f"LINES={args.rows}",
        "-e", "TERM=xterm-256color", "-e", "HOME=/tmp/cb",
        args.image,
        "/carbonyl/carbonyl", "--no-sandbox", "--disable-dev-shm-usage",
        "--user-data-dir=/tmp/cb", "--enable-logging=stderr",
    ] + extra + [args.url]

    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
    os.set_blocking(p.stdout.fileno(), False)
    start = time.time()
    raw = bytearray()
    buckets: dict[float, list[int]] = {}
    while time.time() - start < args.duration:
        chunk = None
        try:
            chunk = p.stdout.read(65536)
        except Exception:
            pass
        if chunk:
            raw += chunk
            now = time.time() - start
            stripped = ANSI.sub(b"", chunk)
            glyph = sum(1 for b in stripped if b not in (0x20, 0x09, 0x0a, 0x0d) and (b >= 0x80 or 0x21 <= b <= 0x7e))
            w = round(now * 2) / 2.0
            b = buckets.setdefault(w, [0, 0])
            b[0] += glyph
            b[1] += len(chunk)
        elif p.poll() is not None:
            break
        else:
            time.sleep(0.05)

    try:
        p.kill()
    except Exception:
        pass
    subprocess.run(["docker", "rm", "-f", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    with open(args.out, "wb") as fh:
        fh.write(raw)
    print(json.dumps({
        "url": args.url,
        "flags": extra,
        "raw_bytes": len(raw),
        "raw_path": args.out,
        "timeline": [{"t": t, "glyphs": v[0], "bytes": v[1]} for t, v in sorted(buckets.items())],
    }, indent=2))


if __name__ == "__main__":
    main()
