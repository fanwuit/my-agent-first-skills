param(
  [string]$Repo = (Get-Location).Path,
  [int]$MaxRounds = 1,
  [switch]$RunUntilBoundary,
  [int]$WorkerTimeoutSeconds = 1800,
  [string]$QueueFile = 'NEXT.md',
  [string]$CheckpointFile = '.harness/run-checkpoint.md',
  [string]$Model = '',
  [string]$VerificationCommand = '',
  [switch]$CommitAllowed,
  [string]$HarnessStatusScript = $env:HARNESS_STATUS_SCRIPT,
  [switch]$SkipStatusRefresh
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ($RunUntilBoundary -and $MaxRounds -eq 1) { $MaxRounds = 50 }

$repoPath = (Resolve-Path -LiteralPath $Repo).Path
$harnessDir = Join-Path $repoPath '.harness'
New-Item -ItemType Directory -Force -Path $harnessDir | Out-Null
$lastMessage = Join-Path $harnessDir 'last-codex-message.md'
$promptFile = Join-Path $harnessDir 'autonomous-worker-prompt.txt'
$checkpointPath = Join-Path $repoPath $CheckpointFile

function Resolve-HarnessStatusScript {
  param([string]$ExplicitPath)
  $candidates = @()
  if ($ExplicitPath) { $candidates += $ExplicitPath }
  if ($PSScriptRoot) { $candidates += (Join-Path $PSScriptRoot '..\..\harness-visualization\scripts\harness-status.mjs') }
  if ($env:CODEX_HOME) { $candidates += (Join-Path $env:CODEX_HOME 'skills\harness-visualization\scripts\harness-status.mjs') }
  if ($HOME) { $candidates += (Join-Path $HOME '.codex\skills\harness-visualization\scripts\harness-status.mjs') }
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  return $null
}

function Invoke-HarnessStatusRefresh {
  param([string]$Reason)
  if ($SkipStatusRefresh) { return }
  if (-not $statusScriptPath) {
    Write-Warning "Harness status refresh skipped after $Reason; harness-status.mjs was not found. Set -HarnessStatusScript or HARNESS_STATUS_SCRIPT."
    return
  }
  try {
    & node $statusScriptPath --repo $repoPath --queue $QueueFile --checkpoint $CheckpointFile --write-md --write-json | Out-Null
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "Harness status refresh failed after $Reason with exit code $LASTEXITCODE."
    }
  } catch {
    Write-Warning "Harness status refresh failed after ${Reason}: $($_.Exception.Message)"
  }
}

function Write-RunCheckpoint {
  param([string]$Path,[string]$QueueFile,[int]$Round,[string]$Result,[string]$StopReason)
  $directory = Split-Path -Parent $Path
  if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
  $timestamp = Get-Date -Format o
  $content = @('# Run Checkpoint','','## Last Worker',"- Started: $timestamp","- Queue item: first ready from $QueueFile","- Result: $Result",'','## Durable State Updated','- Runner wrote this checkpoint after a worker stop/failure path.','','## Verification','- Not completed by runner after worker stop/failure.','','## Next Resume Source',"- Queue: $QueueFile",'- First ready item: read from queue before next worker starts','','## Stop Reason',"- Round ${Round}: $StopReason") -join [Environment]::NewLine
  Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
  Invoke-HarnessStatusRefresh -Reason "checkpoint write for round $Round"
}

function Invoke-VerificationPreset {
  param([string]$Preset)
  if (-not $Preset) { return }

  switch ($Preset) {
    'routing-guardrails' {
      & python 'harness-engineering/scripts/check-routing-guardrails.py'
      if ($LASTEXITCODE -ne 0) { throw "Verification preset failed: $Preset" }
    }
    'harness-visualization-tests' {
      & node --test 'harness-visualization/tests/harness-status.test.mjs'
      if ($LASTEXITCODE -ne 0) { throw "Verification preset failed: $Preset" }
    }
    'all-local-checks' {
      Invoke-VerificationPreset -Preset 'routing-guardrails'
      Invoke-VerificationPreset -Preset 'harness-visualization-tests'
      & node --test 'autonomous-ready-loop/tests/runner-verification-command.test.mjs'
      if ($LASTEXITCODE -ne 0) { throw "Verification preset failed: autonomous-ready-loop-tests" }
    }
    default {
      throw "Unknown verification preset: $Preset. Allowed presets: routing-guardrails, harness-visualization-tests, all-local-checks."
    }
  }
}

$statusScriptPath = Resolve-HarnessStatusScript -ExplicitPath $HarnessStatusScript

for ($round = 1; $round -le $MaxRounds; $round++) {
  $verificationLine = if ($VerificationCommand) { ": $VerificationCommand" } else { '' }
  $mode = if ($RunUntilBoundary) { 'RunUntilBoundary' } else { 'BoundedBatch' }
  $prompt = @(
    'You are an autonomous-ready-loop short-session Codex worker.',
    '',
    'Restore state only from repository files. Do not rely on previous chat.',
    "Repository: $repoPath",
    "Queue source: $QueueFile",
    "Checkpoint file: $CheckpointFile",
    "Runner mode: $mode",
    "Round: $round of $MaxRounds",
    '',
    'Read project instructions first. Execute only the first ready item from the queue source unless project rules explicitly define a smaller active item.',
    'Keep changes inside that ready item boundary.',
    '',
    'Before exiting:',
    '- Update durable project state and the checkpoint file.',
    "- Run matching verification$verificationLine.",
    "- Commit only if project rules require it and CommitAllowed is true. CommitAllowed: $CommitAllowed.",
    '- If context usage appears near 70%, stop expanding scope, preserve or split remaining work in the queue, write checkpoint, and finish with AUTONOMOUS_CONTEXT_HANDOFF.',
    '- If the queue is empty, phase boundary is reached, human material is required, or the next item would expand beyond the current project boundary, finish with AUTONOMOUS_BOUNDARY_REACHED or AUTONOMOUS_BLOCKED as appropriate.',
    '',
    'Finish your final response with exactly one marker:',
    'AUTONOMOUS_READY_DONE, AUTONOMOUS_CONTEXT_HANDOFF, AUTONOMOUS_BLOCKED, AUTONOMOUS_BOUNDARY_REACHED, or AUTONOMOUS_FAILED.'
  ) -join [Environment]::NewLine
  Set-Content -LiteralPath $promptFile -Value $prompt -Encoding UTF8

  $args = @('exec', '--cd', $repoPath, '--sandbox', 'workspace-write', '--output-last-message', $lastMessage)
  if ($Model) { $args += @('--model', $Model) }
  $args += @('-')

  $worker = Start-Process -FilePath 'codex' -ArgumentList $args -RedirectStandardInput $promptFile -NoNewWindow -PassThru
  if (-not $worker.WaitForExit($WorkerTimeoutSeconds * 1000)) {
    Stop-Process -Id $worker.Id -Force -ErrorAction SilentlyContinue
    Write-RunCheckpoint -Path $checkpointPath -QueueFile $QueueFile -Round $round -Result 'timeout' -StopReason "codex exec exceeded WorkerTimeoutSeconds=$WorkerTimeoutSeconds"
    throw "codex exec timed out in round $round after $WorkerTimeoutSeconds seconds"
  }
  if ($worker.ExitCode -ne 0) {
    Write-RunCheckpoint -Path $checkpointPath -QueueFile $QueueFile -Round $round -Result 'failed' -StopReason "codex exec exited with code $($worker.ExitCode)"
    throw "codex exec failed in round $round with exit code $($worker.ExitCode)"
  }

  $message = Get-Content -LiteralPath $lastMessage -Raw
  if ($message -match 'AUTONOMOUS_BLOCKED|AUTONOMOUS_BOUNDARY_REACHED|AUTONOMOUS_FAILED') {
    Write-RunCheckpoint -Path $checkpointPath -QueueFile $QueueFile -Round $round -Result 'blocked' -StopReason 'worker emitted stop marker'
    Write-Host "Stopping after round $round due to marker."
    exit 0
  }
  if ($message -notmatch 'AUTONOMOUS_READY_DONE|AUTONOMOUS_CONTEXT_HANDOFF') {
    Write-RunCheckpoint -Path $checkpointPath -QueueFile $QueueFile -Round $round -Result 'failed' -StopReason 'worker did not emit a recognized continue marker'
    throw 'Worker did not emit a recognized continue marker.'
  }

  if ($VerificationCommand) {
    Push-Location $repoPath
    try {
      Invoke-VerificationPreset -Preset $VerificationCommand
    } catch {
      Write-RunCheckpoint -Path $checkpointPath -QueueFile $QueueFile -Round $round -Result 'failed' -StopReason "verification failed after round $round"
      throw "Verification failed after round $round. $($_.Exception.Message)"
    } finally { Pop-Location }
  }
  Invoke-HarnessStatusRefresh -Reason "round $round completed"
}

Write-Host "Reached MaxRounds=$MaxRounds."
