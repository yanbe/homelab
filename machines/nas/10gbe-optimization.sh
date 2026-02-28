#!/usr/bin/env bash
set +e

echo "Applying IRQ Coalescing (ixgbe compatible)..."
# ixgbeドライバ向けに、個別設定ではなく一括設定を試みます
# 値を 1 にするとドライバ側で「適応型（Adaptive）」として扱われる場合があります
ethtool -C enp2s0 rx-usecs 100 || echo "IRQ Coalescing failed, trying fallback..."
ethtool -C enp2s0 rx-usecs 1 || echo "Adaptive fallback failed"

echo "Setting MTU 9000..."
ip link set enp2s0 mtu 9000 || echo "MTU 9000 failed"

echo "Applying Offload settings..."
ethtool -K enp2s0 tso on gso on gro on lro on

set -e
