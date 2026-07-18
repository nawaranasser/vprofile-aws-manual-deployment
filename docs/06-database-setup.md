# MariaDB Database Setup

## Overview

In this part of the project, I installed and configured MariaDB on a private EC2 instance.

MariaDB stores the permanent data used by the VProfile application.

The database server was not exposed directly to the internet.

The Tomcat application connects to it through the private AWS network using:

```text
db.vprofile.internal:3306
```

The database name is:

```text
accounts
```

---

## Database Server Details

The database EC2 instance used:

```text
Operating System: Red Hat Enterprise Linux 9.8
Architecture: x86_64
Connection Method: AWS Systems Manager Session Manager
Session User: ssm-user
Database Service: MariaDB
Database Port: 3306
```

The instance was placed inside a private backend subnet.

It did not require:

- A public IP address
- An SSH key
- Public access to port 22
- Public access to port 3306

---

## Database Communication Flow

```text
Tomcat EC2
    |
    | TCP 3306
    v
db.vprofile.internal
    |
    v
MariaDB EC2
```

The MariaDB Security Group accepts port `3306` only from the Tomcat Security Group.

---

## Step 1: Connect to the EC2 Instance

I connected to the database EC2 instance using AWS Systems Manager Session Manager.

```text
EC2
-> Instances
-> Select the database instance
-> Connect
-> Session Manager
-> Connect
```

I checked the current user:

```bash
whoami
```

Expected output:

```text
ssm-user
```

I verified that administrative access worked:

```bash
sudo whoami
```

Expected output:

```text
root
```

I also checked the operating system:

```bash
cat /etc/os-release
```

---

## Step 2: Update the Package Metadata

```bash
sudo dnf makecache
```

---

## Step 3: Install MariaDB and Git

```bash
sudo dnf install -y mariadb-server git
```

MariaDB provides the database server.

Git was used to download the VProfile source code that contains the database backup file.

Verify the installed packages:

```bash
rpm -q mariadb-server
rpm -q git
```

---

## Step 4: Start MariaDB

Start and enable the MariaDB service:

```bash
sudo systemctl enable --now mariadb
```

Check the service status:

```bash
sudo systemctl status mariadb --no-pager
```

A shorter verification command is:

```bash
sudo systemctl is-active mariadb
```

Expected output:

```text
active
```

---

## Step 5: Configure MariaDB for Private Network Access

By default, a database service may listen only on the local machine.

Tomcat runs on another EC2 instance, so MariaDB must listen on the EC2 private network interface.

I created a separate MariaDB configuration file:

```bash
sudo tee /etc/my.cnf.d/vprofile.cnf > /dev/null <<'EOF'
[mysqld]
bind-address=0.0.0.0
EOF
```

Restart MariaDB:

```bash
sudo systemctl restart mariadb
```

Verify that the service is still active:

```bash
sudo systemctl is-active mariadb
```

Check the listening address and port:

```bash
sudo ss -lntp | grep 3306
```

The expected result should show MariaDB listening on:

```text
0.0.0.0:3306
```

This does not make the database public by itself.

The AWS Security Group still controls which resources can connect to port `3306`.

---

## Step 6: Create the Database

Open the MariaDB shell:

```bash
sudo mariadb
```

Create the application database:

```sql
CREATE DATABASE IF NOT EXISTS accounts
CHARACTER SET utf8
COLLATE utf8_general_ci;
```

Verify the database:

```sql
SHOW DATABASES;
```

Exit MariaDB:

```sql
EXIT;
```

The same operation can be executed directly from the Linux shell:

```bash
sudo mariadb -e "
CREATE DATABASE IF NOT EXISTS accounts
CHARACTER SET utf8
COLLATE utf8_general_ci;
"
```

---

## Step 7: Create an Application Database User

The application should use a dedicated database user instead of using the MariaDB root account remotely.

The public documentation uses example values.

Replace the password before running this command.

```bash
sudo mariadb <<'SQL'
CREATE USER IF NOT EXISTS 'vprofile_app'@'%'
IDENTIFIED BY 'CHANGE_ME_STRONG_PASSWORD';

GRANT ALL PRIVILEGES ON accounts.*
TO 'vprofile_app'@'%';

FLUSH PRIVILEGES;
SQL
```

Verify the account and grants:

```bash
sudo mariadb -e "
SELECT User, Host
FROM mysql.user
WHERE User = 'vprofile_app';
"
```

```bash
sudo mariadb -e "
SHOW GRANTS FOR 'vprofile_app'@'%';
"
```

### Important Security Note

Do not commit the real database password to GitHub.

Use placeholders in public documentation:

```text
DB_USER=vprofile_app
DB_PASSWORD=<YOUR_DATABASE_PASSWORD>
```

For a production environment, credentials should be stored in a secure service such as:

- AWS Secrets Manager
- AWS Systems Manager Parameter Store

---

## Step 8: Download the Application Source Code

The database backup is stored inside the VProfile source code repository.

Remove any previous temporary copy:

```bash
sudo rm -rf /tmp/sourcecodeseniorwr
```

Clone the repository:

```bash
git clone \
  https://github.com/abdelrahmanonline4/sourcecodeseniorwr.git \
  /tmp/sourcecodeseniorwr
```

Verify the backup file:

```bash
ls -lh \
  /tmp/sourcecodeseniorwr/src/main/resources/db_backup.sql
```

The database backup path is:

```text
/tmp/sourcecodeseniorwr/src/main/resources/db_backup.sql
```

---

## Step 9: Import the Database Backup

Import the SQL file into the `accounts` database:

```bash
sudo mariadb accounts < \
  /tmp/sourcecodeseniorwr/src/main/resources/db_backup.sql
```

If the command finishes without an error, the import was completed.

---

## Step 10: Verify the Imported Tables

List the tables:

```bash
sudo mariadb -e "SHOW TABLES FROM accounts;"
```

Expected tables include:

```text
role
user
user_role
```

Verify the data:

```bash
sudo mariadb accounts -e "
SELECT COUNT(*) AS users_count FROM \`user\`;
SELECT COUNT(*) AS roles_count FROM role;
SELECT COUNT(*) AS user_roles_count FROM user_role;
"
```

The backup used by this project contains:

```text
users_count: 10
roles_count: 1
user_roles_count: 10
```

You can also display a small sample:

```bash
sudo mariadb accounts -e "
SELECT id, username, userEmail
FROM \`user\`
LIMIT 5;
"
```

Do not publish screenshots that contain personal or sensitive data.

---

## Step 11: Verify the Database User Login

Test the application database user locally:

```bash
mariadb \
  -h 127.0.0.1 \
  -P 3306 \
  -u vprofile_app \
  -p \
  accounts
```

Enter the password when requested.

Inside MariaDB, run:

```sql
SHOW TABLES;
```

Then exit:

```sql
EXIT;
```

The password was entered interactively so that it did not appear in the command history.

---

## Step 12: Create the Route 53 Record

A private DNS record was created for the MariaDB EC2 instance.

```text
Hosted Zone: vprofile.internal
Record Name: db.vprofile.internal
Record Type: A
Value: MariaDB EC2 private IP address
```

The record allows Tomcat to connect using:

```text
db.vprofile.internal
```

instead of a hardcoded private IP address.

DNS configuration is documented in:

```text
10-route53-private-dns.md
```

---

## Step 13: Update the Application Database Configuration

The original application configuration used a local hostname such as:

```properties
jdbc.url=jdbc:mysql://db01:3306/accounts
```

For the AWS deployment, the hostname was changed to the Route 53 private DNS name:

```properties
jdbc.url=jdbc:mysql://db.vprofile.internal:3306/accounts?useUnicode=true&characterEncoding=UTF-8&zeroDateTimeBehavior=convertToNull
jdbc.username=vprofile_app
jdbc.password=<YOUR_DATABASE_PASSWORD>
```

The real password must not be committed to a public repository.

---

## Step 14: Test DNS from the Tomcat Server

From the Tomcat EC2 instance:

```bash
getent hosts db.vprofile.internal
```

The command should return the private IP address of the MariaDB EC2 instance.

Another DNS test is:

```bash
nslookup db.vprofile.internal
```

If `nslookup` is unavailable, install the required package or use `getent hosts`.

---

## Step 15: Test Port 3306 from Tomcat

From the Tomcat EC2 instance:

```bash
nc -zv db.vprofile.internal 3306
```

Expected result:

```text
Connection succeeded
```

Another test is:

```bash
timeout 5 bash -c \
  '</dev/tcp/db.vprofile.internal/3306'

echo $?
```

Exit code `0` means the port is reachable.

---

## Step 16: Test Database Login from Tomcat

Install a MariaDB client on the Tomcat server if required:

### RHEL or Amazon Linux

```bash
sudo dnf install -y mariadb
```

### Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y mariadb-client
```

Test the connection:

```bash
mariadb \
  -h db.vprofile.internal \
  -P 3306 \
  -u vprofile_app \
  -p \
  accounts
```

After entering the password:

```sql
SHOW TABLES;
```

This test confirms four things:

- Route 53 DNS works
- The Security Group allows port 3306
- MariaDB listens on the private network
- The username and password are correct

---

# Problem: MariaDB Worked Locally but Tomcat Could Not Reach It

## Symptoms

MariaDB worked on the database server:

```bash
sudo mariadb
```

But the connection from Tomcat failed.

Possible errors included:

```text
Connection refused
```

```text
Connection timed out
```

```text
Communications link failure
```

---

## Reason 1: MariaDB Listened Only on Localhost

Check the listening address:

```bash
sudo ss -lntp | grep 3306
```

If the result shows:

```text
127.0.0.1:3306
```

MariaDB accepts only local connections.

### Solution

Create:

```text
/etc/my.cnf.d/vprofile.cnf
```

with:

```ini
[mysqld]
bind-address=0.0.0.0
```

Then restart MariaDB:

```bash
sudo systemctl restart mariadb
```

Verify again:

```bash
sudo ss -lntp | grep 3306
```

---

## Reason 2: The Security Group Blocked Port 3306

The MariaDB Security Group must contain:

```text
Type: MySQL/MariaDB
Protocol: TCP
Port: 3306
Source: vprofile-app-sg
```

Do not open port `3306` to:

```text
0.0.0.0/0
```

Test again from Tomcat:

```bash
nc -zv db.vprofile.internal 3306
```

---

## Reason 3: The Database User Was Allowed Only from Localhost

A user created as:

```sql
'vprofile_app'@'localhost'
```

can connect only from the database server.

Tomcat connects from another EC2 instance.

Verify the user host:

```bash
sudo mariadb -e "
SELECT User, Host
FROM mysql.user
WHERE User = 'vprofile_app';
"
```

For this lab, the application user was created as:

```sql
'vprofile_app'@'%'
```

The AWS Security Group still limits network access to the Tomcat server.

---

## Reason 4: The Route 53 Record Was Incorrect

From Tomcat:

```bash
getent hosts db.vprofile.internal
```

Verify that the returned address matches the private IP of the MariaDB EC2 instance.

Possible causes include:

- Wrong private IP in the record
- Private Hosted Zone not associated with the VPC
- VPC DNS resolution disabled
- Typing the record name incorrectly

---

# Problem: Access Denied for the Database User

## Example Error

```text
Access denied for user 'vprofile_app'
```

## Possible Reasons

- Incorrect password
- Incorrect username
- User created for the wrong host
- Missing database privileges
- Application still using old credentials

Verify the user:

```bash
sudo mariadb -e "
SELECT User, Host
FROM mysql.user
WHERE User = 'vprofile_app';
"
```

Verify its privileges:

```bash
sudo mariadb -e "
SHOW GRANTS FOR 'vprofile_app'@'%';
"
```

Reapply the privileges when required:

```bash
sudo mariadb <<'SQL'
GRANT ALL PRIVILEGES ON accounts.*
TO 'vprofile_app'@'%';

FLUSH PRIVILEGES;
SQL
```

---

# Problem: Database Import Failed

## Check the SQL File

```bash
ls -lh \
  /tmp/sourcecodeseniorwr/src/main/resources/db_backup.sql
```

## Verify the Database Exists

```bash
sudo mariadb -e "SHOW DATABASES LIKE 'accounts';"
```

## Run the Import Again

```bash
sudo mariadb accounts < \
  /tmp/sourcecodeseniorwr/src/main/resources/db_backup.sql
```

## Check the Tables

```bash
sudo mariadb -e "SHOW TABLES FROM accounts;"
```

---

# Problem: MariaDB Service Failed to Start

Check the service:

```bash
sudo systemctl status mariadb --no-pager
```

Read the logs:

```bash
sudo journalctl -u mariadb --no-pager -n 100
```

Validate the configuration file:

```bash
sudo cat /etc/my.cnf.d/vprofile.cnf
```

The file should contain:

```ini
[mysqld]
bind-address=0.0.0.0
```

After correcting the configuration:

```bash
sudo systemctl restart mariadb
```

---

## Useful Verification Commands

### Service Status

```bash
sudo systemctl is-active mariadb
```

### Listening Port

```bash
sudo ss -lntp | grep 3306
```

### Databases

```bash
sudo mariadb -e "SHOW DATABASES;"
```

### Tables

```bash
sudo mariadb -e "SHOW TABLES FROM accounts;"
```

### Database Users

```bash
sudo mariadb -e "
SELECT User, Host
FROM mysql.user;
"
```

### Recent Logs

```bash
sudo journalctl -u mariadb --no-pager -n 50
```

---

## Final Verification Checklist

```text
[ ] MariaDB package is installed
[ ] MariaDB service is active
[ ] MariaDB starts automatically after reboot
[ ] MariaDB listens on port 3306
[ ] bind-address is set to 0.0.0.0
[ ] accounts database exists
[ ] role table exists
[ ] user table exists
[ ] user_role table exists
[ ] Application database user exists
[ ] Application user has privileges on accounts
[ ] db.vprofile.internal resolves from Tomcat
[ ] Port 3306 is reachable from Tomcat
[ ] Remote database login works from Tomcat
```

---

## Security Notes

- Do not expose port `3306` to the internet
- Allow port `3306` only from the Tomcat Security Group
- Do not use the root account from the application
- Do not store real passwords in GitHub
- Do not place passwords directly in screenshots
- Use secure secret management in production
- Take regular database backups
- Restrict database privileges using the principle of least privilege

---

## Screenshots

Recommended screenshots for this section:

```text
screenshots/ec2/database/01-rhel-version.png
screenshots/ec2/database/02-mariadb-active.png
screenshots/ec2/database/03-mariadb-listening.png
screenshots/ec2/database/04-accounts-database.png
screenshots/ec2/database/05-imported-tables.png
screenshots/ec2/database/06-route53-database-resolution.png
screenshots/ec2/database/07-remote-connection-test.png
```

Hide the following before uploading screenshots:

- Database passwords
- AWS account IDs
- Session tokens
- Unnecessary private information

---

## What I Learned

During this part, I learned how to:

- Install MariaDB on RHEL
- Manage a Linux service using systemd
- Configure MariaDB for private network connections
- Create a database and application user
- Import an SQL backup
- Verify database tables and records
- Use Route 53 Private DNS
- Test network and database connectivity
- Distinguish between a network error and an authentication error
- Protect a database using Security Groups

---

## Next Step

Continue to:

[Memcached Setup](07-memcached-setup.md)