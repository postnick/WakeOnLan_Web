#!/usr/bin/env bash
# gpt5-script.bash — x86_64-only setup and runner for WakeOnLan_Web
# - Installs PHP CLI, git, and a WOL tool
# - Clones/updates your repo
# - Starts a PHP built-in server as a systemd service on port 8080
# - Hard-requires x86_64 (amd64)

set -euo pipefail

# --------------------------
# Config (edit as needed)
# --------------------------
GIT_URL="https://github.com/postnick/WakeOnLan_Web.git"
APP_NAME="WakeOnLan_Web"
APP_DIR="/opt/${APP_NAME}"
HOST="0.0.0.0"
PORT="${PORT:-8080}"   # override by exporting PORT=xxxx before running
USER_TO_RUN="${SUDO_USER:-$(whoami)}"

# --------------------------
# Pre-flight checks
# --------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (use sudo)."
  exit 1
fi

ARCH_RAW="$(uname -m || true)"
case "${ARCH_RAW}" in
  x86_64|amd64)
    ARCH="amd64"
    ;;
  *)
    echo "This script is for x86_64 (amd64) only. Detected: ${ARCH_RAW}"
    exit 1
    ;;
esac

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemd is required to manage the service."
  exit 1
fi

# --------------------------
# Detect OS / package manager
# --------------------------
PKG=""
INSTALL_CMD=""
UPDATE_CMD=""
WOL_PKG=""
PHP_CLI_PKG="php-cli"
GIT_PKG="git"
CURL_PKG="curl"

if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  ID_LIKE="${ID_LIKE:-}"
  case "${ID} ${ID_LIKE}" in
    *debian*|*ubuntu*|*mint*)
      PKG="apt-get"
      UPDATE_CMD="apt-get update -y"
      INSTALL_CMD="apt-get install -y"
      WOL_PKG="wakeonlan"
      ;;
    *rhel*|*centos*|*fedora*|*rocky*|*almalinux*)
      # Prefer dnf if available
      if command -v dnf >/dev/null 2>&1; then
        PKG="dnf"
        UPDATE_CMD="dnf -y makecache"
        INSTALL_CMD="dnf install -y"
      else
        PKG="yum"
        UPDATE_CMD="yum makecache -y"
        INSTALL_CMD="yum install -y"
      fi
      # On RHEL-like, the WOL tool is often 'wol' or 'etherwake'
      # Try 'wol' first; if not found, we’ll fallback later.
      WOL_PKG="wol"
      ;;
    *arch*|*manjaro*)
      PKG="pacman"
      UPDATE_CMD="pacman -Sy --noconfirm"
      INSTALL_CMD="pacman -S --noconfirm --needed"
      WOL_PKG="wakeonlan"
      PHP_CLI_PKG="php"
      ;;
    *)
      :
      ;;
  esac
fi

if [[ -z "${PKG}" ]]; then
  # Fallback detection
  if command -v apt-get >/dev/null 2>&1; then
    PKG="apt-get"
    UPDATE_CMD="apt-get update -y"
    INSTALL_CMD="apt-get install -y"
    WOL_PKG="wakeonlan"
  elif command -v dnf >/dev/null 2>&1; then
    PKG="dnf"
    UPDATE_CMD="dnf -y makecache"
    INSTALL_CMD="dnf install -y"
    WOL_PKG="wol"
  elif command -v yum >/dev/null 2>&1; then
    PKG="yum"
    UPDATE_CMD="yum makecache -y"
    INSTALL_CMD="yum install -y"
    WOL_PKG="wol"
  elif command -v pacman >/dev/null 2>&1; then
    PKG="pacman"
    UPDATE_CMD="pacman -Sy --noconfirm"
    INSTALL_CMD="pacman -S --noconfirm --needed"
    WOL_PKG="wakeonlan"
    PHP_CLI_PKG="php"
  else
    echo "Unsupported or undetected package manager."
    exit 1
  fi
fi

echo "Detected arch: ${ARCH_RAW} -> ${ARCH}"
echo "Using package manager: ${PKG}"
sleep 1

# --------------------------
# Install dependencies
# --------------------------
eval "${UPDATE_CMD}"

set +e
eval "${INSTALL_CMD} ${PHP_CLI_PKG} ${GIT_PKG} ${CURL_PKG} ${WOL_PKG}"
INSTALL_STATUS=$?
set -e

# Fallback for WOL on RHEL-like if 'wol' not found
if [[ ${INSTALL_STATUS} -ne 0 ]]; then
  if [[ "${WOL_PKG}" == "wol" ]]; then
    echo "Falling back to etherwake package for Wake-on-LAN..."
    eval "${INSTALL_CMD} etherwake" || true
  fi
fi

# --------------------------
# Clone or update repo
# --------------------------
if [[ -d "${APP_DIR}/.git" ]]; then
  echo "Updating ${APP_DIR} ..."
  git -C "${APP_DIR}" fetch --all --prune
  git -C "${APP_DIR}" reset --hard origin/main
else
  echo "Cloning into ${APP_DIR} ..."
  mkdir -p "$(dirname "${APP_DIR}")"
  git clone "${GIT_URL}" "${APP_DIR}"
fi

chown -R "${USER_TO_RUN}:${USER_TO_RUN}" "${APP_DIR}"

# --------------------------
# Create systemd service
# --------------------------
SERVICE_NAME="wakeonlan-web.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=WakeOnLan_Web (PHP server) [x86_64]
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_TO_RUN}
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/env php -S ${HOST}:${PORT} -t ${APP_DIR}
Restart=on-failure
RestartSec=2

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${APP_DIR}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"

# --------------------------
# Optional: open firewall
# --------------------------
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${PORT}/tcp" || true
fi
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --add-port="${PORT}/tcp" --permanent || true
  firewall-cmd --reload || true
fi

echo
echo "Done. Service: ${SERVICE_NAME}"
echo "Listening on: http://${HOST}:${PORT}"
echo "Repo dir: ${APP_DIR}"
echo
echo "Common commands:"
echo "  journalctl -u ${SERVICE_NAME} -f"
echo "  systemctl restart ${SERVICE_NAME}"
echo "  systemctl status ${SERVICE_NAME}"
