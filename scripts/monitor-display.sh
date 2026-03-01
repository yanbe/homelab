#!/usr/bin/env bash
# scripts/monitor-display.sh
# Monitors the Windows display state from WSL2 and manages NAS/Incus power states.

# --- Configuration ---
CHECK_INTERVAL=30    # Seconds
SNAPRAID_START="04:25"
SNAPRAID_END="06:30"
# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHUTDOWN_NAS="$SCRIPT_DIR/shutdown-nas.sh"
WAKE_NAS="$SCRIPT_DIR/wake-nas.sh"
# SHUTDOWN_INCUS="$SCRIPT_DIR/shutdown-incus.sh"
# WAKE_INCUS="$SCRIPT_DIR/wake-incus.sh"

last_state="unknown"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

is_maintenance_time() {
    local now
    now=$(date +%H:%M)
    [[ "$now" > "$SNAPRAID_START" && "$now" < "$SNAPRAID_END" ]]
}

get_display_active() {
    # Calls a custom PowerShell script to detect if DPMS display sleep is active
    # By checking user idle time vs Windows powercfg VIDEOIDLE timeout
    powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w "$SCRIPT_DIR/check-display.ps1")" | tr -d '\r' | tail -n 1
}

log "Starting display monitor service..."

# Initialize last_state on first run
current_active=$(get_display_active)
if [[ "$current_active" == "True" ]]; then
    last_state="ON"
else
    last_state="OFF"
fi
log "Initial display state: $last_state"

while true; do
    current_active=$(get_display_active)
    
    if [[ "$current_active" == "True" ]]; then
        current_state="ON"
    elif [[ "$current_active" == "False" ]]; then
        current_state="OFF"
    else
        current_state="unknown"
    fi

    # State transition: OFF -> ON
    if [[ "$last_state" == "OFF" && "$current_state" == "ON" ]]; then
        log "Display turned ON. Waking up hosts..."
        "$WAKE_NAS" || log "Failed to wake NAS"
        # "$WAKE_INCUS" || log "Failed to wake Incus"
    
    # State transition: ON -> OFF (or unknown -> OFF)
    elif [[ "$current_state" == "OFF" && "$last_state" != "OFF" ]]; then
        if is_maintenance_time; then
            log "Display is OFF. Initiating shutdown for NAS and Incus..."
  
            # Trigger shutdown concurrently
            "$SHUTDOWN_NAS" &
            # "$SHUTDOWN_INCUS" &
            wait
        else
            log "Display turned OFF. Shutting down hosts..."
            "$SHUTDOWN_NAS" || log "Failed to shut down NAS"
            # "$SHUTDOWN_INCUS" || log "Failed to shut down Incus"
        fi

    # Maintenance check when display is OFF
    elif [[ "$current_state" == "OFF" ]]; then
        # If it just entered maintenance time, wake the NAS
        now=$(date +%H:%M)
        if [[ "$now" == "$SNAPRAID_START" ]]; then
            log "Maintenance time started. Waking NAS..."
            "$WAKE_NAS" || log "Failed to wake NAS"
        fi
    fi

    last_state="$current_state"
    sleep "$CHECK_INTERVAL"
done
