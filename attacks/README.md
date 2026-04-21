# Attacks (Stratus Red Team)

This folder helps you generate safe, controlled "known-bad" cloud activity for detection testing.

## Quick setup

1. If you have not deployed the lab yet, build the AWS resources:
   ```bash
   cd infra
   ./build.sh
   ```
2. Configure Stratus in your shell:
   ```bash
   cd attacks
   source ./configure-stratus.sh
   ```

### Each session

- Each new terminal session: run `source ./configure-stratus.sh`.
- `configure-stratus.sh` already adds Go's bin directory to `PATH` for the current shell and reuses local Terraform automatically when present.
- If you prefer not to use `source`, run commands through the script:
  `./configure-stratus.sh stratus detonate <technique-id> --cleanup`

## Run a simulation

```bash
stratus list --platform aws
stratus detonate <technique-id> --cleanup
```

These actions create telemetry that flows into CloudTrail and then into Splunk, where you can validate detections.

## Starter playbooks

### 1. Privilege Escalation (CloudTrail)
Simulates a rogue admin creating an IAM user with AdministratorAccess so you can confirm CloudTrail records the event and detections fire.

```bash
# Run the attack
stratus detonate aws.persistence.iam-create-admin-user

# Clean up
stratus cleanup aws.persistence.iam-create-admin-user
```

### 2. S3 Data Exposure (CloudTrail)
Tests whether you alert on bucket-policy tampering that opens a bucket to the world.

```bash
# Run the attack
stratus detonate aws.exfiltration.s3-backdoor-bucket-policy

# Clean up
stratus cleanup aws.exfiltration.s3-backdoor-bucket-policy
```

### 3. Network Visibility Evasion (VPC Flow Logs)
Disables VPC Flow Logs so you can prove monitoring catches attempts to blind network telemetry.

```bash
# Run the attack
stratus detonate aws.defense-evasion.vpc-remove-flow-logs

# Clean up
stratus cleanup aws.defense-evasion.vpc-remove-flow-logs
```

## Important notes

- If you open a new terminal, run `source ./configure-stratus.sh` again.
- For teardown, switch back to build/admin credentials before `./destroy.sh`.
- Use Stratus only in a sandbox/test account.

Reference: [Stratus usage guide](https://stratus-red-team.cloud/user-guide/usage/)

More attack walkthroughs: [Medium blog post](https://medium.com/p/a11e0ea98430/edit)
