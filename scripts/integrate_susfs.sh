#!/usr/bin/env bash
# 集成 SUSFS（susfs4ksu，gki-android15-6.6 分支）到荣耀 GKI 内核树。
# 用法：integrate_susfs.sh <KERNEL_PLATFORM>
#   KERNEL_PLATFORM —— 含 common/ 的内核工程根（SukiSU-Nova 已先由 integrate_sukisu.sh 集成）。
#
# 官方流程（不预判锚点、不补 include、不做垫片回退——失败就失败）：
#   1) clone susfs4ksu 的 gki-android15-6.6 分支
#   2) patch -p1 -f 主补丁 50_add_susfs_in_gki-android15-6.6.patch（内核树 27 文件）
#   3) 复制 3 个新增文件：fs/susfs.c、include/linux/susfs.h、include/linux/susfs_def.h
#   4) patch -p1 -f KSU 侧补丁 10_enable_susfs_for_ksu.patch（打在 drivers/kernelsu/）
#   5) 在 ksu_defconfig fragment 里打开 CONFIG_KSU_SUSFS=y 及 11 个子项
#
# 失败语义（方案 A）：主补丁/KSU 侧补丁若产生 .rej（锚点缺失），本脚本只负责
#   「暴露失败」，不做任何自动改写源码的动作；.rej 文件保留，由后续编译环节
#   自然失败（susfs_def.h 未 include 导致宏未定义、编译报错）。这是刻意的：
#   荣耀树删除上游 include 锚点（如 dma-buf.h / zswap.h）是厂商改动，需人工判断，
#   不能脚本擅自动源码。
set -euo pipefail

ROOT="${1:?用法: integrate_susfs.sh <KERNEL_PLATFORM>}"
COMMON="${ROOT}/common"
SUSFS_BRANCH="gki-android15-6.6"
SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"

echo "==> KERNEL_PLATFORM = $ROOT"
echo "==> SUSFS 分支 = $SUSFS_BRANCH"
test -d "$COMMON" || { echo "::error::找不到 common/ ($COMMON)"; exit 1; }

# ============ 1) clone susfs4ksu ============
SUSFS_DIR="${ROOT}/susfs4ksu"
if [ ! -d "$SUSFS_DIR/.git" ]; then
  echo "==> clone susfs4ksu ($SUSFS_BRANCH)"
  git clone --depth 1 -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_DIR"
else
  echo "==> susfs4ksu 已存在，跳过 clone"
fi
KP="$SUSFS_DIR/kernel_patches"
test -f "$KP/50_add_susfs_in_gki-android15-6.6.patch" || { echo "::error::找不到主补丁 50_add_susfs_in_gki-android15-6.6.patch"; exit 1; }
test -f "$KP/KernelSU/10_enable_susfs_for_ksu.patch" || { echo "::error::找不到 KSU 侧补丁 10_enable_susfs_for_ksu.patch"; exit 1; }
echo "    SUSFS 版本: $(cd "$SUSFS_DIR" && git log -1 --format='%h %s' 2>/dev/null)"

# ============ 2) 打主补丁（内核树） ============
echo "==> 应用主补丁 50_add_susfs_in_gki-android15-6.6.patch"
cd "$COMMON"
# -f：失败 hunk 生成 .rej 并继续；--forward：忽略 reversed/already-applied。
# 注意：官方流程不预判锚点，荣耀树删了 include 锚点（dma-buf.h / zswap.h 等）
#       就会在这里 FAILED 并产出 .rej——这是预期内的「失败暴露」，不在此处兜底。
if patch -p1 -f --forward < "$KP/50_add_susfs_in_gki-android15-6.6.patch" > /tmp/susfs-main-apply.log 2>&1; then
  echo "  ✓ 主补丁干净应用（无失败 hunk）"
else
  echo "  ⚠ 主补丁有失败 hunk（-f 已生成 .rej 并跳过失败 hunk）"
fi
n_rej=$(find . -name '*.rej' -newer "$KP/50_add_susfs_in_gki-android15-6.6.patch" 2>/dev/null | wc -l | tr -d ' ')
n_fail=$(grep -c 'FAILED' /tmp/susfs-main-apply.log 2>/dev/null || true)
n_patch=$(grep -c 'patching file' /tmp/susfs-main-apply.log 2>/dev/null || true)
echo "    patching_file=$n_patch FAILED=$n_fail .rej=$n_rej"
if [ "$n_rej" -gt 0 ]; then
  echo "  ⚠ 主补丁产生 $n_rej 个 .rej（锚点缺失，荣耀树改动所致）。"
  echo "    按方案 A：不自动修复，保留 .rej，后续编译会自然失败。"
  find . -name '*.rej' 2>/dev/null | head -20
fi
tail -20 /tmp/susfs-main-apply.log

# ============ 3) 复制 3 个新增文件 ============
echo "==> 复制 3 个新增文件（fs/susfs.c + include/linux/susfs.{h,def.h}）"
for rel in fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h; do
  src="$KP/$rel"
  dst="$COMMON/$rel"
  test -f "$src" || { echo "::error::上游缺新增文件 $rel"; exit 1; }
  mkdir -p "$(dirname "$dst")"
  cp -v "$src" "$dst"
done

# ============ 4) 打 KSU 侧补丁（drivers/kernelsu） ============
KSU_KERNEL="$COMMON/drivers/kernelsu"
test -d "$KSU_KERNEL" || { echo "::error::找不到 drivers/kernelsu（SukiSU 未集成？）"; exit 1; }
echo "==> 应用 KSU 侧补丁 10_enable_susfs_for_ksu.patch（打在 drivers/kernelsu/）"
cd "$KSU_KERNEL"
if patch -p1 -f --forward < "$KP/KernelSU/10_enable_susfs_for_ksu.patch" > /tmp/susfs-ksu-apply.log 2>&1; then
  echo "  ✓ KSU 侧补丁干净应用"
else
  echo "  ⚠ KSU 侧补丁有失败 hunk（.rej 已生成）"
fi
n_ksu_rej=$(find . -name '*.rej' -newer "$KP/KernelSU/10_enable_susfs_for_ksu.patch" 2>/dev/null | wc -l | tr -d ' ')
echo "    KSU 侧 .rej=$n_ksu_rej"
if [ "$n_ksu_rej" -gt 0 ]; then
  echo "  ⚠ KSU 侧补丁产生 .rej，按方案 A 保留，不自动修复。"
  find . -name '*.rej' 2>/dev/null | head -20
fi
tail -20 /tmp/susfs-ksu-apply.log

# ============ 5) fragment 打开 CONFIG_KSU_SUSFS ============
FRAGMENT="$COMMON/ksu_defconfig"
test -f "$FRAGMENT" || { echo "::error::找不到 ksu_defconfig（SukiSU 未集成？）"; exit 1; }
echo "==> 打开 fragment 里的 CONFIG_KSU_SUSFS 及子项"
# 先把原来的「# CONFIG_KSU_SUSFS is not set」注释行删掉，再追加 =y 项
sed -i '/^# CONFIG_KSU_SUSFS is not set/d' "$FRAGMENT"
# 追加 SUSFS 主开关 + 11 个子项（与 KSU 侧补丁 Kconfig 的 default y 对齐）
cat >> "$FRAGMENT" <<'EOF'
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER=y
EOF
echo "==> fragment 当前内容 =="
cat "$FRAGMENT"

# ============ 自检 ============
echo "==> 自检"
test -f "$COMMON/fs/susfs.c" && echo "  ✓ fs/susfs.c 已复制" || { echo "  ✗ fs/susfs.c 缺失"; exit 1; }
test -f "$COMMON/include/linux/susfs.h" && echo "  ✓ include/linux/susfs.h 已复制" || { echo "  ✗ susfs.h 缺失"; exit 1; }
test -f "$COMMON/include/linux/susfs_def.h" && echo "  ✓ include/linux/susfs_def.h 已复制" || { echo "  ✗ susfs_def.h 缺失"; exit 1; }
grep -q '^CONFIG_KSU_SUSFS=y' "$FRAGMENT" && echo "  ✓ fragment 有 CONFIG_KSU_SUSFS=y" || { echo "  ✗ fragment 缺 CONFIG_KSU_SUSFS=y"; exit 1; }
grep -q 'CONFIG_KSU_SUSFS' "$KSU_KERNEL/Kconfig" && echo "  ✓ kernelsu/Kconfig 已注入 SUSFS 菜单（KSU 侧补丁生效）" || echo "  ⚠ kernelsu/Kconfig 未见 SUSFS（KSU 侧补丁可能失败）"

echo "==> SUSFS 集成步骤完成（方案 A：不自动修复 .rej，失败由编译暴露）"
