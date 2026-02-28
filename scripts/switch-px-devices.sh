#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
	echo "Usage: $0 <target_instance_name>"
	echo "Example: $0 win11-p2v"
	exit 1
fi

PROJECT="default"
WIN_INSTANCE="win11-p2v"
LINUX_INSTANCE="nixos-dev"
PCI0="0000:03:00.0"
PCI1="0000:04:00.0"
DEV0="px-w3pe"
DEV1="px-q3pe"

if [[ "$TARGET" != "$WIN_INSTANCE" && "$TARGET" != "$LINUX_INSTANCE" ]]; then
	echo "Error: Target must be either '$WIN_INSTANCE' or '$LINUX_INSTANCE'."
	exit 1
fi

if [[ "$TARGET" == "$WIN_INSTANCE" ]]; then
	OTHER="$LINUX_INSTANCE"
else
	OTHER="$WIN_INSTANCE"
fi

echo "Switching PCI tuners ($DEV0, $DEV1) to $TARGET..."

# 1. Stop both instances if they are running (forcing to prevent host hang on graceful shutdown)
for INST in "$TARGET" "$OTHER"; do
	STATUS=$(incus info "$INST" --project "$PROJECT" 2>/dev/null | grep -i '^Status:' | awk '{print $2}' || true)
	if [[ "$STATUS" == "Running" || "$STATUS" == "RUNNING" ]]; then
		echo "Stopping $INST (forced)..."
		incus stop "$INST" --project "$PROJECT" --force
	fi
done

# 2. Detach from OTHER (ignore errors if not attached)
echo "Detaching from $OTHER..."
incus config device remove "$OTHER" "$DEV0" --project "$PROJECT" 2>/dev/null || true
incus config device remove "$OTHER" "$DEV1" --project "$PROJECT" 2>/dev/null || true

# 3. Attach to TARGET (ignore errors if already attached)
echo "Attaching to $TARGET..."
incus config device add "$TARGET" "$DEV0" pci address="$PCI0" --project "$PROJECT" 2>/dev/null || true
incus config device add "$TARGET" "$DEV1" pci address="$PCI1" --project "$PROJECT" 2>/dev/null || true

# 4. Start TARGET
echo "Starting $TARGET..."
incus start "$TARGET" --project "$PROJECT"

echo "Done!"
echo "Current devices attached to $TARGET:"
incus config device list "$TARGET" --project "$PROJECT"
