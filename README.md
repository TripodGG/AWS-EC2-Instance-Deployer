# EC2 Instance Deployer

A single interactive Bash script for deploying **EC2 instances** (general-purpose servers _or_ SSM-based bastion hosts) with:

- Smart AWS profile & region selection
- OS & architecture menus
- AMI discovery by owner/filters
- VPC / Subnet / Security Group selection or creation
- Key pair creation & safe local storage
- SSM-ready IAM role & instance profile
- Cost-conscious defaults (tiny instances, gp3, etc.)

Designed to be reusable across **multiple AWS accounts** and **multiple environments** with minimal friction.

---

## Features

- **Profile-aware & region-aware**
  - Detects configured AWS CLI profiles and lets you pick one
  - Or uses default credentials (env vars / instance role) if you prefer
  - Restricts region choices to **North America** (`us-*`, `ca-*`)
  - Defaults to the profile’s configured region if it’s in North America

- **Two main server modes**
  - **General Use Server**
  - **Bastion Server** (SSM-based, no inbound rules required by default)

- **OS selection**
  - Amazon Linux
  - macOS
  - Ubuntu
  - Windows Server
  - Red Hat Enterprise Linux (RHEL)
  - SUSE Linux
  - Debian

- **Architecture selection**
  - `x86_64`
  - `arm64`

- **AMI discovery**
  - Uses known owner IDs (e.g., Canonical, Debian, Red Hat, Amazon)
  - Filters for:
    - public AMIs
    - matching architecture
    - EBS + HVM
  - Shows the 10 newest matching AMIs with:
    - ID
    - Name
    - Creation date
  - You choose by **numeric index**

- **Root volume sizing**
  - Detects the AMI’s **minimum root volume size** from the snapshot
  - Uses that as the default when prompting for size
  - If you enter a smaller size, it automatically bumps up to the minimum  
    (prevents `InvalidBlockDeviceMapping` errors, especially for Windows)

- **Network configuration**
  - Lists existing **VPCs** → choose by index, ID, or create a new one
  - Lists existing **Subnets** in the chosen VPC → choose by index, ID, or create a new one
  - Lists existing **Security Groups** in the chosen VPC → choose by index, ID, or create a new one
  - New subnets can optionally map public IPs on launch
  - New security groups are created with **no inbound rules by default** (good for SSM-only access)

- **Key pair management**
  - You can:
    1. Attach an **existing** SSH key pair
    2. **Create a new** SSH key pair (saved locally)
    3. Launch **without** a key pair
  - New key pairs:
    - Created via `aws ec2 create-key-pair`
    - Private key saved to: `~/.aws/keypairs/<name>.pem`
    - File is set to mode `600`
    - If the key pair name already exists in AWS, it offers to reuse it instead

- **IAM & SSM integration**
  - Creates (if missing) or reuses:
    - `EC2SSMRole` / `EC2SSMInstanceProfile` for general servers
    - `EC2BastionSSMRole` / `EC2BastionSSMInstanceProfile` for bastions
  - Attaches `AmazonSSMManagedInstanceCore` to the role
  - Waits for IAM eventual consistency before calling `run-instances`
  - Instances are immediately ready for **SSM Session Manager**

- **Tagging**
  - Always tags:
    - `Name`
    - `Role`
    - `OS`
    - `ServerMode`
  - Optional:
    - `Customer`
    - `Environment`
    - `Owner`
    - `CostCenter`

- **Cost-friendly defaults**
  - Instance types:
    - `t4g.nano` for `arm64`
    - `t3.micro` for `x86_64`
  - Volume type: `gp3` by default
  - Public IP association: **yes** by default

---

## Prerequisites

- **AWS CLI v2**
  - Installed and available in `PATH`
  - Configured with at least one profile _or_ default credentials

- **Bash**
  - Script is intended for Linux/macOS (or WSL) with Bash

- **Permissions**
  The identity you use should have permissions to:
  - `sts:GetCallerIdentity`
  - `ec2:Describe*`, `ec2:RunInstances`, `ec2:CreateVpc`, `ec2:CreateSubnet`, `ec2:CreateSecurityGroup`, etc.
  - `iam:GetRole`, `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:CreateInstanceProfile`, `iam:AddRoleToInstanceProfile`, `iam:GetInstanceProfile`
  - `ssm:*` (for Session Manager usage), especially `ssm:StartSession`

If you don’t already have IAM permissions for these actions, you may want to run this as an admin or through an automation/infra account.

---

## Installation

```bash
git clone https://github.com/<your-org-or-user>/ec2-instance-deployer.git
cd ec2-instance-deployer
chmod +x ec2-instance-deployer.sh
