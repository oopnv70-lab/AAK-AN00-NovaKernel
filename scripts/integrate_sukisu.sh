#!/usr/bin/env bash
# 集成 SukiSU-Nova（builtin-new 分支，CONFIG_KSU=y 内置）到荣耀 GKI 内核树。
# 用法：integrate_sukisu.sh <KERNEL_PLATFORM>   （KERNEL_PLATFORM 是含 common/ 的内核工程根）
#
# 分两部分：
#   A. 内核源码侧（软链 + Kconfig/Makefile 注入）——与 SukiSU-Nova builtin-new 官方 setup.sh 一致
#      但 clone 源固定为 GitHub（builtin-new 分支，避开自建 git 服务器）。
#   B. Kleaf 配置侧（正确方式：defconfig fragment，而不是改 gki_defconfig 本体）——
#      生成 common/ksu_defconfig fragment，并在 common/BUILD.bazel 的
#      define_common_kernels(target_configs={"kernel_aarch64": {...}}) 字典里注入
#      "defconfig_fragments": ["ksu_defconfig"]。
#      原因：Kleaf 的 check_defconfig 默认 "minimized"，要求 savedefconfig 结果与
#      gki_defconfig 逐字节一致；直接改 gki_defconfig 追加 CONFIG_KSU=y 会因
#      Kconfig 依赖/默认值被 savedefconfig 规范化后丢弃而 mismatch。
#      defconfig_fragments 是官方 post-defconfig 语义（make defconfig 之后叠加，
#      等效 POST_DEFCONFIG_CMDS），不触发 savedefconfig 比对，是 vendor 加配置的正道。
# 不碰 SUSFS / KPM / ARM64_BRANCH_LINK / TAMPER_SYSCALL_TABLE（全部保持默认 n）。
set -euo pipefail

ROOT="${1:?用法: integrate_sukisu.sh <KERNEL_PLATFORM>}"
COMMON="${ROOT}/common"
DRI="${COMMON}/drivers"
MAKEFILE="${DRI}/Makefile"
KCONFIG="${DRI}/Kconfig"
BUILD_BAZEL="${COMMON}/BUILD.bazel"
FRAGMENT="${COMMON}/ksu_defconfig"

echo "==> KERNEL_PLATFORM = $ROOT"
test -d "$COMMON" || { echo "::error::找不到 common/ ($COMMON)"; exit 1; }
test -d "$DRI" || { echo "::error::找不到 drivers/ ($DRI)"; exit 1; }
test -f "$BUILD_BAZEL" || { echo "::error::找不到 common/BUILD.bazel ($BUILD_BAZEL)"; exit 1; }

# ============ A. 内核源码侧：clone + 软链 + Kconfig/Makefile 注入 ============

# A1) clone SukiSU-Nova（builtin-new 分支，GitHub 源）
if [ ! -d "$ROOT/KernelSU/.git" ]; then
  echo "==> clone SukiSU-Nova (builtin-new)"
  git clone --depth 1 -b builtin-new https://github.com/SukiSU-Nova/SukiSU-Nova.git "$ROOT/KernelSU"
else
  echo "==> KernelSU 已存在，跳过 clone"
fi
test -d "$ROOT/KernelSU/kernel" || { echo "::error::KernelSU/kernel 不存在"; exit 1; }
echo "    内置版本: $(cd "$ROOT/KernelSU" && git log -1 --format='%h %s' 2>/dev/null)"

# A2) 软链 KernelSU/kernel -> drivers/kernelsu
if [ -L "$DRI/kernelsu" ] || [ -e "$DRI/kernelsu" ]; then
  echo "==> drivers/kernelsu 已存在，先移除"
  rm -rf "$DRI/kernelsu"
fi
ln -sf "$(realpath --relative-to="$DRI" "$ROOT/KernelSU/kernel")" "$DRI/kernelsu"
echo "==> 软链: $DRI/kernelsu -> $(readlink -f "$DRI/kernelsu")"

# A3) Makefile 注入
if grep -q "CONFIG_KSU" "$MAKEFILE"; then
  echo "==> Makefile 已有 kernelsu 条目，跳过"
else
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$MAKEFILE"
  echo "==> Makefile 已追加 obj-\$(CONFIG_KSU) += kernelsu/"
fi

# A4) Kconfig 注入（endmenu 前）
if grep -q 'drivers/kernelsu/Kconfig' "$KCONFIG"; then
  echo "==> Kconfig 已有 kernelsu 条目，跳过"
else
  sed -i '/^endmenu/i\source "drivers/kernelsu/Kconfig"' "$KCONFIG"
  echo "==> Kconfig 已插入 source \"drivers/kernelsu/Kconfig\""
fi

# ============ B. Kleaf 配置侧：fragment + BUILD.bazel 注入 ============

# B1) 生成 defconfig fragment 文件（不改 gki_defconfig 本体）
cat > "$FRAGMENT" <<'EOF'
# SukiSU-Nova (builtin) defconfig fragment —— 通过 define_common_kernels 的
# defconfig_fragments 注入（post-defconfig 语义），不直接改 gki_defconfig。
# SUSFS / KPM 均不启用（保持默认 n）。
CONFIG_KSU=y
CONFIG_KSU_FEATURE_ADBROOT=y
# CONFIG_KSU_SUSFS is not set
# CONFIG_KPM is not set
EOF
echo "==> 已生成 fragment: $FRAGMENT"
cat "$FRAGMENT"

# B2) 往 BUILD.bazel 的 kernel_aarch64 字典注入 defconfig_fragments
if grep -q '"defconfig_fragments"' "$BUILD_BAZEL"; then
  echo "==> BUILD.bazel 已有 defconfig_fragments，跳过"
else
  python3 - "$BUILD_BAZEL" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding='utf-8').read().split('\n')
out = []
inserted = False
i = 0
while i < len(lines):
    line = lines[i]
    out.append(line)
    if line.strip() == '"kernel_aarch64": {':
        j = i + 1
        while j < len(lines) and lines[j].strip() == '':
            out.append(lines[j]); j += 1
        out.append('        "defconfig_fragments": ["ksu_defconfig"],')
        inserted = True
        i = j
        continue
    i += 1
if not inserted:
    print('::error::未在 BUILD.bazel 找到 "kernel_aarch64": { 字典，注入失败', file=sys.stderr)
    sys.exit(1)
open(p, 'w', encoding='utf-8').write('\n'.join(out))
print('已注入 defconfig_fragments 到 kernel_aarch64 字典')
PY
  echo "==> BUILD.bazel 已注入 defconfig_fragments"
fi

# ============ 自检 ============
echo "==> 自检"
grep -q "kernelsu/" "$MAKEFILE" && echo "  ✓ Makefile 有 kernelsu 条目" || { echo "  ✗ Makefile 缺条目"; exit 1; }
grep -q 'drivers/kernelsu/Kconfig' "$KCONFIG" && echo "  ✓ Kconfig 有 source 条目" || { echo "  ✗ Kconfig 缺条目"; exit 1; }
test -f "$DRI/kernelsu/Kconfig" && echo "  ✓ drivers/kernelsu/Kconfig 存在" || { echo "  ✗ 软链未生效"; exit 1; }
test -f "$DRI/kernelsu/Makefile" && echo "  ✓ drivers/kernelsu/Makefile 存在" || { echo "  ✗ 软链未生效"; exit 1; }
test -f "$FRAGMENT" && echo "  ✓ ksu_defconfig fragment 存在" || { echo "  ✗ fragment 缺失"; exit 1; }
grep -q '"defconfig_fragments": \["ksu_defconfig"\]' "$BUILD_BAZEL" && echo "  ✓ BUILD.bazel 有 defconfig_fragments" || { echo "  ✗ BUILD.bazel 缺 defconfig_fragments"; exit 1; }
grep -q '^CONFIG_KSU=' "${COMMON}/arch/arm64/configs/gki_defconfig" && { echo "  ✗ gki_defconfig 被污染（含 CONFIG_KSU），不允许"; exit 1; } || echo "  ✓ gki_defconfig 本体干净（无 CONFIG_KSU）"

echo "==> SukiSU-Nova 集成完成（fragment 方式）"