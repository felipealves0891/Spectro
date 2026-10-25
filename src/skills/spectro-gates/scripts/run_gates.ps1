param(
    [string]$FeatureId = "workspace",
    [string]$ConfigPath = ".spectro/config.yaml",
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$ContinueOnFailure
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "ProjectRoot must resolve to an existing directory: $root"
}
$configFullPath = (Resolve-Path -LiteralPath (Join-Path $root $ConfigPath)).Path

if ($FeatureId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "FeatureId contains unsupported path characters."
}

function Get-Scalar([string]$Text, [string]$Key, [string]$Default) {
    $match = [regex]::Match($Text, "(?m)^\s+$([regex]::Escape($Key)):\s*(.+?)\s*$")
    if (-not $match.Success) { return $Default }
    return $match.Groups[1].Value.Trim().Trim('"', "'")
}

function Get-List([string]$Text, [string]$Key) {
    $match = [regex]::Match($Text, "(?m)^\s+$([regex]::Escape($Key)):\s*\[(.*?)\]\s*$")
    if (-not $match.Success -or [string]::IsNullOrWhiteSpace($match.Groups[1].Value)) { return @() }
    return @($match.Groups[1].Value.Split(',') | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ })
}

function Get-Commands([string]$Text) {
    $commands = @{}
    $inCommands = $false
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s{2}commands:\s*$') { $inCommands = $true; continue }
        if ($inCommands -and $line -match '^\S') { $inCommands = $false }
        if ($inCommands -and $line -match '^\s{4}([A-Za-z0-9._-]+):\s*(.*)$') {
            $commands[$matches[1]] = $matches[2].Trim().Trim('"', "'")
        }
    }
    return $commands
}

function Get-Sha256([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
    return $null
}

function Get-CodeRevision {
    try {
        $revision = (& git -C $root rev-parse HEAD 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $revision) { return $revision }
    } catch { }
    return "uncommitted"
}

function Get-OutputInventory([string]$Directory) {
    $files = @()
    $diagnostics = @()
    $resolvedDirectory = (Resolve-Path -LiteralPath $Directory).Path.TrimEnd('\') + '\'
    foreach ($item in @(Get-ChildItem -LiteralPath $Directory -File -Recurse -Force -ErrorAction Stop)) {
        if ($item.LinkType) {
            $diagnostics += "Ignored linked output: $($item.FullName)"
            continue
        }
        $resolvedFile = (Resolve-Path -LiteralPath $item.FullName).Path
        if (-not $resolvedFile.StartsWith($resolvedDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
            $diagnostics += "Ignored output outside gate directory: $($item.FullName)"
            continue
        }
        $files += $resolvedFile.Substring($resolvedDirectory.Length).Replace('\', '/')
    }
    return [pscustomobject]@{
        files = @($files | Sort-Object)
        diagnostics = @($diagnostics)
    }
}

$configText = Get-Content -Raw -Encoding utf8 -LiteralPath $configFullPath
$required = @(Get-List $configText "required")
$optional = @(Get-List $configText "optional")
$commands = Get-Commands $configText
$timeoutSeconds = [int](Get-Scalar $configText "timeout_seconds" "900")
$failFast = (Get-Scalar $configText "fail_fast" "true") -ne "false"
if ($ContinueOnFailure) { $failFast = $false }
$gateNames = @($required + $optional | Select-Object -Unique)
if ($gateNames.Count -eq 0) { throw "No gates are configured." }

$featureDir = Join-Path $root (Join-Path ".spectro/features" $FeatureId)
$outputsRoot = Join-Path $featureDir "outputs"
$executionBase = "gate-{0}" -f (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$executionId = $executionBase
$executionNumber = 1
while (Test-Path -LiteralPath (Join-Path $outputsRoot $executionId)) {
    $executionNumber++
    $executionId = "{0}-{1:D2}" -f $executionBase, $executionNumber
}
$executionOutputDir = Join-Path $outputsRoot $executionId
$evidenceDir = Join-Path $executionOutputDir "evidence"
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$runner = Join-Path $PSScriptRoot "run_gate.ps1"
$started = Get-Date
$results = @()
$blockedByFailFast = $false
$index = 0

foreach ($gateName in $gateNames) {
    $index++
    if ($gateName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Gate name contains unsupported path characters: $gateName"
    }
    $requiredGate = $required -contains $gateName
    $command = if ($commands.ContainsKey($gateName)) { [string]$commands[$gateName] } else { "" }
    $evidencePath = Join-Path $evidenceDir ("{0:D2}-{1}.log" -f $index, $gateName)
    $gateOutputDir = Join-Path $executionOutputDir $gateName
    New-Item -ItemType Directory -Force -Path $gateOutputDir | Out-Null
    $gate = [ordered]@{
        id = "GATE-{0:D3}" -f $index
        name = $gateName
        required = $requiredGate
        status = "skipped"
        command = $command
        exit_code = $null
        duration_ms = 0
        diagnostics = @()
        evidence = @()
        output_directory = $gateOutputDir.Substring($root.Length + 1).Replace('\', '/')
        output_files = @()
        output_file_count = 0
    }

    if ($blockedByFailFast) {
        $gate.status = "blocked"
        $gate.diagnostics = @("Skipped because a previous required gate failed and fail-fast is enabled.")
        Set-Content -LiteralPath $evidencePath -Value ($gate.diagnostics -join "`n") -Encoding utf8
        $gate.evidence = @($evidencePath.Substring($root.Length + 1).Replace('\', '/'))
        $results += [pscustomobject]$gate
        continue
    }

    if ([string]::IsNullOrWhiteSpace($command)) {
        $gate.status = "blocked"
        $gate.diagnostics = @("No command configured for gate '$gateName'.")
        Set-Content -LiteralPath $evidencePath -Value ($gate.diagnostics -join "`n") -Encoding utf8
        $gate.evidence = @($evidencePath.Substring($root.Length + 1).Replace('\', '/'))
        $results += [pscustomobject]$gate
        if ($requiredGate -and $failFast) { $blockedByFailFast = $true }
        continue
    }

    $json = & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Command $command -WorkingDirectory $root -OutputDirectory $gateOutputDir -TimeoutSeconds $timeoutSeconds -EvidencePath $evidencePath 2>&1 | Out-String
    $runnerExit = $LASTEXITCODE
    try { $runResult = $json | ConvertFrom-Json } catch { $runResult = $null }
    if ($null -eq $runResult) {
        $gate.status = "error"
        $gate.exit_code = if ($runnerExit) { $runnerExit } else { 1 }
        $gate.diagnostics = @("Gate runner did not return valid JSON.", $json.Trim())
    } else {
        $gate.status = [string]$runResult.status
        $gate.exit_code = [int]$runResult.exit_code
        $gate.duration_ms = [int]$runResult.duration_ms
        if ($gate.status -ne "passed") {
            $diagnosticText = ([string]$runResult.output).Trim()
            if ($diagnosticText) { $gate.diagnostics = @($diagnosticText) }
        }
    }
    if (Test-Path -LiteralPath $evidencePath) { $gate.evidence = @($evidencePath.Substring($root.Length + 1).Replace('\', '/')) }
    $inventory = Get-OutputInventory $gateOutputDir
    $gate.output_files = @($inventory.files)
    $gate.output_file_count = $gate.output_files.Count
    if ($inventory.diagnostics.Count -gt 0) { $gate.diagnostics = @($gate.diagnostics + $inventory.diagnostics) }
    $results += [pscustomobject]$gate
    if ($requiredGate -and $failFast -and $gate.status -ne "passed") { $blockedByFailFast = $true }
}

$artifactHashes = [ordered]@{}
foreach ($name in @("spec.md", "clarifications.md", "plan.md", "tasks.md")) {
    $path = Join-Path $featureDir $name
    $hash = Get-Sha256 $path
    if ($hash) { $artifactHashes[$name] = $hash }
}
$requiredFailures = @($results | Where-Object { $_.required -and $_.status -in @("failed", "blocked", "error") })
$aggregate = if ($requiredFailures.Count -gt 0) { if ($requiredFailures.status -contains "error") { "error" } elseif ($requiredFailures.status -contains "blocked") { "blocked" } else { "failed" } } else { "passed" }
$report = [ordered]@{
    schema_version = "1.0"
    feature_id = $FeatureId
    execution_id = $executionId
    project_root = $root
    code_revision = Get-CodeRevision
    config_hash = "sha256:" + (Get-Sha256 $configFullPath)
    artifact_hashes = $artifactHashes
    started_at = $started.ToUniversalTime().ToString("o")
    duration_ms = [int]((New-TimeSpan -Start $started -End (Get-Date)).TotalMilliseconds)
    gates = @($results)
    result = $aggregate
}
$reportPath = Join-Path $featureDir "gates.json"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8
$statePath = Join-Path $featureDir "state.json"
$oldState = if (Test-Path -LiteralPath $statePath) { Get-Content -Raw -Encoding utf8 -LiteralPath $statePath | ConvertFrom-Json } else { $null }
$phases = [ordered]@{}
if ($oldState -and $oldState.phases) {
    foreach ($phase in $oldState.phases.PSObject.Properties) { $phases[$phase.Name] = $phase.Value }
}
$phases.gates = [ordered]@{
    status = if ($aggregate -eq "passed") { "completed" } else { $aggregate }
    execution_id = $executionId
    report = $reportPath.Substring($root.Length + 1)
}
$attempts = [ordered]@{}
if ($oldState -and $oldState.attempts) {
    foreach ($attempt in $oldState.attempts.PSObject.Properties) { $attempts[$attempt.Name] = $attempt.Value }
}
$state = [ordered]@{
    schema_version = "1.0"
    feature_id = $FeatureId
    current_phase = if ($aggregate -eq "passed") { "review" } else { "gates" }
    status = if ($aggregate -eq "passed") { "completed" } else { $aggregate }
    phases = $phases
    attempts = $attempts
    invalidated_executions = if ($oldState) { @($oldState.invalidated_executions) } else { @() }
    last_failure = if ($oldState) { $oldState.last_failure } else { $null }
    last_execution_id = $executionId
    updated_at = (Get-Date).ToUniversalTime().ToString("o")
}
$state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8
Write-Output ($report | ConvertTo-Json -Depth 8)
if ($aggregate -ne "passed") { exit 1 }
