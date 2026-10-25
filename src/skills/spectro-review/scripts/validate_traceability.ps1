param(
    [Parameter(Mandatory = $true)][string]$FeatureId,
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$ReviewId = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$featureDir = Join-Path $root (Join-Path ".spectro/features" $FeatureId)
if (-not $ReviewId) {
    $reviewRoot = Join-Path $featureDir "reviews"
    $ReviewId = (Get-ChildItem -Directory -LiteralPath $reviewRoot | Sort-Object Name -Descending | Select-Object -First 1).Name
}
$reviewDir = Join-Path $featureDir (Join-Path "reviews" $ReviewId)
$specPath = Join-Path $featureDir "spec.md"
$planPath = Join-Path $featureDir "plan.md"
$tasksPath = Join-Path $featureDir "tasks.md"
foreach ($path in @($specPath, $tasksPath)) { if (-not (Test-Path -LiteralPath $path)) { throw "Required artifact not found: $path" } }
$spec = Get-Content -Raw -Encoding utf8 -LiteralPath $specPath
$plan = if (Test-Path -LiteralPath $planPath) { Get-Content -Raw -Encoding utf8 -LiteralPath $planPath } else { "" }
$tasks = Get-Content -Raw -Encoding utf8 -LiteralPath $tasksPath

$requirementIds = @([regex]::Matches($spec, '\b(?:FR|NFR|CON)-\d+\b') | ForEach-Object Value | Sort-Object -Unique)
$acceptanceIds = @([regex]::Matches($spec, '\bAC-\d+\b') | ForEach-Object Value | Sort-Object -Unique)
$taskIds = @([regex]::Matches($tasks, '\bTASK(?:-[A-Z]+)?-\d+\b') | ForEach-Object Value | Sort-Object -Unique)
$requirements = @()
$taskSections = @([regex]::Matches($tasks, '(?ms)^##\s+(TASK(?:-[A-Z]+)?-\d+).*?(?=^##\s+TASK|\z)'))
foreach ($id in $requirementIds) {
    $linked = @($taskSections | Where-Object { $_.Value -match "\b$([regex]::Escape($id))\b" } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $requirements += [pscustomobject]@{
        id = $id
        linked_tasks = $linked
        appears_in_plan = $plan -match "\b$([regex]::Escape($id))\b"
    }
}
$acceptance = @()
foreach ($id in $acceptanceIds) {
    $acceptance += [pscustomobject]@{
        id = $id
        appears_in_plan_or_tasks = (($plan + "`n" + $tasks) -match "\b$([regex]::Escape($id))\b")
        validation_hint = (($plan + "`n" + $tasks) -match "(?i)(test|validat|gate|evidence).{0,180}\b$([regex]::Escape($id))\b|\b$([regex]::Escape($id))\b.{0,180}(test|validat|gate|evidence)")
    }
}
$uncoveredRequirements = @($requirements | Where-Object { $_.linked_tasks.Count -eq 0 } | ForEach-Object id)
$uncoveredAcceptance = @($acceptance | Where-Object { -not $_.validation_hint } | ForEach-Object id)
$result = [ordered]@{
    schema_version = "1.0"
    feature_id = $FeatureId
    review_id = $ReviewId
    requirements = $requirements
    acceptance_criteria = $acceptance
    task_ids = $taskIds
    uncovered_requirements = $uncoveredRequirements
    uncovered_acceptance_criteria = $uncoveredAcceptance
    result = if ($uncoveredRequirements.Count -or $uncoveredAcceptance.Count) { "gaps" } else { "complete" }
}
$outputPath = Join-Path $reviewDir "traceability.json"
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding utf8
$result | ConvertTo-Json -Depth 10
if ($result.result -eq "gaps") { exit 1 }
