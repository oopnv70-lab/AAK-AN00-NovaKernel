# AAK-AN00-NovaKernel — 荣耀 WIN RT（AAK-AN00）GKI 内核构建工程

> 设备：荣耀 WIN RT（AAK-AN00）｜ 系统：MagicOS 10.0（Android 15）｜ 内核：Linux 6.6.56（android15-6.6）
> 自编译 GKI 内核 + 内置 SukiSU-Nova（builtin-new 分支，CONFIG_KSU=y）+ AnyKernel3 刷机包。
> AI（Operit）参与构建与验证，刷机风险自负。

## 项目说明

本工程用荣耀开源的 AAK-AN00 内核源码（6.6.56），配合 AOSP 原生 Kleaf/Bazel 构建工具链，
编译出内置 SukiSU-Nova 的 GKI 内核，并打包为 AnyKernel3 刷机包。

- **内核源码**：荣耀开源发布中心 `AAK-AN00_MagicOS10.0_Opensource.zip`（Linux 6.6.56，厂商魔改）
- **构建工具链**：AOSP `kernel/build`（Kleaf）+ `kernel/manifest` 分支 `common-android15-6.6`
- **集成组件**：SukiSU-Nova（builtin-new 分支，GPL-2.0），通过 `defconfig_fragments` 注入 `CONFIG_KSU=y`
- **功能组件**：susfs4ksu（simonpunk，`gki-android15-6.6` 分支，GPL-3.0），SUSFS 路径隐藏/重定向/maps 欺骗
- **打包模板**：AnyKernel3（osm0sis，BSD-3-Clause）

## 目录结构

- `scripts/` —— 源码拉取与集成脚本
  - `fetch_honor_source.sh` —— 从荣耀开源中心拉取并解压源码
  - `integrate_sukisu.sh` —— 集成 SukiSU-Nova（软链 + Kconfig/Makefile 注入 + defconfig fragment）
  - `get_opensource_link.sh` —— 获取荣耀开源包下载链接
- `src/` —— 辅助源码/脚本
- `docs/` —— 文档、笔记、调研记录
- `.github/workflows/` —— CI 流程（含编译后 KSU 编入自动门禁）

## 许可证

- 根 `LICENSE`：**GPL-2.0**（本仓库自有代码 + 内核衍生部分）
- 第三方组件许可证逐项声明见 [NOTICE.md](NOTICE.md)
- 各协议全文见 `LICENSES/` 目录

## 刷机风险（必读）

自编译 GKI **未使用厂商私钥签名**，且公开源码版本（6.6.56）可能不等于真机固件版本（6.6.89），
AVB / vermagic 不匹配时刷入可能无法开机。请在解锁引导加载程序并理解风险后操作，刷机与使用风险自负。

## 构建

详见 `docs/build-plan-honor-gki.md`。构建由 GitHub Actions 手动触发（`workflow_dispatch`）。