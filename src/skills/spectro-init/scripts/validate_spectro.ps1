[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspacePath,
    [switch]$AsObject
)

$ErrorActionPreference = 'Stop'

function New-ValidationResult {
    param([string]$Status, [string[]]$Errors, [string[]]$Warnings)
    [pscustomobject]@{
        structure = if ($Errors | Where-Object { $_ -like 'structure:*' }) { 'failed' } else { 'passed' }
        config = if ($Errors | Where-Object { $_ -like 'config:*' }) { 'failed' } else { 'passed' }
        templates = if ($Errors | Where-Object { $_ -like 'templates:*' }) { 'failed' } else { 'passed' }
        status = $Status
        errors = @($Errors)
        warnings = @($Warnings)
    }
}

try {
    $workspace = [IO.Path]::GetFullPath($WorkspacePath)
    if (-not (Test-Path -LiteralPath $workspace -PathType Container)) {
        throw "Workspace is not an accessible directory: $WorkspacePath"
    }

    $root = Join-Path $workspace '.spectro'
    $errors = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        $errors.Add('structure: missing .spectro directory')
    }

    foreach ($directory in @('templates', 'features')) {
        $path = Join-Path $root $directory
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            $errors.Add("structure: missing directory .spectro/$directory")
        }
    }

    foreach ($file in @('constitution.md', 'config.yaml')) {
        $path = Join-Path $root $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $errors.Add("structure: missing file .spectro/$file")
        }
    }

    $templateNames = @('specification.md', 'clarifications.md', 'plan.md', 'tasks.md', 'review.md')
    foreach ($name in $templateNames) {
        $path = Join-Path $root (Join-Path 'templates' $name)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $errors.Add("templates: missing file .spectro/templates/$name")
        } elseif ([string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $path -Raw -Encoding utf8))) {
            $errors.Add("templates: empty file .spectro/templates/$name")
        }
    }

    $configPath = Join-Path $root 'config.yaml'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding utf8
        foreach ($required in @(
            'version:',
            'paths:',
            'root:',
            'features:',
            'templates:',
            'workflow:',
            'states:',
            'retry_limit:',
            'recovery:',
            'gates:'
        )) {
            if ($config -notmatch "(?m)^\s*$([regex]::Escape($required))") {
                $errors.Add("config: missing required key $required")
            }
        }

        if ($config -notmatch 'version:\s*["'']1\.0["'']') {
            $errors.Add('config: unsupported or missing contract version')
        }

        foreach ($configuredPath in @('.spectro', '.spectro/features', '.spectro/templates')) {
            if ($configuredPath.StartsWith('/') -or $configuredPath -match '^[A-Za-z]:') {
                $errors.Add("config: absolute path is not allowed: $configuredPath")
            }
        }
    }

    $status = if ($errors.Count -gt 0) { 'failed' } elseif ($warnings.Count -gt 0) { 'passed_with_warnings' } else { 'passed' }
    $result = New-ValidationResult -Status $status -Errors $errors -Warnings $warnings
    if ($AsObject) { $result | ConvertTo-Json -Depth 8 } else { $result }
    if ($errors.Count -gt 0) { exit 1 }
    exit 0
}
catch {
    $result = New-ValidationResult -Status 'failed' -Errors @("structure: $($_.Exception.Message)") -Warnings @()
    if ($AsObject) { $result | ConvertTo-Json -Depth 8 } else { $result }
    exit 1
}
