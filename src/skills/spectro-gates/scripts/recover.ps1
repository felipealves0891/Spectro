param(
    [Parameter(Mandatory = $true)][string]$FeatureId,
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$ConfigPath = ".spectro/config.yaml",
    [ValidateSet("implementation-defect", "test-defect", "environment-failure", "specification-gap", "planning-defect", "needs-human-review")]
    [string]$FailureCategory = "",
    [string]$GateReportPath = "",
    [string]$CorrectionCommand = "",
    [switch]$ResumeGates
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ($FeatureId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "FeatureId contains unsupported path characters." }
$featureDir = Join-Path $root (Join-Path ".spectro/features" $FeatureId)
$statePath = Join-Path $featureDir "state.json"
if (-not $GateReportPath) { $GateReportPath = Join-Path $featureDir "gates.json" }
$reportPath = (Resolve-Path -LiteralPath $GateReportPath).Path

function Get-Scalar([string]$Text, [string]$Key, [string]$Default) {
    $match = [regex]::Match($Text, "(?m)^\s+$([regex]::Escape($Key)):\s*(.+?)\s*$")
    if (-not $match.Success) { return $Default }
    return $match.Groups[1].Value.Trim().Trim('"', "'")
}

function Get-Sha256([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
    return ""
}

function Save-State($State) {
    New-Item -ItemType Directory -Force -Path $featureDir | Out-Null
    $State.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8
}

$configFullPath = (Resolve-Path -LiteralPath (Join-Path $root $ConfigPath)).Path
$configText = Get-Content -Raw -Encoding utf8 -LiteralPath $configFullPath
$retryLimit = [int](Get-Scalar $configText "retry_limit" "3")
$timeoutSeconds = [int](Get-Scalar $configText "timeout_seconds" "900")
$report = Get-Content -Raw -Encoding utf8 -LiteralPath $reportPath | ConvertFrom-Json
$failedGates = @($report.gates | Where-Object { $_.status -in @("failed", "blocked", "error") })
if ($failedGates.Count -eq 0) { throw "The gate report contains no failed, blocked, or errored gates." }

$diagnosticText = (($failedGates | ForEach-Object { "$($_.name):$($_.status):$($_.exit_code):$($_.diagnostics -join ',')" }) -join "`n")
$failureKey = if ($FailureCategory) { $FailureCategory } else { "needs-human-review" }
if (-not $FailureCategory) {
    if ($failedGates.status -contains "blocked" -or $failedGates.status -contains "error") { $failureKey = "environment-failure" }
}
$stageByCategory = @{
    "implementation-defect" = "implement"
    "test-defect" = "implement"
    "environment-failure" = "gates"
    "specification-gap" = "clarify"
    "planning-defect" = "plan"
    "needs-human-review" = "waiting_input"
}
$targetStage = $stageByCategory[$failureKey]

$state = if (Test-Path -LiteralPath $statePath) { Get-Content -Raw -Encoding utf8 -LiteralPath $statePath | ConvertFrom-Json } else { $null }
if ($null -eq $state) {
    $state = [ordered]@{
        schema_version = "1.0"
        feature_id = $FeatureId
        current_phase = "gates"
        status = "failed"
        phases = [pscustomobject]@{}
        attempts = [pscustomobject]@{}
        invalidated_executions = @()
        last_failure = $null
        updated_at = ""
    }
}
if ($null -eq $state.attempts) { $state.attempts = [pscustomobject]@{} }
$attemptProperty = ($failureKey + ":" + (($failedGates | ForEach-Object { $_.id }) -join ","))
$attempts = @($state.attempts.PSObject.Properties | Where-Object { $_.Name -eq $attemptProperty })
$attempt = if ($attempts.Count) { [int]$attempts[0].Value } else { 0 }
$attempt++
$lastFailure = [ordered]@{
    category = $failureKey
    stage = $targetStage
    execution_id = $report.execution_id
    gate_ids = @($failedGates | ForEach-Object { $_.id })
    diagnostics = @($failedGates | ForEach-Object { "$($_.name): $($_.diagnostics -join ' ')" })
    detected_at = (Get-Date).ToUniversalTime().ToString("o")
}

if ($state.attempts -is [hashtable]) { $state.attempts[$attemptProperty] = $attempt } else { $state.attempts | Add-Member -NotePropertyName $attemptProperty -NotePropertyValue $attempt -Force }
if ($null -eq $state.phases) { $state | Add-Member -NotePropertyName phases -NotePropertyValue ([pscustomobject]@{}) }
$state.current_phase = $targetStage
$state.status = if ($attempt -gt $retryLimit) { "blocked" } else { "waiting_input" }
$state.last_failure = [pscustomobject]$lastFailure
if ($state.invalidated_executions -is [array]) { $state.invalidated_executions = @($state.invalidated_executions) + $report.execution_id } else { $state.invalidated_executions = @($report.execution_id) }
$state | Add-Member -NotePropertyName invalidation_reason -NotePropertyValue "Recovery invalidated evidence for $($report.execution_id)." -Force

if ($attempt -gt $retryLimit) {
    Save-State $state
    Write-Output "Retry limit exceeded for $attemptProperty. State is blocked."
    exit 1
}

if (-not $CorrectionCommand) {
    Save-State $state
    Write-Output ($state | ConvertTo-Json -Depth 10)
    exit 0
}

$executionOutputDir = Join-Path $featureDir (Join-Path "outputs" $report.execution_id)
$recoveryOutputDir = Join-Path $executionOutputDir (Join-Path "recovery" ("attempt-{0:D2}" -f $attempt))
$recoveryEvidence = Join-Path $executionOutputDir (Join-Path "evidence" ("recovery-{0:D2}.log" -f $attempt))
$null = New-Item -ItemType Directory -Force -Path $recoveryOutputDir
$runner = Join-Path $root "skills/spectro-gates/scripts/run_gate.ps1"
$json = & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Command $CorrectionCommand -WorkingDirectory $root -OutputDirectory $recoveryOutputDir -TimeoutSeconds $timeoutSeconds -EvidencePath $recoveryEvidence 2>&1 | Out-String
try { $correction = $json | ConvertFrom-Json } catch { $correction = $null }
if ($null -eq $correction -or $correction.status -ne "passed") {
    $state.status = "failed"
    $state.last_failure = [pscustomobject](@{ category = "environment-failure"; stage = $targetStage; correction_status = "failed"; diagnostics = @($json.Trim()) })
    Save-State $state
    Write-Output $json
    exit 1
}

$state.status = "completed"
$state.current_phase = $targetStage
$state.last_failure = [pscustomobject](@{ category = $failureKey; stage = $targetStage; correction_status = "passed"; correction_evidence = $recoveryEvidence.Substring($root.Length + 1) })
Save-State $state
Write-Output ($state | ConvertTo-Json -Depth 10)

if ($ResumeGates -and $targetStage -eq "gates") {
    $gateRunner = Join-Path $root "skills/spectro-gates/scripts/run_gates.ps1"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $gateRunner -FeatureId $FeatureId -ConfigPath $ConfigPath -ProjectRoot $root
    exit $LASTEXITCODE
}
