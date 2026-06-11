# Initialize planning files for a new session.
# Usage:
#   .\init-session.ps1
#   .\init-session.ps1 -Template analytics
#   .\init-session.ps1 "Backend Refactor"
#   .\init-session.ps1 -PlanDir
#   .\init-session.ps1 -PlanDir "Quick Spike"

param(
    [Parameter(Position = 0)]
    [string]$ProjectName = "",
    [string]$Template = "default",
    [switch]$PlanDir
)

$DateValue = Get-Date -Format "yyyy-MM-dd"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillRoot = Split-Path -Parent $ScriptDir
$TemplateDir = Join-Path $SkillRoot "templates"

if ($Template -ne "default" -and $Template -ne "analytics") {
    Write-Host "Unknown template: $Template (available: default, analytics). Using default."
    $Template = "default"
}

function ConvertTo-Slug {
    param([string]$Value)
    $slug = $Value.ToLowerInvariant() -replace '[^a-z0-9]', '-'
    $slug = $slug -replace '-{2,}', '-'
    $slug = $slug.Trim('-')
    if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40).Trim('-') }
    return $slug
}

function New-ShortId {
    return [Guid]::NewGuid().ToString("N").Substring(0, 8)
}

function Write-DefaultTaskPlan {
    param([string]$Path)
    @"
# Task Plan: [Brief Description]

## Goal
[One sentence describing the end state]

## Current Phase
Phase 1

## Phases

### Phase 1: Requirements & Discovery
- [ ] Understand user intent
- [ ] Identify constraints
- [ ] Document in findings.md
- **Status:** in_progress

### Phase 2: Planning & Structure
- [ ] Define approach
- [ ] Create project structure
- **Status:** pending

### Phase 3: Implementation
- [ ] Execute the plan
- [ ] Write to files before executing
- **Status:** pending

### Phase 4: Testing & Verification
- [ ] Verify requirements met
- [ ] Document test results
- **Status:** pending

### Phase 5: Delivery
- [ ] Review outputs
- [ ] Deliver to user
- **Status:** pending

## Decisions Made
| Decision | Rationale |
|----------|-----------|

## Errors Encountered
| Error | Resolution |
|-------|------------|
"@ | Out-File -FilePath $Path -Encoding UTF8
}

function Write-DefaultFindings {
    param([string]$Path)
    @"
# Findings & Decisions

## Requirements
-

## Research Findings
-

## Technical Decisions
| Decision | Rationale |
|----------|-----------|

## Issues Encountered
| Issue | Resolution |
|-------|------------|

## Resources
-
"@ | Out-File -FilePath $Path -Encoding UTF8
}

function Write-DefaultProgress {
    param([string]$Path, [string]$DateValue, [string]$Template)
    if ($Template -eq "analytics") {
        @"
# Progress Log

## Session: $DateValue

### Current Status
- **Phase:** 1 - Data Discovery
- **Started:** $DateValue

### Actions Taken
-

### Query Log
| Query | Result Summary | Interpretation |
|-------|---------------|----------------|

### Errors
| Error | Resolution |
|-------|------------|
"@ | Out-File -FilePath $Path -Encoding UTF8
        return
    }

    @"
# Progress Log

## Session: $DateValue

### Current Status
- **Phase:** 1 - Requirements & Discovery
- **Started:** $DateValue

### Actions Taken
-

### Test Results
| Test | Expected | Actual | Status |
|------|----------|--------|--------|

### Errors
| Error | Resolution |
|-------|------------|
"@ | Out-File -FilePath $Path -Encoding UTF8
}

function New-PlanningFiles {
    param([string]$TargetDir)
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

    $planPath = Join-Path $TargetDir "task_plan.md"
    $findingsPath = Join-Path $TargetDir "findings.md"
    $progressPath = Join-Path $TargetDir "progress.md"

    if (-not (Test-Path $planPath)) {
        $analyticsPlan = Join-Path $TemplateDir "analytics_task_plan.md"
        if ($Template -eq "analytics" -and (Test-Path $analyticsPlan)) {
            Copy-Item $analyticsPlan $planPath
        } else {
            Write-DefaultTaskPlan -Path $planPath
        }
        Write-Host "Created $planPath"
    } else {
        Write-Host "$planPath already exists, skipping"
    }

    if (-not (Test-Path $findingsPath)) {
        $analyticsFindings = Join-Path $TemplateDir "analytics_findings.md"
        if ($Template -eq "analytics" -and (Test-Path $analyticsFindings)) {
            Copy-Item $analyticsFindings $findingsPath
        } else {
            Write-DefaultFindings -Path $findingsPath
        }
        Write-Host "Created $findingsPath"
    } else {
        Write-Host "$findingsPath already exists, skipping"
    }

    if (-not (Test-Path $progressPath)) {
        Write-DefaultProgress -Path $progressPath -DateValue $DateValue -Template $Template
        Write-Host "Created $progressPath"
    } else {
        Write-Host "$progressPath already exists, skipping"
    }
}

$projectNameWasBound = $PSBoundParameters.ContainsKey("ProjectName")
$slugMode = $PlanDir -or $projectNameWasBound

if ($slugMode) {
    $displayName = if ($ProjectName) { $ProjectName } else { "untitled" }
    $slug = ConvertTo-Slug $ProjectName
    if (-not $slug) { $slug = "untitled-$(New-ShortId)" }

    $planRoot = Join-Path (Get-Location) ".planning"
    $baseId = "$DateValue-$slug"
    $planId = $baseId
    $counter = 2
    while (Test-Path (Join-Path $planRoot $planId) -PathType Container) {
        $planId = "$baseId-$counter"
        $counter += 1
    }

    $targetPlanDir = Join-Path $planRoot $planId
    Write-Host "Initializing planning files for: $displayName (template: $Template)"
    Write-Host "PLAN_ID=$planId"
    New-PlanningFiles -TargetDir $targetPlanDir
    New-Item -ItemType Directory -Force -Path $planRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $planRoot ".active_plan") -Value $planId -Encoding UTF8
    Write-Host ""
    Write-Host "Active plan recorded: $(Join-Path $planRoot '.active_plan')"
    Write-Host "Pin this terminal to the plan for parallel sessions:"
    Write-Host "  `$env:PLAN_ID='$planId'"
    exit 0
}

Write-Host "Initializing planning files for: project (template: $Template)"
New-PlanningFiles -TargetDir (Get-Location)
Write-Host ""
Write-Host "Planning files initialized!"
Write-Host "Files: task_plan.md, findings.md, progress.md"
