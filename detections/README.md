# Detections

This folder is for Splunk material tied to the lab indexes `aws_cloudtrail`, `aws_config`, and `aws_vpcflow`. That can be SPL you paste into Search, a short note about a saved search, or a brief write-up. Use whatever format helps someone else reproduce or adapt the idea.

## Contributing

Name files so the topic is obvious, for example `failed-console-login.spl` or `iam-create-user.md`.

In each file, mention the index, the fields that matter (for example `eventName`), and what activity the search is meant to surface.

Send a pull request to `main`. If the change is large, opening an issue first is fine.

Example SPL is in the [main README](../README.md) under Detection examples. To create traffic you can search for, try [Stratus Red Team](https://stratus-red-team.cloud/attack-techniques/AWS/) against this lab’s AWS account.
