#!/usr/bin/env bash
# package-macos.sh — build an UNSIGNED macOS installer (.pkg + .dmg) from a
# Carbonyl macOS runtime payload. (#129, ADR-003)
#
# Runs on macOS (mutsu) using the built-in pkgbuild / productbuild / hdiutil.
# No Apple Developer ID -> unsigned; Gatekeeper will warn (see
# packaging/macos/GATEKEEPER.txt, bundled into the .dmg).
#
# Input payload = the contents of build/pre-built/aarch64-apple-darwin/
# (carbonyl + libcarbonyl.dylib + libvk_swiftshader.dylib + icudtl.dat +
# v8_context_snapshot*.bin).
#
# Usage:
#   bash scripts/package-macos.sh --payload DIR --version 0.2.0-alpha.9 \
#        [--arch arm64] [--out build/packages-native]
#
# Install layout: /usr/local/carbonyl/<payload>; postinstall symlinks
# /usr/local/bin/carbonyl. The .dmg wraps the .pkg + the Gatekeeper note.

set -euo pipefail

IDENTIFIER="net.integrolabs.carbonyl"
CARBONYL_ROOT="$(cd "$(dirname -- "$0")" && cd .. && pwd)"

payload=""
version=""
arch="arm64"
out="${CARBONYL_ROOT}/build/packages-native"

usage() { sed -n '2,24p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --payload) payload="$2"; shift 2 ;;
    --payload=*) payload="${1#--payload=}"; shift ;;
    --version) version="$2"; shift 2 ;;
    --version=*) version="${1#--version=}"; shift ;;
    --arch) arch="$2"; shift 2 ;;
    --arch=*) arch="${1#--arch=}"; shift ;;
    --out) out="$2"; shift 2 ;;
    --out=*) out="${1#--out=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "ERROR: package-macos.sh must run on macOS (got ${OSTYPE:-unknown})" >&2
  exit 2
fi
[ -n "$payload" ] || { echo "ERROR: --payload is required" >&2; exit 2; }
[ -n "$version" ] || { echo "ERROR: --version is required" >&2; exit 2; }
[ -d "$payload" ] || { echo "ERROR: payload dir not found: $payload" >&2; exit 2; }
[ -f "$payload/carbonyl" ] || { echo "ERROR: no 'carbonyl' binary in payload: $payload" >&2; exit 2; }

mkdir -p "$out"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT

# ── component payload root ──────────────────────────────────────────────────
PKGROOT="$STAGE/pkgroot"
mkdir -p "$PKGROOT/usr/local/carbonyl"
cp -a "$payload/." "$PKGROOT/usr/local/carbonyl/"
chmod 0755 "$PKGROOT/usr/local/carbonyl/carbonyl"

# ── postinstall script ──────────────────────────────────────────────────────
SCRIPTS="$STAGE/scripts"
mkdir -p "$SCRIPTS"
install -m 0755 "$CARBONYL_ROOT/packaging/macos/postinstall" "$SCRIPTS/postinstall"

# ── component pkg ───────────────────────────────────────────────────────────
component="$STAGE/carbonyl-component.pkg"
echo "[pkg] pkgbuild component"
pkgbuild \
  --root "$PKGROOT" \
  --identifier "$IDENTIFIER" \
  --version "$version" \
  --scripts "$SCRIPTS" \
  --install-location "/" \
  "$component"

# ── product archive (distribution) ──────────────────────────────────────────
RES="$STAGE/resources"
mkdir -p "$RES"
[ -f "$CARBONYL_ROOT/LICENSE" ] && cp "$CARBONYL_ROOT/LICENSE" "$RES/LICENSE.txt"
cp "$CARBONYL_ROOT/packaging/macos/GATEKEEPER.txt" "$RES/welcome.txt"

dist="$STAGE/distribution.xml"
cat > "$dist" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>Carbonyl ${version}</title>
  <welcome file="welcome.txt"/>
  $( [ -f "$RES/LICENSE.txt" ] && echo '<license file="LICENSE.txt"/>' )
  <options customize="never" require-scripts="false" hostArchitectures="${arch}"/>
  <choices-outline>
    <line choice="default"/>
  </choices-outline>
  <choice id="default" title="Carbonyl">
    <pkg-ref id="${IDENTIFIER}"/>
  </choice>
  <pkg-ref id="${IDENTIFIER}" version="${version}" onConclusion="none">carbonyl-component.pkg</pkg-ref>
</installer-gui-script>
XML

product="$out/carbonyl-${version}-macos-${arch}.pkg"
echo "[pkg] productbuild (unsigned)"
productbuild \
  --distribution "$dist" \
  --package-path "$STAGE" \
  --resources "$RES" \
  "$product"

# ── .dmg wrapping the .pkg + the Gatekeeper note ────────────────────────────
DMGDIR="$STAGE/dmg"
mkdir -p "$DMGDIR"
cp "$product" "$DMGDIR/"
cp "$CARBONYL_ROOT/packaging/macos/GATEKEEPER.txt" "$DMGDIR/READ ME FIRST - Gatekeeper.txt"
dmg="$out/carbonyl-${version}-macos-${arch}.dmg"
echo "[pkg] hdiutil create .dmg"
rm -f "$dmg"
hdiutil create -volname "Carbonyl ${version}" -srcfolder "$DMGDIR" -ov -format UDZO "$dmg"

# ── verify ──────────────────────────────────────────────────────────────────
echo
echo "[pkg] verify"
pkgutil --check-signature "$product" 2>&1 | head -3 || true
echo "  pkg payload (first entries):"
pkgutil --payload-files "$product" 2>/dev/null | sed 's/^/    /' | head -20 || true
hdiutil verify "$dmg" >/dev/null 2>&1 && echo "  dmg verify: OK" || echo "  dmg verify: WARN"

echo
echo "[pkg] artifacts in $out:"
ls -lh "$out"/carbonyl-"${version}"-macos-"${arch}".* | sed 's/^/  /'
