#!/usr/bin/env bash

# VProfile MariaDB setup script
#
# Run:
# chmod +x scripts/mariadb-setup.sh
# sudo env DB_PASSWORD='CHANGE_ME' ./scripts/mariadb-setup.sh
#
# Optional variables:
# DB_NAME=accounts
# DB_USER=vprofile_app
# APP_REPO_BRANCH=Master

set -Eeuo pipefail

DB_NAME="${DB_NAME:-accounts}"
DB_USER="${DB_USER:-vprofile_app}"
DB_PASSWORD="${DB_PASSWORD:-}"

APP_REPO_URL="${APP_REPO_URL:-https://github.com/abdelrahmanonline4/sourcecodeseniorwr.git}"
APP_REPO_BRANCH="${APP_REPO_BRANCH:-Master}"
APP_DIR="/tmp/sourcecodeseniorwr"
SQL_FILE="${APP_DIR}/src/main/resources/db_backup.sql"

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo."
    exit 1
fi

if [[ -z "${DB_PASSWORD}" ]]; then
    echo "ERROR: DB_PASSWORD is required."
    echo "Example:"
    echo "sudo env DB_PASSWORD='CHANGE_ME' ./scripts/mariadb-setup.sh"
    exit 1
fi

if [[ ! "${DB_NAME}" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "ERROR: DB_NAME contains invalid characters."
    exit 1
fi

if [[ ! "${DB_USER}" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "ERROR: DB_USER contains invalid characters."
    exit 1
fi

escape_sql_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\'/\'\'}"
    printf '%s' "${value}"
}

DB_PASSWORD_SQL="$(escape_sql_string "${DB_PASSWORD}")"

echo "==> Installing MariaDB and Git..."

dnf install -y mariadb-server git

echo "==> Starting MariaDB..."

systemctl enable --now mariadb

echo "==> Configuring MariaDB to accept private network connections..."

cat > /etc/my.cnf.d/vprofile.cnf <<'EOF'
[mysqld]
bind-address=0.0.0.0
EOF

systemctl restart mariadb

echo "==> Creating the database and application user..."

mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
CHARACTER SET utf8
COLLATE utf8_general_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'%'
IDENTIFIED BY '${DB_PASSWORD_SQL}';

ALTER USER '${DB_USER}'@'%'
IDENTIFIED BY '${DB_PASSWORD_SQL}';

GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.*
TO '${DB_USER}'@'%';

FLUSH PRIVILEGES;
SQL

echo "==> Downloading the VProfile source code..."

rm -rf "${APP_DIR}"

git clone \
    --depth 1 \
    --branch "${APP_REPO_BRANCH}" \
    "${APP_REPO_URL}" \
    "${APP_DIR}"

if [[ ! -f "${SQL_FILE}" ]]; then
    echo "ERROR: Database backup was not found:"
    echo "${SQL_FILE}"
    exit 1
fi

echo "==> Importing the database backup..."

mariadb "${DB_NAME}" < "${SQL_FILE}"

if systemctl is-active --quiet firewalld; then
    echo "==> Allowing MariaDB through firewalld..."

    firewall-cmd \
        --permanent \
        --add-port=3306/tcp

    firewall-cmd --reload
fi

echo "==> Verifying the installation..."

mariadb-admin ping

echo
echo "Imported tables:"
mariadb -e "SHOW TABLES FROM \`${DB_NAME}\`;"

echo
echo "Number of users:"
mariadb "${DB_NAME}" \
    -e 'SELECT COUNT(*) AS users_count FROM `user`;'

echo
echo "Listening port:"
ss -lntp | grep 3306 || true

echo
echo "MariaDB setup completed successfully."
echo
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Port: 3306"
echo
echo "Required AWS Security Group rule:"
echo "TCP 3306 from the Tomcat Security Group only."