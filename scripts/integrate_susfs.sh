#!/usr/bin/env bash
# 集成 SUSFS（susfs4ksu，gki-android15-6.6 分支）到荣耀 GKI 内核树。
# 用法：integrate_susfs.sh <KERNEL_PLATFORM>
#   KERNEL_PLATFORM —— 含 common/ 的内核工程根（SukiSU-Nova 已先由 integrate_sukisu.sh 集成）。
#
# 关键前提（借鉴一加思路，但针对荣耀 6.6 + 内置 SukiSU-Nova 重写）：
#   荣耀走「内置 KSU」路线（CONFIG_KSU=y），管理器是 SukiSU-Nova（builtin-new 分支）。
#   SukiSU-Nova 的 kernel/Kconfig 已经【内置】了完整的 "KernelSU - SUSFS" 菜单
#   （config KSU_SUSFS + KSU_SUSFS_INLINE_HOOK + 11 个子项），且 kernel/Makefile
#   在 CONFIG_KSU_SUSFS=y 时自动切到 SUSFS_INLINE_HOOK 后端。
#   因此 KSU 侧【无需打任何补丁】——susfs4ksu 的 10_enable_susfs_for_ksu.patch
#   是给 weishu 官方 KernelSU（其 Kconfig 无 SUSFS 菜单）用的，与 SukiSU-Nova
#   重构后的 supercall 结构对不上，打了反而报「No file to patch」。这一步明确不做。
#
# 本脚本只做两件事（SUSFS 的真正功能来自内核侧主补丁，KSU 侧由 SukiSU-Nova 自带）：
#   1) 打内核侧主补丁 50_add_susfs_in_gki-android15-6.6.patch（27 文件 inline hook）
#      + 复制 3 个新增文件：fs/susfs.c、include/linux/susfs.h、include/linux/susfs_def.h
#   2) 在 ksu_defconfig fragment 里打开 CONFIG_KSU_SUSFS=y + INLINE_HOOK + 11 子项
#
# 失败语义：主补丁若产生 .rej（荣耀树删了 include 锚点，如 dma-buf.h / zswap.h），
#   本脚本只负责「暴露失败」，不自动改写源码；.rej 保留，由后续编译环节自然失败。
set -euo pipefail

ROOT="${1:?用法: integrate_susfs.sh <KERNEL_PLATFORM>}"
COMMON="${ROOT}/common"
SUSFS_BRANCH="gki-android15-6.6"
SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"

# 可选手动开关：ENABLE_SUSFS=false 时整段跳过（不打补丁、不写 fragment）。
# 默认开启。由 workflow_dispatch 的 enable_susfs boolean 输入透传。
ENABLE_SUSFS="${ENABLE_SUSFS:-true}"
if [ "$ENABLE_SUSFS" != "true" ]; then
  echo "==> SUSFS 已禁用（ENABLE_SUSFS=$ENABLE_SUSFS），跳过集成，保持内核不含 SUSFS"
  exit 0
fi

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
echo "    SUSFS 版本: $(cd "$SUSFS_DIR" && git log -1 --format='%h %s' 2>/dev/null)"

# ============ 2) 打内核侧主补丁（唯一要打的补丁） ============
echo "==> 应用内核侧主补丁 50_add_susfs_in_gki-android15-6.6.patch"
cd "$COMMON"
# -f：失败 hunk 生成 .rej 并继续；--forward：忽略 reversed/already-applied。
# 荣耀树删了 include 锚点（dma-buf.h / zswap.h）会在这里 FAILED 并产出 .rej，
# 这是预期内的「失败暴露」，不在此处兜底。
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
  echo "    不自动修复，保留 .rej，后续编译会自然失败。"
  find . -name '*.rej' 2>/dev/null | head -20
fi
# 完整展示 patch 结果（不 tail 截断）：把每个文件的 hunk 成功/失败明细都暴露，
# 避免 base.c 这种多 hunk 文件的后续 hunk 结果被吞掉（此前 tail -20 的盲区）。
echo "==> 完整 patch 结果（hunk 明细） =="
cat /tmp/susfs-main-apply.log

# ============ 2.5) 补齐已知 .rej 的 susfs_def.h include（荣耀 6.6 树专属） ============
# 背景（本地源码树 grep 坐实，非类推）：
#   荣耀 sm8650/android15-6.6 树的 mm/memory.c、fs/proc/base.c 两个文件
#   【不 include】 <linux/zswap.h> / <linux/dma-buf.h>（头文件本身在树里完好，
#   只是这两个 .c 文件不再引用）。上游补丁以这两个 include 行当锚点，
#   在其后插入 #include <linux/susfs_def.h>，锚点缺失导致 Hunk #1 FAILED。
#
#   注意：缺的不是 zswap.h/dma-buf.h 本身（它们无关紧要），而是 susfs_def.h
#   这个 include——它的 Hunk #2（真正用到 SUSFS_IS_INODE_SUS_MAP 等宏的代码）
#   已经成功打上，宏定义却在 susfs_def.h 里。不补 include 编译必报 undeclared。
#
#   修复：在这两个文件的【现存锚点】后手动插入 susfs_def.h include，
#   与上游补丁意图完全一致，不碰荣耀的 zswap/dma-buf 逻辑。
fix_rej_include() {
  local file="$1" anchor="$2" guard="$3"
  local abs="$COMMON/$file"
  test -f "$abs" || { echo "  ⚠ 找不到 $file，跳过"; return 0; }
  # 幂等：已 include 过则跳过
  if grep -q 'susfs_def.h' "$abs"; then
    echo "  ✓ $file 已 include susfs_def.h，跳过"
    return 0
  fi
  # 锚点必须存在（唯一匹配）
  if ! grep -qF "$anchor" "$abs"; then
    echo "  ✗ $file 缺锚点「$anchor」，无法补齐 include（需人工介入）"
    return 1
  fi
  # 在锚点行后插入 guard + susfs_def.h + endif（用 awk，锚点用 index() 做前缀匹配，
  # 避免 sed 多行 a 命令在 shell/JSON 层层转义下出错）
  awk -v anchor="$anchor" -v guard="$guard" '
    { print }
    index($0, anchor) == 1 {
      print guard
      print "#include <linux/susfs_def.h>"
      print "#endif"
    }
  ' "$abs" > "$abs.tmp" && mv "$abs.tmp" "$abs"
  # 校验插入结果
  grep -q 'susfs_def.h' "$abs" || { echo "  ✗ $file 插入后仍无 susfs_def.h"; return 1; }
  echo "  ✓ $file 已补齐 susfs_def.h include（guard: $guard）"
  # 清理对应的 .rej
  rm -f "$abs.rej"
}

echo "==> 补齐已知 .rej 的 susfs_def.h include"
fix_rej_include "mm/memory.c" \
  "#include <linux/sched/sysctl.h>" \
  "#ifdef CONFIG_KSU_SUSFS_SUS_MAP" || { echo "::error::mm/memory.c include 补齐失败"; exit 1; }
fix_rej_include "fs/proc/base.c" \
  "#include <linux/cpufreq_times.h>" \
  "#if defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)" || { echo "::error::fs/proc/base.c include 补齐失败"; exit 1; }
echo "==> 补齐完成，剩余 .rej：$(find "$COMMON" -name '*.rej' 2>/dev/null | wc -l)"

# ============ 3) 复制 3 个新增文件 ============
echo "==> 复制 3 个新增文件（fs/susfs.c + include/linux/susfs.{h,def.h}）"
for rel in fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h; do
  src="$KP/$rel"
  dst="$COMMON/$rel"
  test -f "$src" || { echo "::error::上游缺新增文件 $rel"; exit 1; }
  mkdir -p "$(dirname "$dst")"
  cp -v "$src" "$dst"
done

# ============ 4) fragment 打开 CONFIG_KSU_SUSFS ============
# 注意：不在这里打 KSU 侧补丁（见文件头说明）。SukiSU-Nova 的 Kconfig 已内置
# SUSFS 菜单，fragment 直接写 CONFIG_KSU_SUSFS=y 即被其识别。
FRAGMENT="$COMMON/ksu_defconfig"
test -f "$FRAGMENT" || { echo "::error::找不到 ksu_defconfig（SukiSU 未集成？）"; exit 1; }
echo "==> 打开 fragment 里的 CONFIG_KSU_SUSFS 及子项"
# 先把原来的「# CONFIG_KSU_SUSFS is not set」注释行删掉，再追加 =y 项
sed -i '/^# CONFIG_KSU_SUSFS is not set/d' "$FRAGMENT"
# 追加 SUSFS 主开关 + INLINE_HOOK + 11 个子项（与 SukiSU-Nova Kconfig 的 default y 对齐）
cat >> "$FRAGMENT" <<'EOF'
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_INLINE_HOOK=y
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
KSU_KCONFIG="$COMMON/drivers/kernelsu/Kconfig"
test -f "$COMMON/fs/susfs.c" && echo "  ✓ fs/susfs.c 已复制" || { echo "  ✗ fs/susfs.c 缺失"; exit 1; }
test -f "$COMMON/include/linux/susfs.h" && echo "  ✓ include/linux/susfs.h 已复制" || { echo "  ✗ susfs.h 缺失"; exit 1; }
test -f "$COMMON/include/linux/susfs_def.h" && echo "  ✓ include/linux/susfs_def.h 已复制" || { echo "  ✗ susfs_def.h 缺失"; exit 1; }
grep -q '^CONFIG_KSU_SUSFS=y' "$FRAGMENT" && echo "  ✓ fragment 有 CONFIG_KSU_SUSFS=y" || { echo "  ✗ fragment 缺 CONFIG_KSU_SUSFS=y"; exit 1; }
# 核对 SukiSU-Nova 自己的 Kconfig 已内置 SUSFS 菜单（这是「无需 KSU 侧补丁」的根据）
grep -q 'config KSU_SUSFS$' "$KSU_KCONFIG" && echo "  ✓ SukiSU-Nova Kconfig 已内置 config KSU_SUSFS" || { echo "  ✗ SukiSU-Nova Kconfig 缺 config KSU_SUSFS（内置形态被破坏？）"; exit 1; }
grep -q 'config KSU_SUSFS_INLINE_HOOK' "$KSU_KCONFIG" && echo "  ✓ Kconfig 有 KSU_SUSFS_INLINE_HOOK" || echo "  ⚠ Kconfig 未见 KSU_SUSFS_INLINE_HOOK"

echo "==> SUSFS 集成完成（内置 KSU 形态：仅内核侧主补丁 + fragment，不打 KSU 侧补丁）"