#!/usr/bin/env bash

# VProfile Tomcat setup script
#
# Run:
# chmod +x scripts/tomcat-setup.sh
#
# sudo env \
#   DB_PASSWORD='CHANGE_ME' \
#   RABBITMQ_PASSWORD='CHANGE_ME' \
#   ./scripts/tomcat-setup.sh

set -Eeuo pipefail

TOMCAT_VERSION="${TOMCAT_VERSION:-9.0.75}"
TOMCAT_HOME="/usr/local/tomcat"

APP_REPO_URL="${APP_REPO_URL:-https://github.com/abdelrahmanonline4/sourcecodeseniorwr.git}"
APP_REPO_BRANCH="${APP_REPO_BRANCH:-Master}"
APP_DIR="/tmp/sourcecodeseniorwr"

DB_HOST="${DB_HOST:-db.vprofile.internal}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-accounts}"
DB_USER="${DB_USER:-vprofile_app}"
DB_PASSWORD="${DB_PASSWORD:-}"

CACHE_HOST="${CACHE_HOST:-cache.vprofile.internal}"
CACHE_PORT="${CACHE_PORT:-11211}"

RABBITMQ_HOST="${RABBITMQ_HOST:-mq.vprofile.internal}"
RABBITMQ_PORT="${RABBITMQ_PORT:-5672}"
RABBITMQ_USER="${RABBITMQ_USER:-vprofile_app}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-}"

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo."
    exit 1
fi

if [[ -z "${DB_PASSWORD}" || -z "${RABBITMQ_PASSWORD}" ]]; then
    echo "ERROR: DB_PASSWORD and RABBITMQ_PASSWORD are required."
    exit 1
fi

echo "==> Installing Java, Maven, Git, wget, and netcat..."

dnf install -y \
    java-11-openjdk \
    java-11-openjdk-devel \
    maven \
    git \
    wget \
    nmap-ncat

JAVA_HOME="$(
    dirname "$(dirname "$(readlink -f "$(command -v java)")")"
)"

echo "==> Installing Apache Tomcat ${TOMCAT_VERSION}..."

cd /tmp

wget -q \
    "https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"

rm -rf "${TOMCAT_HOME}"
mkdir -p "${TOMCAT_HOME}"

tar -xzf "apache-tomcat-${TOMCAT_VERSION}.tar.gz"

cp -a \
    "apache-tomcat-${TOMCAT_VERSION}/." \
    "${TOMCAT_HOME}/"

if ! id tomcat >/dev/null 2>&1; then
    useradd \
        --system \
        --home-dir "${TOMCAT_HOME}" \
        --shell /sbin/nologin \
        tomcat
fi

chown -R tomcat:tomcat "${TOMCAT_HOME}"

echo "==> Creating the Tomcat systemd service..."

cat > /etc/systemd/system/tomcat.service <<EOF
[Unit]
Description=Apache Tomcat
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat

Environment="JAVA_HOME=${JAVA_HOME}"
Environment="CATALINA_HOME=${TOMCAT_HOME}"
Environment="CATALINA_BASE=${TOMCAT_HOME}"
Environment="CATALINA_PID=${TOMCAT_HOME}/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms256M -Xmx768M -server"

ExecStart=${TOMCAT_HOME}/bin/startup.sh
ExecStop=${TOMCAT_HOME}/bin/shutdown.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

echo "==> Downloading the VProfile source code..."

rm -rf "${APP_DIR}"

git clone \
    --depth 1 \
    --branch "${APP_REPO_BRANCH}" \
    "${APP_REPO_URL}" \
    "${APP_DIR}"

PROPERTIES_FILE="${APP_DIR}/src/main/resources/application.properties"

if [[ ! -f "${PROPERTIES_FILE}" ]]; then
    echo "ERROR: application.properties was not found."
    exit 1
fi

echo "==> Updating the backend service configuration..."

awk \
    -v db_host="${DB_HOST}" \
    -v db_port="${DB_PORT}" \
    -v db_name="${DB_NAME}" \
    -v db_user="${DB_USER}" \
    -v db_password="${DB_PASSWORD}" \
    -v cache_host="${CACHE_HOST}" \
    -v cache_port="${CACHE_PORT}" \
    -v mq_host="${RABBITMQ_HOST}" \
    -v mq_port="${RABBITMQ_PORT}" \
    -v mq_user="${RABBITMQ_USER}" \
    -v mq_password="${RABBITMQ_PASSWORD}" '
BEGIN { FS="=" }

$1 == "jdbc.url" {
    print "jdbc.url=jdbc:mysql://" db_host ":" db_port "/" db_name "?useUnicode=true&characterEncoding=UTF-8&zeroDateTimeBehavior=convertToNull"
    next
}
$1 == "jdbc.username" {
    print "jdbc.username=" db_user
    next
}
$1 == "jdbc.password" {
    print "jdbc.password=" db_password
    next
}
$1 == "memcached.active.host" {
    print "memcached.active.host=" cache_host
    next
}
$1 == "memcached.active.port" {
    print "memcached.active.port=" cache_port
    next
}
$1 == "memcached.standBy.host" {
    print "memcached.standBy.host=" cache_host
    next
}
$1 == "memcached.standBy.port" {
    print "memcached.standBy.port=" cache_port
    next
}
$1 == "rabbitmq.address" {
    print "rabbitmq.address=" mq_host
    next
}
$1 == "rabbitmq.port" {
    print "rabbitmq.port=" mq_port
    next
}
$1 == "rabbitmq.username" {
    print "rabbitmq.username=" mq_user
    next
}
$1 == "rabbitmq.password" {
    print "rabbitmq.password=" mq_password
    next
}

{ print }
' "${PROPERTIES_FILE}" > "${PROPERTIES_FILE}.tmp"

mv "${PROPERTIES_FILE}.tmp" "${PROPERTIES_FILE}"

echo "==> Testing backend ports..."

for service in \
    "${DB_HOST}:${DB_PORT}" \
    "${CACHE_HOST}:${CACHE_PORT}" \
    "${RABBITMQ_HOST}:${RABBITMQ_PORT}"
do
    host="${service%:*}"
    port="${service##*:}"

    if ! nc -z -w 5 "${host}" "${port}"; then
        echo "ERROR: Cannot connect to ${host}:${port}"
        exit 1
    fi
done

echo "==> Building the WAR file..."

cd "${APP_DIR}"
mvn clean package -DskipTests

WAR_FILE="${APP_DIR}/target/vprofile-v2.war"

if [[ ! -f "${WAR_FILE}" ]]; then
    echo "ERROR: WAR file was not created."
    exit 1
fi

echo "==> Deploying the application..."

systemctl stop tomcat 2>/dev/null || true

rm -rf \
    "${TOMCAT_HOME}/webapps/ROOT" \
    "${TOMCAT_HOME}/webapps/ROOT.war"

cp "${WAR_FILE}" "${TOMCAT_HOME}/webapps/ROOT.war"
chown tomcat:tomcat "${TOMCAT_HOME}/webapps/ROOT.war"

systemctl enable --now tomcat

echo "==> Waiting for the application..."

for attempt in {1..18}; do
    if curl -fsS \
        "http://localhost:8080/login" \
        >/dev/null 2>&1; then
        break
    fi

    if [[ "${attempt}" -eq 18 ]]; then
        echo "ERROR: The application did not become ready."
        tail -n 100 "${TOMCAT_HOME}/logs/catalina.out" || true
        exit 1
    fi

    sleep 5
done

echo
echo "Tomcat deployment completed successfully."
echo
echo "Tomcat status: $(systemctl is-active tomcat)"
echo "Application port: 8080"
echo "Local URL: http://localhost:8080/login"
echo
echo "Required AWS Security Group rule:"
echo "TCP 8080 from the ALB Security Group only."
echo
echo "Next test:"
echo "http://<ALB-DNS-NAME>/login"