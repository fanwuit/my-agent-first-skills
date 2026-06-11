# planning-with-files: resolve active plan directory (PowerShell mirror).
#
# Resolution order matches scripts/resolve-plan-dir.sh:
#   1. $env:PLAN_ID -> .\.planning\$PLAN_ID\
#   2. .\.planning\.active_plan content
#   3. Newest .\.planning\<dir>\ by LastWriteTime
#   4. Empty (legacy fallback to .\task_plan.md handled by caller)

param(
    [string]$PlanRoot = (Join-Path (Get-Location) ".planning")
)

$activeFile = Join-Path $PlanRoot ".active_plan"
$slugPattern = '^[A-Za-z0-9_][A-Za-z0-9._-]*$'

function Test-SafePlanId {
    param([string]$PlanId)
    if (-not $PlanId) { return $false }
    return $PlanId -match $slugPattern
}

if (Test-SafePlanId $env:PLAN_ID) {
    $candidate = Join-Path $PlanRoot $env:PLAN_ID
    if (Test-Path $candidate -PathType Container) {
        Write-Output $candidate
        exit 0
    }
}

if (Test-Path $activeFile) {
    $planId = ((Get-Content $activeFile -Raw) -replace '\s', '')
    if (Test-SafePlanId $planId) {
        $candidate = Join-Path $PlanRoot $planId
        if (Test-Path $candidate -PathType Container) {
            Write-Output $candidate
            exit 0
        }
    }
}

if (Test-Path $PlanRoot -PathType Container) {
    $latest = Get-ChildItem -Path $PlanRoot -Directory |
        Where-Object { -not $_.Name.StartsWith('.') -and (Test-SafePlanId $_.Name) -and (Test-Path (Join-Path $_.FullName 'task_plan.md') -PathType Leaf) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latest) {
        Write-Output $latest.FullName
    }
}

exit 0
