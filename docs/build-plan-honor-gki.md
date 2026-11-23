# 荣耀 WIN RT（AAK-AN00）GKI 内核编译方案

> 前提：BL 未解锁 ≠ 不能编译。编译产物能否刷进机器是后话，但按官方源码编出 GKI Image 现在完全可做，将来解锁即可用。

## 一、源码包真实结构（以 AAK-AN00_MagicOS10.0_Opensource 为准）
```
Code_Opensource/
├── README_Kernel.txt   # ⚠️ 荣耀通用旧模板(msm8953/Image.gz-dtb)，对 6.x GKI 无效，勿信
├── README_MODULE.txt / README_Version.txt
├── kernel/             # = AOSP common kernel 树 (Linux 6.6.56)
├── external/           # AOSP external 工具/自测工程 (dtc、bpftool…)
└── vendor/{honor,open_source}   # 少量厂商件 (exfat-utils、samba…)
```
判定构建体系的关键证据（均在 kernel/ 内）：
- `build.config.common`：`BRANCH=android15-6.6`、`KMI_GENERATION=8`、`CLANG_VERSION=r510928`
- `build.config.gki`：`DEFCONFIG=gki_defconfig`
- `build.config.gki.aarch64`：`BUILD_GKI_ARTIFACTS=1`、`BUILD_SYSTEM_DLKM=1`
- `BUILD.bazel`：`define_common_kernels(... "kernel_aarch64" ...)`
- `Makefile`：VERSION 6.6.56

结论：这是 **android15-6.6 的 Kleaf/Bazel 体系 GKI 源码**，标准产物 `//common:kernel_aarch64_dist`。

## 二、为什么不能"拿包直接编"
包内**不含**构建基础设施：
- `build/`（Kleaf 构建脚本、build-tools/path、build.sh）
- `prebuilts/clang/host/linux-x86/clang-r510928`（工具链）
- `prebuilts/bazel`、`tools/bazel`（bazel 启动器与 WORKSPACE 依赖）
- `BUILD.bazel` 里 `load("//build/kernel/kleaf/...")` 依赖这些缺失仓库

所以必须配一套 AOSP `common-android15-6.6` 的 kernel_platform 基础架构，再把荣耀 `kernel/` 覆盖进其 `common/`。

## 三、构建流程（见 .github/workflows/honor-gki-build.yml）
1. `scripts/fetch_honor_source.sh`：实时查荣耀接口→拿"当前有效"签名 URL→带 Referer 下载→解压（解决链接过期/防盗链）。
2. `repo init -u https://android.googlesource.com/kernel/manifest -b common-android15-6.6 --depth=1` + `repo sync`（拿 prebuilts/build/tools）。
3. `rsync` 用荣耀 `kernel/` 覆盖 `common/`（保留 .git）。
4. `tools/bazel build --config=fast //common:kernel_aarch64_dist`。
5. 收集 Image / boot*.img / system_dlkm / System.map / vmlinux 并上传 artifact。

## 四、风险 & 首轮要验证的点
- **磁盘**：GitHub 托管 runner 空间紧，repo 全量约 13GB + 构建产物；workflow 已先清盘，若仍不够需换 larger runner 或裁剪 manifest。
- **共性兼容**：荣耀 common 与 AOSP 同分支 infra 理论可对，但其可能隐含对 prebuilts/ABI 的特定依赖，首轮重点看 bazel 报错（KMI/abi 校验、缺失 .bzl）。
- **BL 锁**：产物是 GKI 通用 boot，不含荣耀 vendor ramdisk/cmdline，不能直接刷；仅验证"能编出"。
- **KMI**：`KMI_GENERATION=8`、`kmi_symbol_list_strict_mode=True`（BUILD.bazel），若符号表不匹配会在构建期拦，需按实际调整。

## 五、产物落点
- `bazel-bin/common/kernel_aarch64_gki_artifacts/*.tar.gz`（gki boot 镜像包）
- `bazel-bin/common/dist/`（dist 目标拷贝）
- Image / system_dlkm 等