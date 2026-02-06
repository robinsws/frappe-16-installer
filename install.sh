#!/usr/bin/env bash
# ERPNext v16 Install Script for Ubuntu 24.04
# Tested for amd64 systems.

# -------------------------
# Vars 
# -------------------------
DB_ROOT_PASS="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*()-_=+' | head -c 32)"
# -------------------------
# Update & Core Packages
# -------------------------
set -e
echo "[1/6] Updating system..."
sudo apt update -y
sudo apt upgrade -y

# -------------------------
# Install Essential Packages
# -------------------------
echo "[2/6] Installing base dependencies..."
sudo apt install -y git curl wget software-properties-common \
    build-essential python3-dev python3-pip python3-setuptools python3-venv \
    pkg-config xvfb libmysqlclient-dev nodejs  redis-server \
    mariadb-server mariadb-client yarnpkg 
1 | sudo apt-get install cron-apt -y
curl -LsSf https://astral.sh/uv/install.sh | sh
uv python install 3.14 --default
# -------------------------
# Install wkhtmltopdf
# -------------------------
echo "[3/6] Installing wkhtmltopdf..."
WK_DEB="wkhtmltox_0.12.6.1-2.jammy_amd64.deb"
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/$WK_DEB
sudo apt install -y ./$WK_DEB || sudo apt-get -f install -y && sudo apt install -y ./$WK_DEB
rm -f $WK_DEB

# -------------------------
# MariaDB Secure Install
# -------------------------
echo "[4/6] Securing MariaDB..."
sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
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
echo "[5/6] Installing bench CLI..."
source ~/.bashrc
uv tool install frappe-bench



# -------------------------
# Init Frappe Bench
# -------------------------
echo "[6/6] Initializing bench..."
source ~/.bashrc
bench init --frappe-branch version-16 frappe-bench



echo "Installation successfully completed!"

