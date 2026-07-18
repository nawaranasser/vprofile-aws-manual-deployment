# Application Load Balancer Configuration

## Overview

I used an AWS Application Load Balancer as the public entry point for the VProfile application.

```text
Internet User
      |
      | HTTP 80
      v
Application Load Balancer
      |
      | HTTP 8080
      v
Tomcat EC2 Instance
```

The ALB replaced the NGINX load balancer used in the original local environment.

---

## 1. Create the Target Group

From the AWS Console:

```text
EC2
-> Target Groups
-> Create target group
```

Use:

```text
Target type: Instances
Name: vprofile-app-tg
Protocol: HTTP
Port: 8080
VPC: vprofile-vpc
```

Health check settings:

```text
Protocol: HTTP
Path: /login
Port: Traffic port
Success codes: 200-399
```

---

## 2. Register the Tomcat Instance

Select the Tomcat EC2 instance and register it using port:

```text
8080
```

The target may show:

```text
Initial
```

for a short time before becoming:

```text
Healthy
```

---

## 3. Create the Application Load Balancer

From:

```text
EC2
-> Load Balancers
-> Create Load Balancer
-> Application Load Balancer
```

Use:

```text
Name: vprofile-alb
Scheme: Internet-facing
IP address type: IPv4
VPC: vprofile-vpc
```

Select two public subnets in different Availability Zones:

```text
vprofile-public-a
vprofile-public-b
```

Attach:

```text
vprofile-alb-sg
```

---

## 4. Configure the Listener

Create the following listener:

```text
Protocol: HTTP
Port: 80
Default action: Forward to vprofile-app-tg
```

The request flow becomes:

```text
ALB Port 80 -> Target Group -> Tomcat Port 8080
```

---

## 5. Security Group Rules

### ALB Security Group

```text
Inbound:
HTTP 80 from 0.0.0.0/0
```

### Tomcat Security Group

```text
Inbound:
TCP 8080 from vprofile-alb-sg
```

Tomcat port `8080` should not be open directly to the internet.

---

## 6. Verify Tomcat Before Testing the ALB

On the Tomcat EC2 instance:

```bash
sudo systemctl is-active tomcat
sudo ss -lntp | grep 8080
curl -I http://localhost:8080/login
```

Expected response:

```text
HTTP/1.1 200
```

The application must work locally before the ALB can reach it.

---

## 7. Check Target Health

Open:

```text
EC2
-> Target Groups
-> vprofile-app-tg
-> Targets
```

The target should show:

```text
Healthy
```

If it is unhealthy, open the health status details to see the reason.

---

## 8. Open the Application

Copy the ALB DNS name:

```text
EC2
-> Load Balancers
-> vprofile-alb
-> DNS name
```

Open:

```text
http://<ALB-DNS-NAME>/login
```

The VProfile login page should appear.

---

## Common Problems

### Target Is Unhealthy

Check Tomcat locally:

```bash
curl -I http://localhost:8080/login
```

Check the port:

```bash
sudo ss -lntp | grep 8080
```

Verify:

```text
Target Group Port: 8080
Health Check Path: /login
Tomcat SG Source: vprofile-alb-sg
```

Also confirm that the target group and Tomcat instance use the same VPC.

---

### ALB DNS Does Not Open

Check:

- The ALB is `internet-facing`
- The ALB uses public subnets
- The public route table points to the Internet Gateway
- The ALB Security Group allows port `80`
- The listener forwards to the correct target group
- The target is healthy

Test the ALB from a terminal:

```bash
curl -I http://<ALB-DNS-NAME>/login
```

---

### Tomcat Works Locally but the Target Is Unhealthy

This normally means the problem is between the ALB and Tomcat.

Check the Tomcat Security Group:

```text
Protocol: TCP
Port: 8080
Source: vprofile-alb-sg
```

Do not use the ALB public IP as the source.

Use the ALB Security Group.

---

### Wrong Health Check Path

If the target group checks `/` but the application does not return a successful response there, the target may stay unhealthy.

Use:

```text
/login
```

and allow success codes:

```text
200-399
```

---

## Final Verification

```text
[ ] ALB is internet-facing
[ ] ALB uses two public subnets
[ ] Listener uses HTTP port 80
[ ] Target Group uses HTTP port 8080
[ ] Health Check Path is /login
[ ] Tomcat target is healthy
[ ] ALB DNS opens the login page
```

---

## Next Step

Continue to:

[Testing the Deployment](12-testing.md)