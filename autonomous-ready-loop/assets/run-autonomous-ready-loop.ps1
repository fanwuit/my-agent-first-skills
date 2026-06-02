param(
  [string]$Repo = (Get-Location).Path,
  [int]$MaxRounds = 1,
  [switch]$RunUntilBoundary,
  [int]$WorkerTimeoutSeconds = 1800,
  [string]$QueueFile = 'NEXT.md',
  [string]$CheckpointFile = '.harness/run-checkpoint.md',
  [string]$Model = '',
  [string]$VerificationCommand = '',
  [switch]$CommitAllowed
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
      Invoke-Expression $VerificationCommand
      if ($LASTEXITCODE -ne 0) {
        Write-RunCheckpoint -Path $checkpointPath -QueueFile $QueueFile -Round $round -Result 'failed' -StopReason "verification failed after round $round"
        throw "Verification failed after round $round."
      }
    } finally { Pop-Location }
  }
}

Write-Host "Reached MaxRounds=$MaxRounds."

function Write-RunCheckpoint {
  param([string]$Path,[string]$QueueFile,[int]$Round,[string]$Result,[string]$StopReason)
  $directory = Split-Path -Parent $Path
  if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
  $timestamp = Get-Date -Format o
  $content = @('# Run Checkpoint','','## Last Worker',"- Started: $timestamp","- Queue item: first ready from $QueueFile","- Result: $Result",'','## Durable State Updated','- Runner wrote this checkpoint after a worker stop/failure path.','','## Verification','- Not completed by runner after worker stop/failure.','','## Next Resume Source',"- Queue: $QueueFile",'- First ready item: read from queue before next worker starts','','## Stop Reason',"- Round ${Round}: $StopReason") -join [Environment]::NewLine
  Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}
