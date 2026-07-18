# Project Overview

## Introduction

VProfile is a Java web application that uses several backend services.

The application was originally designed to run on separate virtual machines.

In this project, I moved the application to AWS and created the infrastructure manually using the AWS Management Console.

This project helped me understand how a multi-tier application works inside a cloud network.

---

## Project Goal

The main goal was to deploy the VProfile application on AWS without using:

- Terraform
- Docker Compose
- Kubernetes
- kubeadm

All AWS resources were created manually from the AWS Management Console.

The project also focused on understanding the communication between the application components.

---

## Original Application Architecture

The original application used the following components:

- NGINX as the frontend load balancer
- Apache Tomcat as the application server
- MariaDB as the database
- Memcached as the caching service
- RabbitMQ as the message broker
- Elasticsearch as the search service

The original environment used local hostnames such as:

```text
db01
mc01
rmq01
app01
```

These hostnames were suitable for the local environment, but they were replaced during the AWS migration.

---

## AWS Architecture

The AWS deployment uses the following services:

- Amazon VPC for network isolation
- Public and private subnets
- Internet Gateway for public internet access
- Route Tables for network routing
- Amazon EC2 for the application and backend services
- AWS Systems Manager Session Manager for server access
- Security Groups to control network traffic
- Route 53 Private Hosted Zone for internal DNS
- Application Load Balancer for incoming user traffic

The internal services use private DNS names:

```text
db.vprofile.internal
cache.vprofile.internal
mq.vprofile.internal
```

The application does not need to use the private IP address of each backend server.

---

## Application Components

### 1. Application Load Balancer

The Application Load Balancer is the public entry point.

It receives HTTP requests from users and sends them to the Tomcat application server.

```text
User -> Application Load Balancer -> Tomcat
```

---

### 2. Tomcat Application Server

Apache Tomcat runs the VProfile Java application.

The application is packaged as a WAR file.

Tomcat connects to:

- MariaDB
- Memcached
- RabbitMQ

Tomcat listens on port:

```text
8080
```

---

### 3. MariaDB

MariaDB stores the application data.

The database name is:

```text
accounts
```

The database was initialized using:

```text
src/main/resources/db_backup.sql
```

MariaDB listens on port:

```text
3306
```

---

### 4. Memcached

Memcached stores frequently used data in memory.

It helps reduce repeated database queries and improves response time.

Memcached listens on port:

```text
11211
```

---

### 5. RabbitMQ

RabbitMQ is the message broker used by the application.

It allows the application to send and process messages.

RabbitMQ listens on port:

```text
5672
```

---

### 6. Route 53 Private DNS

A Route 53 Private Hosted Zone was created with the following name:

```text
vprofile.internal
```

Private DNS records were created for the backend services:

| Service | Private DNS Name |
|---|---|
| MariaDB | `db.vprofile.internal` |
| Memcached | `cache.vprofile.internal` |
| RabbitMQ | `mq.vprofile.internal` |

These records are available only inside the VPC.

---

## Request Flow

The normal request flow is:

```text
Internet User
      |
      v
Application Load Balancer
      |
      v
Tomcat Application
      |
      +------> MariaDB
      |
      +------> Memcached
      |
      +------> RabbitMQ
```

Using private DNS names, the flow becomes:

```text
Internet User
      |
      v
AWS Application Load Balancer
      |
      v
Tomcat EC2 Instance
      |
      +------> db.vprofile.internal
      |
      +------> cache.vprofile.internal
      |
      +------> mq.vprofile.internal
```

---

## Project Scope

This repository documents a hands-on learning project.

The network was designed to support multiple Availability Zones and multiple application servers.

Some backend services were deployed as single EC2 instances to keep the lab simple and reduce AWS cost.

This means that the architecture can be improved further for a real production environment.

---

## Elasticsearch Note

Elasticsearch was part of the original VProfile architecture.

It was not included in the first working AWS deployment.

The first goal was to successfully connect:

- Tomcat
- MariaDB
- Memcached
- RabbitMQ
- Application Load Balancer

Elasticsearch can be added later as an improvement.

---

## What I Practiced

During this project, I practiced how to:

- Design a cloud network
- Create public and private subnets
- Configure route tables
- Create security groups
- Launch and configure EC2 instances
- Use AWS Systems Manager instead of direct SSH access
- Install Linux services
- Deploy a Java WAR application on Tomcat
- Create private DNS records
- Configure an Application Load Balancer
- Test communication between application components
- Read logs and troubleshoot deployment problems

---

## Important Security Note

This repository does not include real passwords, AWS account IDs, tokens, or private IP addresses from the original deployment.

Example values are used in the documentation.

Never store real credentials inside a public GitHub repository.

---

## Next Step

Continue to:

[Architecture Design](02-architecture.md)