# Cleanup

## Overview

AWS resources may continue to generate cost after completing the project.

I deleted the resources in a safe order to avoid dependency errors.

> Stop and review each resource before deleting it.

---

## Recommended Deletion Order

```text
1. Application Load Balancer
2. Target Group
3. EC2 Instances
4. NAT Gateway
5. Elastic IP
6. Route 53 Private Hosted Zone
7. Security Groups
8. Route Tables
9. Subnets
10. Internet Gateway
11. VPC
12. IAM Role
```

---

## 1. Delete the Application Load Balancer

Open:

```text
EC2
-> Load Balancers
-> Select vprofile-alb
-> Actions
-> Delete
```

Wait until the ALB is completely deleted.

---

## 2. Delete the Target Group

Open:

```text
EC2
-> Target Groups
-> Select vprofile-app-tg
-> Actions
-> Delete
```

The target group cannot be deleted while it is still used by the ALB.

---

## 3. Terminate the EC2 Instances

Terminate:

```text
Tomcat EC2
MariaDB EC2
Memcached EC2
RabbitMQ EC2
```

From:

```text
EC2
-> Instances
-> Select the instances
-> Instance state
-> Terminate instance
```

Check whether any attached EBS volumes should also be deleted.

---

## 4. Delete the NAT Gateway

Open:

```text
VPC
-> NAT Gateways
-> Select the NAT Gateway
-> Actions
-> Delete NAT Gateway
```

NAT Gateway is a paid service and should be deleted when the lab is finished.

Wait until its state becomes:

```text
Deleted
```

---

## 5. Release the Elastic IP

After deleting the NAT Gateway:

```text
EC2
-> Elastic IP addresses
-> Select the unused address
-> Actions
-> Release Elastic IP address
```

An unused Elastic IP may generate cost.

---

## 6. Delete the Route 53 Private Hosted Zone

Open:

```text
Route 53
-> Hosted zones
-> vprofile.internal
```

Delete the custom records:

```text
db.vprofile.internal
cache.vprofile.internal
mq.vprofile.internal
```

Do not manually delete the default `NS` and `SOA` records.

Then delete the hosted zone.

---

## 7. Delete the Security Groups

Delete:

```text
vprofile-alb-sg
vprofile-app-sg
vprofile-db-sg
vprofile-cache-sg
vprofile-rabbitmq-sg
```

A Security Group cannot be deleted while it is:

- Attached to an EC2 instance
- Attached to an ALB
- Referenced by another Security Group

Delete the dependent resources first.

---

## 8. Delete the Route Tables

Open:

```text
VPC
-> Route Tables
```

Delete the custom route tables:

```text
vprofile-public-rt
vprofile-private-rt
```

Remove subnet associations when required.

The main VPC route table is deleted automatically with the VPC.

---

## 9. Delete the Subnets

Delete all project subnets:

```text
vprofile-public-a
vprofile-public-b
vprofile-private-app-a
vprofile-private-app-b
vprofile-private-services-a
vprofile-private-services-b
```

A subnet cannot be deleted while it contains active resources or network interfaces.

---

## 10. Detach and Delete the Internet Gateway

Open:

```text
VPC
-> Internet Gateways
-> Select vprofile-igw
```

First detach it:

```text
Actions
-> Detach from a VPC
```

Then delete it:

```text
Actions
-> Delete internet gateway
```

---

## 11. Delete the VPC

Open:

```text
VPC
-> Your VPCs
-> Select vprofile-vpc
-> Actions
-> Delete VPC
```

If AWS reports dependencies, check for:

- Remaining subnets
- Network interfaces
- Security Groups
- NAT Gateways
- Internet Gateways
- Route 53 associations
- Load Balancers

---

## 12. Delete the IAM Role

Delete the IAM Role only when it is no longer used by another project.

```text
IAM
-> Roles
-> vprofile-ec2-ssm-role
-> Delete
```

The role contains:

```text
AmazonSSMManagedInstanceCore
```

Do not delete it if other EC2 instances still use it.

---

## Final Cost Check

Review:

```text
AWS Billing and Cost Management
-> Bills
```

Check that no unwanted resources remain in:

```text
EC2 Instances
EBS Volumes
Load Balancers
NAT Gateways
Elastic IPs
Route 53 Hosted Zones
```

Also check other AWS Regions because resources are region-specific.

---

## Important Notes

- Stopping an EC2 instance does not remove its EBS storage cost.
- Deleting an EC2 instance does not automatically delete every external resource.
- NAT Gateway continues generating cost until it is deleted.
- An unused Elastic IP may generate cost.
- Save required screenshots before deleting the infrastructure.
- Never delete resources that belong to another project.

---

## Cleanup Complete

After cleanup, the manually created AWS infrastructure for this project was removed.

The GitHub repository and documentation remain available as a record of the implementation.