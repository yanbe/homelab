#!/usr/bin/env bash
# scripts/log-power-event.sh
# Logs power-related events to a CSV file in the Windows user documents folder.

EVENT_LOG="/mnt/c/Users/yanbe/Documents/homelab_power_events.csv"
TIMESTAMP=$(TZ="Asia/Tokyo" date '+%Y-%m-%d %H:%M:%S')

EVENT="$1"
TRIGGER="$2"
STATUS="$3"
DETAILS="$4"

# Create header if not exists
if [ ! -f "$EVENT_LOG" ]; then
    echo "Timestamp,Event,Trigger,Status,Details" > "$EVENT_LOG"
fi

# Append event
echo "$TIMESTAMP,$EVENT,$TRIGGER,$STATUS,\"$DETAILS\"" >> "$EVENT_LOG"
