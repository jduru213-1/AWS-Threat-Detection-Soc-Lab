# Step-by-step deployment

This guide takes you from nothing running to **AWS logs searchable in Splunk**. Skip any step you have already completed.

---

## Overview

- **Splunk** runs in Docker on your machine; the UI is at localhost.
- **build.ps1** creates AWS logging and three S3 buckets; IAM user `soc-lab-splunk-addon` can read only those buckets.
- **Splunk Add-on for AWS** pulls from S3 into indexes `aws_cloudtrail`, `aws_config`, `aws_vpcflow`.

Deeper reference on sources and inputs: [aws-data-and-splunk-ingestion.md](aws-data-and-splunk-ingestion.md).

---

## Terminology

| Term | Meaning |
|------|---------|
| Index | Splunk storage for events; one per source in this lab. |
| Add-on | Splunk app that reads AWS S3. |
| build.ps1 | Creates buckets, trail, Config, VPC Flow Logs, Splunk IAM user. |
| destroy.ps1 | Empties buckets and deletes lab AWS resources. |

---

## Requirements

- Docker Desktop  
- Python 3.10+  
- AWS account  
- PowerShell  

If `build.ps1` keeps asking for keys, run `aws configure` once, then rerun build.

---

## Deployment instructions

### 1. Splunk (Docker)

```bash
cd soc
docker compose up -d
```

Open **https://localhost:8000**. Default login is `admin` with password from `soc/.env` or compose defaults (e.g. `ChangeMe123!`). First start may take several minutes.

---

### 2. Indexes

```bash
pip install splunk-sdk
python ./scripts/setup_splunk.py
```

Use the Splunk admin password when prompted. Confirm under **Settings → Indexes**: `aws_cloudtrail`, `aws_config`, `aws_vpcflow`.

---

### 3. Splunk Add-on for AWS

Splunkbase “Already installed” applies to your Splunkbase account only—you still install the `.tgz` into your local Splunk.

1. Download: https://splunkbase.splunk.com/app/1876/  
2. Optional: save the `.tgz` under `soc/add-on/`  
3. In Splunk: **Apps → Manage Apps → Install app from file** → upload → restart  

Inputs are configured after AWS build (Step 5). Field-level detail: [aws-data-and-splunk-ingestion.md](aws-data-and-splunk-ingestion.md).

---

### 4. AWS (build)

```powershell
cd infra
.\build.ps1
```

Use your IAM user keys if prompted. Confirm with `yes`.

**Before closing the terminal**, copy:

- Three bucket names (`soc-lab-cloudtrail-…`, `soc-lab-config-…`, `soc-lab-vpcflow-…`)  
- `soc-lab-splunk-addon` access key ID and secret (add-on only; secret is shown once)

#### Credentials {#credentials}

```powershell
aws configure
```

Stops repeated credential prompts on later runs.

If the script is blocked:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

---

### 5. Add-on inputs

1. Add-on **Configuration → AWS Account** using the Splunk IAM keys from Step 4.  
2. **Inputs → Create New Input** (three times):

| Input type | Bucket (from build output) | Index |
|------------|---------------------------|--------|
| CloudTrail | cloudtrail bucket | `aws_cloudtrail` |
| Config | config bucket | `aws_config` |
| VPC Flow Logs | vpcflow bucket | `aws_vpcflow` |

Use **plain S3** only—do not use SQS-based S3 inputs for this lab.

---

### 6. Verify

In Search:

```
index=aws_cloudtrail earliest=-30m
index=aws_config earliest=-30m
index=aws_vpcflow earliest=-30m
```

Empty results at first are normal; AWS writes and add-on polling are asynchronous—wait and retry.

---

## Cleanup

```powershell
cd infra
.\destroy.ps1
```

Confirm with `yes`. Splunk can remain running; only AWS resources are removed.

---

## Notes on security

- Keep `soc-lab-splunk-addon` keys out of repos; use only in the add-on UI.  
- Restrict execution policy bypass to trusted scripts only.

---

## Troubleshooting

| Issue | Action |
|-------|--------|
| Script blocked by policy | `powershell -ExecutionPolicy Bypass -File .\build.ps1` |
| SQS errors in add-on | [aws-data-and-splunk-ingestion.md §4](aws-data-and-splunk-ingestion.md#4-sqs-based-s3-vs-plain-s3) — use plain S3 inputs only. |
