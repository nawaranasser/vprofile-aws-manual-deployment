# Testing the Deployment

## Overview

After deploying all components, I tested the application from the backend services up to the public ALB endpoint.

The final request flow was:

```text
User
  |
  v
Application Load Balancer
  |
  v
Tomcat
  |
  +--> MariaDB
  +--> Memcached
  +--> RabbitMQ
```

---

## 1. Test Private DNS

Run these commands from the Tomcat EC2 instance:

```bash
getent hosts db.vprofile.internal
getent hosts cache.vprofile.internal
getent hosts mq.vprofile.internal
```

Each name should return the correct private IP address.

---

## 2. Test Backend Ports

From the Tomcat server:

```bash
nc -zv db.vprofile.internal 3306
nc -zv cache.vprofile.internal 11211
nc -zv mq.vprofile.internal 5672
```

All connections should succeed.

---

## 3. Test MariaDB

Connect from Tomcat:

```bash
mariadb \
  -h db.vprofile.internal \
  -u vprofile_app \
  -p \
  accounts
```

Inside MariaDB:

```sql
SHOW TABLES;
SELECT COUNT(*) FROM `user`;
EXIT;
```

Expected tables include:

```text
role
user
user_role
```

---

## 4. Test Memcached

From Tomcat:

```bash
printf "version\r\n" \
  | nc cache.vprofile.internal 11211
```

Expected output:

```text
VERSION <memcached-version>
```

---

## 5. Test RabbitMQ

Check the RabbitMQ port:

```bash
nc -zv mq.vprofile.internal 5672
```

On the RabbitMQ server:

```bash
sudo rabbitmq-diagnostics -q ping
sudo rabbitmqctl list_users
sudo rabbitmqctl list_permissions -p /
```

Expected result:

```text
Ping succeeded
```

The application user should have permissions on virtual host `/`.

---

## 6. Test Tomcat Locally

On the Tomcat EC2 instance:

```bash
sudo systemctl is-active tomcat
sudo ss -lntp | grep 8080
curl -I http://localhost:8080/login
```

Expected result:

```text
active
HTTP/1.1 200
```

---

## 7. Check the Application Logs

```bash
sudo tail -n 100 \
  /usr/local/tomcat/logs/catalina.out
```

Check for errors related to:

```text
MariaDB
Memcached
RabbitMQ
Application startup
```

Follow the logs in real time:

```bash
sudo tail -f \
  /usr/local/tomcat/logs/catalina.out
```

---

## 8. Check ALB Target Health

Open:

```text
EC2
-> Target Groups
-> vprofile-app-tg
-> Targets
```

The Tomcat target should show:

```text
Healthy
```

If the target is unhealthy, first confirm that this command works on Tomcat:

```bash
curl -I http://localhost:8080/login
```

---

## 9. Test the Public Application

Open the ALB DNS name:

```text
http://<ALB-DNS-NAME>/login
```

The VProfile login page should appear.

The same test can be performed from a terminal:

```bash
curl -I http://<ALB-DNS-NAME>/login
```

Expected result:

```text
HTTP/1.1 200
```

---

## 10. Test the Application Features

After opening the application:

1. Log in using a test account.
2. Open the user profile page.
3. Confirm that user data loads from MariaDB.
4. Open the RabbitMQ test endpoint:

```text
http://<ALB-DNS-NAME>/user/rabbit
```

A successful response confirms that the application can communicate with RabbitMQ.

Check RabbitMQ after the test:

```bash
sudo rabbitmqctl list_connections
sudo rabbitmqctl list_exchanges
sudo rabbitmqctl list_queues
```

---

## Final Verification

```text
[ ] Private DNS names resolve correctly
[ ] MariaDB port 3306 is reachable
[ ] Memcached port 11211 is reachable
[ ] RabbitMQ port 5672 is reachable
[ ] Database login works from Tomcat
[ ] Memcached responds to the version command
[ ] RabbitMQ diagnostic ping succeeds
[ ] Tomcat is active
[ ] Local /login request returns HTTP 200
[ ] ALB target is healthy
[ ] Public ALB /login request returns HTTP 200
[ ] The login page opens in the browser
[ ] The RabbitMQ application test works
```

---

## Test Order

When troubleshooting, test in this order:

```text
1. Service status
2. Listening port
3. Private DNS
4. Network connection
5. Username and password
6. Tomcat local request
7. ALB target health
8. Public ALB request
```

This makes it easier to find the failed layer.

---

## Next Step

Continue to:

[Troubleshooting](13-troubleshooting.md)