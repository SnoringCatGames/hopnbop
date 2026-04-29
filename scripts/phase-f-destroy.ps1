# Phase F destroy script. Tears down the AWS-side resources
# that the Phase A-E migration has rendered obsolete.
#
# DOES NOT RUN ANYTHING BY DEFAULT. Pass -Confirm to actually
# delete. -DryRun (default) prints what would be deleted.
#
# Order matters: matchmaker depends on queue, queue depends on
# fleet (already gone), container group depends on no live
# fleets, ECR/secrets are leaf, hopnbop-website (S3+CloudFront)
# requires the Cloudflare Pages cutover to land first, and the
# Route 53 zone for hopnbop.net is the very last step (only
# after the Cloudflare zone is authoritative).
#
# Resources confirmed live as of Phase F audit (2026-04-29):
#   - GameLift container group `hopnbop-server-group:95`
#   - FlexMatch matchmaker `hopnbop-ffa-matchmaker`
#   - Game session queue `hopnbop-game-queue`
#   - FlexMatch rulesets `hopnbop-ffa-ruleset`,
#     `hopnbop-ffa-ruleset-v2`
#   - ECR repo `hopnbop-server`
#   - S3 bucket `hopnbop-website` + CloudFront
#     `E3LT833LSVTW9R` (alias hopnbop.net)
#   - Route 53 hosted zone `Z05562172A1JF6AX39U2N`
#     (hopnbop.net) — DELETE LAST, only after Cloudflare zone
#     for hopnbop.net is active.
#   - Secrets Manager: hopnbop/jwt-signing-key,
#     hopnbop/oauth/google, hopnbop/oauth/facebook,
#     hopnbop/server-api-key, hopnbop/tls-wildcard-cert.
#
# Already gone (from audit):
#   - Container fleet `containerfleet-5568a04e-...`
#   - SAM stack `hopnbop-backend`
#
# Preserved:
#   - S3 bucket `hopnbop-pulumi-state` — Phase A backend.

[CmdletBinding()]
param(
	[switch]$Confirm,
	[switch]$IncludeRoute53Zone
)

$ErrorActionPreference = "Stop"
$env:AWS_PROFILE = "hopnbop"
$env:AWS_REGION  = "us-west-2"

function Step {
	param([string]$desc, [scriptblock]$cmd)
	Write-Host "[$(if ($Confirm) {'EXEC'} else {'DRY '})] $desc" -ForegroundColor Cyan
	if ($Confirm) {
		& $cmd
		if ($LASTEXITCODE -ne 0) { throw "$desc failed (exit $LASTEXITCODE)" }
	}
}

# ---------------------------------------------------------
# 1. Matchmaker → queue → rulesets (FlexMatch chain).
# ---------------------------------------------------------
Step "delete matchmaker hopnbop-ffa-matchmaker" {
	aws gamelift delete-matchmaking-configuration `
		--name hopnbop-ffa-matchmaker
}
Step "delete game-session-queue hopnbop-game-queue" {
	aws gamelift delete-game-session-queue `
		--name hopnbop-game-queue
}
foreach ($rs in @("hopnbop-ffa-ruleset", "hopnbop-ffa-ruleset-v2")) {
	Step "delete matchmaking-rule-set $rs" {
		aws gamelift delete-matchmaking-rule-set --name $rs
	}
}

# ---------------------------------------------------------
# 2. Container group definition (all versions).
# ---------------------------------------------------------
Step "delete container-group-definition hopnbop-server-group" {
	aws gamelift delete-container-group-definition `
		--name hopnbop-server-group
}

# ---------------------------------------------------------
# 3. ECR repository.
# ---------------------------------------------------------
Step "delete ECR repo hopnbop-server (force, includes images)" {
	aws ecr delete-repository --repository-name hopnbop-server `
		--force
}

# ---------------------------------------------------------
# 4. Secrets Manager.
# ---------------------------------------------------------
foreach ($secret in @(
	"hopnbop/jwt-signing-key",
	"hopnbop/oauth/google",
	"hopnbop/oauth/facebook",
	"hopnbop/server-api-key",
	"hopnbop/tls-wildcard-cert"
)) {
	Step "delete secret $secret (force, no recovery window)" {
		aws secretsmanager delete-secret --secret-id $secret `
			--force-delete-without-recovery
	}
}

# ---------------------------------------------------------
# 5. CloudFront + S3 hopnbop-website.
# WARNING: only after Cloudflare Pages is serving hopnbop.net.
# ---------------------------------------------------------
Step "disable CloudFront E3LT833LSVTW9R" {
	$cfg = aws cloudfront get-distribution-config --id E3LT833LSVTW9R `
		| ConvertFrom-Json
	$cfg.DistributionConfig.Enabled = $false
	$cfg.DistributionConfig | ConvertTo-Json -Depth 30 -Compress `
		| Out-File -Encoding ASCII -FilePath "$env:TEMP\cf-cfg.json"
	aws cloudfront update-distribution --id E3LT833LSVTW9R `
		--distribution-config file://"$env:TEMP/cf-cfg.json" `
		--if-match $cfg.ETag
}
Step "wait + delete CloudFront E3LT833LSVTW9R (re-run later)" {
	# CloudFront takes ~15 min to fully disable. Re-run this
	# script after that to finish the deletion.
	$d = aws cloudfront get-distribution --id E3LT833LSVTW9R `
		| ConvertFrom-Json
	if ($d.Distribution.Status -eq "Deployed" -and `
			-not $d.Distribution.DistributionConfig.Enabled) {
		aws cloudfront delete-distribution --id E3LT833LSVTW9R `
			--if-match $d.ETag
	} else {
		Write-Host "CloudFront not yet 'Deployed + disabled'; skip"
	}
}
Step "empty + delete S3 bucket hopnbop-website" {
	aws s3 rm s3://hopnbop-website/ --recursive
	aws s3api delete-bucket --bucket hopnbop-website
}

# ---------------------------------------------------------
# 6. Route 53 hosted zone for hopnbop.net.
# ABSOLUTE LAST. Only with -IncludeRoute53Zone, only after
# Cloudflare zone for hopnbop.net is authoritative
# (verify: dig +trace hopnbop.net NS shows CF nameservers).
# ---------------------------------------------------------
if ($IncludeRoute53Zone) {
	Step "list + delete Route 53 records under hopnbop.net" {
		$records = aws route53 list-resource-record-sets `
			--hosted-zone-id Z05562172A1JF6AX39U2N `
			| ConvertFrom-Json
		# Delete everything except SOA + NS (auto-managed).
		foreach ($r in $records.ResourceRecordSets) {
			if ($r.Type -in @("SOA", "NS") -and $r.Name -eq "hopnbop.net.") {
				continue
			}
			$change = @{
				Changes = @(@{
					Action = "DELETE"
					ResourceRecordSet = $r
				})
			}
			$change | ConvertTo-Json -Depth 10 -Compress `
				| Out-File -Encoding ASCII "$env:TEMP\r53-del.json"
			aws route53 change-resource-record-sets `
				--hosted-zone-id Z05562172A1JF6AX39U2N `
				--change-batch file://"$env:TEMP/r53-del.json"
		}
	}
	Step "delete Route 53 hosted zone Z05562172A1JF6AX39U2N" {
		aws route53 delete-hosted-zone `
			--id Z05562172A1JF6AX39U2N
	}
} else {
	Write-Host "[skip] Route 53 zone deletion (-IncludeRoute53Zone not set)"
}

# ---------------------------------------------------------
# 7. CloudWatch budget alarm at $5/mo (residual catch).
# ---------------------------------------------------------
Step "create CloudWatch billing alarm at \$5/mo" {
	# Budgets API requires the account ID. Use a safe stub.
	Write-Host "TODO: aws budgets create-budget ... (manual)"
}

Write-Host ""
if ($Confirm) {
	Write-Host "Phase F destroy complete." -ForegroundColor Green
} else {
	Write-Host "Dry run complete. Re-run with -Confirm to actually delete." -ForegroundColor Yellow
}
