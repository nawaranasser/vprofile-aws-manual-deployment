# Memcached Setup

## Overview

In this part of the project, I installed and configured Memcached on a private EC2 instance.

Memcached is an in-memory caching service.

The VProfile application uses it to store frequently requested data for a short time.

This can reduce repeated database queries and improve application response time.

The Tomcat application connects to Memcached using:

```text
cache.vprofile.internal:11211
```

---

## Memcached Server Details

The setup used:

```text
Operating System: RHEL-compatible Linux
Connection Method: AWS Systems Manager Session Manager
Service: Memcached
Protocol: TCP
Port: 11211
Private DNS: cache.vprofile.internal
```

The EC2 instance was placed inside a private backend subnet.

It did not require:

- A public IP address
- Public SSH access
- Public access to port 11211

---

## Communication Flow

```text
Tomcat EC2
    |
    | TCP 11211
    v
cache.vprofile.internal
    |
    v
Memcached EC2
```

The Memcached Security Group accepts port `11211` only from the Tomcat Security Group.

---

## What Memcached Does

Without caching, the application may request the same data from MariaDB many times.

```text
Tomcat -> MariaDB -> Return Data
Tomcat -> MariaDB -> Return Same Data
Tomcat -> MariaDB -> Return Same Data
```

With Memcached, the application can temporarily store the data in memory.

```text
First Request:
Tomcat -> MariaDB -> Store Data in Memcached

Next Request:
Tomcat -> Memcached -> Return Cached Data
```

Memcached does not replace MariaDB.

MariaDB stores permanent data.

Memcached stores temporary data in memory.

---

## Step 1: Connect to the EC2 Instance

I connected to the Memcached EC2 instance using AWS Systems Manager Session Manager.

```text
EC2
-> Instances
-> Select the Memcached instance
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

## Step 2: Update Package Metadata

```bash
sudo dnf makecache
```

---

## Step 3: Install Memcached

```bash
sudo dnf install -y memcached
```

Verify the installed package:

```bash
rpm -q memcached
```

Display the installed version:

```bash
memcached --version
```

---

## Step 4: Review the Default Configuration

The Memcached configuration file is:

```text
/etc/sysconfig/memcached
```

Display the current configuration:

```bash
sudo cat /etc/sysconfig/memcached
```

A default configuration may look similar to:

```text
PORT="11211"
USER="memcached"
MAXCONN="1024"
CACHESIZE="64"
OPTIONS="-l 127.0.0.1"
```

The default listening address may allow only local connections.

Tomcat runs on another EC2 instance, so Memcached must listen on the private network interface.

---

## Step 5: Configure Memcached

Before editing the file, create a backup:

```bash
sudo cp \
  /etc/sysconfig/memcached \
  /etc/sysconfig/memcached.backup
```

Write the required configuration:

```bash
sudo tee /etc/sysconfig/memcached > /dev/null <<'EOF'
PORT="11211"
USER="memcached"
MAXCONN="1024"
CACHESIZE="64"
OPTIONS="-l 0.0.0.0 -U 0"
EOF
```

Configuration explanation:

| Option | Purpose |
|---|---|
| `PORT="11211"` | Memcached TCP port |
| `USER="memcached"` | Linux user that runs the service |
| `MAXCONN="1024"` | Maximum number of connections |
| `CACHESIZE="64"` | Cache memory size in MB |
| `-l 0.0.0.0` | Listen on the EC2 network interfaces |
| `-U 0` | Disable the UDP listener |

---

## Why UDP Was Disabled

The VProfile application connects to Memcached using TCP port `11211`.

It does not require Memcached UDP communication.

Disabling UDP reduces unnecessary network exposure.

```text
TCP 11211: Enabled
UDP: Disabled
```

---

## Step 6: Start and Enable Memcached

```bash
sudo systemctl enable --now memcached
```

Check the service status:

```bash
sudo systemctl status memcached --no-pager
```

A shorter check is:

```bash
sudo systemctl is-active memcached
```

Expected output:

```text
active
```

Verify that Memcached starts automatically after a restart:

```bash
sudo systemctl is-enabled memcached
```

Expected output:

```text
enabled
```

---

## Step 7: Verify the Listening Port

```bash
sudo ss -lntp | grep 11211
```

The expected result should show:

```text
0.0.0.0:11211
```

This means Memcached is listening for TCP connections on the EC2 private network.

It does not mean the service is publicly accessible.

The AWS Security Group still controls who can connect.

---

## Step 8: Configure the Operating System Firewall

First, check whether `firewalld` is running:

```bash
sudo systemctl is-active firewalld
```

If the result is:

```text
active
```

allow Memcached TCP traffic:

```bash
sudo firewall-cmd \
  --permanent \
  --add-port=11211/tcp
```

Reload the firewall:

```bash
sudo firewall-cmd --reload
```

Verify the rule:

```bash
sudo firewall-cmd --list-ports
```

Expected output should include:

```text
11211/tcp
```

If `firewalld` is not active, the AWS Security Group still controls network access.

---

## Step 9: Configure the AWS Security Group

The Memcached Security Group is:

```text
vprofile-cache-sg
```

Its inbound rule allows traffic only from the Tomcat Security Group.

| Type | Protocol | Port | Source |
|---|---|---:|---|
| Custom TCP | TCP | `11211` | `vprofile-app-sg` |

Do not use:

```text
Source: 0.0.0.0/0
```

Memcached should never be directly exposed to the internet.

---

## Step 10: Test Memcached Locally

Install the `nc` command if it is not available:

```bash
sudo dnf install -y nmap-ncat
```

Send the `version` command to Memcached:

```bash
printf "version\r\n" | nc 127.0.0.1 11211
```

Expected output:

```text
VERSION <installed-version>
```

---

## Step 11: Read Memcached Statistics

```bash
printf "stats\r\n" | nc 127.0.0.1 11211
```

The output should contain information such as:

```text
STAT pid
STAT uptime
STAT version
STAT curr_connections
STAT cmd_get
STAT cmd_set
STAT get_hits
STAT get_misses
END
```

This confirms that the Memcached service is responding.

---

## Step 12: Test Storing and Reading Data

Open a connection to Memcached:

```bash
nc 127.0.0.1 11211
```

Store a test value:

```text
set test-key 0 60 5
hello
```

Expected response:

```text
STORED
```

Read the value:

```text
get test-key
```

Expected response:

```text
VALUE test-key 0 5
hello
END
```

Close the connection:

```text
quit
```

The value expires after `60` seconds because that was the expiration time used in the test.

---

## Step 13: Create the Route 53 Private DNS Record

A private DNS record was created for the Memcached EC2 instance.

```text
Hosted Zone: vprofile.internal
Record Name: cache.vprofile.internal
Record Type: A
Value: Memcached EC2 private IP address
```

This allows the Tomcat application to use:

```text
cache.vprofile.internal
```

instead of a fixed private IP address.

---

## Step 14: Test DNS from Tomcat

From the Tomcat EC2 instance:

```bash
getent hosts cache.vprofile.internal
```

The command should return the private IP address of the Memcached EC2 instance.

Another possible command is:

```bash
nslookup cache.vprofile.internal
```

---

## Step 15: Test Port 11211 from Tomcat

Install `nc` on the Tomcat instance if required.

### RHEL-Compatible Linux

```bash
sudo dnf install -y nmap-ncat
```

### Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y netcat-openbsd
```

Test the port:

```bash
nc -zv cache.vprofile.internal 11211
```

Expected result:

```text
Connection succeeded
```

Another test is:

```bash
timeout 5 bash -c \
  '</dev/tcp/cache.vprofile.internal/11211'

echo $?
```

Exit code `0` means the port is reachable.

---

## Step 16: Test Memcached from Tomcat

From the Tomcat EC2 instance:

```bash
printf "version\r\n" \
  | nc cache.vprofile.internal 11211
```

Expected output:

```text
VERSION <installed-version>
```

Read the remote statistics:

```bash
printf "stats\r\n" \
  | nc cache.vprofile.internal 11211
```

This confirms:

- Route 53 Private DNS works
- The Security Group allows port 11211
- The operating system firewall allows the connection
- Memcached is listening on the private network
- Memcached is responding correctly

---

## Step 17: Update the Application Configuration

The original application used:

```properties
memcached.active.host=mc01
memcached.active.port=11211

memcached.standBy.host=mc01
memcached.standBy.port=11211
```

For the AWS deployment, the hostname was changed to:

```properties
memcached.active.host=cache.vprofile.internal
memcached.active.port=11211

memcached.standBy.host=cache.vprofile.internal
memcached.standBy.port=11211
```

In this learning project, the active and standby settings used the same Memcached server.

This was enough to test the application.

It does not provide real Memcached High Availability.

---

## Active and Standby Note

The VProfile application contains settings for:

```text
Active Memcached Host
Standby Memcached Host
```

A real High Availability design should use different cache servers.

Example:

```properties
memcached.active.host=cache-a.vprofile.internal
memcached.active.port=11211

memcached.standBy.host=cache-b.vprofile.internal
memcached.standBy.port=11211
```

The lab used one Memcached EC2 instance to reduce AWS cost.

---

# Problem: Memcached Worked Locally but Tomcat Could Not Connect

## Symptoms

The local test worked:

```bash
printf "version\r\n" | nc 127.0.0.1 11211
```

But the remote test from Tomcat failed:

```bash
nc -zv cache.vprofile.internal 11211
```

Possible errors included:

```text
Connection refused
```

```text
Connection timed out
```

---

## Reason 1: Memcached Listened Only on Localhost

Check the listening address:

```bash
sudo ss -lntp | grep 11211
```

If the output shows:

```text
127.0.0.1:11211
```

Memcached accepts only local connections.

### Solution

Update:

```text
/etc/sysconfig/memcached
```

Use:

```text
OPTIONS="-l 0.0.0.0 -U 0"
```

Restart the service:

```bash
sudo systemctl restart memcached
```

Verify again:

```bash
sudo ss -lntp | grep 11211
```

---

## Reason 2: The Security Group Blocked Port 11211

The Memcached Security Group must contain:

```text
Protocol: TCP
Port: 11211
Source: vprofile-app-sg
```

Test again from Tomcat:

```bash
nc -zv cache.vprofile.internal 11211
```

---

## Reason 3: The Operating System Firewall Blocked the Port

Check the firewall:

```bash
sudo firewall-cmd --list-ports
```

If required, add the port:

```bash
sudo firewall-cmd \
  --permanent \
  --add-port=11211/tcp

sudo firewall-cmd --reload
```

---

## Reason 4: The Route 53 Record Was Incorrect

From Tomcat:

```bash
getent hosts cache.vprofile.internal
```

Verify that the returned IP matches the Memcached EC2 private IP.

Possible problems include:

- Wrong private IP in Route 53
- Private Hosted Zone not connected to the VPC
- VPC DNS resolution disabled
- Incorrect DNS record name

---

# Problem: Connection Refused

Example:

```text
Connection refused
```

This normally means the EC2 instance was reached, but Memcached was not accepting connections on port `11211`.

Check:

```bash
sudo systemctl status memcached --no-pager
```

Check the port:

```bash
sudo ss -lntp | grep 11211
```

Restart the service:

```bash
sudo systemctl restart memcached
```

Read the logs:

```bash
sudo journalctl \
  -u memcached \
  --no-pager \
  -n 100
```

---

# Problem: Connection Timed Out

Example:

```text
Connection timed out
```

This normally indicates a network or firewall problem.

Check:

- Memcached Security Group
- Tomcat Security Group outbound rules
- Network ACLs
- Route 53 DNS result
- Operating system firewall
- Correct VPC and subnets

Test DNS:

```bash
getent hosts cache.vprofile.internal
```

Test the port:

```bash
nc -zv cache.vprofile.internal 11211
```

---

# Problem: Memcached Failed to Start

Check the service status:

```bash
sudo systemctl status memcached --no-pager
```

Read the logs:

```bash
sudo journalctl \
  -u memcached \
  --no-pager \
  -n 100
```

Review the configuration:

```bash
sudo cat /etc/sysconfig/memcached
```

A syntax error in the configuration can prevent the service from starting.

After fixing the configuration:

```bash
sudo systemctl restart memcached
```

---

# Problem: Two Memcached Processes Were Running

The Memcached service should normally be managed by `systemd`.

Check the running processes:

```bash
ps -ef | grep '[m]emcached'
```

Check the port owner:

```bash
sudo ss -lntp | grep 11211
```

Do not start another manual daemon after starting the systemd service.

Avoid running:

```bash
memcached -p 11211 -u memcached -d
```

while the systemd service is already running.

This can cause:

- Port conflicts
- Confusing process management
- Different configuration values
- A service that does not stop correctly with systemctl

Use:

```bash
sudo systemctl start memcached
sudo systemctl stop memcached
sudo systemctl restart memcached
```

---

## Useful Verification Commands

### Service Status

```bash
sudo systemctl is-active memcached
```

### Service Enabled

```bash
sudo systemctl is-enabled memcached
```

### Listening Port

```bash
sudo ss -lntp | grep 11211
```

### Local Version Test

```bash
printf "version\r\n" \
  | nc 127.0.0.1 11211
```

### Local Statistics

```bash
printf "stats\r\n" \
  | nc 127.0.0.1 11211
```

### DNS Test from Tomcat

```bash
getent hosts cache.vprofile.internal
```

### Remote Port Test

```bash
nc -zv cache.vprofile.internal 11211
```

### Remote Memcached Test

```bash
printf "version\r\n" \
  | nc cache.vprofile.internal 11211
```

### Recent Logs

```bash
sudo journalctl \
  -u memcached \
  --no-pager \
  -n 50
```

---

## Final Verification Checklist

```text
[ ] Memcached package is installed
[ ] Memcached service is active
[ ] Memcached service is enabled
[ ] Memcached listens on TCP port 11211
[ ] Memcached listens on the private network
[ ] UDP listener is disabled
[ ] Local version test works
[ ] Local stats test works
[ ] firewalld allows TCP 11211 when firewalld is active
[ ] Security Group allows TCP 11211 from Tomcat only
[ ] cache.vprofile.internal resolves from Tomcat
[ ] Port 11211 is reachable from Tomcat
[ ] Remote version test works from Tomcat
[ ] Application configuration uses the private DNS name
```

---

## Security Notes

- Never expose Memcached to the public internet
- Do not allow port `11211` from `0.0.0.0/0`
- Allow access only from the Tomcat Security Group
- Disable UDP when it is not required
- Do not store sensitive permanent data only in Memcached
- Remember that cached data is lost when the service restarts
- Use Amazon ElastiCache for a managed production design

---

## Production Improvements

A production environment can improve this setup by using:

- Amazon ElastiCache
- Multiple cache nodes
- Private subnets
- Automatic node replacement
- Monitoring and alarms
- Restricted Security Groups
- Encryption where supported
- A clear cache expiration policy
- Separate active and standby cache nodes

---

## Screenshots

Recommended screenshots for this section:

```text
screenshots/ec2/memcached/01-memcached-package.png
screenshots/ec2/memcached/02-memcached-configuration.png
screenshots/ec2/memcached/03-memcached-active.png
screenshots/ec2/memcached/04-memcached-listening.png
screenshots/ec2/memcached/05-local-version-test.png
screenshots/ec2/memcached/06-cache-dns-resolution.png
screenshots/ec2/memcached/07-remote-port-test.png
screenshots/ec2/memcached/08-remote-version-test.png
```

Hide sensitive AWS information before uploading screenshots.

---

## What I Learned

During this part, I learned how to:

- Install Memcached on a Linux EC2 instance
- Manage Memcached using systemd
- Configure a service to listen on the private network
- Disable an unnecessary UDP listener
- Protect Memcached using Security Groups
- Create and use a Route 53 private DNS record
- Test a TCP service using netcat
- Read Memcached statistics
- Distinguish between a local service problem and a network problem
- Understand the difference between temporary cache data and permanent database data

---

## Next Step

Continue to:

[RabbitMQ Setup](08-rabbitmq-setup.md)