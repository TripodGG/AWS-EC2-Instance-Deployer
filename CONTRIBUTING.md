# Contributing to EC2 Instance Deployer

Thank you for considering contributing to this project!  
All contributions — large or small, code or documentation — are welcome.

---

## How to Contribute

### 1. Fork the Repository

Click **Fork** at the top of the GitHub page to create your own copy of the repo.

Clone your fork:

```bash
git clone https://github.com/<your-username>/ec2-instance-deployer.git
cd ec2-instance-deployer
```

### 2. Create a Feature Branch

Use a descriptive name:

```bash
git checkout -b feature/add-windows-2025-support
```

### 3. Make Your Changes
Before submitting code:

- Keep the script POSIX-friendly (bash assumed).
- Include clear comments for complex AWS operations.
- Maintain the project’s formatting and structure.
- Do not include any private AWS resources or secrets.
- Test changes with at least:
	- One Linux AMI
	- One Windows AMI
	- At least two regions (if applicable)

### 4. Commit Your Changes

Use clear commit messages:

```bash
git commit -m "Add support for Ubuntu 26.04 AMIs"
```

### 5. Push and Open a Pull Request

```bash
git push origin feature/add-windows-2025-support
```

Then open a Pull Request (PR) on GitHub.

A good PR includes:
- Summary of what changed
- Reason for the change
- Any test results or examples
- Notes about potential impact or edge cases

## Coding Standards

- Shell scripts should be Bash (#!/usr/bin/env bash)
- Maintain compatibility with:
	- Amazon Linux 2 / Amazon Linux 2023
	- Ubuntu
	- macOS (local execution)
- Never hardcode ARNs, account IDs, or sensitive values
- Reference IAM roles, policies, filters, etc. dynamically where possible

## Reporting Issues

Please open an Issue on GitHub for:
- Bugs
- Feature requests
- Documentation improvements
- Questions

Include as much detail as possible:
- OS and version
- AWS CLI version
- Region(s) used
- Exact script options selected
- Log output or error messages

## Security & Responsible Disclosure

If you find a security-sensitive issue, do not open a public issue.
See ``SECURITY.md`` for proper reporting.