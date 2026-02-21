#!/usr/bin/env bash
set -euo pipefail

WIN_INSTANCE="${WIN_INSTANCE:-win11-p2v}"
LINUX_INSTANCE="${LINUX_INSTANCE:-nixos-dev}"
PROJECT="${PROJECT:-default}"
PCI0="${PCI0:-0000:03:00.0}"
PCI1="${PCI1:-0000:04:00.0}"
DEV0="${DEV0:-px_w3pe}"
DEV1="${DEV1:-px_q3pe}"
START_TIMEOUT="${START_TIMEOUT:-180}"
STOP_TIMEOUT="${STOP_TIMEOUT:-120}"
AUTO_START_TARGET="${AUTO_START_TARGET:-false}"
ATTACH_BOTH="${ATTACH_BOTH:-false}"
POST_START_WATCH="${POST_START_WATCH:-30}"
ROLLBACK_ON_PANIC="${ROLLBACK_ON_PANIC:-true}"
FORCE_START="${FORCE_START:-false}"
ALLOW_RISKY_0300="${ALLOW_RISKY_0300:-false}"
PANIC_STOP_ONLY="${PANIC_STOP_ONLY:-false}"
COLLECT_QMP_LOG="${COLLECT_QMP_LOG:-}"

usage() {
  cat <<'EOF'
Usage:
  switch-px-devices.sh --to win
  switch-px-devices.sh --to linux

Options:
  --to <win|linux>       Destination instance side.
  --project <name>       Incus project name (default: default).
  --win <name>           Windows instance name (default: win11-p2v).
  --linux <name>         Linux instance name (default: nixos-dev).
  --pci0 <addr>          PCI address for device key DEV0.
  --pci1 <addr>          PCI address for device key DEV1.
  --dev0 <name>          Incus device key name for PCI0 (default: px_w3pe).
  --dev1 <name>          Incus device key name for PCI1 (default: px_q3pe).
  --start-timeout <sec>  Timeout for starting target instance (default: 180).
  --stop-timeout <sec>   Timeout for stopping instances (default: 120).
  --start                Start target instance after switch (default: off).
  --force-start          Required together with --start.
  --both                 Attach both cards (default: off; attach only DEV0/PCI0).
  --watch <sec>          Post-start watch window for panic detection (default: 30).
  --no-rollback          Do not rollback PCI assignment when panic is detected.
  --panic-stop-only      On panic, stop target only (keep PCI devices attached).
  --collect-qmp-log <f>  Save qemu.qmp.log to file when failure is detected.
  --allow-0300           Allow 0000:03:00.0 passthrough (blocked by default).
  --help                 Show this help.

Environment overrides:
  WIN_INSTANCE, LINUX_INSTANCE, PROJECT
  PCI0, PCI1             Defaults: 0000:03:00.0, 0000:04:00.0
  DEV0, DEV1             Incus device keys (labels only; not hardware identity)
  START_TIMEOUT, STOP_TIMEOUT
  AUTO_START_TARGET, ATTACH_BOTH
  POST_START_WATCH, ROLLBACK_ON_PANIC
  FORCE_START, ALLOW_RISKY_0300
  PANIC_STOP_ONLY
  COLLECT_QMP_LOG
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

run_with_timeout() {
  local timeout_sec="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "${timeout_sec}" "$@"
  else
    "$@"
  fi
}

collect_qmp_log() {
  local inst="$1"
  local reason="${2:-failure}"
  [[ -n "$COLLECT_QMP_LOG" ]] || return 0

  local out="$COLLECT_QMP_LOG"
  local ts
  ts="$(date '+%Y%m%d-%H%M%S')"

  if [[ -d "$out" ]]; then
    out="${out%/}/${inst}-${reason}-${ts}.qmp.log"
  fi

  mkdir -p "$(dirname "$out")" >/dev/null 2>&1 || true
  if incus query "/1.0/instances/${inst}/logs/qemu.qmp.log" >"${out}" 2>/dev/null; then
    log "Collected qemu.qmp.log: ${out}"
  else
    echo "Failed to collect qemu.qmp.log for ${inst}" >&2
  fi
}

state_of() {
  local inst="$1"
  local st
  st="$(incus info "$inst" --project "$PROJECT" 2>/dev/null | sed -n 's/^Status:[[:space:]]*//p' | head -n1 || true)"
  if [[ -z "$st" ]]; then
    echo "UNKNOWN"
  else
    echo "$st"
  fi
}

is_panicked_state() {
  local st="$1"
  case "$st" in
    *PANIC*|*panic*|*guest-panicked*|*GUEST-PANICKED*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_running_state() {
  local st="$1"
  [[ "$st" == "RUNNING" || "$st" == "Running" ]]
}

is_stopped_state() {
  local st="$1"
  [[ "$st" == "STOPPED" || "$st" == "Stopped" ]]
}

is_error_state() {
  local st="$1"
  [[ "$st" == "ERROR" || "$st" == "Error" || "$st" == "error" ]]
}

stop_if_running() {
  local inst="$1"
  local st
  st="$(state_of "$inst")"
  log "State(${inst})=${st}"
  if is_running_state "$st"; then
    log "Stopping ${inst}..."
    if ! run_with_timeout "$STOP_TIMEOUT" incus stop "$inst" --project "$PROJECT" --force; then
      echo "Timed out or failed while stopping ${inst}." >&2
      exit 1
    fi
  fi
}

start_if_stopped() {
  local inst="$1"
  local st
  st="$(state_of "$inst")"
  log "State(${inst})=${st}"
  if is_error_state "$st"; then
    log "Instance ${inst} is in ERROR state, trying force stop first..."
    run_with_timeout "$STOP_TIMEOUT" incus stop "$inst" --project "$PROJECT" --force >/dev/null 2>&1 || true
    st="$(state_of "$inst")"
    log "State(${inst}) after force stop=${st}"
  fi

  if is_stopped_state "$st"; then
    log "Starting ${inst}..."
    if ! run_with_timeout "$START_TIMEOUT" incus start "$inst" --project "$PROJECT"; then
      collect_qmp_log "$inst" "start-failed"
      echo "Timed out or failed while starting ${inst}." >&2
      echo "Hint: run 'incus info ${inst} --project ${PROJECT}' and 'incus operation list --project ${PROJECT}'." >&2
      exit 1
    fi
  elif is_running_state "$st"; then
    log "${inst} is already running."
  else
    echo "Cannot start ${inst} from state=${st}" >&2
    exit 1
  fi
}

ensure_instance_exists() {
  local inst="$1"
  incus info "$inst" --project "$PROJECT" >/dev/null
}

detach_cards() {
  local inst="$1"
  log "Detaching PCI devices from ${inst}..."
  incus config device remove "$inst" "$DEV0" --project "$PROJECT" >/dev/null 2>&1 || true
  incus config device remove "$inst" "$DEV1" --project "$PROJECT" >/dev/null 2>&1 || true
}

attach_cards() {
  local inst="$1"
  local both="${2:-false}"
  log "Attaching PCI devices to ${inst}..."
  incus config device add "$inst" "$DEV0" pci address="$PCI0" --project "$PROJECT"
  if [[ "$both" == "true" ]]; then
    incus config device add "$inst" "$DEV1" pci address="$PCI1" --project "$PROJECT"
  fi
}

rollback_assignment() {
  log "Rollback: stopping ${TARGET} and detaching PCI devices."
  incus stop "$TARGET" --project "$PROJECT" --force >/dev/null 2>&1 || true
  detach_cards "$TARGET"
  log "Rollback: restoring PCI devices to ${OTHER} (not starting)."
  attach_cards "$OTHER" "$ATTACH_BOTH"
}

stop_only_on_panic() {
  log "Panic handling: stopping ${TARGET} only (keeping PCI devices attached)."
  incus stop "$TARGET" --project "$PROJECT" --force >/dev/null 2>&1 || true
}

watch_for_panic() {
  local inst="$1"
  local seconds="$2"
  local i=0
  local seen_running="false"
  while (( i < seconds )); do
    local st
    st="$(state_of "$inst")"
    log "Post-start state(${inst})=${st}"
    if is_running_state "$st"; then
      seen_running="true"
    fi
    if is_error_state "$st"; then
      collect_qmp_log "$inst" "state-error"
      echo "Detected ERROR state on ${inst}" >&2
      return 1
    fi
    if is_panicked_state "$st"; then
      collect_qmp_log "$inst" "guest-panicked"
      echo "Detected guest panic state on ${inst}: ${st}" >&2
      return 1
    fi
    sleep 1
    i=$((i + 1))
  done
  if [[ "$seen_running" != "true" ]]; then
    echo "Instance ${inst} never reached RUNNING state within watch window." >&2
    return 1
  fi
  return 0
}

selected_pci_addresses() {
  if [[ "$ATTACH_BOTH" == "true" ]]; then
    printf '%s\n%s\n' "$PCI0" "$PCI1"
  else
    printf '%s\n' "$PCI0"
  fi
}

TO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)
      TO="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT="${2:-}"
      shift 2
      ;;
    --win)
      WIN_INSTANCE="${2:-}"
      shift 2
      ;;
    --linux)
      LINUX_INSTANCE="${2:-}"
      shift 2
      ;;
    --pci0)
      PCI0="${2:-}"
      shift 2
      ;;
    --pci1)
      PCI1="${2:-}"
      shift 2
      ;;
    --dev0)
      DEV0="${2:-}"
      shift 2
      ;;
    --dev1)
      DEV1="${2:-}"
      shift 2
      ;;
    --start-timeout)
      START_TIMEOUT="${2:-}"
      shift 2
      ;;
    --stop-timeout)
      STOP_TIMEOUT="${2:-}"
      shift 2
      ;;
    --start)
      AUTO_START_TARGET="true"
      shift
      ;;
    --force-start)
      FORCE_START="true"
      shift
      ;;
    --both)
      ATTACH_BOTH="true"
      shift
      ;;
    --watch)
      POST_START_WATCH="${2:-}"
      shift 2
      ;;
    --no-rollback)
      ROLLBACK_ON_PANIC="false"
      shift
      ;;
    --panic-stop-only)
      PANIC_STOP_ONLY="true"
      shift
      ;;
    --collect-qmp-log)
      COLLECT_QMP_LOG="${2:-}"
      shift 2
      ;;
    --allow-0300)
      ALLOW_RISKY_0300="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$TO" != "win" && "$TO" != "linux" ]]; then
  echo "--to must be either 'win' or 'linux'" >&2
  usage
  exit 1
fi

if [[ "$AUTO_START_TARGET" == "true" && "$FORCE_START" != "true" ]]; then
  echo "--start requires explicit --force-start to avoid accidental host/guest hangs." >&2
  exit 1
fi

require_cmd incus

ensure_instance_exists "$WIN_INSTANCE"
ensure_instance_exists "$LINUX_INSTANCE"

if [[ "$TO" == "win" ]]; then
  TARGET="$WIN_INSTANCE"
  OTHER="$LINUX_INSTANCE"
else
  TARGET="$LINUX_INSTANCE"
  OTHER="$WIN_INSTANCE"
fi

log "Project: ${PROJECT}"
log "Target:  ${TARGET}"
log "Other:   ${OTHER}"
log "PCI0:    ${PCI0} (${DEV0})"
if [[ "$ATTACH_BOTH" == "true" ]]; then
  log "PCI1:    ${PCI1} (${DEV1})"
else
  log "PCI1:    ${PCI1} (${DEV1}) [not used in this run]"
fi
log "Attach both cards: ${ATTACH_BOTH}"
log "Auto start target: ${AUTO_START_TARGET}"
log "Force start: ${FORCE_START}"
log "Panic stop only: ${PANIC_STOP_ONLY}"

if [[ "$ATTACH_BOTH" == "true" && "$PCI0" == "$PCI1" ]]; then
  echo "When --both is enabled, --pci0 and --pci1 must be different addresses." >&2
  exit 1
fi

if selected_pci_addresses | grep -qx '0000:03:00.0'; then
  if [[ "$ALLOW_RISKY_0300" != "true" ]]; then
    echo "Blocked risky PCI address 0000:03:00.0. Re-run with --allow-0300 if you really want this test." >&2
    exit 1
  fi
  log "Warning: allowing risky PCI address 0000:03:00.0 by explicit override."
fi

# PCI device passthrough is not hotplug-capable for Incus VMs.
stop_if_running "$TARGET"
stop_if_running "$OTHER"

detach_cards "$OTHER"
detach_cards "$TARGET"
attach_cards "$TARGET" "$ATTACH_BOTH"

if [[ "$AUTO_START_TARGET" == "true" ]]; then
  start_if_stopped "$TARGET"
  if ! watch_for_panic "$TARGET" "$POST_START_WATCH"; then
    if [[ "$PANIC_STOP_ONLY" == "true" ]]; then
      stop_only_on_panic
    elif [[ "$ROLLBACK_ON_PANIC" == "true" ]]; then
      rollback_assignment
    fi
    echo "Switch failed: guest panicked after start." >&2
    exit 1
  fi
else
  log "Skip start (default). Start manually when ready:"
  log "  incus start ${TARGET} --project ${PROJECT}"
fi

log "Done. Current assignments:"
incus config device list "$TARGET" --project "$PROJECT" || true
