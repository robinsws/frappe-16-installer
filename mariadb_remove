#!/usr/bin/env bash

echo "Stoppe MariaDB..."
sudo systemctl stop mariadb || true

echo "Entferne MariaDB Pakete..."
sudo apt-get purge -y mariadb-server mariadb-client mariadb-common mysql-common

echo "Entferne Abhängigkeiten und Verzeichnisse..."
sudo apt-get autoremove -y
sudo apt-get autoclean

# Lösche alle Datenbanken und Konfigurationsdateien!
# VORSICHT: Alle Daten gehen verloren.
sudo rm -rf /var/lib/mysql
sudo rm -rf /etc/mysql
sudo rm -rf /var/log/mysql
sudo rm -f /etc/mysql/mariadb.conf.d/99-frappe.cnf

echo "MariaDB wurde vollständig entfernt."
