# Attacks (Stratus Red Team)

Use IAM user **soc-lab-stratus** to run techniques. Events → **CloudTrail → Splunk**.

---

## Setup

1. **Build infra** (creates Stratus user, `.env.stratus`):
   ```powershell
   cd infra
   .\build.ps1
   ```

2. **Configure Stratus** (installs Go + Stratus CLI if needed, creates `stratus-lab` profile):
   ```powershell
   cd attacks
   .\configure-stratus.ps1
   ```

---

## Run

Same PowerShell window:

```powershell
stratus list --platform aws
stratus detonate <technique-id> --cleanup
```

[Stratus usage guide](https://stratus-red-team.cloud/user-guide/usage/) — list, detonate, warmup, cleanup, status.

**New terminal?** Run `.\configure-stratus.ps1` again or `$env:AWS_PROFILE = "stratus-lab"`.

**Destroy:** Use build credentials (not Stratus). Open a new terminal or unset `AWS_PROFILE` before `.\destroy.ps1`.

---

## Threat scenarios for this repo

Each scenario demonstrates how cloud threats can impact confidentiality, integrity, and availability of systems, while highlighting detection opportunities across AWS telemetry sources.

### 1) Credential access / suspicious login
- Threat: Unauthorized user gains access using valid credentials.
- How to run:
  ```powershell
  stratus detonate aws.credential_access.console_login
  ```
- Logs:
  - CloudTrail: `ConsoleLogin`
- Detection ideas:
  - Multiple failed logins followed by success
  - Login from a new IP/location
  - Login without MFA
- Business impact (generic):
  - Unauthorized access to cloud resources and sensitive systems increases the risk of further compromise.

### 2) Privilege escalation (IAM abuse)
- Threat: User escalates privileges to gain elevated access.
- How to run:
  ```powershell
  stratus detonate aws.privilege_escalation.create_admin_user
  ```
- Logs:
  - CloudTrail: `AttachUserPolicy`, `CreateAccessKey`
- Detection ideas:
  - Non-admin assigning admin privileges
  - Sudden creation of new access keys
- Business impact (generic):
  - Elevated access can allow broad control of cloud resources and bypass existing security controls.

### 3) Security group exposure
- Threat: Network access is opened broadly to the internet.
- How to run:
  ```powershell
  stratus detonate aws.persistence.security_group_open
  ```
- Logs:
  - CloudTrail: `AuthorizeSecurityGroupIngress`
  - AWS Config: security group configuration changes
- Detection ideas:
  - Ports exposed to `0.0.0.0/0`
  - Sensitive ports like `22` or `3389` opened
- Business impact (generic):
  - Increased exposure of internal systems can make them reachable by unauthorized external entities.

### 4) Resource abuse / crypto-mining style activity
- Threat: Unapproved compute resources are created for malicious use.
- How to run:
  ```powershell
  stratus detonate aws.impact.ec2_spot_fleet
  ```
- Logs:
  - CloudTrail: `RunInstances`
  - VPC Flow Logs: unusual traffic spikes
- Detection ideas:
  - Sudden instance creation
  - High-cost or uncommon instance types
  - Unexpected region usage
- Business impact (generic):
  - Uncontrolled resource usage can increase operational cost and reduce service availability.

### 5) Data exfiltration (S3 access)
- Threat: Sensitive data is accessed or downloaded in bulk.
- How to run:
  ```powershell
  stratus detonate aws.exfiltration.s3_download
  ```
- Logs:
  - CloudTrail: `GetObject`
- Detection ideas:
  - High volume of object access
  - Unusual user behavior or access pattern
- Business impact (generic):
  - Unauthorized data access may lead to sensitive data loss and compliance risk.