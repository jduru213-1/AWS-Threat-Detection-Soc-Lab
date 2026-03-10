<#
.SYNOPSIS
    Tear down the lab: empty S3 buckets, then terraform destroy.
.DESCRIPTION
    Installs AWS CLI if missing; prompts for AWS credentials if not set; empties
    the three S3 buckets then runs terraform destroy.
#>

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$infraDir = if (Test-Path (Join-Path $scriptDir "versions.tf")) { $scriptDir } else { Join-Path $scriptDir "infra" }
Set-Location $infraDir

# Refresh PATH (so we see AWS CLI / Terraform after winget install)
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# Install AWS CLI if missing (same as build.ps1)
$awsCmd = Get-Command aws -ErrorAction SilentlyContinue
if (-not $awsCmd) {
    Write-Host "`n[AWS CLI] Not found. Installing via winget..." -ForegroundColor Yellow
    try {
        winget install Amazon.AWSCLI --accept-package-agreements --accept-source-agreements
    } catch {
        Write-Error "AWS CLI install failed. Install manually: winget install Amazon.AWSCLI"
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-Error "AWS CLI installed but not found. Close and reopen PowerShell, then run this script again."
    }
    Write-Host "[AWS CLI] Installed successfully." -ForegroundColor Green
}
$awsCmd = Get-Command aws -ErrorAction SilentlyContinue

# Prompt for credentials if not set (Terraform needs these for destroy)
function Test-AwsCredentialsSet {
    if ($env:AWS_ACCESS_KEY_ID -and $env:AWS_SECRET_ACCESS_KEY) { return $true }
    try {
        $null = aws sts get-caller-identity 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}
if (-not (Test-AwsCredentialsSet)) {
    Write-Host "`n[AWS] No credentials found. Enter your AWS access key (same as used for build)." -ForegroundColor Yellow
    $accessKey = Read-Host "AWS Access Key ID"
    if ([string]::IsNullOrWhiteSpace($accessKey)) { throw "Access Key ID is required." }
    $secretPrompt = Read-Host "AWS Secret Access Key" -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secretPrompt)
    try {
        $env:AWS_SECRET_ACCESS_KEY = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $env:AWS_ACCESS_KEY_ID = $accessKey.Trim()
    Write-Host "[AWS] Credentials set for this run." -ForegroundColor Green
}

# Get bucket names from state (state pull = full JSON; most reliable)
$buckets = @()
try {
    $stateJson = terraform state pull 2>$null
    if ($stateJson) {
        $state = $stateJson | ConvertFrom-Json
        $state.resources | Where-Object { $_.type -eq 'aws_s3_bucket' } | ForEach-Object {
            $id = $_.instances[0].attributes.id
            if ($id -and $id -match '^soc-lab-') { $buckets += $id }
        }
    }
} catch {}
if ($buckets.Count -eq 0) {
    try {
        $outJson = terraform output -json 2>$null
        if ($outJson) {
            $j = $outJson | ConvertFrom-Json
            $j.PSObject.Properties | Where-Object { $_.Name -match 'bucket_name' } | ForEach-Object {
                $val = $_.Value.value
                if ($val -and $val -match '^soc-lab-') { $buckets += $val }
            }
        }
    } catch {}
}
if ($buckets.Count -eq 0) {
    try {
        $stateList = terraform state list 2>$null
        if ($stateList) {
            $stateList | Where-Object { $_ -match '^aws_s3_bucket\.' } | ForEach-Object {
                $show = terraform state show $_ 2>$null
                if ($show -match '"(soc-lab-[a-z0-9-]+)"') { $buckets += $Matches[1] }
            }
        }
    } catch {}
}

# If we have buckets but no AWS CLI, tell user to empty in Console then destroy
$awsCmd = Get-Command aws -ErrorAction SilentlyContinue
if ($buckets.Count -gt 0 -and -not $awsCmd) {
    Write-Host "AWS CLI is not installed or not in PATH." -ForegroundColor Yellow
    Write-Host "Empty these buckets in the AWS Console (S3 -> bucket -> Empty):" -ForegroundColor Yellow
    foreach ($b in $buckets) { Write-Host "  - $b" }
    Write-Host ""
    Write-Host "Then run:  terraform destroy" -ForegroundColor Cyan
    exit 1
}

function Empty-S3Bucket {
    param([string]$bucket)
    Write-Host "  $bucket ..." -ForegroundColor Gray
    $keyMarker = $null
    $versionIdMarker = $null
    $awsExe = (Get-Command aws -ErrorAction Stop).Source
    # Run aws without letting stderr terminate the script (PowerShell treats native stderr as error when Stop)
    function Invoke-Aws {
        param([string[]]$Arguments)
        $ErrorActionPreference = 'Continue'
        $out = & $awsExe @Arguments 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        return @{ Output = $out; ExitCode = $code }
    }
    do {
        $listArgs = @("s3api", "list-object-versions", "--bucket", $bucket, "--output", "json")
        if ($keyMarker) { $listArgs += "--key-marker", $keyMarker }
        if ($versionIdMarker) { $listArgs += "--version-id-marker", $versionIdMarker }
        $result = Invoke-Aws -Arguments $listArgs
        if ($result.ExitCode -ne 0) {
            Write-Error "list-object-versions failed for $bucket : $($result.Output)"
        }
        if ($result.Output -is [string]) { $verJson = $result.Output } else { $verJson = ($result.Output | Where-Object { $_ -is [string] }) -join "`n" }
        if (-not $verJson) { break }
        $data = $verJson | ConvertFrom-Json
        $versions = @()
        if ($data.Versions) { $versions = @($data.Versions) }
        $markers = @()
        if ($data.DeleteMarkers) { $markers = @($data.DeleteMarkers) }
        $objects = @()
        foreach ($v in $versions) {
            if ($v -and $v.Key) { $objects += @{ Key = $v.Key; VersionId = $v.VersionId } }
        }
        foreach ($m in $markers) {
            if ($m -and $m.Key) { $objects += @{ Key = $m.Key; VersionId = $m.VersionId } }
        }
        if ($objects.Count -eq 0) { break }
        for ($i = 0; $i -lt $objects.Count; $i += 1000) {
            $batch = $objects[$i..([Math]::Min($i + 999, $objects.Count - 1))]
            $arr = @($batch | ForEach-Object {
                $o = @{ Key = $_.Key }
                if ($null -ne $_.VersionId) { $o.VersionId = $_.VersionId }
                $o
            })
            $delete = @{ Objects = $arr }
            $deleteJson = $delete | ConvertTo-Json -Depth 5 -Compress
            $payloadName = "s3delete.json"
            $payloadPath = Join-Path $env:TEMP $payloadName
            # UTF-8 without BOM so AWS CLI doesn't see "∩╗┐" and fail parsing
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText($payloadPath, $deleteJson, $utf8NoBom)
            # Run from TEMP so file://./s3delete.json resolves in CWD (avoids file:///C:/ [Errno 22] on Windows)
            Push-Location $env:TEMP
            try {
                $result = Invoke-Aws -Arguments @("s3api", "delete-objects", "--bucket", $bucket, "--delete=file://./s3delete.json")
            } finally {
                Pop-Location
            }
            Remove-Item $payloadPath -Force -ErrorAction SilentlyContinue
            if ($result.ExitCode -ne 0) {
                Write-Error "delete-objects failed for $bucket : $($result.Output)"
            }
        }
        $keyMarker = $data.NextKeyMarker
        $versionIdMarker = $data.NextVersionIdMarker
    } while ($keyMarker -or $versionIdMarker)
    # Remove any remaining current objects (e.g. unversioned or race)
    $result = Invoke-Aws -Arguments @("s3", "rm", "s3://$bucket/", "--recursive", "--quiet")
    if ($result.ExitCode -ne 0) {
        Write-Error "s3 rm --recursive failed for $bucket : $($result.Output)"
    }
}

if ($buckets.Count -gt 0) {
    Write-Host "Emptying S3 buckets:" -ForegroundColor Cyan
    foreach ($bucket in $buckets) {
        Empty-S3Bucket -bucket $bucket
    }
} else {
    Write-Host "No bucket outputs in state (already destroyed or not applied)." -ForegroundColor Gray
}

# Delete Splunk IAM user's access keys if they exist. This avoids IAM DeleteConflict
# when Terraform tries to delete the user but keys were created outside of TF or
# rotated multiple times.
try {
    $splunkUser = "soc-lab-splunk-addon"
    $awsExe = (Get-Command aws -ErrorAction Stop).Source
    function Invoke-Aws {
        param([string[]]$Arguments)
        $ErrorActionPreference = 'Continue'
        $out = & $awsExe @Arguments 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        return @{ Output = $out; ExitCode = $code }
    }

    $list = Invoke-Aws -Arguments @("iam", "list-access-keys", "--user-name", $splunkUser, "--output", "json")
    if ($list.ExitCode -eq 0 -and $list.Output) {
        $json = if ($list.Output -is [string]) { $list.Output } else { ($list.Output | Where-Object { $_ -is [string] }) -join "`n" }
        if ($json) {
            $ak = $json | ConvertFrom-Json
            $keys = @()
            if ($ak.AccessKeyMetadata) { $keys = @($ak.AccessKeyMetadata) }
            if ($keys.Count -gt 0) {
                Write-Host "Deleting IAM access keys for $splunkUser ..." -ForegroundColor Cyan
                foreach ($k in $keys) {
                    if ($k.AccessKeyId) {
                        $del = Invoke-Aws -Arguments @("iam", "delete-access-key", "--user-name", $splunkUser, "--access-key-id", $k.AccessKeyId)
                        if ($del.ExitCode -ne 0) {
                            Write-Warning "Failed to delete access key $($k.AccessKeyId): $($del.Output)"
                        }
                    }
                }
            }
        }
    }
} catch {
    # If the user doesn't exist or AWS CLI errors, Terraform destroy will handle it.
}

Write-Host "Running terraform destroy..." -ForegroundColor Cyan
terraform destroy
