# Architecture Design

## Overview

This document explains the architecture used to deploy the VProfile application on AWS.

The infrastructure was created manually using the AWS Management Console.

The main design goals were:

- Keep backend services private
- Allow users to access the application through one public endpoint
- Use private DNS names instead of hardcoded IP addresses
- Control traffic using Security Groups
- Separate the application components
- Design the network to support High Availability

---

## Architecture Diagram

```text
                           Internet
                              |
                              v
                    Internet Gateway
                              |
                              v
              Application Load Balancer
                    Public Subnets
                              |
                         HTTP 8080
                              |
                              v
                   Tomcat EC2 Instance
                    Private App Subnet
                              |
             +----------------+----------------+
             |                |                |
             v                v                v
 db.vprofile.internal  cache.vprofile.internal  mq.vprofile.internal
             |                |                |
             v                v                v
         MariaDB          Memcached         RabbitMQ
       EC2 Instance      EC2 Instance      EC2 Instance
          Port 3306         Port 11211        Port 5672
```

---

## AWS Region

The project was deployed in:

```text
us-east-1
```

This region contains several Availability Zones.

Using more than one Availability Zone helps reduce the risk of a complete application outage when one Availability Zone has a problem.

---

## Main Architecture Layers

The architecture is divided into three main layers:

1. Public Layer
2. Application Layer
3. Backend Services Layer

---

## 1. Public Layer

The public layer receives requests from internet users.

It contains:

- Internet Gateway
- Public Subnets
- Application Load Balancer

### Internet Gateway

The Internet Gateway connects the VPC to the internet.

It allows the public Application Load Balancer to receive requests from users.

### Public Subnets

The Application Load Balancer is placed inside public subnets.

The public subnets have a route to the Internet Gateway.

### Application Load Balancer

The Application Load Balancer is the public entry point of the application.

Users do not connect directly to the Tomcat EC2 instance.

The request flow is:

```text
User -> Application Load Balancer -> Tomcat
```

The Load Balancer:

- Receives HTTP requests
- Performs health checks
- Sends traffic to healthy Tomcat targets
- Hides the private application servers from users
- Can distribute traffic across multiple Tomcat instances

The public listener uses:

```text
HTTP Port 80
```

The Load Balancer forwards requests to Tomcat using:

```text
HTTP Port 8080
```

---

## 2. Application Layer

The application layer contains the Tomcat EC2 instance.

Apache Tomcat runs the VProfile Java application.

The Tomcat server is placed inside a private subnet.

It does not need to receive direct traffic from the internet.

Only the Application Load Balancer is allowed to communicate with Tomcat on port 8080.

```text
Application Load Balancer
          |
          | Port 8080
          v
      Tomcat EC2
```

Tomcat connects to the backend services using private network communication.

---

## 3. Backend Services Layer

The backend layer contains:

- MariaDB
- Memcached
- RabbitMQ

These services should not be directly accessible from the internet.

Only the Tomcat application server needs to communicate with them.

---

## MariaDB Architecture

MariaDB stores the permanent application data.

Examples include:

- User accounts
- User roles
- Application records

The application connects to MariaDB using JDBC.

```text
Tomcat -> MariaDB
```

The MariaDB port is:

```text
3306
```

The database DNS name is:

```text
db.vprofile.internal
```

The database name is:

```text
accounts
```

---

## Memcached Architecture

Memcached stores frequently used data in memory.

It helps reduce repeated database queries.

The application connects to Memcached using:

```text
cache.vprofile.internal:11211
```

The communication flow is:

```text
Tomcat -> Memcached
```

Memcached does not store permanent data.

Its data can be lost when the service restarts.

The permanent application data remains inside MariaDB.

---

## RabbitMQ Architecture

RabbitMQ is the message broker used by the application.

The application sends messages to RabbitMQ for message processing.

The application connects to RabbitMQ using:

```text
mq.vprofile.internal:5672
```

The communication flow is:

```text
Tomcat -> RabbitMQ
```

RabbitMQ is available only inside the VPC.

---

## Route 53 Private DNS

A Route 53 Private Hosted Zone was used for internal service discovery.

The private hosted zone name is:

```text
vprofile.internal
```

The following DNS records were created:

| Service | DNS Record | Port |
|---|---|---:|
| MariaDB | `db.vprofile.internal` | `3306` |
| Memcached | `cache.vprofile.internal` | `11211` |
| RabbitMQ | `mq.vprofile.internal` | `5672` |

These DNS names are available only to resources inside the associated VPC.

Internet users cannot use these records to access the backend services.

---

## Why Private DNS Was Used

EC2 private IP addresses may change when instances are replaced.

Using a hardcoded private IP inside the application configuration would make the deployment difficult to maintain.

For example, this is not recommended:

```properties
jdbc.url=jdbc:mysql://10.0.20.15:3306/accounts
```

A better configuration uses a private DNS name:

```properties
jdbc.url=jdbc:mysql://db.vprofile.internal:3306/accounts
```

The same idea is used for Memcached and RabbitMQ:

```properties
memcached.active.host=cache.vprofile.internal
rabbitmq.address=mq.vprofile.internal
```

This makes the configuration easier to understand and maintain.

---

## Security Group Architecture

A separate Security Group was used for each infrastructure layer.

```text
Internet
   |
   v
ALB Security Group
   |
   v
Tomcat Security Group
   |
   +------> Database Security Group
   |
   +------> Memcached Security Group
   |
   +------> RabbitMQ Security Group
```

The important idea is to reference Security Groups instead of opening backend ports to the whole internet.

---

## ALB Security Group

The Application Load Balancer accepts HTTP traffic from internet users.

Example inbound rule:

| Type | Port | Source |
|---|---:|---|
| HTTP | `80` | `0.0.0.0/0` |

The ALB sends traffic to Tomcat on port 8080.

---

## Tomcat Security Group

Tomcat accepts application traffic only from the ALB Security Group.

Example inbound rule:

| Type | Port | Source |
|---|---:|---|
| Custom TCP | `8080` | ALB Security Group |

Port 8080 should not be open to the whole internet.

---

## Database Security Group

MariaDB accepts database traffic only from the Tomcat Security Group.

Example inbound rule:

| Type | Port | Source |
|---|---:|---|
| MySQL/MariaDB | `3306` | Tomcat Security Group |

---

## Memcached Security Group

Memcached accepts traffic only from the Tomcat Security Group.

Example inbound rule:

| Type | Port | Source |
|---|---:|---|
| Custom TCP | `11211` | Tomcat Security Group |

---

## RabbitMQ Security Group

RabbitMQ accepts application traffic only from the Tomcat Security Group.

Example inbound rule:

| Type | Port | Source |
|---|---:|---|
| Custom TCP | `5672` | Tomcat Security Group |

---

## Complete Request Flow

When a user opens the application, the following steps happen:

### Step 1: User Request

The user sends an HTTP request to the Application Load Balancer.

```text
User -> ALB Port 80
```

### Step 2: Load Balancing

The Application Load Balancer checks the health of the Tomcat target.

If the target is healthy, the ALB forwards the request to Tomcat.

```text
ALB -> Tomcat Port 8080
```

### Step 3: Application Processing

Tomcat processes the request.

Depending on the request, the application may connect to one or more backend services.

### Step 4: Database Communication

The application connects to MariaDB using:

```text
db.vprofile.internal:3306
```

### Step 5: Cache Communication

The application connects to Memcached using:

```text
cache.vprofile.internal:11211
```

### Step 6: Message Communication

The application connects to RabbitMQ using:

```text
mq.vprofile.internal:5672
```

### Step 7: Response

Tomcat sends the response back through the Application Load Balancer.

```text
Backend Service
      |
      v
Tomcat
      |
      v
Application Load Balancer
      |
      v
User
```

---

## Target High Availability Design

The target architecture was designed to support High Availability.

The intended design includes:

- Two public subnets
- Two private application subnets
- More than one Availability Zone
- An Application Load Balancer
- Multiple Tomcat application servers
- Health checks for application servers

Example:

```text
                            Internet
                               |
                               v
                 Application Load Balancer
                    /                     \
                   v                       v
        Tomcat EC2 in AZ 1       Tomcat EC2 in AZ 2
                   \                       /
                    \                     /
                     +---- Backend Services
```

If one Tomcat instance becomes unhealthy, the Load Balancer can send traffic to another healthy instance.

---

## Lab Deployment and Production Design

This repository documents a hands-on learning project.

The network and Load Balancer were designed to support multiple Availability Zones.

To reduce lab cost, some application and backend components may use a single EC2 instance.

A single EC2 instance does not provide full High Availability.

A production deployment should improve the architecture by using:

- Multiple Tomcat instances
- Auto Scaling Group
- Amazon RDS Multi-AZ
- Amazon ElastiCache
- Amazon MQ
- HTTPS using AWS Certificate Manager
- NAT Gateway or controlled outbound access
- Centralized monitoring and logging
- Automated backups
- Secrets Manager or Parameter Store

---

## Original Architecture vs AWS Architecture

| Original Component | AWS Deployment |
|---|---|
| NGINX Load Balancer | AWS Application Load Balancer |
| Local virtual machines | Amazon EC2 |
| Local hostnames | Route 53 Private DNS |
| Local network | Amazon VPC |
| Direct machine access | AWS Systems Manager |
| Local firewall rules | AWS Security Groups |
| Tomcat Server | Tomcat on EC2 |
| MariaDB Server | MariaDB on EC2 |
| Memcached Server | Memcached on EC2 |
| RabbitMQ Server | RabbitMQ on EC2 |

---

## Architecture Benefits

This architecture provides several benefits:

- Backend services are not exposed directly to the internet
- Users access the application through one public endpoint
- Security Groups control communication between services
- Private DNS names replace hardcoded IP addresses
- The infrastructure can be expanded across multiple Availability Zones
- Additional Tomcat instances can be added behind the Load Balancer
- Each service can be managed and troubleshooted separately

---

## Architecture Limitations

The lab architecture also has some limitations:

- Some services may run on a single EC2 instance
- Backend services do not have automatic failover
- HTTPS was not included in the first deployment
- Auto Scaling was not included
- Elasticsearch was not included
- Manual infrastructure creation can cause configuration mistakes
- Recreating the same infrastructure manually takes time

These limitations are addressed in later projects using Terraform, Docker, and Kubernetes.

---

## Important Note

The architecture diagram shows the logical communication between components.

Real AWS resource IDs, account IDs, passwords, and private IP addresses are not included in this public repository.

---

## Next Step

Continue to:

[VPC and Networking](03-vpc-and-networking.md)