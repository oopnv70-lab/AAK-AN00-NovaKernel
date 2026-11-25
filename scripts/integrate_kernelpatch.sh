#!/usr/bin/env bash
# 集成 KernelPatch（KPM 内核补丁模块加载器）到荣耀 GKI 内核产物。
# 用法：integrate_kernelpatch.sh <KERNEL_PLATFORM> <IMAGE_PATH>
#   KERNEL_PLATFORM —— 含 common/ 的内核工程根（SukiSU-Nova 与 SUSFS 已先集成）
#   IMAGE_PATH      —— 已编译出的 Image 绝对路径（Kleaf 产物，未签名裸 Image）
#
# 关键前提（已联网核实，不照搬一加）：
#   KPM 完整可用 = CONFIG_KPM=y（SukiSU-Nova 侧桥接）+ KernelPatch 补丁（加载器）。
#   只开 CONFIG_KPM 完全没用：SukiSU 的 sukisu_kpm_bridge() 通过 magic supercall
#   （__arm64_sys_truncate + EL1h）与 KernelPatch 的加载器通信；没打 KP 补丁时
#   __arm64_sys_truncate 不认识 magic，dispatch 永远 -EOPNOTSUPP。
#
# KernelPatch 本质（不是改内核源码重编译，而是对已编译 Image 后处理）：
#   kptools  解析 Image 拿符号偏移（rest_init / __arm64_sys_truncate 等）
#   kpimg    独立 ELF，附加到 Image 末尾替换启动入口
#   kpatch   用户空间静态修补（patch.cpp）
#   依赖：CONFIG_KALLSYMS=y + has_syscall_wrapper（sukisu.c 第一道门禁）。
#
# 集成方式（老方法：CI 构建时当场 git clone 拉取，不本地打包上传）：
#   与 integrate_sukisu.sh / integrate_susfs.sh 一致，clone 源固定为 GitHub。
#
# TODO（尚未完成，待工具链方案确认后再补）：
#   KernelPatch 三件套的编译依赖较重：
#     - kptools 需要 cmake + NDK（build.sh 写死 r29，CI 需当场装）
#     - kpimg   需要裸机交叉编译器 aarch64-none-elf-gcc（CI ubuntu 镜像默认无）
#     - kpatch  需要 g++ / NDK clang
#   当前脚本只做「当场拉取 + 工具链探测 + 前提核验」，后处理动作留空（见下方 TODO）。
set -euo pipefail

ROOT="${1:?用法: integrate_kernelpatch.sh <KERNEL_PLATFORM> <IMAGE_PATH>}"
IMAGE="${2:?用法: integrate_kernelpatch.sh <KERNEL_PLATFORM> <IMAGE_PATH>}"

KP_REPO="https://github.com/SukiSU-Nova/SukiSU_KernelPatch_patch.git"
KP_BRANCH="main"
KP_DIR="${ROOT}/KernelPatch"

echo "==> KERNEL_PLATFORM = $ROOT"
echo "==> IMAGE = $IMAGE"
test -f "$IMAGE" || { echo "::error::找不到 Image ($IMAGE)"; exit 1; }

# ============ 1) 当场拉取 KernelPatch（GitHub main 分支，GPL-2.0）============
if [ ! -d "$KP_DIR/.git" ]; then
  echo "==> clone KernelPatch ($KP_BRANCH)"
  git clone --depth 1 -b "$KP_BRANCH" "$KP_REPO" "$KP_DIR"
else
  echo "==> KernelPatch 已存在，跳过 clone"
fi
test -f "$KP_DIR/LICENSE" || { echo "::error::KernelPatch/LICENSE 不存在"; exit 1; }
echo "    KernelPatch 版本: $(cat "$KP_DIR/version" 2>/dev/null | tr -d '\n')"
echo "    提交: $(cd "$KP_DIR" && git log -1 --format='%h %s' 2>/dev/null)"

# ============ 2) 许可证核验（GPL-2.0，与内核主体一致）============
if head -3 "$KP_DIR/LICENSE" | grep -q "GNU GENERAL PUBLIC LICENSE" \
   && grep -q "Version 2" "$KP_DIR/LICENSE"; then
  echo "  ✓ KernelPatch LICENSE = GPL-2.0（与内核主体一致）"
else
  echo "::error::KernelPatch LICENSE 不是 GPL-2.0，中止"; exit 1
fi

# ============ 3) 工具链探测（诚实报告缺哪些，缺则跳过后续、不静默失败）============
echo "==> 工具链探测"
have_cmake=0; have_ndk=0; have_noneelf=0; have_gxx=0
command -v cmake >/dev/null 2>&1 && have_cmake=1
[ -n "${ANDROID_NDK_HOME:-}" ] || [ -n "${ANDROID_NDK:-}" ] && have_ndk=1
command -v aarch64-none-elf-gcc >/dev/null 2>&1 && have_noneelf=1
command -v g++ >/dev/null 2>&1 && have_gxx=1

echo "    cmake                  : $([ $have_cmake = 1 ] && echo 'OK' || echo '缺失')"
echo "    NDK (ANDROID_NDK_HOME) : $([ $have_ndk = 1 ] && echo 'OK' || echo '缺失')"
echo "    aarch64-none-elf-gcc   : $([ $have_noneelf = 1 ] && echo 'OK' || echo '缺失')"
echo "    g++                    : $([ $have_gxx = 1 ] && echo 'OK' || echo '缺失')"

# ============ 4) 前提核验（Image 侧，决定「能不能干净打」）============
echo "==> 前提核验（Image 侧）"
# 4.1) CONFIG_KALLSYMS 是否已编入（KernelPatch 硬依赖）
if strings -a "$IMAGE" 2>/dev/null | grep -qE 'kallsyms_lookup_name|kallsyms_expand_symbol'; then
  echo "  ✓ Image 含 kallsyms 符号（CONFIG_KALLSYMS 已编入）"
else
  echo "  ✗ Image 未检出 kallsyms 符号（CONFIG_KALLSYMS 可能未启用，KernelPatch 无法工作）"
  echo "::warning::KernelPatch 依赖 CONFIG_KALLSYMS=y；若未启用，KPM 无法后处理。"
fi
# 4.2) __arm64_sys_truncate 符号是否在位（sukisu.c 的 hook 目标）
if strings -a "$IMAGE" 2>/dev/null | grep -qE '__arm64_sys_truncate'; then
  echo "  ✓ Image 含 __arm64_sys_truncate（KP hook 目标在位）"
else
  echo "  ✗ Image 未检出 __arm64_sys_truncate（syscall wrapper 可能缺失，KP 无法 hook）"
fi

# ============ 5) 后处理（TODO：待工具链方案确认后补）============
# 完整后处理流程（参考 build.sh，但 CI 需重新适配工具链）：
#   1. 编译 kptools（cmake + NDK）：解析 Image 拿符号偏移
#   2. 编译 kpimg（aarch64-none-elf-gcc）：独立 ELF，附加到 Image 末尾
#   3. 编译 kpatch（g++/NDK clang）：对 Image 做静态修补
#   4. 运行 kpatch，产出「KP 补丁版」Image
#   5. 用补丁后的 Image 替换原 Image，供 AnyKernel3 打包
#
# TODO: 上述 1-5 步当前留空。原因：工具链（尤其裸机 aarch64-none-elf-gcc）在
#   GitHub Actions ubuntu 镜像默认缺失，且 build.sh 里的 NDK 路径是本地硬编码
#   （/root/other/ndk/android-ndk-r29），不能直接用于 CI。工具链方案确认后再补。

if [ $have_cmake = 1 ] && [ $have_ndk = 1 ] && [ $have_noneelf = 1 ] && [ $have_gxx = 1 ]; then
  echo "==> 工具链齐全，但后处理逻辑尚未实现（TODO）——当前仅完成拉取 + 核验"
else
  echo "==> 工具链不齐（cmake=$have_cmake ndk=$have_ndk noneelf=$have_noneelf gxx=$have_gxx）"
  echo "    KernelPatch 后处理跳过（当前仅完成当场拉取 + 合规核验 + 前提探测）"
fi

echo "==> KernelPatch 集成脚本执行完毕（拉取 + 合规 + 前提核验完成，后处理 TODO）"
