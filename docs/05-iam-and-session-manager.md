# IAM and AWS Systems Manager

## Overview

The EC2 instances in this project were placed inside private subnets.

They did not have public IP addresses, and I did not open SSH port `22` to the internet.

I used AWS Systems Manager Session Manager to connect to the instances from the AWS Console.

```text
AWS Console
     |
     v
Systems Manager Session Manager
     |
     v
Private EC2 Instance
```

---

## Why I Used Session Manager

Session Manager allowed me to manage private EC2 instances without:

- Creating an SSH key pair
- Giving the instances public IP addresses
- Opening port `22`
- Using a bastion host
- Storing private SSH keys

This made the lab easier and more secure.

---

## Required Components

For an EC2 instance to appear in Session Manager, it needs:

1. AWS Systems Manager Agent
2. An IAM Role
3. An Instance Profile attached to the EC2 instance
4. Outbound HTTPS access on port `443`
5. Access to AWS Systems Manager service endpoints

---

# Step 1: Create the IAM Role

From the AWS Management Console:

```text
IAM
-> Roles
-> Create role
```

I selected:

```text
Trusted entity type: AWS service
Use case: EC2
```

Then I attached this AWS managed policy:

```text
AmazonSSMManagedInstanceCore
```

I used a clear role name:

```text
vprofile-ec2-ssm-role
```

This policy gives the EC2 instance the permissions required to communicate with AWS Systems Manager.

---

## IAM Role Trust Relationship

The role must trust the EC2 service.

The trust relationship should contain:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

This allows an EC2 instance to use the IAM Role.

---

# Step 2: Instance Profile

An IAM Role contains permissions.

An Instance Profile is the object that attaches the IAM Role to an EC2 instance.

When the role is created for the EC2 use case from the AWS Console, AWS normally creates the Instance Profile automatically.

```text
IAM Role
    |
    v
Instance Profile
    |
    v
EC2 Instance
```

This difference was important during troubleshooting.

Creating a role alone is not always enough if it is not attached to the instance through an Instance Profile.

---

# Step 3: Attach the Role to EC2

The IAM Role can be attached while creating the EC2 instance.

It can also be attached later.

To attach it to an existing instance:

```text
EC2
-> Instances
-> Select the instance
-> Actions
-> Security
-> Modify IAM role
```

Then select:

```text
vprofile-ec2-ssm-role
```

I attached the role to the following instances:

- Tomcat EC2
- MariaDB EC2
- Memcached EC2
- RabbitMQ EC2

---

# Step 4: Verify Network Access

The SSM Agent communicates with AWS using outbound HTTPS traffic.

Required outbound port:

```text
TCP 443
```

The private EC2 instances used the following path:

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
AWS Systems Manager
```

The EC2 Security Group must allow outbound HTTPS traffic.

For this lab, the default outbound rule was used:

| Type | Protocol | Port | Destination |
|---|---|---:|---|
| All traffic | All | All | `0.0.0.0/0` |

A more restricted environment can allow only the required outbound traffic.

---

# Step 5: Verify the SSM Agent

Most AWS-provided Linux images already include the SSM Agent.

To check the agent status:

```bash
sudo systemctl status amazon-ssm-agent
```

If the instance uses the Snap package, use:

```bash
sudo systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service
```

The expected status is:

```text
active (running)
```

---

## Start the Agent

If the service is installed but stopped:

```bash
sudo systemctl start amazon-ssm-agent
sudo systemctl enable amazon-ssm-agent
```

For a Snap installation:

```bash
sudo snap start amazon-ssm-agent
```

---

## Check the Agent Process

```bash
ps aux | grep amazon-ssm-agent
```

The output should show the SSM Agent process.

---

## Check the Agent Logs

The main SSM Agent log file is usually:

```text
/var/log/amazon/ssm/amazon-ssm-agent.log
```

Read the latest log messages:

```bash
sudo tail -n 100 /var/log/amazon/ssm/amazon-ssm-agent.log
```

Follow the log in real time:

```bash
sudo tail -f /var/log/amazon/ssm/amazon-ssm-agent.log
```

---

# Step 6: Start a Session

From the AWS Console:

```text
AWS Systems Manager
-> Session Manager
-> Start session
```

Select the EC2 instance and start the session.

Another method is:

```text
EC2
-> Instances
-> Select the instance
-> Connect
-> Session Manager
-> Connect
```

After connecting, I received a shell inside the private EC2 instance.

---

## Default Session User

The Session Manager shell may use a user such as:

```text
ssm-user
```

To confirm the current user:

```bash
whoami
```

To check the hostname:

```bash
hostname
```

To display the operating system:

```bash
cat /etc/os-release
```

---

## Administrative Commands

The `ssm-user` can normally run administrative commands using `sudo`.

Example:

```bash
sudo whoami
```

Expected result:

```text
root
```

Open a root shell when required:

```bash
sudo -i
```

It is better to use `sudo` only for commands that require administrative permissions.

---

# Problem: The Instance Did Not Appear in Session Manager

## Symptoms

The EC2 instance was running, but it did not appear in the list of managed instances.

The Session Manager connection option was not available.

---

## Possible Reasons

- No IAM Role was attached
- The wrong IAM Role was attached
- The role did not contain `AmazonSSMManagedInstanceCore`
- The Instance Profile was missing
- The SSM Agent was not running
- The private subnet had no outbound access
- Port `443` was blocked
- The route to the NAT Gateway was missing
- DNS resolution was not working
- The instance needed more time to register

---

## Fix Used in This Project

The EC2 instance was missing the correct IAM Instance Profile.

I created an EC2 IAM Role with:

```text
AmazonSSMManagedInstanceCore
```

Then I attached the role to the running EC2 instance.

```text
EC2
-> Instance
-> Actions
-> Security
-> Modify IAM role
```

After attaching the role, I waited for a short time and refreshed Session Manager.

The instance then appeared as a managed node.

---

## Verification Checklist

I checked the following items:

```text
[ ] EC2 instance is running
[ ] Correct IAM Role is attached
[ ] AmazonSSMManagedInstanceCore policy is attached
[ ] SSM Agent is installed
[ ] SSM Agent is running
[ ] Outbound TCP 443 is allowed
[ ] Private route table points to the NAT Gateway
[ ] NAT Gateway is available
[ ] VPC DNS resolution is enabled
```

---

# Problem: The Role Exists but the Instance Still Does Not Appear

Creating an IAM Role does not automatically attach it to an existing EC2 instance.

I verified the attached role from:

```text
EC2
-> Instance
-> Security
-> IAM role
```

If the field was empty, I used:

```text
Actions
-> Security
-> Modify IAM role
```

and selected the correct role.

---

# Problem: The SSM Agent Was Not Running

Check the service:

```bash
sudo systemctl status amazon-ssm-agent
```

Start it:

```bash
sudo systemctl start amazon-ssm-agent
```

Enable it after restart:

```bash
sudo systemctl enable amazon-ssm-agent
```

Check the logs:

```bash
sudo journalctl -u amazon-ssm-agent --no-pager -n 100
```

For Snap-based installations:

```bash
sudo journalctl \
  -u snap.amazon-ssm-agent.amazon-ssm-agent.service \
  --no-pager \
  -n 100
```

---

# Problem: The Private Instance Could Not Reach AWS

Test DNS:

```bash
getent hosts amazon.com
```

Test HTTPS:

```bash
curl -I https://aws.amazon.com
```

Check the private route table.

It should contain:

```text
0.0.0.0/0 -> NAT Gateway
```

The NAT Gateway must be located inside a public subnet.

The public subnet route table should contain:

```text
0.0.0.0/0 -> Internet Gateway
```

---

## Alternative: VPC Endpoints

A private EC2 instance can use Session Manager without a NAT Gateway by using VPC Interface Endpoints.

Common Systems Manager endpoints include:

```text
ssm
ssmmessages
ec2messages
```

This option keeps the communication inside the AWS network.

I used a NAT Gateway in this learning project because it was also required for:

- Package installation
- GitHub access
- Maven downloads
- Linux updates

---

## Why SSH Was Not Used

A common EC2 setup uses:

```text
Public IP
SSH Key
Port 22
```

This project used:

```text
Private IP
IAM Role
Session Manager
Outbound HTTPS
```

Comparison:

| SSH Access | Session Manager |
|---|---|
| Requires port `22` | Does not require inbound port `22` |
| Requires SSH key | Uses IAM permissions |
| May require public IP | Works with private EC2 |
| Key files must be protected | No private key file |
| Access is managed manually | Access can be controlled using IAM |

---

## Security Benefits

Using Session Manager provided the following benefits:

- No public SSH port
- No SSH keys stored on my computer
- Private EC2 instances remained private
- Access was controlled through IAM
- Sessions could be managed from the AWS Console
- Fewer inbound Security Group rules were required

---

## Production Improvements

For a production environment, I would also consider:

- Separate IAM Roles for different EC2 responsibilities
- Least-privilege IAM policies
- VPC Endpoints instead of public outbound access
- Session logging to CloudWatch Logs
- Session logging to Amazon S3
- AWS CloudTrail auditing
- Restricted administrator access
- Multi-factor authentication
- Regular IAM policy reviews

---

## Important Security Note

Do not upload the following information to a public repository:

- AWS access keys
- Secret access keys
- Temporary session tokens
- AWS account IDs when not needed
- Private credentials
- Database passwords
- Screenshots containing sensitive IAM information

The IAM Role name can be included, but secrets and credentials must never be committed.

---

## Screenshots

Recommended screenshots for this section:

```text
screenshots/ec2/01-iam-role.png
screenshots/ec2/02-ssm-policy.png
screenshots/ec2/03-instance-profile-attached.png
screenshots/ec2/04-session-manager-instance.png
screenshots/ec2/05-session-manager-terminal.png
```

Hide sensitive information before uploading screenshots.

---

## Final Access Flow

```text
Developer
    |
    v
AWS Management Console
    |
    v
AWS Systems Manager
    |
    | HTTPS 443
    v
SSM Agent
    |
    v
Private EC2 Instance
```

No inbound SSH connection was required.

---

## Next Step

Continue to:

[Database Setup](06-database-setup.md)