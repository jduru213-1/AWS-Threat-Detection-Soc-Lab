# Guides

This folder holds the **full flow** and **reference** material for the AWS Threat Detection Soc Lab. The [main README](../README.md) stays high-level; these docs walk through every step and explain how data moves from AWS into Splunk.

---

## Overview

| Doc | Purpose |
|-----|---------|
| [step-by-step.md](step-by-step.md) | End-to-end deployment: Splunk up through searchable data in indexes. |
| [aws-data-and-splunk-ingestion.md](aws-data-and-splunk-ingestion.md) | Build output, what each log source writes, S3 inputs, and why plain S3 (not SQS) for this lab. |

Read **step-by-step** first if you are going from zero to searches. Use **aws-data-and-splunk-ingestion** when configuring inputs or debugging ingestion.

---

## Quick reference

| Topic | Where |
|-------|--------|
| AWS keys / stop repeated prompts | [step-by-step.md — Credentials](step-by-step.md#credentials) |
| Install Splunk Add-on for AWS | [step-by-step.md — Step 3](step-by-step.md#3-splunk-add-on-for-aws) |
| SQS `AccessDenied` / plain S3 only | [aws-data-and-splunk-ingestion.md — SQS vs plain S3](aws-data-and-splunk-ingestion.md#4-sqs-based-s3-vs-plain-s3) |
| Teardown | `infra` → `.\destroy.ps1` |

---

## Repository paths

| Path | Contents |
|------|----------|
| `soc/` | Docker Splunk, optional add-on `.tgz` |
| `infra/` | Terraform, `build.ps1`, `destroy.ps1` |
| `scripts/` | Index creation (`setup_splunk.py`) |
