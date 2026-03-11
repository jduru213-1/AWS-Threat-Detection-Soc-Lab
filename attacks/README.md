# Attacks (Stratus Red Team)

Use the **Stratus Red Team** IAM user (`soc-lab-stratus`) to run attack techniques in your lab. Events show up in CloudTrail → Splunk for detection practice.

## One-time setup

1. **Build infra** (creates Stratus user and writes `.env.stratus` at repo root):
   ```powershell
   cd infra
   .\build.ps1
   ```

2. **Install Stratus Red Team CLI**  
   [stratus-red-team.cloud](https://stratus-red-team.cloud/)

3. **Create AWS profile and set this session** (run from this folder):
   ```powershell
   cd attacks
   .\set-stratus-profile.ps1
   ```
   This adds/updates the `stratus-lab` profile in `~/.aws/credentials` and sets `AWS_PROFILE` for the current window.

## Run attacks

In the **same** PowerShell window after the script:

```powershell
stratus list --platform aws
stratus detonate <technique-id> --cleanup
```

For **list**, **detonate**, **warmup**, **cleanup**, and **status**, see the [Stratus usage guide](https://stratus-red-team.cloud/user-guide/usage/).

**New terminal?** Run `.\set-stratus-profile.ps1` again, or `$env:AWS_PROFILE = "stratus-lab"`.
