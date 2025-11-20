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

