#!/bin/sh
# vesslet installer for macOS and Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/vesslet/vesslet-releases/main/install.sh | sh
#   curl -fsSL …/install.sh | sh -s -- --version v0.4.2 --yes
#
# Options (or environment):
#   --version vX.Y.Z   VESSLET_VERSION   install this version instead of the latest
#   --yes              VESSLET_YES=1     install missing tools without asking
#   --no-setup         VESSLET_NO_SETUP=1  only install the binary
#   --with vessels     VESSLET_WITH=vessels  also set up preview environments (Docker,
#                                         k3d, kubectl) — otherwise the setup asks, or
#                                         installs agents only when it can't ask
#
# installer — implements BR-1, BR-2, BR-3, BR-4, BR-7, BR-8
set -eu

RELEASES_URL="${VESSLET_RELEASES_URL:-https://github.com/vesslet/vesslet-releases}"
VERSION="${VESSLET_VERSION:-}"
YES="${VESSLET_YES:-}"
NO_SETUP="${VESSLET_NO_SETUP:-}"
WITH="${VESSLET_WITH:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --version=*) VERSION="${1#--version=}"; shift ;;
    --yes|-y) YES=1; shift ;;
    --no-setup) NO_SETUP=1; shift ;;
    --with) WITH="${2:-}"; shift 2 ;;
    --with=*) WITH="${1#--with=}"; shift ;;
    *) echo "vesslet installer: unknown option $1" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
fail() { printf 'vesslet installer: %s\n' "$*" >&2; exit 1; }

# ── platform (BR-2) ──
os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) fail "unsupported system $os — supported: macOS (arm64, amd64), Linux (amd64, arm64); on Windows use install.ps1" ;;
esac
case "$arch" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64) arch=amd64 ;;
  *) fail "unsupported processor $arch — supported: macOS (arm64, amd64), Linux (amd64, arm64)" ;;
esac
asset="vesslet-$os-$arch"

command -v curl >/dev/null 2>&1 || fail "curl is required"

# fetch URL [curl args…]: up to 3 attempts — a ~150 MB download over HTTP/2
# can be cut mid-way ("Error in the HTTP2 framing layer"), so later attempts
# fall back to HTTP/1.1.
fetch() {
  url="$1"; shift
  attempt=1
  while :; do
    if [ $attempt -eq 1 ]; then
      curl -fsS "$@" "$url" && return 0
    else
      curl -fsS --http1.1 "$@" "$url" && return 0
    fi
    [ $attempt -ge 3 ] && return 1
    attempt=$((attempt + 1))
    printf 'retrying (%s/3)...\n' "$attempt" >&2
    sleep 2
  done
}
if command -v sha256sum >/dev/null 2>&1; then sha() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
else fail "sha256sum or shasum is required to verify the download"; fi

# ── version (BR-7) ──
if [ -z "$VERSION" ]; then
  VERSION="$(fetch "$RELEASES_URL/releases/latest" -I | tr -d '\r' | sed -n 's|^[Ll]ocation: .*/releases/tag/\(v[0-9][^ ]*\)$|\1|p' | tail -n 1)"
  [ -n "$VERSION" ] || fail "couldn't find the latest release at $RELEASES_URL"
fi
case "$VERSION" in v*) ;; *) VERSION="v$VERSION" ;; esac

# ── download + verify (BR-3) ──
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
say "Downloading vesslet $VERSION ($os/$arch)..."
fetch "$RELEASES_URL/releases/download/$VERSION/$asset" -L -o "$tmp/$asset" || fail "download failed — is $VERSION published for $os/$arch?"
fetch "$RELEASES_URL/releases/download/$VERSION/checksums.txt" -L -o "$tmp/checksums.txt" || fail "couldn't download checksums.txt for $VERSION"
want="$(awk -v a="$asset" '$2 == a || $2 == "*"a { print $1 }' "$tmp/checksums.txt")"
[ -n "$want" ] || fail "$asset isn't listed in checksums.txt — refusing to install it"
got="$(sha "$tmp/$asset")"
[ "$want" = "$got" ] || fail "checksum mismatch for $asset — the download isn't the published file; nothing was installed"

# ── install (BR-4, BR-8): write next to the target, then rename over it ──
bin_dir="$HOME/.vesslet/bin"
link_dir="$HOME/.local/bin"
mkdir -p "$bin_dir" "$link_dir"
previous=""
[ -x "$bin_dir/vesslet" ] && previous="$("$bin_dir/vesslet" version 2>/dev/null | awk '{print $2}' || true)"
cp "$tmp/$asset" "$bin_dir/.vesslet.new"
chmod 755 "$bin_dir/.vesslet.new"
mv -f "$bin_dir/.vesslet.new" "$bin_dir/vesslet"
ln -sf "$bin_dir/vesslet" "$link_dir/vesslet"
if [ -n "$previous" ] && [ "$previous" != "$VERSION" ]; then
  say "vesslet upgraded: $previous → $VERSION"
else
  say "vesslet $VERSION installed: $bin_dir/vesslet"
fi

case ":$PATH:" in
  *":$link_dir:"*) ;;
  *)
    shell_rc="$HOME/.profile"
    case "${SHELL:-}" in */zsh) shell_rc="$HOME/.zshrc" ;; */bash) shell_rc="$HOME/.bashrc" ;; esac
    say ""
    say "$link_dir isn't on your PATH yet. Add it:"
    say "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> $shell_rc && export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac

# ── setup: tools + harbor (BR-5, BR-6) ──
[ -n "$NO_SETUP" ] && exit 0
set -- setup
[ -n "$YES" ] && set -- "$@" --yes
[ -n "$WITH" ] && set -- "$@" --with "$WITH"   # capabilities — BR-3
say ""
if [ -r /dev/tty ] && [ -z "$YES" ]; then
  "$bin_dir/vesslet" "$@" </dev/tty
else
  "$bin_dir/vesslet" "$@" </dev/null
fi
