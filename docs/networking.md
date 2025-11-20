# 🛠 **docs/networking.md**

# Networking Considerations

This document explains networking requirements and best practices for EC2 deployments using the EC2 Instance Deployer script.

---

## VPC Requirements

The script supports:

- Existing VPCs  
- Newly created VPCs  

If you create a new VPC:

⚠ **The script does NOT automatically create an Internet Gateway or route tables.**

You must manually create:

- An IGW (if you want public subnets)
- Route tables with `0.0.0.0/0` routes
- NAT Gateway (optional)

---

## Subnet Types

### Public Subnet
- `MapPublicIpOnLaunch = true`
- Ideal for:
  - SSH-accessible servers
  - Public-facing services

### Private Subnet
- `MapPublicIpOnLaunch = false`
- Ideal for:
  - Internal workloads
  - SSM-only bastion hosts

---

## SSM Networking Requirements

SSM-connected instances need outbound access to:

- `ssm.<region>.amazonaws.com`
- `ec2messages.<region>.amazonaws.com`
- `ssmmessages.<region>.amazonaws.com`

This can be supplied via:

### Option A — Public Subnet
- Internet Gateway → outbound access works automatically

### Option B — Private Subnet
- NAT Gateway, **or**
- VPC Interface Endpoints:
	- com.amazonaws.<region>.ssm
	- com.amazonaws.<region>.ec2messages
	- com.amazonaws.<region>.ssmmessages

---

## Security Groups

The script supports:

- Selecting existing SGs
- Creating new SGs

### Bastion Defaults
- **No inbound rules**
- Outbound allowed (default)

### General Server Defaults
- Same as above
- Add your inbound rules as needed (HTTP, SSH, etc.)

---

## Example Configurations

### SSM-Only Bastion (Private Subnet, No Public IP)

✔ Requires VPC Endpoints  
✔ No SSH  
✔ No inbound SG rules  
✔ Fully private + secure

### Standard Web Server (Public Subnet)

✔ Public IP  
✔ Inbound 80/443  
✔ Outbound updates

---

## Recommended CloudCore Patterns

- Bastions: **private subnet + SSM**
- Product workloads: private subnet + ALB
- Dev/test: public subnet, small instance classes
