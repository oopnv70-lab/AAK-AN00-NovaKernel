#!/usr/bin/env bash
# 集成 SukiSU-Nova（builtin-new 分支，CONFIG_KSU=y 内置）到荣耀 GKI 内核树。
# 用法：integrate_sukisu.sh <KERNEL_PLATFORM>   （KERNEL_PLATFORM 是含 common/ 的内核工程根）
#
# 做的事（与 SukiSU-Nova builtin-new 官方 setup.sh 一致，但 clone 源固定为 GitHub）：
#   1. clone SukiSU-Nova（builtin-new 分支）到 $ROOT/KernelSU
#   2. ln -sf 软链 KernelSU/kernel -> common/drivers/kernelsu
#   3. common/drivers/Makefile 追加 obj-$(CONFIG_KSU) += kernelsu/
#   4. common/drivers/Kconfig 在 endmenu 前插入 source "drivers/kernelsu/Kconfig"
#   5. gki_defconfig 追加 CONFIG_KSU=y（及必要的显式项）
# 不碰 SUSFS / KPM / ARM64_BRANCH_LINK / TAMPER_SYSCALL_TABLE（全部保持默认 n）。
set -euo pipefail

ROOT="${1:?用法: integrate_sukisu.sh <KERNEL_PLATFORM>}"
COMMON="${ROOT}/common"
DRI="${COMMON}/drivers"
MAKEFILE="${DRI}/Makefile"
KCONFIG="${DRI}/Kconfig"
DEFCONFIG="${COMMON}/arch/arm64/configs/gki_defconfig"

echo "==> KERNEL_PLATFORM = $ROOT"
test -d "$COMMON" || { echo "::error::找不到 common/ ($COMMON)"; exit 1; }
test -d "$DRI" || { echo "::error::找不到 drivers/ ($DRI)"; exit 1; }
test -f "$DEFCONFIG" || { echo "::error::找不到 gki_defconfig ($DEFCONFIG)"; exit 1; }

# 1) clone SukiSU-Nova（builtin-new 分支，GitHub 源）
if [ ! -d "$ROOT/KernelSU/.git" ]; then
  echo "==> clone SukiSU-Nova (builtin-new)"
  git clone --depth 1 -b builtin-new https://github.com/SukiSU-Nova/SukiSU-Nova.git "$ROOT/KernelSU"
else
  echo "==> KernelSU 已存在，跳过 clone"
fi
test -d "$ROOT/KernelSU/kernel" || { echo "::error::KernelSU/kernel 不存在"; exit 1; }
echo "    内置版本: $(cd "$ROOT/KernelSU" && git log -1 --format='%h %s' 2>/dev/null)"

# 2) 软链 KernelSU/kernel -> drivers/kernelsu
if [ -L "$DRI/kernelsu" ] || [ -e "$DRI/kernelsu" ]; then
  echo "==> drivers/kernelsu 已存在，先移除"
  rm -rf "$DRI/kernelsu"
fi
ln -sf "$(realpath --relative-to="$DRI" "$ROOT/KernelSU/kernel")" "$DRI/kernelsu"
echo "==> 软链: $DRI/kernelsu -> $(readlink -f "$DRI/kernelsu")"

# 3) Makefile 注入
if grep -q "CONFIG_KSU" "$MAKEFILE"; then
  echo "==> Makefile 已有 kernelsu 条目，跳过"
else
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$MAKEFILE"
  echo "==> Makefile 已追加 obj-\$(CONFIG_KSU) += kernelsu/"
fi

# 4) Kconfig 注入（endmenu 前）
if grep -q 'drivers/kernelsu/Kconfig' "$KCONFIG"; then
  echo "==> Kconfig 已有 kernelsu 条目，跳过"
else
  sed -i '/^endmenu/i\source "drivers/kernelsu/Kconfig"' "$KCONFIG"
  echo "==> Kconfig 已插入 source \"drivers/kernelsu/Kconfig\""
fi

# 5) gki_defconfig 追加 CONFIG_KSU=y
if grep -q '^CONFIG_KSU=' "$DEFCONFIG"; then
  echo "==> gki_defconfig 已有 CONFIG_KSU，跳过"
else
  cat >> "$DEFCONFIG" <<'EOF'

# --- SukiSU-Nova (builtin) ---
CONFIG_KSU=y
CONFIG_KSU_FEATURE_ADBROOT=y
# CONFIG_KSU_SUSFS is not set
# CONFIG_KPM is not set
EOF
  echo "==> gki_defconfig 已追加 CONFIG_KSU=y"
fi

# 自检
echo "==> 自检"
grep -q "kernelsu/" "$MAKEFILE" && echo "  ✓ Makefile 有 kernelsu 条目" || { echo "  ✗ Makefile 缺条目"; exit 1; }
grep -q 'drivers/kernelsu/Kconfig' "$KCONFIG" && echo "  ✓ Kconfig 有 source 条目" || { echo "  ✗ Kconfig 缺条目"; exit 1; }
grep -q '^CONFIG_KSU=y' "$DEFCONFIG" && echo "  ✓ gki_defconfig CONFIG_KSU=y" || { echo "  ✗ gki_defconfig 缺 CONFIG_KSU=y"; exit 1; }
test -f "$DRI/kernelsu/Kconfig" && echo "  ✓ drivers/kernelsu/Kconfig 存在" || { echo "  ✗ 软链未生效"; exit 1; }
test -f "$DRI/kernelsu/Makefile" && echo "  ✓ drivers/kernelsu/Makefile 存在" || { echo "  ✗ 软链未生效"; exit 1; }

echo "==> SukiSU-Nova 集成完成"
