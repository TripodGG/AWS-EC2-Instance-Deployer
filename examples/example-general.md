# Example Deployment: General Ubuntu Server

This example walks through deploying a **general-purpose Ubuntu EC2 server**.

---

## Goal

Deploy a small, inexpensive Ubuntu server suitable for:

- Application hosting
- Lightweight services
- Docker / dev environments

---

## Steps

### 1. Run the script

```bash
./ec2-instance-deployer.sh
```

### 2. Choose AWS Profile

```bash
Available AWS profiles:
  1) default
Select profile by number [1]:
```
Select ``1`` or press Enter.

### 3. Choose Region

```bash
Available North American regions:
  1) us-east-1
  2) us-east-2
  3) us-west-1
  4) us-west-2
Select region by number [2]:
```
Choose ``us-east-2``.

### 4. Select Server Type → General

```bash
What type of EC2 instance would you like to launch:
  1) General Use Server
  2) Bastion Server
Select an option (1-2) [1]:
```
Choose 1.

### 5. Choose OS → Ubuntu

```bash
Choose an OS:
  1) Amazon Linux
  2) macOS
  3) Ubuntu
  4) Windows Server
  5) Red Hat Enterprise Linux
  6) SUSE Linux
  7) Debian
Select an OS (1-7) [3]:
```
Choose 3 for Ubuntu.

### 6. Choose Architecture → x86_64

```bash
Choose architecture:
  1) x86_64
  2) arm64
Select an architecture (1-2) [1]:
```
Choose x86_64 unless you specifically want ARM.

### 7. Select AMI

The script will list the 10 newest Ubuntu AMIs:

```bash
Available AMIs (newest first):
  1) ami-0a123... | ubuntu-24.04.... | 2025-01-02T12:34:56
  2) ami-0b789... | ubuntu-24.04.... | 2024-12-28T09:21:00
  ...
Select an AMI by number [1]:
```
Press Enter to use the newest.

### 8. Configure Root Volume

Ubuntu AMIs typically require a minimum of 8GB.

```bash
Root volume size (GB) [8]:
```
- Press Enter to accept 8GB
- Or enter a larger size (e.g. 30 for Docker workloads)
The script will not allow you to go below the AMI’s minimum.

### 9. Instance Name & Tags

You’ll be prompted:

```bash
EC2 instance name [server-20251119-134512]:
```
Then optional tags:

```bash
Customer tag:
Environment tag:
Owner tag:
CostCenter tag:
Role tag [Server]:
```
Tags help with billing clarity, automation, grouping, and dashboards.

### 10. Instance Type

Defaults for general servers:
- ARM → ``t4g.nano``
- x86_64 → ``t3.micro``
For Ubuntu/x86_64:

```bash
Instance type [t3.micro]:
```
Press Enter or choose another instance family.

### 11. Key Pair

Three options:

```bash
1) Attach an existing SSH key pair
2) Create a new SSH key pair
3) Do not attach an SSH key pair
Select an option (1-3) [3]:
```
If you choose option 2, the key is saved at:

```bash
~/.aws/keypairs/<name>.pem
```

### 12. Associate Public IP

```bash
Associate public IP to instance ENI? (yes/no) [yes]:
```
If you're planning SSH access, leave this as yes.

### 13. VPC / Subnet / Security Group

You may select:
- Existing VPC by number or ID
- Existing Subnet by number or ID
- Existing SG by number or ID
- OR create new ones on the fly
Example:

```bash
Indexed VPC list:
  1) vpc-0d123abcd123abcd
Select VPC (number, 'new', or VPC ID):
```

### 14. Summary Confirmation

You’ll see a deployment summary like:

```bash
=== EC2 Deployment Summary ===
Profile: default
Region: us-east-2
Server Mode: general
OS Family: ubuntu
Architecture: x86_64
AMI ID: ami-xxxxx
Instance Type: t3.micro
...
Proceed with EC2 deployment? (yes/no) [yes]:
```
Type yes to continue.

## After Launch

The script will output:
- Instance ID
- Region
- Key pair info
- SSM session command (if applicable)
- SSH connection command
Example SSH:

```bash
ssh -i ~/.aws/keypairs/myserver.pem ubuntu@<public-ip>
```

## Result

You now have a fully configured, secure, cost-efficient Ubuntu EC2 server ready to:
- Host web services
- Run Docker
- Serve internal applications
- Act as an automation or CI runner
- Run APIs or small workloads
All deployed consistently across any AWS account with a single script.