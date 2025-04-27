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
readonly DOWNLOAD_URL="https://github.com/frozen-lab/turbofox/releases/latest/download/${BINARY_NAME}-linux-amd64"

usage() {
  cat <<EOF
Usage: install.sh [DEST_DIR]

By default, if run as root, installs to /usr/local/bin;
otherwise installs to \$HOME/.local/bin.

EOF
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
fi

# ─── DESTINATION DETERMINATION & CONFIRMATION ───────────────────────────────
if [[ -n "${1:-}" ]]; then
  DEST_DIR="$1"
else
  if [[ $EUID -eq 0 ]]; then
    DEST_DIR="/usr/local/bin"
  else
    DEST_DIR="$HOME/.local/bin"
  fi
fi

echo "Installation directory: $DEST_DIR"
read -rp "Proceed with installation to $DEST_DIR? [Y/n]: " confirm_dir
confirm_dir=${confirm_dir:-Y}
if [[ ! $confirm_dir =~ ^[Yy] ]]; then
  echo "Installation aborted by user."
  exit 1
fi

# ─── USER PERMISSION TO DOWNLOAD & INSTALL ──────────────────────────────────
read -rp "Download and install ${BINARY_NAME} to $DEST_DIR? [Y/n]: " confirm_install
confirm_install=${confirm_install:-Y}
if [[ ! $confirm_install =~ ^[Yy] ]]; then
  echo "Operation cancelled by user."
  exit 1
fi

# Ensure destination exists
mkdir -p "$DEST_DIR"

# ─── DOWNLOAD WITH HTTP-FALIURE CHECK ────────────────────────────────────────
echo "Downloading ${BINARY_NAME}…"
if command -v curl &>/dev/null; then
  curl -fsSL "$DOWNLOAD_URL" -o "${DEST_DIR}/${BINARY_NAME}" || {
    echo "Error: download failed (URL or network)." >&2
    exit 1
  }
else
  wget --server-response -qO "${DEST_DIR}/${BINARY_NAME}" "$DOWNLOAD_URL" || {
    echo "Error: download failed (URL or network)." >&2
    exit 1
  }
fi

# ─── VALIDATE ELF ─────────────────────────────────────────────────────────
if ! head -c 4 "${DEST_DIR}/${BINARY_NAME}" | grep -q $'\x7fELF'; then
  echo "Error: downloaded file is not a Linux/x86_64 binary." >&2
  exit 1
fi

chmod +x "${DEST_DIR}/${BINARY_NAME}"
echo "✔ Installed to ${DEST_DIR}/${BINARY_NAME}"
