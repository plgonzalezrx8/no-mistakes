#!/bin/sh
set -e

REPO="kunchenguid/no-mistakes"
INSTALL_DIR="${NO_MISTAKES_INSTALL_DIR:-$HOME/.no-mistakes/bin}"
LINK_DIR="${NO_MISTAKES_LINK_DIR:-}"
START_DAEMON="${NO_MISTAKES_START_DAEMON:-0}"

if [ -z "$LINK_DIR" ]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) LINK_DIR="$HOME/.local/bin" ;;
    *) LINK_DIR="/usr/local/bin" ;;
  esac
fi

BIN_PATH="$INSTALL_DIR/no-mistakes"
LINK_PATH="$LINK_DIR/no-mistakes"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$OS" in
  darwin|linux) ;;
  *) echo "Unsupported OS: $OS"; exit 1 ;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
if [ -z "$VERSION" ]; then
  echo "Could not determine latest release"
  exit 1
fi

FILENAME="no-mistakes-${VERSION}-${OS}-${ARCH}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${VERSION}/${FILENAME}"
CHECKSUMS_URL="https://github.com/${REPO}/releases/download/${VERSION}/checksums.txt"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

checksum_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "No SHA-256 checksum tool found (need sha256sum or shasum)" >&2
    return 1
  fi
}

archive_path="${TMPDIR}/${FILENAME}"
checksums_path="${TMPDIR}/checksums.txt"

echo "Downloading no-mistakes ${VERSION} for ${OS}/${ARCH}..."
curl -fsSL "$URL" -o "$archive_path"
curl -fsSL "$CHECKSUMS_URL" -o "$checksums_path"

expected_checksum="$(awk -v file="$FILENAME" '$2 == file {print $1; found=1} END { if (!found) exit 1 }' "$checksums_path")"
if [ -z "$expected_checksum" ]; then
  echo "checksum not found for ${FILENAME}"
  exit 1
fi
actual_checksum="$(checksum_file "$archive_path")"
if [ "$actual_checksum" != "$expected_checksum" ]; then
  echo "checksum mismatch for ${FILENAME}: got ${actual_checksum}, want ${expected_checksum}"
  exit 1
fi

tar xzf "$archive_path" -C "$TMPDIR"

if ! mkdir -p "$INSTALL_DIR"; then
  echo "Could not create install directory: $INSTALL_DIR"
  exit 1
fi

mv "${TMPDIR}/no-mistakes" "$BIN_PATH"
chmod 755 "$BIN_PATH" 2>/dev/null || true

resolve_path() {
  (cd "$1" 2>/dev/null && pwd -P)
}

REAL_INSTALL_DIR="$(resolve_path "$INSTALL_DIR")"
REAL_LINK_DIR="$(resolve_path "$LINK_DIR" 2>/dev/null || echo "")"

if [ -n "$REAL_INSTALL_DIR" ] && [ "$REAL_INSTALL_DIR" = "$REAL_LINK_DIR" ]; then
  echo "Install dir and link dir resolve to the same path; skipping symlink."
else
  if [ -w "$LINK_DIR" ] || (mkdir -p "$LINK_DIR" 2>/dev/null && [ -w "$LINK_DIR" ]); then
    rm -f "$LINK_PATH"
    ln -s "$BIN_PATH" "$LINK_PATH"
  else
    echo "Linking ${LINK_PATH} to ${BIN_PATH} (requires sudo)..."
    sudo mkdir -p "$LINK_DIR"
    sudo rm -f "$LINK_PATH"
    sudo ln -s "$BIN_PATH" "$LINK_PATH"
  fi
fi

echo "no-mistakes ${VERSION} installed to ${BIN_PATH}"
echo "Command path: ${LINK_PATH} -> ${BIN_PATH}"

if [ "$START_DAEMON" = "1" ]; then
  "$BIN_PATH" daemon restart >/dev/null
else
  echo "Daemon not started. Run 'no-mistakes daemon restart' or set NO_MISTAKES_START_DAEMON=1 during install."
fi

case ":$PATH:" in
  *":$LINK_DIR:"*) ;;
  *) echo "Add ${LINK_DIR} to your PATH and restart your terminal." ;;
esac
