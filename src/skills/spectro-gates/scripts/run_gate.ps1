param(
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [int]$TimeoutSeconds = 900,
    [string]$EvidencePath = ""
)

$started = Get-Date
$output = ""
$status = "passed"
$exitCode = 0

try {
    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
        throw "WorkingDirectory must be an existing directory: $WorkingDirectory"
    }
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    }
    $resolvedWorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
    $resolvedOutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
    $job = Start-Job -ScriptBlock {
        param($Text, $WorkingDirectory, $OutputDirectory)
        try {
            Set-Location -LiteralPath $WorkingDirectory
            $env:SPECTRO_GATE_OUTPUT_DIR = $OutputDirectory
            $captured = & ([scriptblock]::Create($Text)) 2>&1 | Out-String
            [pscustomobject]@{
                output = $captured
                exit_code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
            }
        } catch {
            [pscustomobject]@{
                output = $_.Exception.Message
                exit_code = 1
            }
        }
    } -ArgumentList $Command, $resolvedWorkingDirectory, $resolvedOutputDirectory

    if (-not (Wait-Job -Job $job -Timeout $TimeoutSeconds)) {
        Stop-Job -Job $job
        $status = "blocked"
        $exitCode = 124
        $output = "Command timed out after $TimeoutSeconds seconds."
    } else {
        $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
        $output = [string]$result.output
        $exitCode = [int]$result.exit_code
        if ($exitCode -ne 0) { $status = "failed" }
        if ($job.State -eq "Failed") {
            $status = "error"
            $exitCode = 1
        }
    }
} catch {
    $status = "error"
    $exitCode = 1
    $output = $_.Exception.Message
} finally {
    if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
}

if ($EvidencePath) {
    $parent = Split-Path -Parent $EvidencePath
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Set-Content -Path $EvidencePath -Value $output -Encoding utf8
}

$durationMs = [int]((New-TimeSpan -Start $started -End (Get-Date)).TotalMilliseconds)
[pscustomobject]@{
    status = $status
    exit_code = $exitCode
    duration_ms = $durationMs
    output = $output
} | ConvertTo-Json -Depth 4

if ($exitCode -ne 0) { exit $exitCode }
