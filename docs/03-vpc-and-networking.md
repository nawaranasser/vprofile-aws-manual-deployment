# VPC and Networking

## Overview

In this part of the project, I created the AWS network manually using the AWS Management Console.

The network separates public resources from private application and backend resources.

The main goals were:

- Keep the application servers private
- Keep the backend services private
- Expose only the Application Load Balancer to the internet
- Allow private EC2 instances to download packages
- Support more than one Availability Zone
- Use private communication between all application components

---

## AWS Region

The project was deployed in:

```text
us-east-1
```

The network uses two Availability Zones:

```text
us-east-1a
us-east-1b
```

Using two Availability Zones makes it possible to run application servers in different physical locations.

---

## VPC Configuration

I created a custom VPC for the project.

```text
Name: vprofile-vpc
IPv4 CIDR: 10.0.0.0/16
Tenancy: Default
```

The CIDR block provides enough private IP addresses for the application resources.

### DNS Settings

The following VPC settings were enabled:

```text
DNS resolution: Enabled
DNS hostnames: Enabled
```

These settings are important because Route 53 Private DNS names must be resolved inside the VPC.

Without DNS resolution, names such as the following would not work:

```text
db.vprofile.internal
cache.vprofile.internal
mq.vprofile.internal
```

---

## Subnet Design

I created six subnets across two Availability Zones.

The subnets were divided into three groups:

1. Public subnets
2. Private application subnets
3. Private backend service subnets

---

## Public Subnets

The public subnets contain internet-facing resources such as:

- Application Load Balancer
- NAT Gateway

| Subnet | CIDR | Availability Zone | Purpose |
|---|---|---|---|
| Public Subnet A | `10.0.1.0/24` | `us-east-1a` | ALB and NAT Gateway |
| Public Subnet B | `10.0.2.0/24` | `us-east-1b` | ALB High Availability |

The Application Load Balancer requires at least two subnets in different Availability Zones.

---

## Private Application Subnets

The private application subnets are used for the Tomcat application servers.

| Subnet | CIDR | Availability Zone | Purpose |
|---|---|---|---|
| Private App Subnet A | `10.0.11.0/24` | `us-east-1a` | Tomcat application server |
| Private App Subnet B | `10.0.12.0/24` | `us-east-1b` | Additional Tomcat server |

Tomcat instances do not need direct public access.

Users access the application through the Application Load Balancer.

```text
Internet
   |
   v
Application Load Balancer
   |
   v
Private Tomcat EC2
```

---

## Private Backend Subnets

The private backend subnets contain the internal services.

| Subnet | CIDR | Availability Zone | Purpose |
|---|---|---|---|
| Private Services Subnet A | `10.0.21.0/24` | `us-east-1a` | Database and backend services |
| Private Services Subnet B | `10.0.22.0/24` | `us-east-1b` | Future backend redundancy |

The following services can be placed inside these subnets:

- MariaDB
- Memcached
- RabbitMQ

These services should not receive direct traffic from the internet.

---

## Final Subnet Layout

```text
VPC: 10.0.0.0/16
|
|-- us-east-1a
|   |
|   |-- Public Subnet A
|   |   10.0.1.0/24
|   |
|   |-- Private App Subnet A
|   |   10.0.11.0/24
|   |
|   |-- Private Services Subnet A
|       10.0.21.0/24
|
|-- us-east-1b
    |
    |-- Public Subnet B
    |   10.0.2.0/24
    |
    |-- Private App Subnet B
    |   10.0.12.0/24
    |
    |-- Private Services Subnet B
        10.0.22.0/24
```

---

## Step 1: Create the VPC

From the AWS Management Console:

```text
VPC Console
-> Your VPCs
-> Create VPC
```

I used the following values:

```text
Name tag: vprofile-vpc
IPv4 CIDR: 10.0.0.0/16
IPv6 CIDR: No IPv6 CIDR block
Tenancy: Default
```

After creating the VPC, I enabled:

```text
DNS resolution
DNS hostnames
```

---

## Step 2: Create the Public Subnets

I created the first public subnet:

```text
Name: vprofile-public-a
VPC: vprofile-vpc
Availability Zone: us-east-1a
IPv4 CIDR: 10.0.1.0/24
```

I created the second public subnet:

```text
Name: vprofile-public-b
VPC: vprofile-vpc
Availability Zone: us-east-1b
IPv4 CIDR: 10.0.2.0/24
```

These subnets are used by the internet-facing Application Load Balancer.

---

## Step 3: Create the Private Application Subnets

I created the first private application subnet:

```text
Name: vprofile-private-app-a
VPC: vprofile-vpc
Availability Zone: us-east-1a
IPv4 CIDR: 10.0.11.0/24
```

I created the second private application subnet:

```text
Name: vprofile-private-app-b
VPC: vprofile-vpc
Availability Zone: us-east-1b
IPv4 CIDR: 10.0.12.0/24
```

These subnets are used for Tomcat EC2 instances.

---

## Step 4: Create the Private Backend Subnets

I created the first private backend subnet:

```text
Name: vprofile-private-services-a
VPC: vprofile-vpc
Availability Zone: us-east-1a
IPv4 CIDR: 10.0.21.0/24
```

I created the second private backend subnet:

```text
Name: vprofile-private-services-b
VPC: vprofile-vpc
Availability Zone: us-east-1b
IPv4 CIDR: 10.0.22.0/24
```

These subnets are used for MariaDB, Memcached, and RabbitMQ.

---

## Internet Gateway

An Internet Gateway allows public resources inside the VPC to communicate with the internet.

I created an Internet Gateway:

```text
Name: vprofile-igw
```

Then I attached it to:

```text
vprofile-vpc
```

Creating the Internet Gateway is not enough by itself.

A route must also be added to the public route table.

---

## Public Route Table

I created a route table for the public subnets.

```text
Name: vprofile-public-rt
VPC: vprofile-vpc
```

The route table contains the following routes:

| Destination | Target |
|---|---|
| `10.0.0.0/16` | Local |
| `0.0.0.0/0` | Internet Gateway |

The following subnets were associated with this route table:

```text
vprofile-public-a
vprofile-public-b
```

The default route means that internet traffic is sent to the Internet Gateway.

```text
0.0.0.0/0 -> Internet Gateway
```

---

## NAT Gateway

The Tomcat and backend EC2 instances are inside private subnets.

They do not have direct public internet access.

However, they still need outbound internet access for tasks such as:

- Installing Linux packages
- Downloading Java and Tomcat
- Downloading Maven dependencies
- Cloning the application repository
- Communicating with AWS Systems Manager

For this reason, I created a NAT Gateway.

The NAT Gateway was placed inside:

```text
vprofile-public-a
```

Before creating the NAT Gateway, I allocated an Elastic IP address.

The setup was:

```text
Private EC2
    |
    v
Private Route Table
    |
    v
NAT Gateway
    |
    v
Internet Gateway
    |
    v
Internet
```

The NAT Gateway allows outbound connections from private instances.

It does not allow internet users to start direct inbound connections to the private instances.

---

## Private Route Table

I created a route table for the private subnets.

```text
Name: vprofile-private-rt
VPC: vprofile-vpc
```

The route table contains:

| Destination | Target |
|---|---|
| `10.0.0.0/16` | Local |
| `0.0.0.0/0` | NAT Gateway |

The private route table was associated with:

```text
vprofile-private-app-a
vprofile-private-app-b
vprofile-private-services-a
vprofile-private-services-b
```

The private instances use the NAT Gateway only for outbound internet access.

They are still not directly accessible from the internet.

---

## Route Table Summary

### Public Route Table

```text
10.0.0.0/16 -> Local
0.0.0.0/0   -> Internet Gateway
```

Associated subnets:

```text
Public Subnet A
Public Subnet B
```

### Private Route Table

```text
10.0.0.0/16 -> Local
0.0.0.0/0   -> NAT Gateway
```

Associated subnets:

```text
Private App Subnet A
Private App Subnet B
Private Services Subnet A
Private Services Subnet B
```

---

## Public and Private Communication

Resources inside the same VPC can communicate using their private IP addresses.

The local VPC route handles this communication:

```text
10.0.0.0/16 -> Local
```

For example:

```text
Tomcat -> MariaDB
Tomcat -> Memcached
Tomcat -> RabbitMQ
```

This traffic stays inside the AWS network.

It does not travel through the Internet Gateway or NAT Gateway.

---

## Network Traffic Flow

### User Traffic

User traffic follows this path:

```text
Internet User
      |
      v
Internet Gateway
      |
      v
Application Load Balancer
      |
      v
Tomcat EC2 Instance
```

### Application-to-Database Traffic

```text
Tomcat EC2
      |
      v
db.vprofile.internal
      |
      v
MariaDB EC2
```

### Application-to-Cache Traffic

```text
Tomcat EC2
      |
      v
cache.vprofile.internal
      |
      v
Memcached EC2
```

### Application-to-RabbitMQ Traffic

```text
Tomcat EC2
      |
      v
mq.vprofile.internal
      |
      v
RabbitMQ EC2
```

### Private Instance Internet Access

```text
Private EC2
      |
      v
Private Route Table
      |
      v
NAT Gateway
      |
      v
Internet Gateway
      |
      v
Internet
```

---

## Why EC2 Instances Were Placed in Private Subnets

Placing the EC2 instances in private subnets provides better security.

The instances do not need public IP addresses.

The internet cannot connect directly to:

- Tomcat
- MariaDB
- Memcached
- RabbitMQ

Only the Application Load Balancer receives public application traffic.

Administrative access is performed using AWS Systems Manager Session Manager.

---

## Why Two Public Subnets Were Required

The Application Load Balancer requires subnets in at least two Availability Zones.

This allows the ALB to continue receiving traffic if one Availability Zone has a problem.

```text
ALB
 |
 +-- Public Subnet A in us-east-1a
 |
 +-- Public Subnet B in us-east-1b
```

---

## Why Six Subnets Were Created

The six-subnet design separates the infrastructure into clear layers.

```text
Public Layer
- Application Load Balancer
- NAT Gateway

Application Layer
- Tomcat EC2 instances

Backend Layer
- MariaDB
- Memcached
- RabbitMQ
```

This separation makes the network easier to secure and understand.

---

## Important NAT Gateway Note

Only one NAT Gateway was used in this lab to reduce AWS cost.

The NAT Gateway was created in `us-east-1a`.

This means that the NAT design itself was not fully High Available.

A production environment should normally use one NAT Gateway in each Availability Zone.

Example production design:

```text
Private Subnets in AZ A -> NAT Gateway in AZ A
Private Subnets in AZ B -> NAT Gateway in AZ B
```

Using multiple NAT Gateways increases availability but also increases AWS cost.

---

## Network Verification

After creating the network, I verified the following:

- The VPC CIDR was correct
- DNS resolution was enabled
- DNS hostnames were enabled
- All six subnets were created
- The subnets were created in the correct Availability Zones
- The Internet Gateway was attached to the VPC
- The public route table had a route to the Internet Gateway
- The private route table had a route to the NAT Gateway
- Public subnets were associated with the public route table
- Private subnets were associated with the private route table

---

## Useful Linux Tests

From a private EC2 instance, I tested outbound internet access:

```bash
curl -I https://aws.amazon.com
```

I also tested DNS resolution:

```bash
getent hosts amazon.com
```

Another possible test is:

```bash
curl -I https://github.com
```

If these commands work, the private instance can reach the internet through the NAT Gateway.

---

## Common Problem: Private EC2 Cannot Access the Internet

### Symptoms

Package installation fails:

```text
Could not resolve host
Connection timed out
Failed to download metadata
```

### Possible Reasons

- The private subnet is associated with the wrong route table
- The private route table does not have a NAT Gateway route
- The NAT Gateway is not available
- The NAT Gateway is inside a private subnet
- The public subnet does not have a route to the Internet Gateway
- The Network ACL blocks the traffic
- DNS resolution is disabled

### Solution

Verify that the private route table contains:

```text
0.0.0.0/0 -> NAT Gateway
```

Verify that the NAT Gateway is located inside a public subnet.

Verify that the public route table contains:

```text
0.0.0.0/0 -> Internet Gateway
```

---

## Common Problem: Route 53 Private DNS Does Not Work

### Symptoms

The application cannot resolve:

```text
db.vprofile.internal
```

A command such as the following fails:

```bash
getent hosts db.vprofile.internal
```

### Possible Reasons

- DNS resolution is disabled in the VPC
- DNS hostnames are disabled
- The Private Hosted Zone is not associated with the VPC
- The DNS record contains the wrong private IP
- The EC2 instance is using the wrong VPC

### Solution

Enable the following VPC settings:

```text
DNS resolution
DNS hostnames
```

Then verify that the Private Hosted Zone is associated with `vprofile-vpc`.

---

## Common Problem: Public Subnet Is Not Really Public

A subnet is not public only because its name contains the word `public`.

A subnet becomes public when its route table contains a route to an Internet Gateway.

Required route:

```text
0.0.0.0/0 -> Internet Gateway
```

The route table must also be associated with the correct subnet.

---

## Common Problem: NAT Gateway Was Created in a Private Subnet

A NAT Gateway must be created inside a public subnet.

The public subnet must have a route to the Internet Gateway.

The NAT Gateway must also have an Elastic IP address.

Correct flow:

```text
Private Subnet
      |
      v
NAT Gateway in Public Subnet
      |
      v
Internet Gateway
```

---

## Screenshots

Recommended screenshots for this section:

```text
screenshots/vpc/01-vpc-details.png
screenshots/vpc/02-subnets.png
screenshots/vpc/03-internet-gateway.png
screenshots/vpc/04-public-route-table.png
screenshots/vpc/05-nat-gateway.png
screenshots/vpc/06-private-route-table.png
```

Before uploading screenshots, remove or hide any sensitive information.

---

## Cost Warning

NAT Gateway is a paid AWS service.

It can continue generating cost even when the EC2 instances are stopped.

After completing the lab, delete the NAT Gateway if it is no longer needed.

The Elastic IP address should also be released when it is not being used.

---

## Final Network Design

```text
                               Internet
                                  |
                                  v
                         Internet Gateway
                                  |
                    +-------------+-------------+
                    |                           |
                    v                           v
          Public Subnet A              Public Subnet B
          10.0.1.0/24                  10.0.2.0/24
          us-east-1a                   us-east-1b
          NAT Gateway                  ALB Node
                    \                           /
                     \                         /
                      +--- Application ALB ---+
                                  |
                    +-------------+-------------+
                    |                           |
                    v                           v
          Private App A               Private App B
          10.0.11.0/24                10.0.12.0/24
          us-east-1a                  us-east-1b
                    |
                    v
              Tomcat Application
                    |
          +---------+---------+
          |         |         |
          v         v         v
       MariaDB   Memcached  RabbitMQ
          |
          v
 Private Services Subnets
 10.0.21.0/24 and 10.0.22.0/24
```

---

## Next Step

Continue to:

[Security Groups](04-security-groups.md)