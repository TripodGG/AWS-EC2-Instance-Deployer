# Example Deployment: SSM Bastion Host (Amazon Linux)

This example shows a full run-through of deploying an **SSM-only bastion host** using the `ec2-instance-deployer.sh` script.

---

## Goal

Deploy a *minimal-cost* Amazon Linux bastion instance in:

- **Region:** us-east-2
- **VPC:** existing
- **Subnet:** existing public subnet
- **Security Group:** dedicated SSM-only SG
- **Access:** SSM Session Manager only (no SSH inbound)
- **Instance Type:** t4g.nano (ARM, lowest cost)

---

## Steps

### 1. Run the script

```bash
./ec2-instance-deployer.sh```

### 2. Choose AWS Profile

```bash
Available AWS profiles:
  1) default
Select profile by number [1]:```
Select ``1`` or press Enter.

### 3. Choose Region

```bash
Available North American regions:
  1) us-east-1
  2) us-east-2
  3) us-west-1
  4) us-west-2
Select region by number [2]:```
Choose ``us-east-2``.

### 4. Select Server Type

```bash
What type of EC2 instance would you like to launch:
  1) General Use Server
  2) Bastion Server
Select an option (1-2) [2]:```
Choose 2.

### 5. Choose OS → Amazon Linux

```bash
Choose an OS:
  1) Amazon Linux
  2) macOS
  3) Ubuntu
  ...
Select an OS (1-7) [1]:```

### 6. Choose Architecture

```bash
Choose architecture:
  1) x86_64
  2) arm64
Select an architecture (1-2) [2]:```
Choose arm64 for lowest cost.

### 7. Select AMI

A list of Amazon Linux AMIs appears:

```bash
1) ami-0ab123...
2) ami-0ac456...
Select an AMI by number [1]:```

### 8. Accept root volume default

```bash
Root volume size (GB) [8]:```
Press Enter.

### 9. Provide instance name (optional)

```bash
EC2 instance name [bastion-20251119-132755]:```
Enter a custom name or press Enter.

### 10. Tag values (optional)

Skip or enter as needed:

```bash
Customer tag:
Environment tag:
Owner tag:
CostCenter tag:```

### 11. Key Pair Option

```bash
1) Attach an existing SSH key pair
2) Create a new SSH key pair
3) Do not attach an SSH key pair
Select an option (1-3) [3]:```
Select 3 (SSM-only).

### 12. Associate Public IP

```bash
Associate public IP? (yes/no) [yes]:```
Press Enter.

### 13. Select VPC, subnet, and SG

Pick existing resources or create new ones.

### 14. Confirm Summary

Review the summary and choose Yes to deploy.

## Connect via SSM

```bash
aws ssm start-session \
  --target i-xxxxxxxxxxxx \
  --region us-east-2```

## Result

You now have a fully managed, cost-optimized, SSM-only bastion host.