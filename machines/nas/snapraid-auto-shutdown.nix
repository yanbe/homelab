{ pkgs, lib, ... }:

let
  shutdownScript = pkgs.writeShellScriptBin "snapraid-auto-shutdown" ''
    #!/usr/bin/env bash
    # Checks if the system should power off after SnapRAID maintenance.

    # 1. Window check (04:00 - 09:00 JST)
    HOUR=$(date +%H)
    if [[ $HOUR -le 4 || $HOUR -ge 9 ]]; then
        echo "[$(date)] Outside maintenance shutdown window ($HOUR:00). Skipping autonomous shutdown."
        exit 0
    fi

    # 2. Desktop activity check (Pushed by monitor-display.sh via SSH)
    # This is our primary 'User Active' indicator.
    if [[ -f /run/desktop_active ]]; then
        STATE=$(cat /run/desktop_active)
        # Check if the state file is relatively fresh (last 10 minutes)
        FILE_AGE=$(($(date +%s) - $(date -r /run/desktop_active +%s)))
        if [[ $FILE_AGE -le 600 ]]; then
            if [[ "$STATE" == "True" ]]; then
                echo "[$(date)] Desktop reported as ACTIVE ($FILE_AGEs ago). Skipping autonomous shutdown."
                exit 0
            fi
        else
            echo "[$(date)] Warning: Desktop state file is stale ($FILE_AGEs old). Falling back to Samba check."
        fi
    fi

    # 3. Fallback: Samba activity check
    # If the user is streaming a movie or has files open, smbstatus will show locks.
    # Exclude matches for 'No locked files' by checking for numeric PIDs at start of line.
    if ${pkgs.samba}/bin/smbstatus -L | grep -qE "^[0-9]+"; then
        echo "[$(date)] Active Samba file handles detected. Skipping autonomous shutdown."
        exit 0
    fi

    echo "[$(date)] Maintenance complete, window active, and system idle. Initiating poweroff..."
    ${pkgs.systemd}/bin/systemctl poweroff
  '';
in
{
  systemd.services.snapraid-auto-shutdown = {
    description = "Autonomous Shutdown Check after SnapRAID Tasks";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${shutdownScript}/bin/snapraid-auto-shutdown";
    };
  };

  # Hook into existing SnapRAID services
  systemd.services.snapraid-sync.serviceConfig.ExecStopPost = [
    "+${pkgs.systemd}/bin/systemctl start snapraid-auto-shutdown.service"
  ];
  systemd.services.snapraid-scrub.serviceConfig.ExecStopPost = [
    "+${pkgs.systemd}/bin/systemctl start snapraid-auto-shutdown.service"
  ];
}
