#!/usr/bin/env bash
# package-linux.sh — build native Linux install packages (.deb, .rpm, .AppImage)
# from a Carbonyl runtime payload. (#129, ADR-003)
#
# Real release artifacts are produced in CI (release.yml on titan). Running this
# locally is for test/debug only.
#
# Input payload = the contents of build/pre-built/<triple>/ (carbonyl + bundled
# libs + data), i.e. exactly what runtime-pull.sh / the runtime tarball provide.
#
# Usage:
#   bash scripts/package-linux.sh --payload DIR --version 0.2.0-alpha.9 \
#        [--arch amd64] [--variant headless] [--out build/packages-native] \
#        [--formats deb,rpm,appimage]
#
# Tools: nfpm (deb+rpm) and appimagetool (AppImage). If not on PATH they are
# fetched, pinned by version + sha256, into a cache dir (CARBONYL_PKG_CACHE or
# /tmp/carbonyl-pkg-tools). CI builders should preinstall both.

set -euo pipefail

# ── pinned tools (ci-action-pinning: version + sha256) ──────────────────────
NFPM_VERSION="2.41.3"
NFPM_SHA256="22aa6d3bc2ec239d62d3d190bcb036a47f2b24e0c3c6edfccebb6a55fbb2078e"
NFPM_URL="https://github.com/goreleaser/nfpm/releases/download/v${NFPM_VERSION}/nfpm_${NFPM_VERSION}_Linux_x86_64.tar.gz"
APPIMAGETOOL_VERSION="1.9.1"
APPIMAGETOOL_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_VERSION}/appimagetool-x86_64.AppImage"

CACHE="${CARBONYL_PKG_CACHE:-/tmp/carbonyl-pkg-tools}"
CARBONYL_ROOT="$(cd "$(dirname -- "$0")" && cd .. && pwd)"

payload=""
version=""
arch="amd64"
variant="headless"
out="${CARBONYL_ROOT}/build/packages-native"
formats="deb,rpm,appimage"

usage() { sed -n '2,30p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --payload) payload="$2"; shift 2 ;;
    --payload=*) payload="${1#--payload=}"; shift ;;
    --version) version="$2"; shift 2 ;;
    --version=*) version="${1#--version=}"; shift ;;
    --arch) arch="$2"; shift 2 ;;
    --arch=*) arch="${1#--arch=}"; shift ;;
    --variant) variant="$2"; shift 2 ;;
    --variant=*) variant="${1#--variant=}"; shift ;;
    --out) out="$2"; shift 2 ;;
    --out=*) out="${1#--out=}"; shift ;;
    --formats) formats="$2"; shift 2 ;;
    --formats=*) formats="${1#--formats=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$payload" ] || { echo "ERROR: --payload is required" >&2; exit 2; }
[ -n "$version" ] || { echo "ERROR: --version is required" >&2; exit 2; }
[ -d "$payload" ] || { echo "ERROR: payload dir not found: $payload" >&2; exit 2; }
[ -f "$payload/carbonyl" ] || { echo "ERROR: no 'carbonyl' binary in payload: $payload" >&2; exit 2; }
case "$arch" in amd64|arm64) ;; *) echo "ERROR: --arch must be amd64|arm64" >&2; exit 2 ;; esac

# Package name: headless is the default package "carbonyl"; other variants get a
# suffix so they can coexist if ever shipped.
pkgname="carbonyl"
[ "$variant" = "headless" ] || pkgname="carbonyl-${variant}"

mkdir -p "$out" "$CACHE"

fetch_pinned() { # <url> <sha256> <dest>
  local url="$1" sha="$2" dest="$3" got
  if [ -s "$dest" ] && [ "$(sha256sum "$dest" | cut -d' ' -f1)" = "$sha" ]; then return 0; fi
  echo "[pkg] fetching $(basename "$dest") (pinned)"
  curl -fL --retry 3 -o "$dest.tmp" "$url"
  got="$(sha256sum "$dest.tmp" | cut -d' ' -f1)"
  if [ "$got" != "$sha" ]; then
    echo "ERROR: sha256 mismatch for $url" >&2
    echo "  expected $sha" >&2
    echo "  got      $got" >&2
    rm -f "$dest.tmp"; exit 1
  fi
  mv "$dest.tmp" "$dest"
}

resolve_nfpm() {
  if command -v nfpm >/dev/null 2>&1; then NFPM="nfpm"; return; fi
  fetch_pinned "$NFPM_URL" "$NFPM_SHA256" "$CACHE/nfpm.tgz"
  tar xzf "$CACHE/nfpm.tgz" -C "$CACHE" nfpm
  NFPM="$CACHE/nfpm"; chmod +x "$NFPM"
}

resolve_appimagetool() {
  if command -v appimagetool >/dev/null 2>&1; then APPIMAGETOOL=(appimagetool); return; fi
  fetch_pinned "$APPIMAGETOOL_URL" "$APPIMAGETOOL_SHA256" "$CACHE/appimagetool"
  chmod +x "$CACHE/appimagetool"
  APPIMAGETOOL=("$CACHE/appimagetool" --appimage-extract-and-run)
}

want() { case ",$formats," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# ── staged install tree (shared by deb/rpm) ─────────────────────────────────
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
ROOT="$STAGE/root"
mkdir -p "$ROOT/usr/lib/carbonyl" \
         "$ROOT/usr/bin" \
         "$ROOT/usr/share/applications" \
         "$ROOT/usr/share/icons/hicolor/scalable/apps" \
         "$ROOT/usr/share/doc/$pkgname"

cp -a "$payload/." "$ROOT/usr/lib/carbonyl/"
install -m 0755 "$CARBONYL_ROOT/packaging/linux/carbonyl.launcher" "$ROOT/usr/bin/carbonyl"
install -m 0644 "$CARBONYL_ROOT/packaging/linux/carbonyl.desktop"  "$ROOT/usr/share/applications/carbonyl.desktop"
install -m 0644 "$CARBONYL_ROOT/packaging/linux/carbonyl.svg"      "$ROOT/usr/share/icons/hicolor/scalable/apps/carbonyl.svg"
for d in readme.md LICENSE; do
  [ -f "$CARBONYL_ROOT/$d" ] && install -m 0644 "$CARBONYL_ROOT/$d" "$ROOT/usr/share/doc/$pkgname/$d" || true
done

# Optional rasterized PNG icon (hicolor 256x256) when a renderer is available.
png_icon=""
mkdir -p "$ROOT/usr/share/icons/hicolor/256x256/apps"
if command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert -w 256 -h 256 -o "$ROOT/usr/share/icons/hicolor/256x256/apps/carbonyl.png" "$CARBONYL_ROOT/packaging/linux/carbonyl.svg" \
    && png_icon="$ROOT/usr/share/icons/hicolor/256x256/apps/carbonyl.png"
elif command -v convert >/dev/null 2>&1; then
  convert -background none -resize 256x256 "$CARBONYL_ROOT/packaging/linux/carbonyl.svg" "$ROOT/usr/share/icons/hicolor/256x256/apps/carbonyl.png" 2>/dev/null \
    && png_icon="$ROOT/usr/share/icons/hicolor/256x256/apps/carbonyl.png" || true
fi
[ -n "$png_icon" ] || { echo "[pkg] note: no SVG rasterizer (rsvg-convert/convert); shipping scalable SVG icon only"; rmdir "$ROOT/usr/share/icons/hicolor/256x256/apps" 2>/dev/null || true; }

# ── deb + rpm via nfpm ──────────────────────────────────────────────────────
if want deb || want rpm; then
  resolve_nfpm
  cfg="$STAGE/nfpm.yaml"

  png_content=""
  if [ -n "$png_icon" ]; then
    png_content="  - src: \"${png_icon}\"
    dst: \"/usr/share/icons/hicolor/256x256/apps/carbonyl.png\""
  fi

  cat > "$cfg" <<YAML
name: "${pkgname}"
arch: "${arch}"
platform: "linux"
version: "${version}"
section: "web"
priority: "optional"
maintainer: "Carbonyl maintainers <noreply@git.integrolabs.net>"
description: |
  Chromium running in your terminal.
  Carbonyl renders a real Chromium engine directly to the terminal.
vendor: "Carbonyl"
homepage: "https://github.com/fathyb/carbonyl"
license: "BSD-3-Clause"
contents:
  - src: "${ROOT}/usr/lib/carbonyl/*"
    dst: "/usr/lib/carbonyl/"
  - src: "${ROOT}/usr/bin/carbonyl"
    dst: "/usr/bin/carbonyl"
    file_info: { mode: 0755 }
  - src: "${ROOT}/usr/share/applications/carbonyl.desktop"
    dst: "/usr/share/applications/carbonyl.desktop"
  - src: "${ROOT}/usr/share/icons/hicolor/scalable/apps/carbonyl.svg"
    dst: "/usr/share/icons/hicolor/scalable/apps/carbonyl.svg"
${png_content}
  - src: "${ROOT}/usr/share/doc/${pkgname}/*"
    dst: "/usr/share/doc/${pkgname}/"
overrides:
  deb:
    depends:
      - "libc6"
      - "libgcc-s1"
      - "libasound2t64 | libasound2"
      - "libbsd0"
      - "libcap2"
      - "libdbus-1-3"
      - "libdrm2"
      - "libexpat1"
      - "libgbm1"
      # dlopen'd at runtime, so absent from ldd (#136): fontconfig + a font for
      # glyphs, EGL/GL, glib, xkbcommon. Without these: "Fontconfig error" and
      # degraded rendering. glib uses the t64 name on Ubuntu 24.04+.
      - "libfontconfig1"
      - "fonts-liberation"
      - "libegl1"
      - "libgl1"
      - "libglib2.0-0t64 | libglib2.0-0"
      - "libxkbcommon0"
      - "libgcrypt20"
      - "libgpg-error0"
      - "liblz4-1"
      - "liblzma5"
      - "libmd0"
      - "libnspr4"
      - "libnss3"
      - "libsystemd0"
      - "libudev1"
      - "libx11-6"
      - "libxau6"
      - "libxcb1"
      - "libxdmcp6"
      - "libzstd1"
  rpm:
    depends:
      - "glibc"
      - "libgcc"
      - "alsa-lib"
      - "libbsd"
      - "libcap"
      - "dbus-libs"
      - "libdrm"
      - "expat"
      - "mesa-libgbm"
      # dlopen'd at runtime, so absent from ldd (#136): fontconfig + a font for
      # glyphs, EGL/GL (libglvnd), glib, xkbcommon.
      - "fontconfig"
      - "liberation-fonts"
      - "libglvnd-egl"
      - "libglvnd-glx"
      - "glib2"
      - "libxkbcommon"
      - "libgcrypt"
      - "libgpg-error"
      - "lz4-libs"
      - "xz-libs"
      - "libmd"
      - "nspr"
      - "nss"
      - "systemd-libs"
      - "libX11"
      - "libXau"
      - "libxcb"
      - "libXdmcp"
      - "libzstd"
YAML

  want deb && { echo "[pkg] building .deb"; "$NFPM" package --config "$cfg" --packager deb --target "$out/"; }
  want rpm && { echo "[pkg] building .rpm"; "$NFPM" package --config "$cfg" --packager rpm --target "$out/"; }
fi

# ── AppImage ────────────────────────────────────────────────────────────────
if want appimage; then
  resolve_appimagetool
  APPDIR="$STAGE/Carbonyl.AppDir"
  mkdir -p "$APPDIR/usr/lib/carbonyl"
  cp -a "$payload/." "$APPDIR/usr/lib/carbonyl/"
  install -m 0755 "$CARBONYL_ROOT/packaging/linux/AppRun" "$APPDIR/AppRun"
  install -m 0644 "$CARBONYL_ROOT/packaging/linux/carbonyl.desktop" "$APPDIR/carbonyl.desktop"
  if [ -n "$png_icon" ]; then
    install -m 0644 "$png_icon" "$APPDIR/carbonyl.png"
    cp "$png_icon" "$APPDIR/.DirIcon"
  else
    install -m 0644 "$CARBONYL_ROOT/packaging/linux/carbonyl.svg" "$APPDIR/carbonyl.svg"
    cp "$APPDIR/carbonyl.svg" "$APPDIR/.DirIcon"
  fi
  case "$arch" in amd64) AIARCH="x86_64" ;; arm64) AIARCH="aarch64" ;; esac
  outfile="$out/${pkgname}-${version}-${AIARCH}.AppImage"
  echo "[pkg] building .AppImage"
  ARCH="$AIARCH" "${APPIMAGETOOL[@]}" --no-appstream "$APPDIR" "$outfile"
fi

echo
echo "[pkg] artifacts in $out:"
ls -lh "$out" | sed 's/^/  /'
