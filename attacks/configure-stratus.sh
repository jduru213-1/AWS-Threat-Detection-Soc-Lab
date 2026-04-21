#!/usr/bin/env bash

# Detect whether the script is sourced into the current shell.
_IS_SOURCED=0
if (return 0 2>/dev/null); then
  _IS_SOURCED=1
fi

# Only enable strict mode when executed directly. When sourced, enabling these
# options would leak into the caller shell and can terminate interactive sessions.
if [[ $_IS_SOURCED -eq 0 ]]; then
  set -euo pipefail
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_PATH="$REPO_ROOT/.env.stratus"
PROFILE="stratus-lab"
RUN_CMD=("$@")

open_link() {
  local url="$1"
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Start-Process '$url'" >/dev/null 2>&1 || true
  elif command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "$url" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
  fi
}

# Ensure Go-installed binaries (including stratus) are discoverable in this shell.
if command -v go >/dev/null 2>&1; then
  export PATH="$(go env GOPATH)/bin:$PATH"
fi

ensure_cmd() {
  local cmd="$1"
  local app_name="$2"
  local doc_url="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  echo "Missing required application: $app_name"
  echo "Download/Install guide: $doc_url"
  read -r -p "Would you like to open the download page now? (yes/no, default: yes): " open_ans
  open_ans="${open_ans,,}"
  if [[ -z "$open_ans" || "$open_ans" == "y" || "$open_ans" == "yes" ]]; then
    open_link "$doc_url"
  fi
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$app_name is still missing. Install it, restart terminal, then rerun this script."
    exit 1
  fi
}

install_stratus_with_go() {
  if command -v stratus >/dev/null 2>&1; then
    return 0
  fi

  echo "Stratus CLI is not installed."
  echo "Recommended install method: Go (go install ...)."
  echo "Guide: https://stratus-red-team.cloud/user-guide/getting-started/"

  if ! command -v go >/dev/null 2>&1; then
    ensure_cmd go "Go 1.23+ (Linux)" "https://go.dev/dl/"
  fi

  read -r -p "Would you like to install Stratus now with Go? (yes/no, default: yes): " go_ans
  go_ans="${go_ans,,}"
  if [[ -z "$go_ans" || "$go_ans" == "y" || "$go_ans" == "yes" ]]; then
    go install -v github.com/datadog/stratus-red-team/v2/cmd/stratus@latest
    export PATH="$(go env GOPATH)/bin:$PATH"
  fi

  if ! command -v stratus >/dev/null 2>&1; then
    echo "Stratus is still missing. Install manually from: https://stratus-red-team.cloud/user-guide/getting-started/"
    exit 1
  fi
}

resolve_terraform_binary() {
  local tf_path=""

  # On Windows shells, prefer PowerShell's native executable path so stratus.exe
  # receives a usable path format (e.g., C:\...\terraform.exe).
  if command -v powershell.exe >/dev/null 2>&1; then
    tf_path="$(
      powershell.exe -NoProfile -Command "(Get-Command terraform -ErrorAction SilentlyContinue).Source" 2>/dev/null \
        | tr -d '\r' \
        | sed -n '1p'
    )"
    if [[ -n "$tf_path" ]]; then
      echo "$tf_path"
      return 0
    fi
  fi

  # Git Bash / Unix-style PATH lookup.
  if command -v terraform >/dev/null 2>&1; then
    tf_path="$(command -v terraform)"
    if command -v cygpath >/dev/null 2>&1; then
      # Convert /c/... to C:\... for Windows-native stratus.exe.
      tf_path="$(cygpath -w "$tf_path" 2>/dev/null || echo "$tf_path")"
    fi
    echo "$tf_path"
    return 0
  fi

  # Windows executable name.
  if command -v terraform.exe >/dev/null 2>&1; then
    tf_path="$(command -v terraform.exe)"
    if command -v cygpath >/dev/null 2>&1; then
      tf_path="$(cygpath -w "$tf_path" 2>/dev/null || echo "$tf_path")"
    fi
    echo "$tf_path"
    return 0
  fi

  return 1
}

ensure_cmd aws "AWS CLI" "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
ensure_cmd awk "awk" "https://gitforwindows.org/"
ensure_cmd sed "sed" "https://gitforwindows.org/"
install_stratus_with_go

# Prefer a locally installed Terraform binary when available. This avoids
# failures in Stratus auto-download flows when checksum signing keys rotate/expire.
if TF_BINARY_PATH="$(resolve_terraform_binary)"; then
  export STRATUS_TERRAFORM_BINARY_PATH="$TF_BINARY_PATH"
  echo "Using local Terraform binary: $STRATUS_TERRAFORM_BINARY_PATH"
else
  echo "[WARNING] Terraform binary not found in this shell."
  echo "          Install Terraform once (e.g., winget install -e --id HashiCorp.Terraform),"
  echo "          then open a new terminal and re-run: source ./configure-stratus.sh"
fi

if [[ ! -f "$ENV_PATH" ]]; then
  echo "Missing .env.stratus at $ENV_PATH. Run infra/build.sh first."
  exit 1
fi

ACCESS_KEY_ID="$(grep -E '^(STRATUS_AWS_ACCESS_KEY_ID|AWS_ACCESS_KEY_ID)=' "$ENV_PATH" | tail -n1 | cut -d= -f2-)"
SECRET_ACCESS_KEY="$(grep -E '^(STRATUS_AWS_SECRET_ACCESS_KEY|AWS_SECRET_ACCESS_KEY)=' "$ENV_PATH" | tail -n1 | cut -d= -f2-)"

if [[ -z "$ACCESS_KEY_ID" || -z "$SECRET_ACCESS_KEY" ]]; then
  echo ".env.stratus must contain STRATUS_AWS_ACCESS_KEY_ID and STRATUS_AWS_SECRET_ACCESS_KEY."
  exit 1
fi

# ---------------------------------------------------------------------------
# Resolve the AWS region that the lab was deployed into.
#
# Priority order:
#   1. STRATUS_AWS_REGION / AWS_REGION already set in .env.stratus
#      (build.sh writes this when the user picks a non-default region)
#   2. aws_region output from the Terraform state in infra/
#   3. Default: us-east-1 (with a visible warning so the user knows it fell back)
# ---------------------------------------------------------------------------
REGION=""

# 1. Explicit value in the env file.
REGION="$(grep -E '^(STRATUS_AWS_REGION|AWS_REGION)=' "$ENV_PATH" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"

# 2. Terraform output (works when infra/ state is present).
if [[ -z "$REGION" ]]; then
  INFRA_DIR="$REPO_ROOT/infra"
  if [[ -f "$INFRA_DIR/versions.tf" ]]; then
    REGION="$(cd "$INFRA_DIR" && terraform output -raw aws_region 2>/dev/null || true)"
  fi
fi

# 3. Fallback with a visible warning.
if [[ -z "$REGION" || "$REGION" == "null" ]]; then
  REGION="us-east-1"
  echo "[WARNING] Could not determine deployed region from .env.stratus or Terraform output."
  echo "          Defaulting to us-east-1. If your lab is in a different region, set"
  echo "          STRATUS_AWS_REGION=<region> in $ENV_PATH and re-source this script."
fi

mkdir -p "$HOME/.aws"
CRED_PATH="$HOME/.aws/credentials"
touch "$CRED_PATH"

TMP_FILE="$(mktemp)"
awk -v profile="$PROFILE" '
BEGIN { in_section=0 }
/^\s*\[.*\]\s*$/ {
  in_section = ($0 ~ "^[[:space:]]*\\[" profile "\\][[:space:]]*$")
}
{
  if (!in_section) print $0
}
' "$CRED_PATH" > "$TMP_FILE"

{
  echo
  echo "[$PROFILE]"
  echo "aws_access_key_id = $ACCESS_KEY_ID"
  echo "aws_secret_access_key = $SECRET_ACCESS_KEY"
} >> "$TMP_FILE"

mv "$TMP_FILE" "$CRED_PATH"

export AWS_PROFILE="$PROFILE"
export AWS_REGION="$REGION"

echo "Profile '$PROFILE' updated in $CRED_PATH"
echo "Session: AWS_PROFILE=$PROFILE AWS_REGION=$REGION"
echo
echo "Run:"
echo "  stratus list --platform aws"
echo "  stratus detonate <technique-id> --cleanup"

if [[ $_IS_SOURCED -eq 0 ]]; then
  if [[ ${#RUN_CMD[@]} -gt 0 ]]; then
    echo
    echo "Executing command in configured Stratus environment:"
    echo "  ${RUN_CMD[*]}"
    exec "${RUN_CMD[@]}"
  fi

  echo
  echo "[NOTE] This script was executed directly, so AWS_PROFILE/AWS_REGION were set only in a subshell."
  echo "       Use 'source ./configure-stratus.sh' to apply variables to your current terminal."
  echo "       Or run: ./configure-stratus.sh <command> (example: ./configure-stratus.sh stratus list --platform aws)"
fi
