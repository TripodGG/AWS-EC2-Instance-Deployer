# Troubleshooting Guide

Common issues and how to resolve them when using `ec2-instance-deployer.sh`.

---

## Authentication Issues

### ❌ `Unable to locate credentials`
Run:

```bash
aws configure
```
Or ensure correct profile selection.

## Region Issues
❌ AMIs not found

Cause:
- Unsupported OS in selected region
- Architecture mismatch

Fix:
- Try switching to x86_64
- Try Amazon Linux or Ubuntu (widely supported)

## IAM Role / Instance Profile Errors
❌ Invalid IAM Instance Profile name

Cause:
- AWS hadn’t finished propagating the role/profile

Fix:
- Script already waits, but IAM propagation can be slow
- Rerun the script after 10–30 seconds

## Volume Mapping Issues
❌ InvalidBlockDeviceMapping (Windows snapshots)

Cause:
- Trying to set a root volume smaller than the AMI’s snapshot

Fix:
- Script automatically enforces the minimum
- Accept the default when prompted

## SSM Session Issues
❌ Instance online but SSM not connecting

Checklist:
- Instance has IAM role AmazonSSMManagedInstanceCore
- Outbound connectivity to:
	- ``ssm.<region>.amazonaws.com``
	- ``ec2messages.<region>.amazonaws.com``
	- ``ssmmessages.<region>.amazonaws.com``
- If in private subnet:
	- Ensure SSM VPC endpoints or NAT gateway

## SSH Issues
❌ Permission denied (publickey)

Fix:
Ensure private key permissions:
```bash
chmod 600 ~/.aws/keypairs/<key>.pem
```

Use correct username:
- Amazon Linux: ``ec2-user``
- Ubuntu: ``ubuntu``
- Debian: ``admin`` or ``debian``
- RHEL: ``ec2-user``
- SUSE: ``ec2-user``
- Windows: requires password retrieval

## Key Pair Errors
❌ Key pair already exists

Script will offer:
- Reuse
- Rename
- Create new

## VPC / Subnet Issues
❌ No available subnets
- Create a new one in the script
- Ensure proper route tables afterwards

## Still stuck?

Open a GitHub issue with:
- Region
- OS family
- Architecture
- Script output (redacted)