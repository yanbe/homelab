#!/usr/bin/env bash
ethtool -L enp2s0 combined 2

# 割り込みを特定のコアに固定せず、分散を許可する（またはコアごとに分ける）
# 一旦、すべてのコア(mask '3')で受け取れるようにするか、あるいは自動分散に任せる
find /sys/class/net/enp2s0/device/msi_irqs/* -exec basename {} \; | while IFS= read -r irq; do
  echo 3 > /proc/irq/"$irq"/smp_affinity
  echo "Allowing IRQ $irq to use both CPUs (mask 3)"
done
