# Route 53 Private DNS

## Overview

I used Amazon Route 53 Private DNS so the Tomcat application could connect to backend services using simple names instead of private IP addresses.

The private hosted zone name is:

```text
vprofile.internal
```

The DNS names work only inside the project VPC.

---

## Why Private DNS Was Used

Using private IP addresses directly makes the application difficult to maintain.

Instead of:

```text
10.0.21.10
10.0.21.11
10.0.21.12
```

the application uses:

```text
db.vprofile.internal
cache.vprofile.internal
mq.vprofile.internal
```

---

## DNS Records

| Service | DNS Name | Target |
|---|---|---|
| MariaDB | `db.vprofile.internal` | Database EC2 private IP |
| Memcached | `cache.vprofile.internal` | Memcached EC2 private IP |
| RabbitMQ | `mq.vprofile.internal` | RabbitMQ EC2 private IP |

---

## 1. Create the Private Hosted Zone

From the AWS Console:

```text
Route 53
-> Hosted zones
-> Create hosted zone
```

Use:

```text
Domain name: vprofile.internal
Type: Private hosted zone
Region: us-east-1
VPC: vprofile-vpc
```

The hosted zone must be associated with the same VPC used by the EC2 instances.

---

## 2. Create the Database Record

Inside the hosted zone, create:

```text
Record name: db
Record type: A
Value: <DATABASE_PRIVATE_IP>
TTL: 300
```

The complete name becomes:

```text
db.vprofile.internal
```

---

## 3. Create the Memcached Record

```text
Record name: cache
Record type: A
Value: <MEMCACHED_PRIVATE_IP>
TTL: 300
```

The complete name becomes:

```text
cache.vprofile.internal
```

---

## 4. Create the RabbitMQ Record

```text
Record name: mq
Record type: A
Value: <RABBITMQ_PRIVATE_IP>
TTL: 300
```

The complete name becomes:

```text
mq.vprofile.internal
```

---

## 5. Check VPC DNS Settings

The VPC must have these settings enabled:

```text
DNS resolution: Enabled
DNS hostnames: Enabled
```

They can be checked from:

```text
VPC
-> Your VPCs
-> Select vprofile-vpc
-> Actions
-> Edit VPC settings
```

---

## 6. Test DNS from Tomcat

Connect to the Tomcat EC2 instance and run:

```bash
getent hosts db.vprofile.internal
getent hosts cache.vprofile.internal
getent hosts mq.vprofile.internal
```

Each command should return the correct private IP address.

Example:

```text
10.0.21.10 db.vprofile.internal
```

---

## 7. Test the Service Ports

After DNS resolution succeeds, test the ports:

```bash
nc -zv db.vprofile.internal 3306
nc -zv cache.vprofile.internal 11211
nc -zv mq.vprofile.internal 5672
```

All connections should succeed.

---

## 8. Application Configuration

The Tomcat application uses the private DNS names inside `application.properties`.

```properties
jdbc.url=jdbc:mysql://db.vprofile.internal:3306/accounts

memcached.active.host=cache.vprofile.internal
memcached.active.port=11211

memcached.standBy.host=cache.vprofile.internal
memcached.standBy.port=11211

rabbitmq.address=mq.vprofile.internal
rabbitmq.port=5672
```

After changing this file, rebuild and redeploy the WAR file.

---

## Common Problems

### DNS Name Does Not Resolve

Example:

```text
Name or service not known
```

Check:

- The hosted zone is private
- The hosted zone is associated with `vprofile-vpc`
- VPC DNS resolution is enabled
- The record name is correct
- The Tomcat instance is inside the correct VPC

Test again:

```bash
getent hosts db.vprofile.internal
```

---

### DNS Resolves to the Wrong IP

Check the EC2 private IP from:

```text
EC2
-> Instances
-> Select the backend instance
-> Private IPv4 address
```

Then update the Route 53 record.

---

### DNS Works but the Port Test Fails

If this works:

```bash
getent hosts db.vprofile.internal
```

but this fails:

```bash
nc -zv db.vprofile.internal 3306
```

the problem is probably not DNS.

Check:

- Security Groups
- Service status
- Listening address
- Operating system firewall
- Correct port

---

## Important Note

The Route 53 Private Hosted Zone is used only for communication inside the VPC.

Users access the application using the public Application Load Balancer DNS name.

```text
Internet User
      |
      v
Public ALB DNS
      |
      v
Tomcat
      |
      +----> db.vprofile.internal
      +----> cache.vprofile.internal
      +----> mq.vprofile.internal
```

---

## Security Note

Do not create public DNS records for:

```text
MariaDB
Memcached
RabbitMQ
```

These services should remain private.

---

## Next Step

Continue to:

[Application Load Balancer](11-alb-configuration.md)