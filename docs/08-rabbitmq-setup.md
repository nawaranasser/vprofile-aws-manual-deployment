# RabbitMQ Setup

## Overview

In this part of the project, I installed and configured RabbitMQ on a private EC2 instance.

RabbitMQ is the message broker used by the VProfile application.

The application connects to RabbitMQ using:

```text
mq.vprofile.internal:5672
```

The RabbitMQ server was placed inside a private backend subnet.

It was not directly accessible from the internet.

---

## RabbitMQ Server Details

The setup used:

```text
Operating System: RHEL-compatible Linux
Connection Method: AWS Systems Manager Session Manager
Service Name: rabbitmq-server
Protocol: AMQP
Port: 5672
Private DNS: mq.vprofile.internal
```

The EC2 instance did not require:

- A public IP address
- Public SSH access
- Public access to port 5672
- RabbitMQ Management UI access from the internet

---

## Communication Flow

```text
Tomcat EC2
    |
    | TCP 5672
    v
mq.vprofile.internal
    |
    v
RabbitMQ EC2
```

The RabbitMQ Security Group allows port `5672` only from the Tomcat Security Group.

---

## What RabbitMQ Does

RabbitMQ allows the application to send messages to a message broker.

Instead of connecting application components directly, the application sends messages to RabbitMQ.

```text
Application
    |
    v
RabbitMQ Exchange
    |
    v
Queues and Consumers
```

This helps separate application components and supports asynchronous processing.

---

## Original Application Configuration

The original application used:

```properties
rabbitmq.address=rmq01
rabbitmq.port=5672
rabbitmq.username=guest
rabbitmq.password=guest
```

The hostname `rmq01` worked in the original local environment.

It was replaced with an AWS Route 53 private DNS name.

The default `guest` account was also replaced with a dedicated application user.

---

## Step 1: Connect to the RabbitMQ EC2 Instance

I connected to the EC2 instance using AWS Systems Manager Session Manager.

```text
EC2
-> Instances
-> Select the RabbitMQ instance
-> Connect
-> Session Manager
-> Connect
```

Check the current user:

```bash
whoami
```

Check the operating system:

```bash
cat /etc/os-release
```

Verify administrative access:

```bash
sudo whoami
```

Expected output:

```text
root
```

---

## Step 2: Update the Package Metadata

```bash
sudo dnf makecache
```

---

## Step 3: Install wget

The original deployment script installed `wget` before installing RabbitMQ.

```bash
sudo dnf install -y wget
```

Verify the installation:

```bash
wget --version
```

---

## Step 4: Install the RabbitMQ Repository

The reference deployment script used the CentOS RabbitMQ repository package.

```bash
sudo dnf install -y centos-release-rabbitmq-38
```

Verify that the RabbitMQ repository is available:

```bash
sudo dnf repolist | grep -i rabbitmq
```

The exact repository package may depend on the selected Linux image.

A compatible RHEL or CentOS-based image should be used with these commands.

---

## Step 5: Install RabbitMQ Server

```bash
sudo dnf \
  --enablerepo=centos-rabbitmq-38 \
  install -y rabbitmq-server
```

Verify the installed package:

```bash
rpm -q rabbitmq-server
```

Display the RabbitMQ version:

```bash
sudo rabbitmq-diagnostics server_version
```

---

## Step 6: Start and Enable RabbitMQ

```bash
sudo systemctl enable --now rabbitmq-server
```

Check the service status:

```bash
sudo systemctl status rabbitmq-server --no-pager
```

A shorter check is:

```bash
sudo systemctl is-active rabbitmq-server
```

Expected output:

```text
active
```

Verify that RabbitMQ starts automatically after a reboot:

```bash
sudo systemctl is-enabled rabbitmq-server
```

Expected output:

```text
enabled
```

---

## Step 7: Verify RabbitMQ Health

Run the RabbitMQ diagnostic ping:

```bash
sudo rabbitmq-diagnostics -q ping
```

Expected output:

```text
Ping succeeded
```

Display more service information:

```bash
sudo rabbitmqctl status
```

Check whether RabbitMQ is listening on port `5672`:

```bash
sudo ss -lntp | grep 5672
```

The expected result should contain:

```text
0.0.0.0:5672
```

or:

```text
*:5672
```

---

## Step 8: Create a Dedicated Application User

The original application used the RabbitMQ `guest` account.

The `guest` account should not be used as the remote application account.

I created a dedicated RabbitMQ user for VProfile.

The password below is only a placeholder.

```bash
sudo rabbitmqctl add_user \
  vprofile_app \
  'CHANGE_ME_STRONG_PASSWORD'
```

Do not place the real RabbitMQ password inside a public GitHub repository.

---

## Step 9: Give the User Permissions

Creating a RabbitMQ user is not enough.

The user also needs permissions on the RabbitMQ virtual host.

The application uses the default virtual host:

```text
/
```

Give the application user configure, write, and read permissions:

```bash
sudo rabbitmqctl set_permissions \
  -p / \
  vprofile_app \
  ".*" \
  ".*" \
  ".*"
```

The three permission patterns are:

```text
Configure
Write
Read
```

Verify the permissions:

```bash
sudo rabbitmqctl list_permissions -p /
```

The output should contain:

```text
vprofile_app    .*    .*    .*
```

---

## Step 10: Optional Administrator Tag

The application does not require administrator permissions.

The following command is needed only when the user must perform RabbitMQ administrative tasks:

```bash
sudo rabbitmqctl set_user_tags \
  vprofile_app \
  administrator
```

For a production environment, the application user should normally not be an administrator.

A separate administrator user should be used for management tasks.

---

## Step 11: Verify RabbitMQ Users

List the RabbitMQ users:

```bash
sudo rabbitmqctl list_users
```

The output should contain:

```text
vprofile_app
```

Check the permissions again:

```bash
sudo rabbitmqctl list_user_permissions vprofile_app
```

---

## Important Note About the Original Script

The original deployment script created this user:

```text
Username: test
Password: test
```

It also added the administrator tag:

```bash
rabbitmqctl set_user_tags test administrator
```

However, adding the administrator tag does not replace virtual host permissions.

The following command is still required:

```bash
sudo rabbitmqctl set_permissions \
  -p / \
  test \
  ".*" \
  ".*" \
  ".*"
```

For this public guide, I used:

```text
vprofile_app
```

instead of the simple `test/test` credentials.

---

## Loopback User Configuration

The reference script added this configuration:

```erlang
[{rabbit, [{loopback_users, []}]}].
```

It was written to:

```text
/etc/rabbitmq/rabbitmq.config
```

This allows loopback-restricted accounts, including `guest`, to connect remotely.

A cleaner solution is to keep the default `guest` restriction and create a dedicated application user.

Because this project uses `vprofile_app`, remote access using `guest` is not required.

---

## Step 12: Configure the Operating System Firewall

Check whether `firewalld` is running:

```bash
sudo systemctl is-active firewalld
```

If the result is:

```text
active
```

allow RabbitMQ AMQP traffic:

```bash
sudo firewall-cmd \
  --permanent \
  --add-port=5672/tcp
```

Reload the firewall:

```bash
sudo firewall-cmd --reload
```

Verify the rule:

```bash
sudo firewall-cmd --list-ports
```

The output should contain:

```text
5672/tcp
```

If `firewalld` is inactive, the AWS Security Group still controls the network access.

---

## Step 13: Configure the AWS Security Group

The RabbitMQ Security Group is:

```text
vprofile-rabbitmq-sg
```

Its inbound rule allows RabbitMQ traffic only from the Tomcat Security Group.

| Type | Protocol | Port | Source |
|---|---|---:|---|
| Custom TCP | TCP | `5672` | `vprofile-app-sg` |

Do not use:

```text
Port: 5672
Source: 0.0.0.0/0
```

RabbitMQ should not be directly accessible from the internet.

---

## Step 14: Create the Route 53 Private DNS Record

A Route 53 private record was created for the RabbitMQ EC2 instance.

```text
Hosted Zone: vprofile.internal
Record Name: mq.vprofile.internal
Record Type: A
Value: RabbitMQ EC2 private IP address
```

This allows the application to use:

```text
mq.vprofile.internal
```

instead of a hardcoded private IP address.

---

## Step 15: Update the Application Configuration

The old configuration was:

```properties
rabbitmq.address=rmq01
rabbitmq.port=5672
rabbitmq.username=guest
rabbitmq.password=guest
```

The AWS configuration became:

```properties
rabbitmq.address=mq.vprofile.internal
rabbitmq.port=5672
rabbitmq.username=vprofile_app
rabbitmq.password=<YOUR_RABBITMQ_PASSWORD>
```

The real password must not be committed to GitHub.

---

## Step 16: Test DNS from the Tomcat Server

From the Tomcat EC2 instance:

```bash
getent hosts mq.vprofile.internal
```

The command should return the private IP address of the RabbitMQ EC2 instance.

Another possible command is:

```bash
nslookup mq.vprofile.internal
```

---

## Step 17: Test Port 5672 from Tomcat

Install `nc` if it is not available.

### RHEL-Compatible Linux

```bash
sudo dnf install -y nmap-ncat
```

### Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y netcat-openbsd
```

Test the RabbitMQ port:

```bash
nc -zv mq.vprofile.internal 5672
```

Expected result:

```text
Connection succeeded
```

Another test is:

```bash
timeout 5 bash -c \
  '</dev/tcp/mq.vprofile.internal/5672'

echo $?
```

Exit code `0` means the port is reachable.

---

## Important Port Test Note

RabbitMQ port `5672` uses the AMQP protocol.

It is not an HTTP web page.

This command is not a correct application test:

```bash
curl http://mq.vprofile.internal:5672
```

Use a TCP connection test:

```bash
nc -zv mq.vprofile.internal 5672
```

Then test the connection using the VProfile application.

---

## Step 18: Test RabbitMQ Through the Application

After Tomcat was deployed and the application was opened, I logged in and visited:

```text
/user/rabbit
```

Example:

```text
http://<ALB-DNS-NAME>/user/rabbit
```

The expected page contains:

```text
Rabbitmq initiated
```

The application creates RabbitMQ connections and sends test messages.

Tomcat logs may contain output similar to:

```text
Connection open statustrue
[x] Sent 'uuid = ...'
```

The application endpoint is a better final test than checking only port `5672`.

---

## Step 19: Verify Connections in RabbitMQ

List current connections:

```bash
sudo rabbitmqctl list_connections
```

Useful fields can be displayed with:

```bash
sudo rabbitmqctl list_connections \
  user \
  peer_host \
  peer_port \
  state
```

List exchanges:

```bash
sudo rabbitmqctl list_exchanges
```

The VProfile application creates an exchange named:

```text
messages
```

Verify it:

```bash
sudo rabbitmqctl list_exchanges \
  name \
  type \
  | grep messages
```

List queues:

```bash
sudo rabbitmqctl list_queues
```

---

# Problem: Application Received ACCESS_REFUSED

## Example Error

```text
ACCESS_REFUSED
```

or:

```text
access to vhost '/' refused for user
```

## Reason

The RabbitMQ user existed, but it did not have permissions on the default virtual host.

Creating the user and adding an administrator tag was not enough.

## Solution

Run:

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

---

# Problem: Guest Login Worked Locally but Failed Remotely

## Symptoms

The `guest` account worked from the RabbitMQ server but failed from the Tomcat EC2 instance.

## Reason

The default RabbitMQ `guest` user is normally restricted to local connections.

## Solution

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

Update the application configuration:

```properties
rabbitmq.username=vprofile_app
rabbitmq.password=<YOUR_RABBITMQ_PASSWORD>
```

---

# Problem: Connection Timed Out

## Example Error

```text
Connection timed out
```

This normally means the request could not reach RabbitMQ.

Check:

- RabbitMQ Security Group
- Tomcat outbound Security Group rules
- Route 53 private DNS record
- Network ACLs
- Operating system firewall
- Correct port number
- Correct VPC

Test DNS:

```bash
getent hosts mq.vprofile.internal
```

Test the port:

```bash
nc -zv mq.vprofile.internal 5672
```

The RabbitMQ Security Group must contain:

```text
Protocol: TCP
Port: 5672
Source: vprofile-app-sg
```

---

# Problem: Connection Refused

## Example Error

```text
Connection refused
```

This usually means the EC2 instance was reached, but RabbitMQ was not listening on port `5672`.

Check the service:

```bash
sudo systemctl status rabbitmq-server --no-pager
```

Check the diagnostic ping:

```bash
sudo rabbitmq-diagnostics -q ping
```

Check the listener:

```bash
sudo ss -lntp | grep 5672
```

Restart RabbitMQ:

```bash
sudo systemctl restart rabbitmq-server
```

---

# Problem: RabbitMQ Service Failed to Start

Check the service:

```bash
sudo systemctl status rabbitmq-server --no-pager
```

Read the latest logs:

```bash
sudo journalctl \
  -u rabbitmq-server \
  --no-pager \
  -n 100
```

RabbitMQ logs may also be available inside:

```text
/var/log/rabbitmq/
```

List the log files:

```bash
sudo ls -lh /var/log/rabbitmq/
```

Read the latest log messages:

```bash
sudo tail -n 100 /var/log/rabbitmq/*.log
```

After fixing the problem:

```bash
sudo systemctl restart rabbitmq-server
```

---

# Problem: RabbitMQ CLI Could Not Contact the Node

## Example Error

```text
unable to perform an operation on node
```

## Possible Reasons

- RabbitMQ service is stopped
- The RabbitMQ node is still starting
- The command was not executed with enough permissions
- Erlang cookie permissions are incorrect
- The hostname changed after RabbitMQ installation

## Checks

```bash
sudo systemctl is-active rabbitmq-server
```

```bash
sudo rabbitmq-diagnostics -q ping
```

```bash
hostname
```

Run RabbitMQ administration commands using `sudo`:

```bash
sudo rabbitmqctl status
```

---

# Problem: The Firewall Command Failed

## Example Error

```text
FirewallD is not running
```

The original script used:

```bash
firewall-cmd --add-port=5672/tcp
```

If `firewalld` is inactive, this command fails.

Check first:

```bash
sudo systemctl is-active firewalld
```

When `firewalld` is inactive, do not start it only to fix the RabbitMQ application connection without reviewing the existing system configuration.

The AWS Security Group may already be controlling the required traffic.

---

# Problem: Package Installation Failed

## Possible Reasons

- The selected operating system was not compatible with the repository
- The repository package was unavailable
- The private EC2 instance had no internet access
- The NAT Gateway route was missing
- DNS resolution was not working

Test internet access:

```bash
curl -I https://github.com
```

Test DNS:

```bash
getent hosts github.com
```

Verify the private route table:

```text
0.0.0.0/0 -> NAT Gateway
```

Verify the repository:

```bash
sudo dnf repolist | grep -i rabbitmq
```

---

## Useful Verification Commands

### Service Status

```bash
sudo systemctl is-active rabbitmq-server
```

### Service Enabled

```bash
sudo systemctl is-enabled rabbitmq-server
```

### RabbitMQ Diagnostic Ping

```bash
sudo rabbitmq-diagnostics -q ping
```

### RabbitMQ Status

```bash
sudo rabbitmqctl status
```

### Listening Port

```bash
sudo ss -lntp | grep 5672
```

### Users

```bash
sudo rabbitmqctl list_users
```

### Permissions

```bash
sudo rabbitmqctl list_permissions -p /
```

### Connections

```bash
sudo rabbitmqctl list_connections
```

### Exchanges

```bash
sudo rabbitmqctl list_exchanges
```

### Queues

```bash
sudo rabbitmqctl list_queues
```

### DNS Test from Tomcat

```bash
getent hosts mq.vprofile.internal
```

### Port Test from Tomcat

```bash
nc -zv mq.vprofile.internal 5672
```

### Recent Logs

```bash
sudo journalctl \
  -u rabbitmq-server \
  --no-pager \
  -n 50
```

---

## Final Verification Checklist

```text
[ ] RabbitMQ package is installed
[ ] RabbitMQ service is active
[ ] RabbitMQ service is enabled
[ ] RabbitMQ diagnostic ping succeeds
[ ] RabbitMQ listens on TCP port 5672
[ ] Dedicated application user exists
[ ] Application user has permissions on virtual host /
[ ] RabbitMQ Security Group allows port 5672 from Tomcat only
[ ] firewalld allows TCP 5672 when firewalld is active
[ ] mq.vprofile.internal resolves from Tomcat
[ ] Port 5672 is reachable from Tomcat
[ ] Application configuration uses mq.vprofile.internal
[ ] Application uses the dedicated RabbitMQ user
[ ] /user/rabbit test works through the application
[ ] RabbitMQ exchange appears after the application test
```

---

## Security Notes

- Do not expose port `5672` to the internet
- Do not use `0.0.0.0/0` as the RabbitMQ Security Group source
- Do not use `guest/guest` for remote application access
- Do not commit the RabbitMQ password to GitHub
- Do not use a simple password such as `test`
- Give the application user only the permissions it needs
- Do not open the management port publicly
- Use AWS Secrets Manager or Parameter Store in production

---

## Production Improvements

A production environment can improve this setup by using:

- Amazon MQ
- A RabbitMQ cluster
- Multiple Availability Zones
- Encrypted AMQP connections
- Secret management
- Monitoring and alarms
- Automated backups
- Restricted application permissions
- Private management access
- Automatic node replacement

---

## Screenshots

Recommended screenshots for this section:

```text
screenshots/ec2/rabbitmq/01-rabbitmq-package.png
screenshots/ec2/rabbitmq/02-rabbitmq-active.png
screenshots/ec2/rabbitmq/03-rabbitmq-ping.png
screenshots/ec2/rabbitmq/04-rabbitmq-listener.png
screenshots/ec2/rabbitmq/05-rabbitmq-users.png
screenshots/ec2/rabbitmq/06-rabbitmq-permissions.png
screenshots/ec2/rabbitmq/07-rabbitmq-dns-resolution.png
screenshots/ec2/rabbitmq/08-rabbitmq-port-test.png
screenshots/ec2/rabbitmq/09-rabbitmq-application-test.png
```

Hide the following before uploading screenshots:

- RabbitMQ passwords
- AWS account IDs
- Session tokens
- Unnecessary private information

---

## What I Learned

During this part, I learned how to:

- Install RabbitMQ on a Linux EC2 instance
- Manage RabbitMQ using systemd
- Check RabbitMQ health using diagnostic commands
- Create a dedicated RabbitMQ user
- Configure virtual host permissions
- Protect RabbitMQ using Security Groups
- Use Route 53 Private DNS
- Test an AMQP port from another EC2 instance
- Understand the difference between a network error and an authentication error
- Test RabbitMQ through the real application
- Read RabbitMQ service logs

---

## Next Step

Continue to:

[Tomcat Deployment](09-tomcat-deployment.md)