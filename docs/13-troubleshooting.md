# Troubleshooting

## Overview

This page contains the main problems I faced while deploying VProfile manually on AWS.

I used the following troubleshooting order:

```text
1. Check the service
2. Check the listening port
3. Check private DNS
4. Check the Security Group
5. Check credentials
6. Check application logs
7. Check ALB health
```

---

## 1. EC2 Did Not Appear in Session Manager

### Problem

The EC2 instance was running, but I could not connect using Session Manager.

### Cause

The correct IAM Instance Profile was not attached.

### Fix

Create an EC2 role with:

```text
AmazonSSMManagedInstanceCore
```

Attach it from:

```text
EC2
-> Instances
-> Actions
-> Security
-> Modify IAM role
```

Also verify that the instance has outbound HTTPS access through the NAT Gateway.

---

## 2. Private EC2 Could Not Access the Internet

### Problem

Package installation and Git cloning failed.

Example:

```text
Could not resolve host
Connection timed out
```

### Fix

Verify the private route table:

```text
0.0.0.0/0 -> NAT Gateway
```

Verify that the NAT Gateway is inside a public subnet.

The public route table must contain:

```text
0.0.0.0/0 -> Internet Gateway
```

Test from the instance:

```bash
getent hosts github.com
curl -I https://github.com
```

---

## 3. Private DNS Name Did Not Resolve

### Problem

Tomcat could not resolve names such as:

```text
db.vprofile.internal
cache.vprofile.internal
mq.vprofile.internal
```

### Fix

Check that:

- The Route 53 hosted zone is private
- It is associated with `vprofile-vpc`
- VPC DNS resolution is enabled
- VPC DNS hostnames are enabled
- The DNS record contains the correct private IP

Test from Tomcat:

```bash
getent hosts db.vprofile.internal
getent hosts cache.vprofile.internal
getent hosts mq.vprofile.internal
```

---

## 4. MariaDB Worked Locally but Not from Tomcat

### Problem

MariaDB worked on the database server, but Tomcat could not connect.

### Fix

Check MariaDB:

```bash
sudo systemctl is-active mariadb
sudo ss -lntp | grep 3306
```

MariaDB should listen on:

```text
0.0.0.0:3306
```

Configuration:

```ini
[mysqld]
bind-address=0.0.0.0
```

Restart the service:

```bash
sudo systemctl restart mariadb
```

The database Security Group must allow:

```text
TCP 3306 from vprofile-app-sg
```

Test from Tomcat:

```bash
nc -zv db.vprofile.internal 3306
```

---

## 5. Database Access Was Denied

### Problem

The application showed:

```text
Access denied for user
```

### Fix

Verify the database user:

```bash
sudo mariadb -e "
SELECT User, Host
FROM mysql.user
WHERE User = 'vprofile_app';
"
```

The user must be allowed to connect remotely:

```text
vprofile_app@%
```

Verify permissions:

```bash
sudo mariadb -e "
SHOW GRANTS FOR 'vprofile_app'@'%';
"
```

Also confirm that the username and password in `application.properties` are correct.

---

## 6. Memcached Connection Failed

### Problem

Memcached worked locally but Tomcat could not connect.

### Fix

Check the service and port:

```bash
sudo systemctl is-active memcached
sudo ss -lntp | grep 11211
```

Memcached should listen on:

```text
0.0.0.0:11211
```

Configuration:

```text
OPTIONS="-l 0.0.0.0 -U 0"
```

Restart it:

```bash
sudo systemctl restart memcached
```

The Security Group must allow:

```text
TCP 11211 from vprofile-app-sg
```

Test from Tomcat:

```bash
printf "version\r\n" \
  | nc cache.vprofile.internal 11211
```

---

## 7. RabbitMQ User Had No Permission

### Problem

The application showed:

```text
ACCESS_REFUSED
```

### Cause

The RabbitMQ user existed but did not have permissions on virtual host `/`.

### Fix

```bash
sudo rabbitmqctl set_permissions \
  -p / \
  vprofile_app \
  ".*" \
  ".*" \
  ".*"
```

Verify:

```bash
sudo rabbitmqctl list_permissions -p /
```

Also test RabbitMQ:

```bash
sudo rabbitmq-diagnostics -q ping
nc -zv mq.vprofile.internal 5672
```

---

## 8. RabbitMQ Guest User Failed Remotely

### Problem

The `guest` user worked locally but failed from Tomcat.

### Cause

RabbitMQ normally restricts the `guest` user to local connections.

### Fix

Create a dedicated user:

```bash
sudo rabbitmqctl add_user \
  vprofile_app \
  'CHANGE_ME_STRONG_PASSWORD'
```

Give it permissions:

```bash
sudo rabbitmqctl set_permissions \
  -p / \
  vprofile_app \
  ".*" \
  ".*" \
  ".*"
```

Update the application configuration with the new username and password.

---

## 9. Tomcat Was Running but the Application Did Not Open

### Checks

```bash
sudo systemctl is-active tomcat
sudo ss -lntp | grep 8080
curl -I http://localhost:8080/login
```

Check the logs:

```bash
sudo tail -n 100 \
  /usr/local/tomcat/logs/catalina.out
```

Verify that the WAR file exists:

```bash
ls -lh /usr/local/tomcat/webapps/ROOT.war
```

The application should be deployed as:

```text
ROOT.war
```

so it opens from the root URL.

---

## 10. Configuration Changes Did Not Appear

### Problem

I changed `application.properties`, but Tomcat still used the old configuration.

### Cause

The configuration file is packaged inside the WAR during the Maven build.

### Fix

Rebuild and redeploy:

```bash
cd /tmp/sourcecodeseniorwr

mvn clean install

sudo systemctl stop tomcat

sudo rm -rf \
  /usr/local/tomcat/webapps/ROOT \
  /usr/local/tomcat/webapps/ROOT.war

sudo cp \
  target/vprofile-v2.war \
  /usr/local/tomcat/webapps/ROOT.war

sudo chown \
  tomcat:tomcat \
  /usr/local/tomcat/webapps/ROOT.war

sudo systemctl start tomcat
```

---

## 11. ALB Target Was Unhealthy

### Problem

The target group showed:

```text
Unhealthy
```

### Fix

First, test Tomcat locally:

```bash
curl -I http://localhost:8080/login
```

Then verify:

```text
Target Group Protocol: HTTP
Target Group Port: 8080
Health Check Path: /login
Success Codes: 200-399
```

The Tomcat Security Group must allow:

```text
TCP 8080 from vprofile-alb-sg
```

---

## 12. ALB DNS Did Not Open

Check that:

- The ALB is internet-facing
- It uses two public subnets
- The public route table points to the Internet Gateway
- The ALB Security Group allows HTTP port `80`
- The listener forwards to the correct target group
- The Tomcat target is healthy

Test:

```bash
curl -I http://<ALB-DNS-NAME>/login
```

---

## Timeout vs Connection Refused

These two errors usually mean different things.

### Connection Timed Out

```text
Connection timed out
```

Usually check:

- Security Groups
- Route tables
- Network ACLs
- Firewall
- Wrong DNS record

### Connection Refused

```text
Connection refused
```

Usually check:

- Service is stopped
- Service is listening on another port
- Service listens only on localhost

---

## Important Log Commands

### Tomcat

```bash
sudo tail -n 100 \
  /usr/local/tomcat/logs/catalina.out
```

### MariaDB

```bash
sudo journalctl \
  -u mariadb \
  --no-pager \
  -n 100
```

### Memcached

```bash
sudo journalctl \
  -u memcached \
  --no-pager \
  -n 100
```

### RabbitMQ

```bash
sudo journalctl \
  -u rabbitmq-server \
  --no-pager \
  -n 100
```

---

## Quick Diagnostic Commands

Run from the Tomcat server:

```bash
getent hosts db.vprofile.internal
getent hosts cache.vprofile.internal
getent hosts mq.vprofile.internal

nc -zv db.vprofile.internal 3306
nc -zv cache.vprofile.internal 11211
nc -zv mq.vprofile.internal 5672

curl -I http://localhost:8080/login
```

When these tests succeed, check the ALB target health and public DNS.

---

## Next Step

Continue to:

[Cleanup](14-cleanup.md)