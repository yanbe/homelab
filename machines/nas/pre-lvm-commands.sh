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

		# 理由: PMP 経由の 8台同時アクセスは I/O 詰まりと 60s タイムアウトの原因になる。
		# シリアルに PMP を回すことで、非 PMP デバイスの非同期解錠と適度に overlap しつつ
		# バス帯域の破綻を防ぐ。
		PIDS=""
		for dev in /dev/disk/by-partlabel/disk-*; do
			if [ ! -e "$dev" ] || ! cryptsetup isLuks "$dev"; then continue; fi
			LABEL="${dev##*/}"
			TEMP_NAME="${LABEL#disk-}"
			BASE_NAME="${TEMP_NAME%-*}"
			MAP_NAME="luks_${BASE_NAME}"

			if echo "$LABEL" | grep -q "pmp"; then
				echo "TPM-AUTO-UNLOCK: Starting OPEN (SERIAL-PMP) for $dev..."
				echo -n "$RAW_KEY" | cryptsetup open "$dev" "$MAP_NAME" --key-file=-
				echo "TPM-AUTO-UNLOCK: Finished $MAP_NAME"
			else
				echo "TPM-AUTO-UNLOCK: Starting OPEN (ASYNC) for $dev..."
				(
					echo -n "$RAW_KEY" | cryptsetup open "$dev" "$MAP_NAME" --key-file=-
					echo "TPM-AUTO-UNLOCK: Finished $MAP_NAME"
				) &
				PIDS="$PIDS $!"
			fi
		done

		if [ -n "$PIDS" ]; then
			echo "TPM-AUTO-UNLOCK: Waiting for async unlocks..."
			for pid in $PIDS; do
				wait "$pid"
			done
		fi

		unset RAW_KEY
	else
		echo "TPM-AUTO-UNLOCK: Unseal FAILED even with connection."
	fi
else
	echo "TPM-AUTO-UNLOCK: TIMEOUT - tcsd never responded."
fi

kill $TCSD_PID
umount /mnt-boot
