{ pkgs, lib, ... }:

let
  desktopMacs = [
    "80:3f:5d:d5:0d:af" # Realtek USB 5GbE
    "fc:22:1c:40:34:a5" # Wi-Fi
  ];
  shutdownScript = pkgs.writeShellScriptBin "snapraid-auto-shutdown" ''
    #!/usr/bin/env bash
    # Checks if the system should power off after SnapRAID maintenance.

    # 1. Window check (04:00 - 09:00 JST)
    HOUR=$(date +%H)
    if [[ $HOUR -le 4 || $HOUR -ge 9 ]]; then
        echo "[$(date)] Outside maintenance shutdown window ($HOUR:00). Skipping autonomous shutdown."
        exit 0
    fi

    # 2. Desktop check (Robust MAC-based detection)
    # We check the ARP/neighbor table for the desktop's known MAC addresses.
    for mac in ${builtins.concatStringsSep " " desktopMacs}; do
        if ip neighbor show | grep -qi "$mac" | grep -qiE "REACHABLE|DELAY|STALE"; then
            echo "[$(date)] Windows Desktop MAC ($mac) is active. Skipping autonomous shutdown."
            exit 0
        fi
    done

    echo "[$(date)] Maintenance complete, window active, and Desktop absent. Initiating poweroff..."
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
