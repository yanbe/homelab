{ pkgs, lib, ... }:

let
  isNasBusyScript = pkgs.writeShellScriptBin "is-nas-busy" ''
    #!/usr/bin/env bash
    # Returns 0 if busy, 1 if idle.

    # 1. Samba Check: Exit with 0 if locks are detected.
    # Exclude locks on the root directory '.' which are often held idly by Windows Explorer.
    if ${pkgs.samba}/bin/smbstatus -L | awk 'NR>3 && $8 != "."' | grep -qE "^[0-9]+"; then
        exit 0
    fi

    # Exit with 1 if idle.
    exit 1
  '';

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
    if [[ -f /run/desktop_active ]]; then
        STATE=$(cat /run/desktop_active)
        FILE_AGE=$(($(date +%s) - $(date -r /run/desktop_active +%s)))
        if [[ $FILE_AGE -le 600 && "$STATE" == "True" ]]; then
            echo "[$(date)] Desktop reported as ACTIVE ($FILE_AGEs ago). Skipping autonomous shutdown."
            exit 0
        fi
    fi

    # 3. Unified Busy Check (Samba, etc.)
    if ${isNasBusyScript}/bin/is-nas-busy; then
        echo "[$(date)] NAS is busy (Samba). Skipping autonomous shutdown."
        exit 0
    fi

    echo "[$(date)] Maintenance complete, window active, and system idle. Initiating poweroff..."
    ${pkgs.systemd}/bin/systemctl poweroff
  '';
in
{
  environment.systemPackages = [ isNasBusyScript ];

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
