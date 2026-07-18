# VProfile Application Deployment on AWS Using the AWS Console

## Project Overview

This repository documents my hands-on deployment of the VProfile Java application on AWS.

I created the AWS infrastructure manually using the AWS Management Console.

The main goal was to move the application from a local environment to AWS and understand how the application components communicate inside a cloud network.

The application uses:

- Apache Tomcat to run the Java application
- MariaDB to store application data
- Memcached to cache frequently used data
- RabbitMQ for message processing
- AWS Application Load Balancer to receive user requests
- Route 53 Private DNS for communication between internal services

## What I Learned

During this project, I learned how to:

- Design a VPC with public and private subnets
- Create security groups for different application components
- Connect to private EC2 instances using AWS Systems Manager
- Deploy and configure backend services on EC2
- Use private DNS names instead of hardcoded IP addresses
- Configure an Application Load Balancer
- Test and troubleshoot communication between services
