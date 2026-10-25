param(
    [Parameter(Mandatory = $true)][string]$FeatureId,
    [Parameter(Mandatory = $true)][string]$FindingId,
    [Parameter(Mandatory = $true)][ValidateSet("Critical", "High", "Medium", "Low")][string]$Severity,
    [Parameter(Mandatory = $true)][string]$Description,
    [ValidateSet("specify", "clarify", "plan", "implement", "gates", "human_review")][string]$ReturnStage = "implement",
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ($FindingId -notmatch '^FINDING-\d+$') { throw "FindingId must use FINDING-### format." }
$tasksPath = Join-Path $root (Join-Path ".spectro/features" (Join-Path $FeatureId "tasks.md"))
if (-not (Test-Path -LiteralPath $tasksPath)) { throw "tasks.md not found: $tasksPath" }
$text = Get-Content -Raw -Encoding utf8 -LiteralPath $tasksPath
if ($text -match [regex]::Escape($FindingId)) { throw "A remediation task already references $FindingId." }
$existing = @([regex]::Matches($text, '\bTASK-REV-(\d+)\b') | ForEach-Object { [int]$_.Groups[1].Value })
$number = if ($existing.Count) { (($existing | Measure-Object -Maximum).Maximum + 1) } else { 1 }
$task = @(
    "",
    ("## TASK-REV-{0:D3} - Remediate {1}" -f $number, $FindingId),
    "",
    "- **Status:** pending",
    "- **Finding:** $FindingId",
    "- **Severity:** $Severity",
    "- **Return stage:** $ReturnStage",
    "- **Description:** $Description",
    "- **Dependencies:** none",
    "- **Completion criteria:** Finding is resolved and relevant gates/review evidence are renewed.",
    "- **Expected tests:** Add or update behavior-focused coverage as required.",
    ""
)
Add-Content -LiteralPath $tasksPath -Value ($task -join "`n") -Encoding utf8
Write-Output ("Created TASK-REV-{0:D3} for {1}" -f $number, $FindingId)
