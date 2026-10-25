param(
    [Parameter(Mandatory = $true)][ValidateSet("status", "transition", "approve", "run-gates", "resume", "finalize")][string]$Action,
    [Parameter(Mandatory = $true)][string]$FeatureId,
    [string]$ProjectRoot = (Get-Location).Path,
    [ValidateSet("specify", "clarify", "plan", "implement", "gates", "review", "completed")][string]$TargetPhase = "",
    [ValidateSet("specify", "clarify", "plan", "implement", "gates", "review", "completed")][string]$ApprovalStage = "",
    [string]$ApprovedBy = "human",
    [string]$Note = "",
    [string]$ConfigPath = ".spectro/config.yaml"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ($FeatureId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "FeatureId contains unsupported path characters." }
$featureDir = Join-Path $root (Join-Path ".spectro/features" $FeatureId)
$statePath = Join-Path $featureDir "state.json"
$eventsPath = Join-Path $featureDir "events.jsonl"
$phaseOrder = @("specify", "clarify", "plan", "implement", "gates", "review", "completed")

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
function Get-Sha256([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
    return ""
}
function New-InitialState {
    $phases = [ordered]@{}
    foreach ($phase in $phaseOrder) { $phases[$phase] = [ordered]@{ status = if ($phase -eq "specify") { "pending" } else { "pending" }; entered_at = $null } }
    return [ordered]@{
        schema_version = "1.0"
        feature_id = $FeatureId
        status = "pending"
        current_phase = "specify"
        phases = $phases
        approvals = @()
        history = @()
        last_event_id = 0
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
    }
}
function Save-State($State) {
    New-Item -ItemType Directory -Force -Path $featureDir | Out-Null
    $State.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    $State | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding utf8
}
function Load-State {
    if (Test-Path -LiteralPath $statePath) { return Get-Content -Raw -Encoding utf8 -LiteralPath $statePath | ConvertFrom-Json }
    $newState = New-InitialState
    Save-State $newState
    return Get-Content -Raw -Encoding utf8 -LiteralPath $statePath | ConvertFrom-Json
}
function Add-Event($State, [string]$Type, [hashtable]$Data) {
    $next = [int]$State.last_event_id + 1
    $event = [ordered]@{ id = $next; type = $Type; at = (Get-Date).ToUniversalTime().ToString("o"); data = $Data }
    Add-Content -LiteralPath $eventsPath -Value ($event | ConvertTo-Json -Compress -Depth 8) -Encoding utf8
    $State.last_event_id = $next
    $State.history = @($State.history) + [pscustomobject]$event
}
function Test-Artifact([string]$Name) { return Test-Path -LiteralPath (Join-Path $featureDir $Name) -PathType Leaf }
function Test-Entry([string]$Phase, $State) {
    switch ($Phase) {
        "specify" { return $true }
        "clarify" { return (Test-Artifact "spec.md") }
        "plan" { return (Test-Artifact "spec.md") }
        "implement" { return ((Test-Artifact "spec.md") -and (Test-Artifact "plan.md") -and (Test-Artifact "tasks.md")) }
        "gates" { return ((Test-Artifact "spec.md") -and (Test-Artifact "plan.md") -and (Test-Artifact "tasks.md")) }
        "review" {
            if (-not (Test-Artifact "gates.json")) { return $false }
            $gates = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $featureDir "gates.json") | ConvertFrom-Json
            return ($gates.result -eq "passed")
        }
        "completed" {
            if (-not ((Test-Artifact "gates.json") -and (Test-Artifact "review.md"))) { return $false }
            $gates = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $featureDir "gates.json") | ConvertFrom-Json
            $review = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $featureDir "review.md")
            return (($gates.result -eq "passed") -and ($review -match '(?im)(^|\n)\s*(?:Decision\s*[:`]*\s*)?approved\s*$'))
        }
    }
    return $false
}
function Has-Approval($State, [string]$Stage) {
    return @($State.approvals | Where-Object { $_.stage -eq $Stage -and $_.approved -eq $true }).Count -gt 0
}

$configFullPath = (Resolve-Path -LiteralPath (Join-Path $root $ConfigPath)).Path
$configText = Get-Content -Raw -Encoding utf8 -LiteralPath $configFullPath
$approvalStages = @(Get-List $configText "human_approval_stages")
$state = Load-State

switch ($Action) {
    "status" {
        Write-Output ($state | ConvertTo-Json -Depth 12)
        break
    }
    "resume" {
        $phase = [string]$state.current_phase
        Write-Output ([ordered]@{ feature_id = $FeatureId; current_phase = $phase; status = $state.status; next_action = "Use spectro-$phase or transition after its artifact is ready." } | ConvertTo-Json -Depth 5)
        break
    }
    "approve" {
        $stage = if ($ApprovalStage) { $ApprovalStage } else { $TargetPhase }
        if (-not $stage) { throw "ApprovalStage or TargetPhase is required for approve." }
        $approval = [pscustomobject]@{ stage = $stage; approved = $true; approved_by = $ApprovedBy; note = $Note; at = (Get-Date).ToUniversalTime().ToString("o") }
        $state.approvals = @($state.approvals | Where-Object { $_.stage -ne $stage }) + $approval
        Add-Event $state "human_approval" @{ stage = $stage; approved_by = $ApprovedBy; note = $Note }
        Save-State $state
        Write-Output ($approval | ConvertTo-Json -Depth 5)
        break
    }
    "transition" {
        if (-not $TargetPhase) { throw "TargetPhase is required for transition." }
        if (-not (Test-Entry $TargetPhase $state)) { throw "Entry conditions are not satisfied for phase '$TargetPhase'." }
        if ($TargetPhase -eq "implement" -and $approvalStages -contains "plan" -and -not (Has-Approval $state "plan")) { throw "Human approval for plan is required before implementation." }
        if ($TargetPhase -eq "completed" -and $approvalStages -contains "completed" -and -not (Has-Approval $state "completed")) { throw "Human approval for completion is required." }
        $state.current_phase = $TargetPhase
        $state.status = if ($TargetPhase -eq "completed") { "completed" } else { "running" }
        if ($state.phases.PSObject.Properties.Name -contains $TargetPhase) {
            $state.phases.$TargetPhase.status = "running"
            $state.phases.$TargetPhase.entered_at = (Get-Date).ToUniversalTime().ToString("o")
        }
        Add-Event $state "phase_transition" @{ target = $TargetPhase; note = $Note }
        Save-State $state
        Write-Output ($state | ConvertTo-Json -Depth 12)
        break
    }
    "run-gates" {
        $gateRunner = Join-Path $root "skills/spectro-gates/scripts/run_gates.ps1"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $gateRunner -FeatureId $FeatureId -ConfigPath $ConfigPath -ProjectRoot $root
        $gateExit = $LASTEXITCODE
        $state = Load-State
        Add-Event $state "gates_execution" @{ exit_code = $gateExit }
        Save-State $state
        exit $gateExit
    }
    "finalize" {
        if (-not (Test-Entry "completed" $state)) { throw "Cannot finalize: gates must pass and review.md must be approved." }
        if ($approvalStages -contains "completed" -and -not (Has-Approval $state "completed")) { throw "Human approval for completion is required." }
        $artifactNames = @("spec.md", "clarifications.md", "plan.md", "tasks.md", "gates.json", "review.md", "state.json")
        $lines = @("# Spectro final report: $FeatureId", "", "- **Decision:** approved", "- **Generated at:** $((Get-Date).ToUniversalTime().ToString('o'))", "- **Current phase:** completed", "")
        $lines += "## Artifacts"
        foreach ($name in $artifactNames) {
            $path = Join-Path $featureDir $name
            if (Test-Path -LiteralPath $path) { $lines += "- $name - sha256:$(Get-Sha256 $path)" }
        }
        $gates = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $featureDir "gates.json") | ConvertFrom-Json
        $lines += ""
        $lines += "## Gates"
        $lines += "- Result: $($gates.result)"
        foreach ($gate in @($gates.gates)) { $lines += "- $($gate.name): $($gate.status) (required=$($gate.required))" }
        $lines += ""
        $lines += "## Review"
        $lines += "- review.md decision: approved"
        $lines += ""
        $lines += "## Audit"
        $lines += "- State: state.json"
        $lines += "- Events: events.jsonl"
        $reportPath = Join-Path $featureDir "final-report.md"
        Set-Content -LiteralPath $reportPath -Value ($lines -join "`n") -Encoding utf8
        $state.current_phase = "completed"
        $state.status = "completed"
        $state.phases.completed.status = "completed"
        Add-Event $state "workflow_completed" @{ report = $reportPath.Substring($root.Length + 1) }
        Save-State $state
        Write-Output $reportPath
        break
    }
}
