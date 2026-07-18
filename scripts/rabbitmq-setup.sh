#!/usr/bin/env bash

# VProfile RabbitMQ setup script
#
# Run:
# chmod +x scripts/rabbitmq-setup.sh
# sudo env RABBITMQ_PASSWORD='CHANGE_ME' \
#   ./scripts/rabbitmq-setup.sh

set -Eeuo pipefail

RABBITMQ_USER="${RABBITMQ_USER:-vprofile_app}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-}"
RABBITMQ_PORT="${RABBITMQ_PORT:-5672}"

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo."
    exit 1
fi

if [[ -z "${RABBITMQ_PASSWORD}" ]]; then
    echo "ERROR: RABBITMQ_PASSWORD is required."
    echo
    echo "Example:"
    echo "sudo env RABBITMQ_PASSWORD='CHANGE_ME' \\"
    echo "  ./scripts/rabbitmq-setup.sh"
    exit 1
fi

if [[ ! "${RABBITMQ_USER}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "ERROR: RABBITMQ_USER contains invalid characters."
    exit 1
fi

echo "==> Installing RabbitMQ..."

dnf install -y wget

if ! dnf -q list rabbitmq-server >/dev/null 2>&1; then
    dnf install -y centos-release-rabbitmq-38
fi

dnf install -y rabbitmq-server

echo "==> Starting RabbitMQ..."

systemctl enable --now rabbitmq-server

echo "==> Waiting for RabbitMQ..."

for attempt in {1..12}; do
    if rabbitmq-diagnostics -q ping >/dev/null 2>&1; then
        break
    fi

    if [[ "${attempt}" -eq 12 ]]; then
        echo "ERROR: RabbitMQ did not become ready."
        systemctl status rabbitmq-server --no-pager
        exit 1
    fi

    sleep 5
done

echo "==> Creating the application user..."

if rabbitmqctl list_users -q |
    awk '{print $1}' |
    grep -Fxq "${RABBITMQ_USER}"; then

    rabbitmqctl change_password \
        "${RABBITMQ_USER}" \
        "${RABBITMQ_PASSWORD}"
else
    rabbitmqctl add_user \
        "${RABBITMQ_USER}" \
        "${RABBITMQ_PASSWORD}"
fi

echo "==> Setting virtual host permissions..."

rabbitmqctl set_permissions \
    -p / \
    "${RABBITMQ_USER}" \
    '.*' \
    '.*' \
    '.*'

if systemctl is-active --quiet firewalld; then
    echo "==> Allowing TCP ${RABBITMQ_PORT} through firewalld..."

    firewall-cmd \
        --permanent \
        --add-port="${RABBITMQ_PORT}/tcp"

    firewall-cmd --reload
fi

echo "==> Verifying RabbitMQ..."

rabbitmq-diagnostics -q ping

if ! ss -lntp | grep -q ":${RABBITMQ_PORT}"; then
    echo "ERROR: RabbitMQ is not listening on port ${RABBITMQ_PORT}."
    exit 1
fi

echo
echo "RabbitMQ users:"
rabbitmqctl list_users

echo
echo "Virtual host permissions:"
rabbitmqctl list_permissions -p /

echo
echo "RabbitMQ setup completed successfully."
echo
echo "User: ${RABBITMQ_USER}"
echo "Virtual host: /"
echo "AMQP port: ${RABBITMQ_PORT}"
echo
echo "Required AWS Security Group rule:"
echo "TCP ${RABBITMQ_PORT} from the Tomcat Security Group only."
echo
echo "Application configuration:"
echo "rabbitmq.address=mq.vprofile.internal"
echo "rabbitmq.port=${RABBITMQ_PORT}"
echo "rabbitmq.username=${RABBITMQ_USER}"
echo "rabbitmq.password=<YOUR_RABBITMQ_PASSWORD>"
echo
echo "Test from the Tomcat server:"
echo "nc -zv mq.vprofile.internal ${RABBITMQ_PORT}"