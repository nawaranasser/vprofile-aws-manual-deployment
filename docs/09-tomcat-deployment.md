# Tomcat Application Deployment

## Overview

In this step, I deployed the VProfile Java application on a private EC2 instance.

The application runs on Apache Tomcat and listens on port `8080`.

```text
User -> ALB -> Tomcat -> Backend Services
```

Tomcat connects to:

```text
db.vprofile.internal:3306
cache.vprofile.internal:11211
mq.vprofile.internal:5672
```

---

## 1. Connect to the EC2 Instance

I connected using AWS Systems Manager Session Manager.

```bash
whoami
cat /etc/os-release
```

---

## 2. Install the Required Packages

```bash
sudo dnf install -y \
  java-11-openjdk \
  java-11-openjdk-devel \
  git \
  maven \
  wget
```

Verify the installation:

```bash
java -version
mvn -version
git --version
```

---

## 3. Install Apache Tomcat

The project used Tomcat `9.0.75`.

```bash
cd /tmp

wget \
  https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.75/bin/apache-tomcat-9.0.75.tar.gz

tar -xzf apache-tomcat-9.0.75.tar.gz
```

Create a Tomcat user:

```bash
sudo useradd \
  --home-dir /usr/local/tomcat \
  --shell /sbin/nologin \
  tomcat
```

Copy Tomcat files:

```bash
sudo mkdir -p /usr/local/tomcat

sudo cp -r \
  /tmp/apache-tomcat-9.0.75/* \
  /usr/local/tomcat/

sudo chown -R tomcat:tomcat /usr/local/tomcat
```

---

## 4. Create the Tomcat Service

```bash
sudo tee /etc/systemd/system/tomcat.service > /dev/null <<'EOF'
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat

Environment="JAVA_HOME=/usr/lib/jvm/java-11-openjdk"
Environment="CATALINA_HOME=/usr/local/tomcat"
Environment="CATALINA_BASE=/usr/local/tomcat"
Environment="CATALINA_PID=/usr/local/tomcat/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server"
Environment="JAVA_OPTS=-Djava.awt.headless=true"

ExecStart=/usr/local/tomcat/bin/startup.sh
ExecStop=/usr/local/tomcat/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
```

Start Tomcat:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now tomcat
```

Verify it:

```bash
sudo systemctl status tomcat --no-pager
sudo ss -lntp | grep 8080
curl -I http://localhost:8080
```

---

## 5. Download the Application Code

```bash
sudo rm -rf /tmp/sourcecodeseniorwr

git clone \
  -b Master \
  https://github.com/abdelrahmanonline4/sourcecodeseniorwr.git \
  /tmp/sourcecodeseniorwr

cd /tmp/sourcecodeseniorwr
```

---

## 6. Update `application.properties`

Open the configuration file:

```bash
nano src/main/resources/application.properties
```

Use the AWS private DNS names:

```properties
# Database
jdbc.driverClassName=com.mysql.jdbc.Driver
jdbc.url=jdbc:mysql://db.vprofile.internal:3306/accounts?useUnicode=true&characterEncoding=UTF-8&zeroDateTimeBehavior=convertToNull
jdbc.username=vprofile_app
jdbc.password=<DATABASE_PASSWORD>

# Memcached
memcached.active.host=cache.vprofile.internal
memcached.active.port=11211
memcached.standBy.host=cache.vprofile.internal
memcached.standBy.port=11211

# RabbitMQ
rabbitmq.address=mq.vprofile.internal
rabbitmq.port=5672
rabbitmq.username=vprofile_app
rabbitmq.password=<RABBITMQ_PASSWORD>
```

Replace the password placeholders only on the EC2 instance.

Never commit real passwords to GitHub.

---

## 7. Test the Backend Connections

Before building the application, verify DNS:

```bash
getent hosts db.vprofile.internal
getent hosts cache.vprofile.internal
getent hosts mq.vprofile.internal
```

Test the service ports:

```bash
nc -zv db.vprofile.internal 3306
nc -zv cache.vprofile.internal 11211
nc -zv mq.vprofile.internal 5672
```

All three connections should succeed.

---

## 8. Build the WAR File

```bash
cd /tmp/sourcecodeseniorwr

mvn clean install
```

The generated application artifact is:

```text
target/vprofile-v2.war
```

Verify it:

```bash
ls -lh target/vprofile-v2.war
```

---

## 9. Deploy the Application

Stop Tomcat:

```bash
sudo systemctl stop tomcat
```

Remove the default root application:

```bash
sudo rm -rf /usr/local/tomcat/webapps/ROOT*
```

Deploy the VProfile WAR as the root application:

```bash
sudo cp \
  target/vprofile-v2.war \
  /usr/local/tomcat/webapps/ROOT.war

sudo chown \
  tomcat:tomcat \
  /usr/local/tomcat/webapps/ROOT.war
```

Start Tomcat:

```bash
sudo systemctl start tomcat
```

Wait until Tomcat extracts the WAR:

```bash
sleep 15
```

---

## 10. Verify the Application

Check Tomcat:

```bash
sudo systemctl is-active tomcat
sudo ss -lntp | grep 8080
```

Test the login page locally:

```bash
curl -I http://localhost:8080/login
```

Expected result:

```text
HTTP/1.1 200
```

Check the deployed files:

```bash
ls -ld /usr/local/tomcat/webapps/ROOT*
```

Follow the application logs:

```bash
sudo tail -f /usr/local/tomcat/logs/catalina.out
```

---

## Security Group Rule

The Tomcat Security Group allows port `8080` only from the ALB Security Group.

```text
Protocol: TCP
Port: 8080
Source: vprofile-alb-sg
```

Port `8080` should not be open to the whole internet.

---

## Common Problems

### ALB Target Is Unhealthy

Check Tomcat locally:

```bash
curl -I http://localhost:8080/login
```

Check the listener:

```bash
sudo ss -lntp | grep 8080
```

Verify:

```text
Target Group Port: 8080
Health Check Path: /login
Tomcat SG Source: ALB Security Group
```

---

### Application Shows Database or Service Errors

Test DNS:

```bash
getent hosts db.vprofile.internal
getent hosts cache.vprofile.internal
getent hosts mq.vprofile.internal
```

Test ports:

```bash
nc -zv db.vprofile.internal 3306
nc -zv cache.vprofile.internal 11211
nc -zv mq.vprofile.internal 5672
```

Then check:

```bash
sudo tail -n 100 /usr/local/tomcat/logs/catalina.out
```

---

### Configuration Changes Do Not Appear

The `application.properties` file is included inside the WAR during the Maven build.

After changing the file, rebuild and redeploy:

```bash
mvn clean install

sudo systemctl stop tomcat
sudo rm -rf /usr/local/tomcat/webapps/ROOT*
sudo cp target/vprofile-v2.war /usr/local/tomcat/webapps/ROOT.war
sudo chown tomcat:tomcat /usr/local/tomcat/webapps/ROOT.war
sudo systemctl start tomcat
```

---

### Tomcat Is Running but the Root URL Returns 404

Confirm that the artifact was deployed as:

```text
/usr/local/tomcat/webapps/ROOT.war
```

Do not deploy it only as:

```text
vprofile-v2.war
```

Otherwise, the application may open under:

```text
/vprofile-v2/
```

instead of the root path.

---

## Final Test

After connecting Tomcat to the ALB, open:

```text
http://<ALB-DNS-NAME>/login
```

The VProfile login page should appear.

---

## Next Step

Continue to:

[Route 53 Private DNS](10-route53-private-dns.md)