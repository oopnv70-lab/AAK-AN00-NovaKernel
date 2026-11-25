# NOTICE

本仓库（`oopnv70-lab/AAK-AN00-NovaKernel`）是荣耀 WIN RT（AAK-AN00）GKI 内核的第三方构建工程。
仓库根目录 `LICENSE` 为 **GNU General Public License v2.0（GPL-2.0）**，适用于本仓库的自有代码
与内核衍生部分。以下第三方组件分别适用其各自的许可证，特此逐项声明。

## 第三方组件许可证清单

| 组件 | 许可证 | 来源 | 用途 |
| --- | --- | --- | --- |
| 荣耀 AAK-AN00 开源源码（Linux 内核 6.6.56） | GPL-2.0 | 荣耀开源发布中心 `AAK-AN00_MagicOS10.0_Opensource.zip` | 编译内核本体 |
| SukiSU-Nova（builtin-new 分支） | GPL-2.0 | https://github.com/SukiSU-Nova/SukiSU-Nova | 集成 KernelSU 功能（内置，CONFIG_KSU=y） |
| AOSP kernel/build（Kleaf 构建工具链） | Apache-2.0 | https://android.googlesource.com/kernel/build | Bazel/Kleaf 构建工具链 |
| AOSP kernel/common（android15-6.6） | GPL-2.0 | https://android.googlesource.com/kernel/common | 内核源码基线（被荣耀源码覆盖） |
| AnyKernel3（osm0sis） | BSD-3-Clause | https://github.com/osm0sis/AnyKernel3 | AnyKernel3 刷机包打包模板 |
| susfs4ksu（simonpunk） | GPL-3.0 | https://gitlab.com/simonpunk/susfs4ksu | SUSFS 功能（`gki-android15-6.6` 分支主补丁 + 新增源码 `fs/susfs.c` 等） |

各许可证全文见 `LICENSES/` 目录：
- `GPL-2.0.txt` —— GNU GPL v2.0 标准原文
- `GPL-3.0.txt` —— GNU GPL v3.0 标准原文（susfs4ksu）
- `Apache-2.0.txt` —— Apache License 2.0 标准原文
- `AnyKernel3-LICENSE.txt` —— AnyKernel3 的 BSD-3-Clause 许可证原文

## 重要说明

1. **SukiSU-Nova 分支许可证差异**：SukiSU-Nova 的 `main` 分支许可证为 GPL-3.0，但本仓库实际
   集成使用的是 `builtin-new` 分支，其 `LICENSE` 文件为 **GPL-2.0**。本仓库按实际集成的
   `builtin-new` 分支声明为 GPL-2.0。

2. **内核为 GPL-2.0 衍生作品**：本工程产出物（Image / AnyKernel3 刷机包）包含 GPL-2.0 许可的
   内核代码与 SukiSU-Nova 代码，因此整体作为 GPL-2.0 衍生作品分发，须遵循 GPL-2.0 义务
   （含提供对应源码）。

3. **susfs4ksu 为 GPL-3.0**：SUSFS 功能源码（`fs/susfs.c`、`include/linux/susfs.h`、
   `include/linux/susfs_def.h` 及主补丁）来自 susfs4ksu 项目，其上游 `LICENSE` 为
   **GPL-3.0**（与内核主体的 GPL-2.0 不同）。GPL-3.0 与 GPL-2.0 在许可证文本上互不兼容，
   但本项目遵循 susfs4ksu 上游的既有集成实践（SUSFS 作为内核模块补丁被广泛并入 GPL-2.0
   内核），并在刷机包内同时附带 GPL-2.0 与 GPL-3.0 全文，以保留双方许可证义务的落点。

4. **AI 参与声明**：本工程的构建脚本、CI 流程与集成方案由 AI（Operit）辅助编写与验证。
   刷机与使用风险自负。

5. **刷机风险**：自编译 GKI 未使用厂商私钥签名，且公开源码版本（6.6.56）可能不等于真机固件
   版本（6.6.89），AVB / vermagic 不匹配时刷入可能无法开机。请在解锁引导加载程序并理解风险
   后操作。
