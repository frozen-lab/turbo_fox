#!/usr/bin/env bash
set -euo pipefail

# ─── OS & ARCH CHECK ──────────────────────────────────────────────────────
OS=$(uname -s)
ARCH=$(uname -m)

if [[ "$OS" != "Linux" ]]; then
  echo "Error: Only Linux is supported. Detected: $OS" >&2
  exit 1
fi

if [[ "$ARCH" != "x86_64" ]]; then
  echo "Error: Only x86_64 architecture is supported. Detected: $ARCH" >&2
  exit 1
fi

# ─── CONFIG ────────────────────────────────────────────────────────────────
readonly BINARY_NAME="turbofox"
readonly DOWNLOAD_URL="https://github.com/frozen-lab/turbo_fox/releases/download/master/turbo-fox-linux-amd64"

usage() {
  cat <<EOF
Usage: install.sh [DEST_DIR]

By default, if run as root, installs to /usr/local/bin;
otherwise installs to \$HOME/.local/bin.

You can override DEST_DIR by:
  • Passing it as the first argument:
      curl … | bash -s -- /custom/path
  • Or exporting:
      DEST_DIR=/custom/path curl … | bash
EOF
  exit 1
}

# ─── PARSE ARGS & ENV OVERRIDE ─────────────────────────────────────────────
# 1) If user passed a positional arg, use that.
# 2) Else if DEST_DIR is already set in env, use that.
# 3) Else auto-detect based on EUID.

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
fi

if [[ -n "${1:-}" ]]; then
  DEST_DIR="$1"
elif [[ -n "${DEST_DIR:-}" ]]; then
  # exported by user
  DEST_DIR="$DEST_DIR"
elif [[ "$EUID" -eq 0 ]]; then
  DEST_DIR="/usr/local/bin"
else
  DEST_DIR="$HOME/.local/bin"
fi

# Download with HTTP-failure check:
echo "Downloading ${BINARY_NAME}…"
if command -v curl &>/dev/null; then
  curl -fsSL "$DOWNLOAD_URL" -o "${DEST_DIR}/${BINARY_NAME}" ||
    {
      echo "Error: download failed (URL or network)." >&2
      exit 1
    }
else
  wget --server-response -qO "${DEST_DIR}/${BINARY_NAME}" "$DOWNLOAD_URL" ||
    {
      echo "Error: download failed (URL or network)."
      exit 1
    }
fi

# Validate ELF magic:
if ! head -c 4 "${DEST_DIR}/${BINARY_NAME}" | grep -q $'\x7fELF'; then
  echo "Error: downloaded file is not a Linux/x86_64 binary." >&2
  exit 1
fi

chmod +x "${DEST_DIR}/${BINARY_NAME}"
echo "✔ Installed to ${DEST_DIR}/${BINARY_NAME}"
