<#
.SYNOPSIS
    Creates or updates the AWS profile "stratus-lab" from .env.stratus and sets this session to use it.
.DESCRIPTION
    Reads STRATUS_AWS_ACCESS_KEY_ID and STRATUS_AWS_SECRET_ACCESS_KEY from repo root .env.stratus,
    writes [stratus-lab] into ~/.aws/credentials (creating the file/folder if needed), and sets
    AWS_PROFILE and AWS_REGION in the current process so you can run "stratus list/detonate" directly.
    Run once per PowerShell session (or run once to create the profile, then set $env:AWS_PROFILE = "stratus-lab" in new sessions).
.EXAMPLE
    .\set-stratus-profile.ps1
    stratus list --platform aws
    stratus detonate aws.initial-access.ec2-instance-credentials --cleanup
#>

$ErrorActionPreference = "Stop"

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot   = Split-Path $scriptDir -Parent
$envPath    = Join-Path $repoRoot ".env.stratus"

if (-not (Test-Path $envPath)) {
    Write-Error "Missing .env.stratus at $envPath. Run infra\build.ps1 first so Terraform writes it."
}

$accessKeyId = $null
$secretKey   = $null
Get-Content $envPath -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if ($line -and $line -notmatch '^\s*#') {
        $eq = $line.IndexOf('=')
        if ($eq -gt 0) {
            $name = $line.Substring(0, $eq).Trim()
            $val  = $line.Substring($eq + 1).Trim()
            if ($name -eq 'STRATUS_AWS_ACCESS_KEY_ID' -or $name -eq 'AWS_ACCESS_KEY_ID') { $script:accessKeyId = $val }
            if ($name -eq 'STRATUS_AWS_SECRET_ACCESS_KEY' -or $name -eq 'AWS_SECRET_ACCESS_KEY') { $script:secretKey = $val }
        }
    }
}

if (-not $accessKeyId -or -not $secretKey) {
    Write-Error ".env.stratus must contain STRATUS_AWS_ACCESS_KEY_ID and STRATUS_AWS_SECRET_ACCESS_KEY (or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)."
}

$awsDir    = Join-Path $env:USERPROFILE ".aws"
$credPath  = Join-Path $awsDir "credentials"
$profile   = "stratus-lab"
$region    = "us-east-1"

if (-not (Test-Path $awsDir)) {
    New-Item -ItemType Directory -Path $awsDir -Force | Out-Null
}

$newSection = @"
[$profile]
aws_access_key_id = $accessKeyId
aws_secret_access_key = $secretKey

"@

$existing = @()
if (Test-Path $credPath) {
    $inStratus = $false
    Get-Content $credPath -Encoding UTF8 | ForEach-Object {
        if ($_ -match '^\s*\[\s*([^\]]+)\s*\]\s*$') {
            if ($Matches[1] -eq $profile) { $inStratus = $true } else { $inStratus = $false }
            if (-not $inStratus) { $existing += $_ }
        } else {
            if (-not $inStratus) { $existing += $_ }
        }
    }
}

$content = ($existing -join "`n").Trim()
if ($content -and -not $content.EndsWith("`n")) { $content += "`n" }
$content += "`n" + $newSection.TrimEnd()

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($credPath, $content, $utf8NoBom)

$env:AWS_PROFILE = $profile
$env:AWS_REGION  = $region

Write-Host "Profile '$profile' created/updated in $credPath" -ForegroundColor Green
Write-Host "This session is set: AWS_PROFILE=$profile, AWS_REGION=$region" -ForegroundColor Cyan
Write-Host ""
Write-Host "You can now run:" -ForegroundColor Yellow
Write-Host "  stratus list --platform aws" -ForegroundColor Gray
Write-Host "  stratus detonate <technique-id> --cleanup" -ForegroundColor Gray
Write-Host ""
