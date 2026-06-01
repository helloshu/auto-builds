# RSSH 全平台自动构建器 🛡️
[![Build Status](https://github.com/helloshu/rssh-auto-build/actions/workflows/build-upstream.yml/badge.svg)](https://github.com/helloshu/rssh-auto-build/actions)

一个针对 **RSSH** (Tauri 2 + Svelte 5 + Rust) 项目的自动化、安全且透明的独立构建器。

本仓库本身不包含任何核心业务源码，而是利用 GitHub Actions 定时监控上游仓库。一旦发现新版本，它会在纯净的云端环境中直接从源码安全地进行编译，并自动将全平台产物发布到本仓库的 Releases 中。

---

## 🔍 为什么存在这个仓库？

为了彻底防范**供应链攻击**，以及下载未经审查或第三方流水线生成的预编译二进制文件所带来的潜在安全风险。通过在受信任的 GitHub 托管运行器 (Runners) 上直接从原始源码进行透明编译，可以确保最终交付的应用程序 100% 纯净且未被篡改。

- **上游项目**: [shihuili1218/rssh](https://github.com/shihuili1218/rssh)
- **技术栈**: Tauri 2 + Svelte 5 + Rust (russh 0.60.1)

---

## ✨ 功能特点

* **🔒 供应链级安全**: 完全在纯净、临时的 GitHub 虚拟环境中进行编译，杜绝本地污染。
* **🔄 全自动同步**: 每日定时任务（Cron Job）会自动检查上游仓库是否有新的 Git Tag 或 Release。
* **🔧 自动修正版本号**: 在编译前，动态修复并升级内部配置文件中未同步的版本号（例如将源码写死的 `0.0.1` 修正为实际的 Tag 版本） 。
* **🌍 真正的跨平台发布**:
  * **Linux**: 原生二进制、`.deb`、`.rpm` 以及独立的 `.AppImage` 格式。
  * **Windows**: `rssh.exe`（支持自动化的 NSIS 安装包打包以及必要的 `WebView2Loader.dll` 依赖） 。
  * **Android**: 通过 `cargo-ndk` 编译、优化过的多架构调试版 APK（包括 `arm64-v8a` 和 `universal` 架构） 。
  * **macOS**: 支持双架构的 Universal `.dmg` 安装包，同时完美兼容 Intel 和 Apple Silicon (M1/M2/M3) 芯片的 Mac 电脑。

---

## 🚀 它是如何工作的

1. **检查 (Check)**: 工作流每日定时运行（或通过手动触发），获取最新的上游 Tag。
2. **验证 (Verify)**: 检查该特定 Tag 是否已存在于本仓库的 Releases 中。如果已存在，则说明已是最新，跳过后续步骤以节省资源。
3. **构建 (Ubuntu 运行器)**: 自动配置 Node 22、Rust、MinGW-w64 以及完整的 Android SDK/NDK，以编译 Linux、Windows 和 Android 的全端产物 。
4. **构建 (macOS 运行器)**: 启动苹果云端虚拟环境，构建支持双架构的 Universal Mac 应用程序。
5. **发布 (Publish)**: 打包所有平台的编译产物，并无缝上传到与上游版本号一致的全新 GitHub Release 中。

---

## 🛠️ 手动触发

如果你知道上游作者刚刚推送了更新，并且你不想等待每日的自动定时任务：
1. 导航到本仓库顶部的 **Actions** 标签页。
2. 在左侧边栏中选择 **Auto Build Upstream RSSH (All Platforms)**。
3. 点击页面右侧的 **Run workflow** 下拉按钮，然后点击绿色的 **Run workflow** 确认触发。

---

> **免责声明 (Disclaimer)**: 本项目仅作为一个个人安全辅助构建工具。所有上游代码的权利和许可证均属于 RSSH 的原始作者 。
