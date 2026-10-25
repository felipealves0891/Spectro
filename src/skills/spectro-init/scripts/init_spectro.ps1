[CmdletBinding()]
param(
    [string]$WorkspacePath = (Get-Location).Path,
    [switch]$Force,
    [switch]$DryRun,
    [ValidateSet('text', 'json')]
    [string]$Format = 'text'
)

$ErrorActionPreference = 'Stop'

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Test-ManagedFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $head = (Get-Content -LiteralPath $Path -TotalCount 3 -Encoding utf8) -join "`n"
    return $head -match 'spectro-managed:\s*true'
}

function Add-Unique {
    param([System.Collections.Generic.List[string]]$List, [string]$Value)
    if (-not $List.Contains($Value)) { $List.Add($Value) }
}

function Emit-Report {
    param([pscustomobject]$Report, [string]$OutputFormat)
    if ($OutputFormat -eq 'json') {
        $Report | ConvertTo-Json -Depth 12
        return
    }
    Write-Output "spectro-init: $($Report.status)"
    Write-Output "workspace: $($Report.workspace)"
    Write-Output "root: $($Report.root)"
    foreach ($field in @('created', 'replaced', 'preserved', 'conflicts')) {
        $values = @($Report.$field)
        if ($values.Count -gt 0) { Write-Output "${field}:"; $values | ForEach-Object { Write-Output "  - $_" } }
    }
    Write-Output "validation: structure=$($Report.validation.structure), config=$($Report.validation.config), templates=$($Report.validation.templates)"
}

$created = [System.Collections.Generic.List[string]]::new()
$replaced = [System.Collections.Generic.List[string]]::new()
$preserved = [System.Collections.Generic.List[string]]::new()
$conflicts = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

try {
    $workspace = [IO.Path]::GetFullPath($WorkspacePath)
    if (-not (Test-Path -LiteralPath $workspace -PathType Container)) {
        throw "Workspace is not an accessible directory: $WorkspacePath"
    }
    $root = Join-Path $workspace '.spectro'
    $assetRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\assets'))
    $relativeFiles = [ordered]@{
        'constitution.md' = 'constitution.md'
        'config.yaml' = 'config.yaml'
        'templates/specification.md' = 'templates/specification.md'
        'templates/clarifications.md' = 'templates/clarifications.md'
        'templates/plan.md' = 'templates/plan.md'
        'templates/tasks.md' = 'templates/tasks.md'
        'templates/review.md' = 'templates/review.md'
    }

    if (-not (Test-Path -LiteralPath $root)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
        Add-Unique $created '.spectro'
    } elseif (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Add-Unique $conflicts '.spectro is not a directory'
    } else { Add-Unique $preserved '.spectro' }

    foreach ($directory in @('templates', 'features')) {
        $relative = ".spectro/$directory"
        $destination = Join-Path $root $directory
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            Add-Unique $conflicts "$relative is a file"
        } elseif (-not (Test-Path -LiteralPath $destination)) {
            if (-not $DryRun) { New-Item -ItemType Directory -Path $destination -Force | Out-Null }
            Add-Unique $created $relative
        } else { Add-Unique $preserved $relative }
    }

    foreach ($entry in $relativeFiles.GetEnumerator()) {
        $relativeDestination = ".spectro/$($entry.Key)"
        $destination = Join-Path $root ($entry.Key -replace '/', [IO.Path]::DirectorySeparatorChar)
        $source = Join-Path $assetRoot ($entry.Value -replace '/', [IO.Path]::DirectorySeparatorChar)

        if (Test-Path -LiteralPath $destination -PathType Container) {
            Add-Unique $conflicts "$relativeDestination is a directory"
            continue
        }
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            Add-Unique $conflicts "missing packaged asset: $($entry.Value)"
            continue
        }

        $assetContent = Get-Content -LiteralPath $source -Raw -Encoding utf8
        if (-not (Test-Path -LiteralPath $destination)) {
            if (-not $DryRun) { Write-Utf8NoBom $destination $assetContent }
            Add-Unique $created $relativeDestination
            continue
        }

        $existingContent = Get-Content -LiteralPath $destination -Raw -Encoding utf8
        if ($existingContent -ceq $assetContent) {
            Add-Unique $preserved $relativeDestination
        } elseif ($Force -and (Test-ManagedFile $destination)) {
            if (-not $DryRun) { Write-Utf8NoBom $destination $assetContent }
            Add-Unique $replaced $relativeDestination
        } else {
            Add-Unique $conflicts "$relativeDestination contains custom or incompatible content"
        }
    }

    $validationPath = Join-Path $PSScriptRoot 'validate_spectro.ps1'
    $validation = [pscustomobject]@{
        structure = 'failed'
        config = 'failed'
        templates = 'failed'
        status = 'failed'
        errors = @('validation skipped in dry-run')
        warnings = @()
    }
    if (-not $DryRun -and $conflicts.Count -eq 0) {
        $json = & $validationPath -WorkspacePath $workspace -AsObject 2>$null
        if ($LASTEXITCODE -eq 0 -and $json) { $validation = $json | ConvertFrom-Json }
    } elseif ($DryRun) {
        $validation = [pscustomobject]@{ structure = 'not_run'; config = 'not_run'; templates = 'not_run'; status = 'not_run'; errors = @(); warnings = @('dry-run') }
    }

    $status = if ($conflicts.Count -gt 0) { 'blocked' } elseif ($DryRun) { 'completed_with_warnings' } elseif ($validation.status -eq 'failed') { 'failed' } elseif ($warnings.Count -gt 0) { 'completed_with_warnings' } else { 'completed' }
    $report = [pscustomobject]@{
        skill = 'spectro-init'
        status = $status
        workspace = $workspace
        root = $root
        created = @($created)
        replaced = @($replaced)
        preserved = @($preserved)
        conflicts = @($conflicts)
        validation = $validation
    }
    Emit-Report $report $Format
    if ($status -in @('blocked', 'failed')) { exit 1 }
    exit 0
}
catch {
    $report = [pscustomobject]@{
        skill = 'spectro-init'
        status = 'failed'
        workspace = $WorkspacePath
        root = (Join-Path $WorkspacePath '.spectro')
        created = @($created)
        replaced = @($replaced)
        preserved = @($preserved)
        conflicts = @("operational error: $($_.Exception.Message)")
        validation = [pscustomobject]@{ structure = 'failed'; config = 'failed'; templates = 'failed' }
    }
    Emit-Report $report $Format
    exit 1
}
