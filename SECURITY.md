# Security Policy

The security of this project and the users who rely on it is taken seriously.  
If you discover a security vulnerability, **please report it responsibly.**

---

## Supported Versions

| Version | Supported          |
|--------|---------------------|
| 1.x.x  | ✔ Yes               |
| 0.x.x  | ❌ No (pre-release) |

Only the latest released version will receive security updates.

---

## Reporting a Vulnerability

**Do not open a public GitHub Issue for security-related topics.**

Instead:

1. Email the project maintainer privately at:

   **security@cloudcoremsp.com**  
   _(If you'd prefer a different address, I can update it.)_

2. Include:
   - Description of the issue
   - Steps to reproduce
   - Potential impact
   - Suggested remediation (if known)

3. You will receive acknowledgment within **48 hours**.

---

## Disclosure Process

- After validating the issue, a fix will be prepared.
- Maintainer and reporter will coordinate a timeline for:
  - Patch release
  - Public disclosure (if applicable)
- You will be credited unless you wish to remain anonymous.

---

## Best Practices for Users of This Script

To minimize risk:

- Always keep your AWS CLI updated.
- Never commit `.pem` files or AWS credentials.
- Use IAM least-privilege permissions.
- Ensure SSM Session Manager logs & access controls are enabled.
- Rotate key pairs and review IAM roles periodically.

---

Thank you for helping keep the project secure.
