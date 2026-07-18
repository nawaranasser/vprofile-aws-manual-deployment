# Security Groups

## Overview

Security Groups control the traffic that can enter and leave AWS resources.

In this project, I created a separate Security Group for each application component.

This makes the architecture easier to understand and more secure.

The main rule was:

> Only allow the traffic that each service needs.

---

## Security Group Design

The project uses the following Security Groups:

| Security Group | Used By |
|---|---|
| `vprofile-alb-sg` | Application Load Balancer |
| `vprofile-app-sg` | Tomcat EC2 instance |
| `vprofile-db-sg` | MariaDB EC2 instance |
| `vprofile-cache-sg` | Memcached EC2 instance |
| `vprofile-rabbitmq-sg` | RabbitMQ EC2 instance |

The communication flow is:

```text
Internet
   |
   | HTTP 80
   v
ALB Security Group
   |
   | TCP 8080
   v
Tomcat Security Group
   |
   +------ TCP 3306 ------> MariaDB Security Group
   |
   +------ TCP 11211 -----> Memcached Security Group
   |
   +------ TCP 5672 ------> RabbitMQ Security Group
```

---

## Why Separate Security Groups Were Used

Using one Security Group for all servers would make the rules difficult to manage.

Separate Security Groups provide better control.

For example:

- Internet users can access the ALB
- The ALB can access Tomcat
- Tomcat can access the backend services
- Internet users cannot access MariaDB
- Internet users cannot access Memcached
- Internet users cannot access RabbitMQ

---

# 1. Application Load Balancer Security Group

## Name

```text
vprofile-alb-sg
```

## Inbound Rules

| Type | Protocol | Port | Source |
|---|---|---:|---|
| HTTP | TCP | `80` | `0.0.0.0/0` |

This rule allows users to open the application from the internet.

If HTTPS is added later, another rule can be created:

| Type | Protocol | Port | Source |
|---|---|---:|---|
| HTTPS | TCP | `443` | `0.0.0.0/0` |

## Outbound Rules

For this lab, the default outbound rule was used:

| Type | Protocol | Port | Destination |
|---|---|---|---|
| All traffic | All | All | `0.0.0.0/0` |

The ALB needs outbound access to send traffic to Tomcat.

---

# 2. Tomcat Application Security Group

## Name

```text
vprofile-app-sg
```

## Inbound Rules

| Type | Protocol | Port | Source |
|---|---|---:|---|
| Custom TCP | TCP | `8080` | `vprofile-alb-sg` |

This rule allows the Application Load Balancer to reach Tomcat.

The source is the ALB Security Group, not the whole internet.

Correct:

```text
Port 8080
Source: vprofile-alb-sg
```

Not recommended:

```text
Port 8080
Source: 0.0.0.0/0
```

## Outbound Rules

Tomcat needs outbound access to:

- MariaDB on port 3306
- Memcached on port 11211
- RabbitMQ on port 5672
- Package repositories
- GitHub
- AWS Systems Manager endpoints

For this learning project, the default outbound rule was used:

| Type | Protocol | Port | Destination |
|---|---|---|---|
| All traffic | All | All | `0.0.0.0/0` |

In a production environment, outbound access can be restricted.

---

# 3. MariaDB Security Group

## Name

```text
vprofile-db-sg
```

## Inbound Rules

| Type | Protocol | Port | Source |
|---|---|---:|---|
| MySQL/MariaDB | TCP | `3306` | `vprofile-app-sg` |

This rule allows only the Tomcat application server to connect to MariaDB.

MariaDB should not be open to the internet.

Not recommended:

```text
Port 3306
Source: 0.0.0.0/0
```

Correct:

```text
Port 3306
Source: vprofile-app-sg
```

---

# 4. Memcached Security Group

## Name

```text
vprofile-cache-sg
```

## Inbound Rules

| Type | Protocol | Port | Source |
|---|---|---:|---|
| Custom TCP | TCP | `11211` | `vprofile-app-sg` |

Only Tomcat needs to communicate with Memcached.

Memcached should never be directly exposed to the internet.

---

# 5. RabbitMQ Security Group

## Name

```text
vprofile-rabbitmq-sg
```

## Inbound Rules

| Type | Protocol | Port | Source |
|---|---|---:|---|
| Custom TCP | TCP | `5672` | `vprofile-app-sg` |

Port 5672 is used by the application to communicate with RabbitMQ.

RabbitMQ may also provide a management interface on port 15672.

The management port was not opened publicly in this project.

If temporary internal access is required, it should be restricted to a trusted source.

---

## Final Inbound Rules Summary

| Resource | Port | Allowed Source |
|---|---:|---|
| Application Load Balancer | `80` | Internet |
| Tomcat | `8080` | ALB Security Group |
| MariaDB | `3306` | Tomcat Security Group |
| Memcached | `11211` | Tomcat Security Group |
| RabbitMQ | `5672` | Tomcat Security Group |

---

## Security Group References

AWS Security Groups can reference other Security Groups.

For example, the Tomcat rule does not need the ALB private IP address.

It uses:

```text
Source: vprofile-alb-sg
```

The database rule uses:

```text
Source: vprofile-app-sg
```

This is better than using fixed IP addresses because EC2 and ALB private IP addresses may change.

---

## Systems Manager Access

The EC2 instances were accessed using AWS Systems Manager Session Manager.

Because of this, I did not need to open SSH port 22 to the internet.

No inbound SSH rule was required:

```text
Port 22: Not open
```

Session Manager works through outbound HTTPS communication on port 443.

The EC2 instance also needs:

- SSM Agent
- IAM Instance Profile
- Network access to AWS Systems Manager endpoints

---

## Creating a Security Group

From the AWS Management Console:

```text
VPC Console
-> Security Groups
-> Create Security Group
```

For each Security Group, I selected:

```text
VPC: vprofile-vpc
```

After creating the Security Groups, I added the required inbound rules.

---

## Recommended Creation Order

The Security Groups can be created in this order:

```text
1. vprofile-alb-sg
2. vprofile-app-sg
3. vprofile-db-sg
4. vprofile-cache-sg
5. vprofile-rabbitmq-sg
```

After creating them, add the references:

```text
ALB SG -> Tomcat SG
Tomcat SG -> Database SG
Tomcat SG -> Cache SG
Tomcat SG -> RabbitMQ SG
```

---

## Testing Connectivity

The following tests were performed from the Tomcat EC2 instance.

### Test MariaDB Port

```bash
nc -zv db.vprofile.internal 3306
```

Expected result:

```text
Connection succeeded
```

An alternative test is:

```bash
timeout 5 bash -c '</dev/tcp/db.vprofile.internal/3306'
echo $?
```

Exit code `0` means the port is reachable.

---

### Test Memcached Port

```bash
nc -zv cache.vprofile.internal 11211
```

Expected result:

```text
Connection succeeded
```

---

### Test RabbitMQ Port

```bash
nc -zv mq.vprofile.internal 5672
```

Expected result:

```text
Connection succeeded
```

---

### Test Tomcat from Inside the VPC

```bash
curl -I http://localhost:8080
```

Or:

```bash
curl -I http://PRIVATE_APP_IP:8080
```

A response from Tomcat confirms that the application port is listening.

---

## Problem: ALB Target Was Unhealthy

### Symptoms

The Target Group showed:

```text
Unhealthy
```

The application did not open using the ALB DNS name.

### Possible Reasons

- Port 8080 was not allowed from the ALB Security Group
- Tomcat was not running
- Tomcat was listening on another port
- The Target Group used the wrong port
- The Health Check path was incorrect
- The application took time to start

### Security Group Fix

The Tomcat Security Group must contain:

```text
Protocol: TCP
Port: 8080
Source: vprofile-alb-sg
```

Then verify Tomcat:

```bash
sudo systemctl status tomcat
```

Check the listening port:

```bash
sudo ss -lntp | grep 8080
```

Test the application locally:

```bash
curl -I http://localhost:8080
```

---

## Problem: Tomcat Could Not Connect to MariaDB

### Symptoms

The application logs showed a database connection error.

Examples:

```text
Connection refused
```

```text
Communications link failure
```

```text
Connection timed out
```

### Possible Reasons

- Port 3306 was not allowed from the Tomcat Security Group
- MariaDB was not running
- MariaDB was listening only on localhost
- The DNS record pointed to the wrong private IP
- The application used the wrong database username or password

### Security Group Fix

The MariaDB Security Group must contain:

```text
Protocol: TCP
Port: 3306
Source: vprofile-app-sg
```

Then test from the Tomcat server:

```bash
nc -zv db.vprofile.internal 3306
```

---

## Problem: Tomcat Could Not Connect to Memcached

### Symptoms

The application started, but cache-related operations failed.

### Possible Reasons

- Port 11211 was blocked
- Memcached was not running
- Memcached was listening only on `127.0.0.1`
- The DNS record was incorrect

### Security Group Fix

The Memcached Security Group must contain:

```text
Protocol: TCP
Port: 11211
Source: vprofile-app-sg
```

Test from Tomcat:

```bash
nc -zv cache.vprofile.internal 11211
```

---

## Problem: Tomcat Could Not Connect to RabbitMQ

### Symptoms

The application logs showed RabbitMQ connection errors.

Examples:

```text
Connection refused
```

```text
Connection timed out
```

### Possible Reasons

- Port 5672 was blocked
- RabbitMQ was not running
- RabbitMQ was listening only on localhost
- The RabbitMQ username or password was incorrect
- The private DNS record was incorrect

### Security Group Fix

The RabbitMQ Security Group must contain:

```text
Protocol: TCP
Port: 5672
Source: vprofile-app-sg
```

Test from Tomcat:

```bash
nc -zv mq.vprofile.internal 5672
```

---

## Important Troubleshooting Rule

A timeout usually means that traffic is blocked or cannot reach the destination.

```text
Connection timed out
```

A refused connection usually means that the server was reached, but no service was listening on the requested port.

```text
Connection refused
```

This difference helped me identify whether the problem was related to:

- Security Groups
- Network routing
- Service configuration
- Service status

---

## Common Mistake: Opening Backend Ports to the Internet

During testing, it may be tempting to use:

```text
0.0.0.0/0
```

for all ports.

This is not a safe solution.

Backend ports such as the following should not be public:

```text
3306
11211
5672
8080
```

The correct solution is to use Security Group references.

---

## Common Mistake: Using the ALB Security Group for All Servers

The ALB Security Group should not be attached to MariaDB, Memcached, or RabbitMQ.

Each component should have its own Security Group.

This keeps the traffic rules clear and limits unnecessary access.

---

## Security Improvements for Production

A production environment should also consider:

- HTTPS using AWS Certificate Manager
- Restricted outbound rules
- AWS WAF
- VPC Flow Logs
- Secrets Manager
- CloudWatch monitoring
- Regular Security Group reviews
- Separate Security Groups for management tools
- No public access to backend services

---

## Screenshots

Recommended screenshots for this section:

```text
screenshots/security-groups/01-alb-sg.png
screenshots/security-groups/02-app-sg.png
screenshots/security-groups/03-db-sg.png
screenshots/security-groups/04-cache-sg.png
screenshots/security-groups/05-rabbitmq-sg.png
```

Before uploading screenshots, hide:

- AWS account IDs
- Public IP addresses if not needed
- Private information
- Resource identifiers that should not be shared

---

## Final Security Flow

```text
Internet
   |
   | Port 80
   v
Application Load Balancer
   |
   | Port 8080
   v
Tomcat Application
   |
   +------ Port 3306 ------> MariaDB
   |
   +------ Port 11211 -----> Memcached
   |
   +------ Port 5672 ------> RabbitMQ
```

Only the Application Load Balancer is directly accessible from the internet.

---

## Next Step

Continue to:

[IAM and Session Manager](05-iam-and-session-manager.md)