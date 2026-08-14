#!/usr/bin/env bash
# install-external.sh - install a pinned external agent CLI from manifest.lock.json
#
# Usage: install-external.sh <tool-name> [manifest-path]
#
# Downloads the official GitHub release archive for the pinned version, verifies
# sha256, and installs the binary under $HOME/<installSubdir>. Never uses the
# floating "latest" install scripts from upstream.
set -euo pipefail

TOOL=${1:?usage: install-external.sh <tool-name> [manifest-path]}
MANIFEST=${2:-"$(cd "$(dirname "$0")/../.." && pwd)/nix/shared/agent-tools/manifest.lock.json"}

die() {
  printf 'install-external: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'install-external: %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_cmd jq
require_cmd curl
require_cmd tar

if [ ! -f "$MANIFEST" ]; then
  die "manifest not found: $MANIFEST"
fi

entry=$(jq -c --arg tool "$TOOL" '.external[$tool] // empty' "$MANIFEST")
[ -n "$entry" ] || die "unknown external tool in manifest: $TOOL"

version=$(jq -r '.version' <<<"$entry")
repo=$(jq -r '.repo' <<<"$entry")
install_subdir=$(jq -r '.installSubdir' <<<"$entry")
binary=$(jq -r '.binary' <<<"$entry")
pattern=$(jq -r '.archivePattern' <<<"$entry")

install_dir="${HOME}/${install_subdir}"
dest="${install_dir}/${binary}"

if [ "${AGENT_TOOLS_TEST_MODE:-}" = 1 ]; then
  mkdir -p "$install_dir"
  printf '#!/usr/bin/env bash\necho v%s\n' "$version" >"$dest"
  chmod +x "$dest"
  info "test-mode installed $TOOL ${version} to $dest"
  exit 0
fi

os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
case "$arch" in
  x86_64) arch=amd64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) die "unsupported architecture: $arch" ;;
esac
case "$os" in
  darwin | linux) ;;
  *) die "unsupported OS: $os" ;;
esac

platform_key="${os}-${arch}"
sha256=$(jq -r --arg k "$platform_key" '.sha256[$k] // empty' <<<"$entry")
[ -n "$sha256" ] || die "no sha256 pin for platform $platform_key on tool $TOOL"

archive=${pattern//\{version\}/$version}
archive=${archive//\{os\}/$os}
archive=${archive//\{arch\}/$arch}
tag="v${version}"
tag=${tag/vv/v}
url="https://github.com/${repo}/releases/download/${tag}/${archive}"

if [ -x "$dest" ]; then
  installed=$("$dest" --version 2>/dev/null | tr -d '[:space:]' || true)
  case "$installed" in
    "v${version}" | "${version}")
      info "$TOOL ${version} already installed at $dest"
      exit 0
      ;;
  esac
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

info "downloading $TOOL ${version} (${platform_key})"
curl -fsSL --max-filesize 50000000 "$url" -o "$TMP/$archive" \
  || die "download failed: $url"

if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$TMP/$archive" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  actual=$(shasum -a 256 "$TMP/$archive" | awk '{print $1}')
else
  die "need sha256sum or shasum"
fi
[ "$actual" = "$sha256" ] || die "checksum mismatch for $archive (expected $sha256, got $actual)"

tar -xzf "$TMP/$archive" -C "$TMP"
if [ -f "$TMP/$binary" ]; then
  src="$TMP/$binary"
else
  src=$(find "$TMP" -type f -name "$binary" | head -n 1)
  [ -n "$src" ] || die "archive did not contain $binary"
fi

mkdir -p "$install_dir"
install -m 0755 "$src" "$dest"
info "installed $TOOL ${version} to $dest"
