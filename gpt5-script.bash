#!/usr/bin/env bash
set -euo pipefail

# Wake-on-LAN Web Installer
# Usage: sudo bash install_wol_web.sh

APP_DIR="/opt/wol-web"
CONFIG_FILE="/etc/wol_devices.csv"
WAKE_SCRIPT="/usr/local/bin/wake_device.sh"
SERVICE_FILE="/etc/systemd/system/wol-web.service"
PORT="8000"

log() { echo -e "[+] $*"; }
warn() { echo -e "[!] $*" >&2; }
die() { echo -e "[x] $*" >&2; exit 1; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "Please run as root (e.g., sudo $0)"
  fi
}

detect_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    APP_USER="$SUDO_USER"
  else
    APP_USER="${APP_USER_OVERRIDE:-root}"
  fi
  APP_GROUP="$(id -gn "$APP_USER" 2>/dev/null || echo "$APP_USER")"
  log "Using application user: $APP_USER"
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_pkg_mgr() {
  if has_cmd apt-get; then PKG_MGR="apt"
  elif has_cmd dnf; then PKG_MGR="dnf"
  elif has_cmd yum; then PKG_MGR="yum"
  elif has_cmd zypper; then PKG_MGR="zypper"
  elif has_cmd pacman; then PKG_MGR="pacman"
  elif has_cmd apk; then PKG_MGR="apk"
  else PKG_MGR="unknown"
  fi
  log "Detected package manager: $PKG_MGR"
}

pkg_install() {
  case "$PKG_MGR" in
    apt)
      apt-get update -y
      # python3-venv is separate on Debian/Ubuntu
      DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip curl ca-certificates
      ;;
    dnf)
      dnf install -y python3 python3-pip curl ca-certificates
      ;;
    yum)
      yum install -y python3 python3-pip curl ca-certificates
      ;;
    zypper)
      zypper --non-interactive refresh
      zypper --non-interactive install -y python3 python3-pip python3-venv curl ca-certificates || \
      zypper --non-interactive install -y python311 python311-pip curl ca-certificates
      ;;
    pacman)
      pacman -Sy --noconfirm python python-pip curl ca-certificates
      ;;
    apk)
      apk add --no-cache python3 py3-pip py3-virtualenv curl ca-certificates
      ;;
    *)
      warn "Unknown package manager. Please ensure python3 and pip are installed."
      ;;
  esac
}

ensure_python_venv() {
  if ! python3 -c "import venv" 2>/dev/null; then
    warn "Python venv module not available. Trying to bootstrap ensurepip..."
    python3 -m ensurepip --upgrade || true
  fi
}

make_dirs() {
  mkdir -p "$APP_DIR"/templates
  chown -R "$APP_USER":"$APP_GROUP" "$APP_DIR"
}

create_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    log "Config exists at $CONFIG_FILE (leaving as-is)"
    return
  fi
  cat > "$CONFIG_FILE" <<'EOF'
# key,display,mac,broadcast
desktop_office,Office Desktop,AA:BB:CC:DD:EE:01,192.168.1.255
gaming_rig,Gaming PC,AA:BB:CC:DD:EE:02,192.168.1.255
nas,Home NAS,AA:BB:CC:DD:EE:03,192.168.1.255
workstation,Workstation,AA:BB:CC:DD:EE:04,192.168.1.255
htpc,Living Room HTPC,AA:BB:CC:DD:EE:05,192.168.1.255
laptop_dock,Docked Laptop,AA:BB:CC:DD:EE:06,192.168.1.255
EOF
  chmod 0644 "$CONFIG_FILE"
  log "Wrote sample device config to $CONFIG_FILE"
}

create_wake_script() {
  cat > "$WAKE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/wol_devices.csv"

usage() { echo "Usage: $0 <device_key>" >&2; exit 1; }
[[ $# -eq 1 ]] || usage
KEY="$1"

trim() { awk '{$1=$1;print}'; }

FOUND=0
while IFS=, read -r key display mac broadcast || [[ -n "${key-}" ]]; do
  [[ -z "${key-}" ]] && continue
  [[ "$key" =~ ^# ]] && continue
  k="$(echo "$key" | trim)"
  if [[ "$k" == "$KEY" ]]; then
    m="$(echo "${mac:-}" | tr '[:lower:]' '[:upper:]' | trim)"
    b="$(echo "${broadcast:-}" | trim || true)"
    if [[ -z "$m" ]]; then
      echo "MAC not set for key: $KEY" >&2
      exit 2
    fi
    # Send magic packet using Python (no external packages)
    python3 - "$m" "${b:-}" <<'PY'
import sys, socket
mac = sys.argv[1].replace(':','').replace('-','').lower()
bcast = sys.argv[2] if len(sys.argv) > 2 else ''
if len(mac) != 12 or any(c not in '0123456789abcdef' for c in mac):
    sys.exit("Invalid MAC address")
packet = bytes.fromhex('ff'*6 + mac*16)
addr = (bcast if bcast else '255.255.255.255', 9)
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
sock.sendto(packet, addr)
PY
    logger -t wol-web "Woke device '$KEY' (MAC $m, broadcast ${b:-default})"
    FOUND=1
    break
  fi
done < "$CONFIG_FILE"

if [[ "$FOUND" -eq 0 ]]; then
  echo "Unknown device key: $KEY" >&2
  exit 3
fi
EOF
  chmod 0755 "$WAKE_SCRIPT"
  log "Installed wake script at $WAKE_SCRIPT"
}

create_app_files() {
  local SECRET
  SECRET="$(python3 - <<'PY' || true
import secrets, base64
print(secrets.token_urlsafe(32))
PY
)"
  [[ -z "$SECRET" ]] && SECRET="$(head -c 32 /dev/urandom | base64)"

  # app.py
  cat > "$APP_DIR/app.py" <<EOF
from flask import Flask, render_template, request, redirect, url_for, flash
import csv
import subprocess
from pathlib import Path

APP_TITLE = "Wake-on-LAN Control"
CONFIG_PATH = Path("$CONFIG_FILE")

app = Flask(__name__)
app.config["SECRET_KEY"] = "$SECRET"

def load_devices():
    devices = []
    if CONFIG_PATH.exists():
        with CONFIG_PATH.open() as f:
            reader = csv.reader(f)
            for row in reader:
                if not row or row[0].strip().startswith("#"):
                    continue
                key = (row[0] or "").strip()
                display = (row[1] or key).strip() if len(row) > 1 else key
                mac = (row[2] or "").strip() if len(row) > 2 else ""
                broadcast = (row[3] or "").strip() if len(row) > 3 else ""
                if key and mac:
                    devices.append({
                        "key": key,
                        "display": display,
                        "mac": mac,
                        "broadcast": broadcast
                    })
    return devices

@app.route("/", methods=["GET"])
def index():
    devices = load_devices()
    return render_template("index.html", title=APP_TITLE, devices=devices)

@app.route("/wake", methods=["POST"])
def wake():
    key = request.form.get("key", "").strip()
    if not key:
        flash("No device selected.", "error")
        return redirect(url_for("index"))
    try:
        subprocess.run(
            ["$WAKE_SCRIPT", key],
            check=True,
            capture_output=True,
            text=True,
            timeout=5
        )
        flash(f"Sent wake signal to '{key}'.", "success")
    except subprocess.CalledProcessError as e:
        msg = e.stderr.strip() or e.stdout.strip() or str(e)
        flash(f"Failed to wake '{key}': {msg}", "error")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("index"))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=$PORT)
EOF

  # template
  cat > "$APP_DIR/templates/index.html" <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{{ title }}</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link
    href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css"
    rel="stylesheet">
  <style>
    body { padding: 2rem; }
    .device-btn { min-width: 220px; margin: 0.5rem; }
    .grid { display: flex; flex-wrap: wrap; gap: 0.5rem; }
  </style>
</head>
<body class="container">
  <h1 class="mb-4">{{ title }}</h1>

  {% with messages = get_flashed_messages(with_categories=true) %}
    {% if messages %}
      {% for category, message in messages %}
        <div class="alert alert-{{ 'success' if category=='success' else 'danger' }} alert-dismissible fade show" role="alert">
          {{ message }}
          <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
      {% endfor %}
    {% endif %}
  {% endwith %}

  <div class="grid">
    {% for d in devices %}
      <form method="post" action="{{ url_for('wake') }}">
        <input type="hidden" name="key" value="{{ d.key }}">
        <button class="btn btn-primary device-btn" type="submit">
          {{ d.display }}
        </button>
      </form>
    {% endfor %}
  </div>

  <p class="text-muted mt-4">
    Add more devices by editing /etc/wol_devices.csv — they’ll appear here automatically.
  </p>

  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF

  chown -R "$APP_USER":"$APP_GROUP" "$APP_DIR"
  chmod 0755 "$APP_DIR"
  log "Wrote Flask app to $APP_DIR"
}

create_venv_and_deps() {
  local py="python3"
  # Create venv as app user
  if ! sudo -u "$APP_USER" "$py" -m venv "$APP_DIR/.venv" 2>/dev/null; then
    warn "venv creation failed once, attempting to bootstrap ensurepip then retry..."
    "$py" -m ensurepip --upgrade || true
    sudo -u "$APP_USER" "$py" -m venv "$APP_DIR/.venv"
  fi
  # Install deps
  sudo -u "$APP_USER" bash -lc "source '$APP_DIR/.venv/bin/activate' && pip install --upgrade pip && pip install Flask gunicorn"
  log "Virtual environment ready with Flask and gunicorn"
}

create_systemd_service() {
  if ! has_cmd systemctl; then
    warn "systemd not detected. Skipping service creation."
    warn "Run manually: source $APP_DIR/.venv/bin/activate && python $APP_DIR/app.py"
    return
  fi

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Wake-on-LAN Web
After=network-online.target
Wants=network-online.target

[Service]
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/.venv/bin:/usr/bin"
ExecStart=$APP_DIR/.venv/bin/gunicorn -b 0.0.0.0:$PORT app:app
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$SERVICE_FILE"
  systemctl daemon-reload
  systemctl enable wol-web
  systemctl restart wol-web
  systemctl --no-pager --full status wol-web || true
  log "Service installed: wol-web (listens on port $PORT)"
}

open_firewall_port() {
  # Best effort: open port if ufw or firewalld is active
  if has_cmd ufw && ufw status | grep -q "Status: active"; then
    ufw allow "$PORT"/tcp || true
    log "UFW: allowed port $PORT/tcp"
  fi
  if has_cmd firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --add-port="$PORT"/tcp --permanent || true
    firewall-cmd --reload || true
    log "firewalld: opened port $PORT/tcp"
  fi
}

main() {
  require_root
  detect_user
  detect_pkg_mgr
  pkg_install
  ensure_python_venv
  make_dirs
  create_config
  create_wake_script
  create_app_files
  create_venv_and_deps
  create_systemd_service
  open_firewall_port

  log "Done. Edit $CONFIG_FILE to set your MACs and broadcast."
  log "If using systemd, the app is live at: http://<your-pi-ip>:$PORT"
  log "To view logs: journalctl -u wol-web -f"
}

main "$@"
