# Project Architecture

This project follows a simple but powerful architecture for deploying EC2 instances across multiple AWS accounts and environments.

---

## Overview

User → Script → AWS CLI → AWS API → EC2 / IAM / VPC / SSM


The script acts as a guided “wizard” that writes no infrastructure state of its own; it simply orchestrates AWS resources.

---

## Components

### 1. **User Interaction Layer**
- Interactive menus
- Default suggestions
- Input validation
- Summaries before execution

### 2. **Resource Discovery**
- AWS CLI queries for:
  - Profiles
  - Regions (North America only)
  - AMIs based on OS + architecture filters
  - VPCs, subnets, security groups
  - Key pairs

This keeps everything dynamically derived from the AWS environment.

---

### 3. **Resource Creation**
When needed, the script can create:

- New VPCs
- New subnets
- New Security Groups
- New SSH key pairs (stored locally)
- IAM roles for SSM
- Instance profiles

---

### 4. **SSM Integration**

Bastion mode uses:

- `AmazonSSMManagedInstanceCore`
- Dedicated IAM role
- Dedicated instance profile
- No inbound rules required

---

### 5. **Deployment Layer**

Final call uses:

- `aws ec2 run-instances`
- Network interfaces instead of top-level params
- Explicit block device mappings
- Copy-safe tagging array
- Key pair attachment (optional)

---

### 6. **Post-Launch Tools**

Script prints:

- Instance ID
- Region
- Summary of settings
- SSM connection command
- SSH connection instructions (if applicable)

---

## Design Principles

- **Idempotent where possible**
- **Human-friendly**
- **No state files**
- **No dependencies beyond AWS CLI**
- **Secure by default**
- **Minimal AWS cost defaults**

---

## Diagram

```text
                           +-----------------------+
                           |     User Input        |
                           +-----------+-----------+
                                       |
                                       v
                           +-----------+-----------+
                           |     Bash Script       |
                           | (ec2-instance-deployer)|
                           +-----------+-----------+
                                       |
              -------------------------------------------------
              |                 |                 |           |
              v                 v                 v           v
     +---------------+   +--------------+  +-------------+ +--------+
     | IAM Role Mgmt |   | Network Mgmt |  | AMI Lookup | | Keypair|
     +-------+-------+   +------+-------+  +------+------+ +---+----+
             |                  |                |            |
             v                  v                v            v
         AWS IAM          AWS VPC/Subnets     AWS EC2     Local Files
                                       |
                                       v
                            +----------+-----------+
                            |   aws ec2 run-instances  |
                            +----------+-----------+
                                       |
                                       v
                            +----------+-----------+
                            |     Running EC2       |
                            +-----------------------+
