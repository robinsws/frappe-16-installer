#!/usr/bin/env bash
# Frappe v16 Install Script for Debian 13 (Trixie)
#
# Optionen:
#   --site NAME          Site-Name (Pflicht bei --prod)
#   --prod               Produktiv-Setup ohne SSL
#   --admin-pass PASS    Administrator-Passwort (sonst zufällig generiert)
#   -h, --help           Hilfe

set -e

# -------------------------
# Parameter
# -------------------------
SITE=""
PROD=0
ADMIN_PASS=""

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --site)        SITE="$2"; shift 2 ;;
        --site=*)      SITE="${1#*=}"; shift ;;
        --prod)        PROD=1; shift ;;
        --admin-pass)  ADMIN_PASS="$2"; shift 2 ;;
        --admin-pass=*) ADMIN_PASS="${1#*=}"; shift ;;
        -h|--help)     usage 0 ;;
        *) echo "Unbekannte Option: $1"; usage 1 ;;
    esac
done

if [ "$(whoami)" = "root" ]; then
    echo "Bitte NICHT als root ausführen (sudo wird intern genutzt)."
    exit 1
fi

if [ "$PROD" = "1" ] && [ -z "$SITE" ]; then
    echo "--prod benötigt --site NAME"
    exit 1
fi

FRAPPE_USER="$(whoami)"
BENCH_DIR="$HOME/frappe-bench"
DB_ROOT_PASS="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
[ -z "$ADMIN_PASS" ] && ADMIN_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 16)"

# -------------------------
# Update & Core Packages
# -------------------------
echo "[1/7] Updating system..."
sudo apt update -y
sudo apt upgrade -y

echo "[2/7] Installing base dependencies..."
sudo apt install -y wget curl

# -------------------------
# wkhtmltopdf
# -------------------------
echo "[WKHTML] Installing wkhtmltopdf (Debian compatible)..."
WK_DEB="wkhtmltox_0.12.6.1-3.bookworm_amd64.deb"
wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/${WK_DEB}
sudo apt install -y ./${WK_DEB} || sudo apt --fix-broken install -y
rm -f ${WK_DEB}
wkhtmltopdf --version

sudo apt install -y \
    git wget build-essential libfontconfig1 cron gcc certbot supervisor nginx \
    pkg-config xvfb unzip gnupg redis-server \
    mariadb-server mariadb-client ca-certificates libmariadb-dev ansible \
    libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf-2.0-0 libffi-dev shared-mime-info \
    python3-dev python3-pip

# -------------------------
# Node.js (via NVM)
# -------------------------
echo "[3/7] Installing Node.js 24 via NVM..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 24
nvm use 24
nvm alias default 24
npm install -g yarn

# -------------------------
# UV + Python
# -------------------------
echo "[4/7] Installing Python via uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv python install 3.14 --default

# -------------------------
# MariaDB
# -------------------------
echo "[5/7] Securing MariaDB..."
sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db LIKE 'test%';
FLUSH PRIVILEGES;
EOF

sudo tee /etc/mysql/mariadb.conf.d/99-frappe.cnf > /dev/null <<'EOF'
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
innodb_file_per_table = 1
innodb_large_prefix = 1
innodb_buffer_pool_size = 1G
max_connections = 200
max_allowed_packet = 256M
EOF
sudo systemctl restart mariadb

# -------------------------
# Bench
# -------------------------
echo "[6/7] Installing bench CLI..."
uv tool install frappe-bench

echo "[7/7] Initializing bench..."
cd "$HOME"
bench init frappe-bench --frappe-branch version-16 --python python3.14
"$HOME/.local/share/uv/tools/frappe-bench/bin/python" -m ensurepip
chmod o+x "$HOME"     # nginx braucht nur Zugriff auf sites/assets
cd "$BENCH_DIR"

# -------------------------
# Site
# -------------------------
if [ -n "$SITE" ]; then
    echo "[SITE] Lege Site ${SITE} an..."
    if [ ! -d "sites/${SITE}" ]; then
        bench new-site "${SITE}" --set-default \
            --db-root-password "${DB_ROOT_PASS}" \
            --admin-password "${ADMIN_PASS}"
    else
        echo "Site existiert bereits – übersprungen."
        bench use "${SITE}"
    fi

    bench set-config -g developer_mode 0
    bench --site "${SITE}" set-config host_name "http://${SITE}"
    find sites -name site_config.json -exec chmod 600 {} \;
    chmod 600 sites/common_site_config.json
fi

# -------------------------
# Produktiv-Setup
# -------------------------
if [ "$PROD" = "1" ]; then
    echo "[PROD] Produktiv-Setup (nginx Port 80, supervisor, scheduler)..."
    BENCH_BIN="$(command -v bench)"

    # nginx und supervisor müssen laufen, bench macht nur reload
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo systemctl enable --now supervisor
    if ! sudo systemctl enable --now nginx; then
        echo "nginx startet nicht – Ursache:"
        sudo journalctl -u nginx --no-pager | tail -n 20
        sudo ss -tlnp | grep ':80 ' || true
        exit 1
    fi

    # /usr/sbin in PATH, sonst findet bench nginx nicht und startet die
    # mit ansible-core >= 2.19 fehlschlagende Ansible-Rolle
    sudo env "PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin" \
        ANSIBLE_ALLOW_BROKEN_CONDITIONALS=true \
        "$BENCH_BIN" setup production "$FRAPPE_USER" --yes

    # bench startet eigene Redis-Instanzen
    sudo systemctl disable --now redis-server || true

    sudo nginx -t
    sudo systemctl restart nginx

    bench --site "${SITE}" enable-scheduler
    bench --site "${SITE}" set-maintenance-mode off
    sudo supervisorctl reread
    sudo supervisorctl update
    sleep 5
    sudo supervisorctl status || true
fi

echo ""
echo "----------------------------------------"
echo "Installation successfully completed!"
echo "DB Root Password: $DB_ROOT_PASS"
if [ -n "$SITE" ]; then
    echo "Site:            $SITE"
    echo "Admin-Passwort:  $ADMIN_PASS"
fi
[ "$PROD" = "1" ] && echo "URL:             http://${SITE}"
echo "----------------------------------------"
