param(
    [Parameter(Mandatory = $true)][string]$ReportPath
)

$ErrorActionPreference = "Stop"
$report = Get-Content -Raw -Encoding utf8 -LiteralPath $ReportPath | ConvertFrom-Json
$errors = @()
foreach ($field in @("schema_version", "feature_id", "execution_id", "project_root", "code_revision", "config_hash", "started_at", "duration_ms", "gates", "result")) {
    if ($null -eq $report.$field) { $errors += "Missing field: $field" }
}
if ($report.project_root -and -not [System.IO.Path]::IsPathRooted([string]$report.project_root)) {
    $errors += "Invalid project_root: must be an absolute path"
}
if ($report.schema_version -ne "1.0") { $errors += "Unsupported schema_version: $($report.schema_version)" }
if ($report.result -notin @("passed", "failed", "blocked", "error")) { $errors += "Invalid aggregate result: $($report.result)" }
$allowed = @("passed", "failed", "blocked", "error", "skipped")
foreach ($gate in @($report.gates)) {
    foreach ($field in @("id", "name", "required", "status", "command", "duration_ms", "diagnostics", "evidence")) {
        if ($null -eq $gate.$field) { $errors += "$($gate.name): missing field $field" }
    }
    if ($gate.status -notin $allowed) { $errors += "$($gate.name): invalid status $($gate.status)" }
    $hasOutputContract = $null -ne $gate.output_directory -or $null -ne $gate.output_files -or $null -ne $gate.output_file_count
    if ($report.schema_version -eq "1.0" -and $null -eq $gate.output_directory) { $errors += "$($gate.name): missing field output_directory" }
    if ($report.schema_version -eq "1.0" -and $null -eq $gate.output_files) { $errors += "$($gate.name): missing field output_files" }
    if ($report.schema_version -eq "1.0" -and $null -eq $gate.output_file_count) { $errors += "$($gate.name): missing field output_file_count" }
    if ($hasOutputContract) {
        if ([string]::IsNullOrWhiteSpace([string]$gate.output_directory)) {
            $errors += "$($gate.name): output_directory must not be empty"
        } elseif ([System.IO.Path]::IsPathRooted([string]$gate.output_directory)) {
            $errors += "$($gate.name): output_directory must be relative"
        } else {
            $expectedPrefix = (Join-Path $report.project_root (Join-Path ".spectro/features/$($report.feature_id)/outputs/$($report.execution_id)" "")).TrimEnd('\') + '\'
            $resolvedOutput = (Join-Path $report.project_root ([string]$gate.output_directory))
            if (-not $resolvedOutput.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $errors += "$($gate.name): output_directory escapes the execution output directory"
            }
        }
        if ($null -eq $gate.output_files -or $gate.output_files -isnot [System.Collections.IEnumerable]) {
            $errors += "$($gate.name): output_files must be a list"
        }
        if ($null -ne $gate.output_files -and [int]$gate.output_file_count -ne @($gate.output_files).Count) {
            $errors += "$($gate.name): output_file_count does not match output_files"
        }
    }
}
if ($errors.Count) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }
Write-Output "Gate report is valid: $ReportPath"
