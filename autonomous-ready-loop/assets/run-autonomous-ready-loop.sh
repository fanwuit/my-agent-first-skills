#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-$(pwd)}"
MAX_ROUNDS="${MAX_ROUNDS:-1}"
RUN_UNTIL_BOUNDARY="${RUN_UNTIL_BOUNDARY:-false}"
WORKER_TIMEOUT_SECONDS="${WORKER_TIMEOUT_SECONDS:-1800}"
QUEUE_FILE="${QUEUE_FILE:-NEXT.md}"
CHECKPOINT_FILE="${CHECKPOINT_FILE:-.harness/run-checkpoint.md}"
MODEL="${MODEL:-}"
VERIFICATION_COMMAND="${VERIFICATION_COMMAND:-}"
COMMIT_ALLOWED="${COMMIT_ALLOWED:-false}"
HARNESS_STATUS_SCRIPT="${HARNESS_STATUS_SCRIPT:-}"
SKIP_STATUS_REFRESH="${SKIP_STATUS_REFRESH:-false}"

if [ "$RUN_UNTIL_BOUNDARY" = "true" ] && [ "$MAX_ROUNDS" = "1" ]; then MAX_ROUNDS=50; fi

REPO_PATH="$(cd "$REPO" && pwd)"
HARNESS_DIR="$REPO_PATH/.harness"
mkdir -p "$HARNESS_DIR"
LAST_MESSAGE="$HARNESS_DIR/last-codex-message.md"
PROMPT_FILE="$HARNESS_DIR/autonomous-worker-prompt.txt"
CHECKPOINT_PATH="$REPO_PATH/$CHECKPOINT_FILE"

resolve_harness_status_script() {
  local script_dir candidate candidate_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for candidate in \
    "$HARNESS_STATUS_SCRIPT" \
    "$script_dir/../../harness-visualization/scripts/harness-status.mjs" \
    "${CODEX_HOME:-}/skills/harness-visualization/scripts/harness-status.mjs" \
    "$HOME/.codex/skills/harness-visualization/scripts/harness-status.mjs"; do
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then
      candidate_dir="$(cd "$(dirname "$candidate")" && pwd)"
      printf '%s/%s\n' "$candidate_dir" "$(basename "$candidate")"
      return 0
    fi
  done
  return 1
}

STATUS_SCRIPT="$(resolve_harness_status_script || true)"

refresh_harness_status() {
  local reason="$1"
  if [ "$SKIP_STATUS_REFRESH" = "true" ]; then return 0; fi
  if [ -z "$STATUS_SCRIPT" ]; then
    echo "Harness status refresh skipped after $reason; harness-status.mjs was not found. Set HARNESS_STATUS_SCRIPT." >&2
    return 0
  fi
  if ! node "$STATUS_SCRIPT" --repo "$REPO_PATH" --queue "$QUEUE_FILE" --checkpoint "$CHECKPOINT_FILE" --write-md --write-json >/dev/null; then
    echo "Harness status refresh failed after $reason." >&2
  fi
}

write_checkpoint() {
  local round="$1" result="$2" stop_reason="$3"
  mkdir -p "$(dirname "$CHECKPOINT_PATH")"
  cat > "$CHECKPOINT_PATH" <<CHECKPOINT
# Run Checkpoint

## Last Worker
- Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- Queue item: first ready from $QUEUE_FILE
- Result: $result

## Durable State Updated
- Runner wrote this checkpoint after a worker stop/failure path.

## Verification
- Not completed by runner after worker stop/failure.

## Next Resume Source
- Queue: $QUEUE_FILE
- First ready item: read from queue before next worker starts

## Stop Reason
- Round $round: $stop_reason
CHECKPOINT
  refresh_harness_status "checkpoint write for round $round"
}

round=1
while [ "$round" -le "$MAX_ROUNDS" ]; do
  if [ "$RUN_UNTIL_BOUNDARY" = "true" ]; then MODE="RunUntilBoundary"; else MODE="BoundedBatch"; fi
  cat > "$PROMPT_FILE" <<PROMPT
You are an autonomous-ready-loop short-session Codex worker.

Restore state only from repository files. Do not rely on previous chat.
Repository: $REPO_PATH
Queue source: $QUEUE_FILE
Checkpoint file: $CHECKPOINT_FILE
Runner mode: $MODE
Round: $round of $MAX_ROUNDS

Read project instructions first. Execute only the first ready item from the queue source unless project rules explicitly define a smaller active item.
Keep changes inside that ready item boundary.

Before exiting:
- Update durable project state and the checkpoint file.
- Run matching verification${VERIFICATION_COMMAND:+: $VERIFICATION_COMMAND}.
- Commit only if project rules require it and CommitAllowed is true. CommitAllowed: $COMMIT_ALLOWED.
- If context usage appears near 70%, stop expanding scope, preserve or split remaining work in the queue, write checkpoint, and finish with AUTONOMOUS_CONTEXT_HANDOFF.
- If the queue is empty, phase boundary is reached, human material is required, or the next item would expand beyond the current project boundary, finish with AUTONOMOUS_BOUNDARY_REACHED or AUTONOMOUS_BLOCKED as appropriate.

Finish your final response with exactly one marker:
AUTONOMOUS_READY_DONE, AUTONOMOUS_CONTEXT_HANDOFF, AUTONOMOUS_BLOCKED, AUTONOMOUS_BOUNDARY_REACHED, or AUTONOMOUS_FAILED.
PROMPT
  args=(exec --cd "$REPO_PATH" --sandbox workspace-write --output-last-message "$LAST_MESSAGE")
  if [ -n "$MODEL" ]; then args+=(--model "$MODEL"); fi
  args+=(-)
  if ! timeout "$WORKER_TIMEOUT_SECONDS" codex "${args[@]}" < "$PROMPT_FILE"; then
    write_checkpoint "$round" "failed" "codex exec failed or exceeded WORKER_TIMEOUT_SECONDS=$WORKER_TIMEOUT_SECONDS"
    exit 1
  fi
  message="$(cat "$LAST_MESSAGE")"
  if grep -Eq 'AUTONOMOUS_BLOCKED|AUTONOMOUS_BOUNDARY_REACHED|AUTONOMOUS_FAILED' <<< "$message"; then write_checkpoint "$round" "blocked" "worker emitted stop marker"; echo "Stopping after round $round due to marker."; exit 0; fi
  if ! grep -Eq 'AUTONOMOUS_READY_DONE|AUTONOMOUS_CONTEXT_HANDOFF' <<< "$message"; then write_checkpoint "$round" "failed" "worker did not emit a recognized continue marker"; echo "Worker did not emit a recognized continue marker." >&2; exit 1; fi
  if [ -n "$VERIFICATION_COMMAND" ]; then
    if ! (cd "$REPO_PATH" && eval "$VERIFICATION_COMMAND"); then write_checkpoint "$round" "failed" "verification failed after round $round"; exit 1; fi
  fi
  refresh_harness_status "round $round completed"
  round=$((round + 1))
done

echo "Reached MAX_ROUNDS=$MAX_ROUNDS."
