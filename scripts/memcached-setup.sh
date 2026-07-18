#!/usr/bin/env bash

# VProfile Memcached setup script
#
# Run:
# chmod +x scripts/memcached-setup.sh
# sudo ./scripts/memcached-setup.sh

set -Eeuo pipefail

MEMCACHED_PORT="${MEMCACHED_PORT:-11211}"
CACHE_SIZE_MB="${CACHE_SIZE_MB:-64}"
MAX_CONNECTIONS="${MAX_CONNECTIONS:-1024}"
CONFIG_FILE="/etc/sysconfig/memcached"

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo."
    exit 1
fi

echo "==> Installing Memcached and netcat..."

dnf install -y memcached nmap-ncat

echo "==> Configuring Memcached..."

if [[ -f "${CONFIG_FILE}" ]]; then
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.backup"
fi

cat > "${CONFIG_FILE}" <<EOF
PORT="${MEMCACHED_PORT}"
USER="memcached"
MAXCONN="${MAX_CONNECTIONS}"
CACHESIZE="${CACHE_SIZE_MB}"
OPTIONS="-l 0.0.0.0 -U 0"
EOF

echo "==> Starting Memcached..."

systemctl enable --now memcached
systemctl restart memcached

if systemctl is-active --quiet firewalld; then
    echo "==> Allowing TCP ${MEMCACHED_PORT} through firewalld..."

    firewall-cmd \
        --permanent \
        --add-port="${MEMCACHED_PORT}/tcp"

    firewall-cmd --reload
fi

echo "==> Verifying the service..."

if ! systemctl is-active --quiet memcached; then
    echo "ERROR: Memcached is not running."
    systemctl status memcached --no-pager
    exit 1
fi

if ! ss -lntp | grep -q ":${MEMCACHED_PORT}"; then
    echo "ERROR: Memcached is not listening on port ${MEMCACHED_PORT}."
    exit 1
fi

VERSION_OUTPUT="$(
    printf "version\r\n" |
    nc -w 3 127.0.0.1 "${MEMCACHED_PORT}"
)"

if [[ "${VERSION_OUTPUT}" != VERSION* ]]; then
    echo "ERROR: Memcached did not return its version."
    exit 1
fi

echo
echo "Memcached setup completed successfully."
echo
echo "Status: $(systemctl is-active memcached)"
echo "Port: ${MEMCACHED_PORT}"
echo "Cache size: ${CACHE_SIZE_MB} MB"
echo "Maximum connections: ${MAX_CONNECTIONS}"
echo "Response: ${VERSION_OUTPUT}"
echo
echo "Required AWS Security Group rule:"
echo "TCP ${MEMCACHED_PORT} from the Tomcat Security Group only."
echo
echo "Test from the Tomcat server:"
echo "printf 'version\\r\\n' | nc cache.vprofile.internal ${MEMCACHED_PORT}"