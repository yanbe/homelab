#!/usr/bin/env bash
RAW_KEY="/boot/tpm-luks.key"
SEALED_KEY="/boot/tpm-luks.key.sealed"
RECOVERY_PW="/boot/luks-recovery.password"

# 生の鍵ファイルがあるか確認
if [ ! -f "$RAW_KEY" ]; then
  echo "Raw key $RAW_KEY not found. Already initialized?"
  exit 0
fi

echo "Initializing TPM 1.2 sealing..."

# 1. TPM 1.2 の所有権を取得 （N54Lではブート時にCMOSリセットが必要なので注意）
# tpm_takeownership -z -y
cp /var/lib/tpm/system.data /boot/system.data

# 2. 各LUKSパーティションにこの生鍵を追加
# (diskoが作ったスロット0のリカバリパスワードを使って、スロット1にこの鍵を入れる)
for dev in /dev/disk/by-partlabel/disk-*; do
  if cryptsetup isLuks "$dev"; then
    echo "Registering key to $dev..."
    echo -n "$(cat "$RECOVERY_PW")" | cryptsetup luksAddKey "$dev" "$RAW_KEY" --key-file -
  fi
done

# 3. TPM 1.2 に封印
# -z: Well-known auth (0000...)
# -p 0: PCR 0 (BIOS/Firmware構成) に紐付け
echo "Sealing key into TPM 1.2..."
if tpm_sealdata -z -i "$RAW_KEY" -o "$SEALED_KEY"; then
  echo "Success: $SEALED_KEY created."

  # 3. 完了したら「生」のファイル群を削除
  rm "$RAW_KEY"
  # リカバリパスワードは、TPMが壊れた時のために残すか消すか選べますが、
  # 今回は方針通り削除します
  rm "$RECOVERY_PW"
  echo "Sensitive raw files removed."
else
  echo "Error: TPM sealing failed!"
  exit 1
fi
