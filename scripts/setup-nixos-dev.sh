#!/usr/bin/env bash
set -euo pipefail

INSTANCE="${INSTANCE:-nixos-dev}"
PROJECT="${PROJECT:-default}"
IMAGE="${IMAGE:-images:nixos/unstable}"
CPU="${CPU:-5}"
MEMORY="${MEMORY:-8GiB}"
DISK_SIZE="${DISK_SIZE:-80GiB}"
DISK_BUS="${DISK_BUS:-nvme}"
STORAGE_POOL="${STORAGE_POOL:-}"
NETWORK="${NETWORK:-}"
AUTO_START="${AUTO_START:-false}"
IF_EXISTS="${IF_EXISTS:-update}"

usage() {
  cat <<'EOF'
Usage:
  setup-nixos-dev.sh [options]

Options:
  --name <instance>       Instance name (default: nixos-dev)
  --project <name>        Incus project (default: default)
  --image <remote:image>  Source image (default: images:nixos/unstable)
  --cpu <num>             vCPU count (default: 5)
  --memory <size>         Memory limit (default: 8GiB)
  --disk-size <size>      Root disk size (default: 80GiB)
  --disk-bus <type>       Root disk bus, e.g. nvme/virtio-scsi (default: nvme)
  --storage <pool>        Storage pool name (default: use profile root device)
  --network <name>        NIC network (default: profile default)
  --auto-start            Set boot.autostart=true
  --if-exists <mode>      Existing instance mode: update|recreate|skip (default: update)
  --help                  Show this help

Environment overrides:
  INSTANCE, PROJECT, IMAGE, CPU, MEMORY, DISK_SIZE, DISK_BUS, STORAGE_POOL, NETWORK, AUTO_START, IF_EXISTS
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

is_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

image_exists() {
  local ref="$1"
  # Accept both aliases and fingerprints.
  incus image info "$ref" >/dev/null 2>&1
}

discover_nixos_image() {
  # Try common aliases first. If none are available, query remote aliases.
  local candidates=(
    "images:nixos/unstable"
    "images:nixos/unstable/cloud"
    "images:nixos/24.11"
    "images:nixos/24.11/cloud"
  )
  local c
  for c in "${candidates[@]}"; do
    if image_exists "$c"; then
      echo "$c"
      return 0
    fi
  done

  local aliases
  aliases="$(incus image list images: nixos --format csv -c l 2>/dev/null || true)"
  if [[ -z "$aliases" ]]; then
    return 1
  fi

  # Prefer unstable/current, then cloud variants, then first available alias.
  local picked
  picked="$(echo "$aliases" | grep -E '^nixos/(unstable|current)(/cloud)?$' | sed -n '1p' || true)"
  if [[ -z "$picked" ]]; then
    picked="$(echo "$aliases" | grep -E '^nixos/.*/cloud$' | sed -n '1p' || true)"
  fi
  if [[ -z "$picked" ]]; then
    picked="$(echo "$aliases" | sed -n '1p')"
  fi
  [[ -n "$picked" ]] || return 1
  echo "images:${picked}"
}

instance_exists() {
  incus info "$INSTANCE" --project "$PROJECT" >/dev/null 2>&1
}

stop_if_running() {
  if incus info "$INSTANCE" --project "$PROJECT" 2>/dev/null | grep -q '^Status: RUNNING$'; then
    echo "Stopping existing instance: ${INSTANCE}"
    incus stop "$INSTANCE" --project "$PROJECT" --force
  fi
}

validate_if_exists_mode() {
  case "$IF_EXISTS" in
    update|recreate|skip) ;;
    *)
      echo "--if-exists must be one of: update, recreate, skip" >&2
      exit 1
      ;;
  esac
}

update_existing_instance() {
  local cpu_try="$CPU"
  echo "Updating existing instance: ${INSTANCE} (project=${PROJECT})"

  stop_if_running

  # CPU limit retry (same strategy as launch path).
  while :; do
    if incus config set "$INSTANCE" limits.cpu="${cpu_try}" --project "$PROJECT" 2>/dev/null; then
      CPU="$cpu_try"
      break
    fi
    if (( cpu_try <= 1 )); then
      echo "Failed to apply limits.cpu on existing instance." >&2
      return 1
    fi
    cpu_try=$((cpu_try - 1))
    echo "Host CPU limit reached while updating. Retrying limits.cpu=${cpu_try}..."
  done

  incus config set "$INSTANCE" limits.memory="${MEMORY}" --project "$PROJECT"
  incus config set "$INSTANCE" security.secureboot=false --project "$PROJECT"
  incus config set "$INSTANCE" boot.autostart="${AUTO_START}" --project "$PROJECT"

  # Root device tuning; if not possible on the current profile/device topology, continue with warning.
  if ! incus config device set "$INSTANCE" root size "${DISK_SIZE}" --project "$PROJECT"; then
    echo "Warning: Could not set root size=${DISK_SIZE} on existing instance."
  fi
  if ! incus config device set "$INSTANCE" root io.bus "${DISK_BUS}" --project "$PROJECT"; then
    echo "Warning: Could not set root io.bus=${DISK_BUS} on existing instance."
  fi
  if [[ -n "$STORAGE_POOL" ]]; then
    if ! incus config device set "$INSTANCE" root pool "${STORAGE_POOL}" --project "$PROJECT"; then
      echo "Warning: Could not set root pool=${STORAGE_POOL} on existing instance."
    fi
  fi

  if [[ -n "$NETWORK" ]]; then
    if incus config device show "$INSTANCE" --project "$PROJECT" | grep -q '^  eth0:'; then
      if ! incus config device set "$INSTANCE" eth0 network "${NETWORK}" --project "$PROJECT"; then
        echo "Warning: Could not set eth0 network=${NETWORK}."
      fi
    fi
  fi

  incus start "$INSTANCE" --project "$PROJECT" >/dev/null 2>&1 || true
  echo
  echo "Updated: ${INSTANCE}"
  echo "  effective.cpu=${CPU}"
  echo "Check:"
  echo "  incus info ${INSTANCE} --project ${PROJECT}"
}

recreate_existing_instance() {
  echo "Cleaning up existing instance: ${INSTANCE} (project=${PROJECT})"
  stop_if_running
  incus delete "$INSTANCE" --project "$PROJECT"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      INSTANCE="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT="${2:-}"
      shift 2
      ;;
    --image)
      IMAGE="${2:-}"
      shift 2
      ;;
    --cpu)
      CPU="${2:-}"
      shift 2
      ;;
    --memory)
      MEMORY="${2:-}"
      shift 2
      ;;
    --disk-size)
      DISK_SIZE="${2:-}"
      shift 2
      ;;
    --disk-bus)
      DISK_BUS="${2:-}"
      shift 2
      ;;
    --storage)
      STORAGE_POOL="${2:-}"
      shift 2
      ;;
    --network)
      NETWORK="${2:-}"
      shift 2
      ;;
    --auto-start)
      AUTO_START="true"
      shift
      ;;
    --if-exists)
      IF_EXISTS="${2:-}"
      shift 2
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

require_cmd incus
require_cmd mktemp
validate_if_exists_mode

if ! is_positive_int "$CPU"; then
  echo "--cpu must be a positive integer: ${CPU}" >&2
  exit 1
fi

if instance_exists; then
  case "$IF_EXISTS" in
    skip)
      echo "Instance already exists: ${INSTANCE} (project=${PROJECT})"
      echo "Mode=skip. No changes applied."
      exit 0
      ;;
    update)
      update_existing_instance
      exit 0
      ;;
    recreate)
      recreate_existing_instance
      ;;
  esac
fi

if ! image_exists "$IMAGE"; then
  echo "Image not found: ${IMAGE}"
  AUTO_IMAGE="$(discover_nixos_image || true)"
  if [[ -n "${AUTO_IMAGE:-}" ]]; then
    echo "Using discovered image alias instead: ${AUTO_IMAGE}"
    IMAGE="$AUTO_IMAGE"
  else
    echo "Could not auto-discover a usable NixOS image alias." >&2
    echo "Check available aliases with: incus image list images: nixos" >&2
    echo "Then re-run with --image images:<alias>" >&2
    exit 1
  fi
fi

echo "Creating VM instance:"
echo "  project=${PROJECT}"
echo "  name=${INSTANCE}"
echo "  image=${IMAGE}"
echo "  cpu=${CPU}"
echo "  memory=${MEMORY}"
echo "  root.size=${DISK_SIZE}"
if [[ -n "$STORAGE_POOL" ]]; then
  echo "  root.pool=${STORAGE_POOL}"
else
  echo "  root.pool=(from profile default)"
fi

base_args=(
  "${IMAGE}" "${INSTANCE}"
  --vm
  --project "${PROJECT}"
  -c "limits.memory=${MEMORY}"
  -c "security.secureboot=false"
  -c "boot.autostart=${AUTO_START}"
)

args=()
if [[ -n "$STORAGE_POOL" ]]; then
  args+=(-d "root,pool=${STORAGE_POOL}")
  args+=(-d "root,size=${DISK_SIZE}")
  args+=(-d "root,io.bus=${DISK_BUS}")
else
  args+=(-d "root,size=${DISK_SIZE}")
  args+=(-d "root,io.bus=${DISK_BUS}")
fi

if [[ -n "$NETWORK" ]]; then
  base_args+=(-n "${NETWORK}")
fi

launch_with_cpu_retry() {
  local cpu_try="$1"
  local err_file
  err_file="$(mktemp)"
  trap 'rm -f "$err_file"' RETURN

  while :; do
    echo "Launching ${INSTANCE} with ${cpu_try} vCPU..."
    if incus launch "${base_args[@]}" -c "limits.cpu=${cpu_try}" "${args[@]}" 2>"$err_file"; then
      CPU="$cpu_try"
      return 0
    fi

    if grep -q "Cannot allocate more CPUs than available" "$err_file"; then
      if (( cpu_try <= 1 )); then
        cat "$err_file" >&2
        return 1
      fi
      cpu_try=$((cpu_try - 1))
      echo "Host CPU limit reached. Retrying with ${cpu_try} vCPU..."
      continue
    fi

    cat "$err_file" >&2
    return 1
  done
}

launch_with_cpu_retry "$CPU"

echo
echo "Created: ${INSTANCE}"
echo "  effective.cpu=${CPU}"
echo "Check:"
echo "  incus info ${INSTANCE} --project ${PROJECT}"
echo "  incus console ${INSTANCE} --project ${PROJECT}"
