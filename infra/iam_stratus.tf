// =============================================================================
// IAM User for Stratus Red Team (attack simulation)
// =============================================================================
// Dedicated IAM user for Stratus Red Team or similar tools to run cloud attack
// techniques in the lab. Permissions are intentionally minimal; attach
// additional AWS managed policies if you need broader coverage (e.g.
// SecurityAudit, ReadOnlyAccess). Credentials are written to .env.stratus by
// build.ps1 (git-ignored).
// =============================================================================

resource "aws_iam_user" "stratus" {
  name = "${var.project_name}-stratus"
  path = "/"

  tags = {
    Name      = "${var.project_name}-stratus"
    ManagedBy = "terraform"
    Project   = "aws-soc-lab"
  }
}

resource "aws_iam_access_key" "stratus" {
  user = aws_iam_user.stratus.name
}

