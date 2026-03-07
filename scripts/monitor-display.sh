#!/usr/bin/env bash
# scripts/monitor-display.sh
# Monitors the Windows display state from WSL2 and manages NAS power states.

# --- Configuration ---
CHECK_INTERVAL=30    # Seconds
SNAPRAID_START="04:25"
SNAPRAID_END="06:30"

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHUTDOWN_NAS="$SCRIPT_DIR/shutdown-nas.sh"
WAKE_NAS="$SCRIPT_DIR/wake-nas.sh"
SHUTDOWN_INCUS="$SCRIPT_DIR/shutdown-incus.sh"
WAKE_INCUS="$SCRIPT_DIR/wake-incus.sh"

# State: ON, OFF, MAINTENANCE
last_state="unknown"

log() {
    echo "[$(TZ="Asia/Tokyo" date '+%Y-%m-%d %H:%M:%S')] $*"
}

is_maintenance_time() {
    local now
    now=$(TZ="Asia/Tokyo" date +%H:%M)
    [[ "$now" > "$SNAPRAID_START" && "$now" < "$SNAPRAID_END" ]]
}

get_display_active() {
    # Returns "True" if user is active or display is blocked, "False" if idle.
    powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w "$SCRIPT_DIR/check-display.ps1")" | tr -d '\r' | tail -n 1
}

log "Starting display monitor service (State Machine v2)..."

while true; do
    current_active=$(get_display_active)
    
    # Push state to NAS for autonomous shutdown decisions (Maintenance Window)
    # Reuses the same root automation key as shutdown-nas.sh.
    ssh -o BatchMode=yes -o ConnectTimeout=2 -o IdentityAgent=none -o IdentitiesOnly=yes -i "$HOME/.ssh/id_nas_automation" root@192.168.1.154 "echo $current_active > /run/desktop_active" >/dev/null 2>&1 || true

    if [[ "$current_active" == "True" ]]; then
        # 1. State: USER ACTIVE
        if [[ "$last_state" != "ON" ]]; then
            log "Display turned ON / User active. Ensuring NAS and Incus are awake..."
            "$WAKE_NAS" || log "Failed to wake NAS (will retry)"
            "$WAKE_INCUS" || log "Failed to wake Incus (will retry)"
            last_state="ON"
            "$SCRIPT_DIR/log-power-event.sh" "StateChange" "UserActive" "ON" "User detected on Windows PC. NAS/Incus woke up."
        fi
    
    elif [[ "$current_active" == "False" ]]; then
        # 2. State: USER IDLE
        if is_maintenance_time; then
            # Maintenance Window
            if [[ "$last_state" != "MAINTENANCE" ]]; then
                log "User idle, but maintenance window active ($SNAPRAID_START - $SNAPRAID_END). Waking NAS..."
                if "$WAKE_NAS"; then
                    last_state="MAINTENANCE"
                else
                    log "Failed to wake NAS for maintenance (will retry)"
                fi
                "$SCRIPT_DIR/log-power-event.sh" "StateChange" "Maintenance" "MAINTENANCE" "SnapRAID maintenance window started."
            fi
        else
            # Normal Idle
            if [[ "$last_state" != "OFF" ]]; then
                log "User idle for >30m. Checking if NAS is busy before shutdown..."
                # Call the unified busy check on the NAS via SSH. 
                # Reuses the same root automation key.
                ssh -o BatchMode=yes -o ConnectTimeout=5 -o IdentityAgent=none -o IdentitiesOnly=yes -i "$HOME/.ssh/id_nas_automation" root@192.168.1.154 "is-nas-busy" >/dev/null 2>&1
                ssh_exit_code=$?
                if [[ $ssh_exit_code -eq 0 ]]; then
                    log "NAS is currently busy (Samba/Active Streams). Delaying shutdown."
                    "$SCRIPT_DIR/log-power-event.sh" "ShutdownDelay" "IdleTimeout" "BUSY" "NAS skip shutdown due to active Samba sessions."
                elif [[ $ssh_exit_code -eq 1 ]]; then
                    log "Initiating NAS and Incus shutdown..."
                    nas_shutdown_success=false
                    incus_shutdown_success=false
                    
                    if "$SHUTDOWN_NAS"; then
                        nas_shutdown_success=true
                    else
                        log "Failed to shut down NAS"
                    fi
                    
                    if "$SHUTDOWN_INCUS"; then
                        incus_shutdown_success=true
                    else
                        log "Failed to shut down Incus"
                    fi
                    
                    if "$nas_shutdown_success" && "$incus_shutdown_success"; then
                        last_state="OFF"
                        "$SCRIPT_DIR/log-power-event.sh" "StateChange" "IdleTimeout" "OFF" "System idle for >30m. NAS/Incus shut down."
                    else
                        log "Partial or total shutdown failure. State remains '$last_state' to retry later."
                        "$SCRIPT_DIR/log-power-event.sh" "StateChange" "IdleTimeout" "ERROR" "Shutdown sequence failed. Will retry."
                    fi
                else
                    log "Network error checking NAS busy state (exit code: $ssh_exit_code). Delaying shutdown."
                    "$SCRIPT_DIR/log-power-event.sh" "ShutdownDelay" "IdleTimeout" "ERROR" "Failed to reach NAS via SSH."
                fi
            fi
        fi
    else
        log "Warning: Unexpected output from check-display.ps1: '$current_active'"
    fi

    sleep "$CHECK_INTERVAL"
done
