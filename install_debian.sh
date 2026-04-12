#!/usr/bin/env bash
# ERPNext v16 Install Script for Debian 13 (Trixie)
# Clean & compatible version (no Ubuntu leftovers)

set -e

# -------------------------
# Vars
# -------------------------
DB_ROOT_PASS="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*()-_=+' | head -c 32)"

# -------------------------
# Update & Core Packages
# -------------------------
echo "[1/7] Updating system..."
sudo apt update -y
sudo apt upgrade -y

# -------------------------
# Install Essential Packages #1
# -------------------------
echo "[2/7] Installing base dependencies..."
sudo apt install -y \
    wget 

# -------------------------
# wkhtmltopdf
# -------------------------
echo "[WKHTML] Installing wkhtmltopdf (static build)..."

WK_VERSION="0.12.6.1-3"
WK_FILE="wkhtmltox_${WK_VERSION}.linux-amd64.tar.xz"

wget https://github.com/wkhtmltopdf/packaging/releases/download/${WK_VERSION}/${WK_FILE}

tar -xf ${WK_FILE}

sudo cp wkhtmltox/bin/wkhtmltopdf /usr/local/bin/
sudo cp wkhtmltox/bin/wkhtmltoimage /usr/local/bin/

chmod +x /usr/local/bin/wkhtmltopdf
chmod +x /usr/local/bin/wkhtmltoimage

rm -rf wkhtmltox ${WK_FILE}

wkhtmltopdf --version

# -------------------------
# Install Essential Packages #2
# -------------------------
sudo apt install -y \
    git wget build-essential libfontconfig1 cron gcc certbot supervisor \
    pkg-config xvfb unzip gnupg redis-server \
    mariadb-server mariadb-client ca-certificates libmariadb-dev ansible \
    libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf-2.0-0 libffi-dev shared-mime-info \
    python3-dev python3-pip
# -------------------------
# Node.js (via NVM)
# -------------------------
echo "[3/7] Installing Node.js via NVM..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"

nvm install 22
nvm use 22
npm install -g yarn

# -------------------------
# Install UV + Python
# -------------------------
echo "[4/7] Installing Python via uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh

export PATH="$HOME/.local/bin:$PATH"

uv python install 3.11 --default

# -------------------------
# MariaDB Secure Install
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
# Install Bench
# -------------------------
echo "[6/7] Installing bench CLI..."
export PATH="$HOME/.local/bin:$PATH"
uv tool install frappe-bench

# -------------------------
# Init Frappe Bench
# -------------------------
echo "[7/7] Initializing bench..."
bench init frappe-bench --frappe-branch version-16 --python python3.11

cd frappe-bench

chmod -R 755 .

echo ""
echo "----------------------------------------"
echo "Installation successfully completed!"
echo "DB Root Password: $DB_ROOT_PASS"
echo "----------------------------------------"
