# AWS data sources and Splunk ingestion

Reference for **build output**, **what each log source writes**, and **how to wire the Splunk Add-on** (plain S3 vs SQS). Full walkthrough order: [step-by-step.md](step-by-step.md).

---

## Overview

After `build.ps1`, you have three buckets and a dedicated IAM user. The add-on reads objects from S3 directly. This doc maps Terraform output to add-on fields and explains why SQS-based inputs are not used in this lab.

---

## 1. Build (`infra\build.ps1`)

Runs Terraform. Installs AWS CLI and Terraform if missing. Prompts for credentials unless `aws configure` is already set.

**Creates:**

- Three S3 buckets (CloudTrail, Config, VPC Flow Logs)  
- CloudTrail trail → CloudTrail bucket  
- AWS Config recorder and delivery channel → Config bucket  
- VPC Flow Logs → VPC Flow bucket  
- IAM user `soc-lab-splunk-addon` with read access to those buckets only  

**Typical outputs to capture:**

| Output | Use in add-on |
|--------|----------------|
| cloudtrail bucket name | CloudTrail S3 input |
| config bucket name | Config S3 input |
| vpc_flow_logs bucket name | VPC Flow S3 input |
| splunk IAM access key ID / secret | AWS Account configuration |

```powershell
cd infra
.\build.ps1
```

---

## 2. What each source writes

### CloudTrail

Records **management API activity**. The trail delivers JSON into the CloudTrail bucket. No extra console steps—Terraform owns the trail and bucket policy.

### AWS Config

Records **configuration snapshots and changes** into the Config bucket via the delivery channel created by Terraform.

### VPC Flow Logs

**Network flow metadata** (accept/reject, src/dst, etc.) into the VPC Flow bucket. Delivery is asynchronous; allow time after first traffic.

---

## 3. Add-on inputs

Prerequisites:

- Indexes exist (`setup_splunk.py` → `aws_cloudtrail`, `aws_config`, `aws_vpcflow`).  
- One S3 input per bucket; leave SQS-related fields empty or disabled where the UI allows.  

Mapping:

| Source | Index |
|--------|--------|
| CloudTrail bucket | `aws_cloudtrail` |
| Config bucket | `aws_config` |
| VPC Flow bucket | `aws_vpcflow` |

Example searches after data appears:

```
index=aws_cloudtrail earliest=-30m
index=aws_config earliest=-30m
index=aws_vpcflow earliest=-30m
```

---

## 4. SQS-based S3 vs plain S3

| Pattern | Behavior | This lab |
|---------|----------|----------|
| **Plain S3** | Splunk lists and reads objects in the bucket. | **Use this.** |
| **SQS-based S3** | S3 events go to a queue; Splunk consumes the queue. | Do not use. |

The IAM user `soc-lab-splunk-addon` is **S3-only** by design (`s3:GetObject`, `s3:ListBucket` on the three buckets). SQS paths require `sqs:ListQueues`, `sqs:ReceiveMessage`, etc. If the add-on UI probes SQS, you may see `AccessDenied`—that is expected unless you extend IAM and add queues. **Choose plain S3 inputs only**; you can ignore SQS errors if you are not using SQS-based inputs.

---

## Requirements

- Splunk running with add-on installed  
- Build output (bucket names + Splunk IAM keys)  
- Indexes created before configuring inputs  

---

## Cleanup

AWS teardown does not remove Splunk or indexes—only run:

```powershell
cd infra
.\destroy.ps1
```

See [step-by-step.md — Cleanup](step-by-step.md#cleanup).

---

## Notes on security

- Rotate or delete `soc-lab-splunk-addon` keys if exposed; recreate via Terraform if needed.  
- Adding SQS would require new IAM statements and queues—out of scope for the default lab.
