#!/usr/bin/env bash
# 1. ネットワークと名前解決の準備
ip link set lo up
echo "127.0.0.1 localhost" >/etc/hosts # localhost の名前解決を確実にする
mkdir -p /var/lib/tpm /etc /mnt-boot /var/run

# 2. system.data の復元と、最初から完璧な権限設定
mount -t ext4 /dev/disk/by-partlabel/disk-stick_usb2_in-boot /mnt-boot
if [ -f /mnt-boot/system.data ]; then
	cp /mnt-boot/system.data /var/lib/tpm/system.data
	chown 0:0 /var/lib/tpm/system.data
	chmod 600 /var/lib/tpm/system.data
	chmod 700 /var/lib/tpm # ディレクトリ自体を最初から 700 にしておく
fi

# 3. tcsd.conf の作成
echo "system_ps_file = /var/lib/tpm/system.data" >/etc/tcsd.conf

# 4. tcsd の起動
echo "TPM-AUTO-UNLOCK: Starting tcsd..."
tcsd -f -c /etc/tcsd.conf &
TCSD_PID=$!

# 5. デーモンが応答するまで最大 30秒待機するループ
echo "TPM-AUTO-UNLOCK: Waiting for tcsd to respond..."
CONNECTED=0
for i in $(seq 1 30); do
	if tpm_version >/dev/null 2>&1; then
		echo "TPM-AUTO-UNLOCK: tcsd is READY after $i seconds."
		CONNECTED=1
		break
	fi
	sleep 1
done

# 6. 接続できた場合のみアンシールを実行
if [ $CONNECTED -eq 1 ]; then
	echo "TPM-AUTO-UNLOCK: Attempting unseal..."
	if RAW_KEY=$(tpm_unsealdata -z -i /mnt-boot/tpm-luks.key.sealed) && [ -n "$RAW_KEY" ]; then
		echo "TPM-AUTO-UNLOCK: Unseal SUCCESS!"

		# バックグラウンドプロセスのIDを管理する配列（POSIXシェル用）
		PIDS=""

		for dev in /dev/disk/by-partlabel/disk-*; do
			if cryptsetup isLuks "$dev"; then
				# デバイスパスからラベル名を取得 (例: /dev/.../disk-stick_usb3_ex-nix -> disk-stick_usb3_ex-nix)
				LABEL="${dev##*/}"

				# 先頭の "disk-" を削除 (-> stick_usb3_ex-nix)
				TEMP_NAME="${LABEL#disk-}"

				# 最後のハイフンとその直後 (サフィックス) を削除 (-> stick_usb3_ex)
				# %-* は「最後に見つかるハイフンから後ろ」を切り捨てます
				BASE_NAME="${TEMP_NAME%-*}"

				# NixOSが期待するマッパー名を作成
				MAP_NAME="luks_${BASE_NAME}"

				echo "TPM-AUTO-UNLOCK: Starting open for $dev..."
				# サブシェル内で実行し、バックグラウンドへ
				(
					# パイプ経由で鍵を渡し、標準入力を確実に閉じる
					echo -n "$RAW_KEY" | cryptsetup open "$dev" "$MAP_NAME" --key-file=-
					echo "TPM-AUTO-UNLOCK: Finished $MAP_NAME"
				) &
				PIDS="$PIDS $!"
			fi
		done

		# すべての cryptsetup プロセスが終了するまで待機
		echo "TPM-AUTO-UNLOCK: Waiting for all disks to unlock..."
		for pid in $PIDS; do
			wait "$pid"
		done

		unset RAW_KEY
	else
		echo "TPM-AUTO-UNLOCK: Unseal FAILED even with connection."
	fi
else
	echo "TPM-AUTO-UNLOCK: TIMEOUT - tcsd never responded."
fi

kill $TCSD_PID
umount /mnt-boot
