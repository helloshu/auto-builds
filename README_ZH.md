# Auto-Builds (自动编译打包中心)

这是一个用于自动同步上游开源软件最新发布 Tag、跨平台编译打包并发布至 GitHub Releases 的工具仓库。

---

## 📦 已集成的应用 (Apps Status)

| 应用名称 | 说明 / 架构 | 上游源码仓库 | 编译工作流 | 构建状态 |
| :--- | :--- | :--- | :--- | :--- |
| **RSSH** | Rust / Tauri 跨平台 Terminal / SSH 客户端 | [shihuili1218/rssh](https://github.com/shihuili1218/rssh) | [`build-rssh.yml`](.github/workflows/build-rssh.yml) | ![RSSH Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-rssh.yml/badge.svg) |
| **FlowZ** | Electron 工作流桌面端 | [dododook/FlowZ](https://github.com/dododook/FlowZ) | [`build-flowz.yml`](.github/workflows/build-flowz.yml) | ![FlowZ Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-flowz.yml/badge.svg) |
| **MuffinStore** | iOS App Store 降级 / 安装工具 (TrollStore) | [mineek/MuffinStore](https://github.com/mineek/MuffinStore) | [`build-muffinstore.yml`](.github/workflows/build-muffinstore.yml) | ![MuffinStore Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-muffinstore.yml/badge.svg) |
| **Geranium** | iOS 定位模拟、守护进程管理、清理与监管工具 (TrollStore) | [c22dev/Geranium](https://github.com/c22dev/Geranium) | [`build-geranium.yml`](.github/workflows/build-geranium.yml) | ![Geranium Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-geranium.yml/badge.svg) |
| **ChatGBeFree** | iOS 越狱插件 — 绕过 ChatGPT 强制升级限制 | [liamschwie/ChatGBeFree](https://github.com/liamschwie/ChatGBeFree) | [`build-chatgbefree.yml`](.github/workflows/build-chatgbefree.yml) | ![ChatGBeFree Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-chatgbefree.yml/badge.svg) |
| **Asspp** | Swift 多区域 App Store 管理工具 (iOS + macOS) | [Lakr233/Asspp](https://github.com/Lakr233/Asspp) | [`build-asspp.yml`](.github/workflows/build-asspp.yml) | ![Asspp Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-asspp.yml/badge.svg) |
| **OPPO Health Export** | Android LSPosed 模块 — 导出加密健康数据对接 AI Agent | [foxlesbiao/oppo-health-export](https://github.com/foxlesbiao/oppo-health-export) | [`build-oppo-health-export.yml`](.github/workflows/build-oppo-health-export.yml) | ![OPPO Health Export Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-oppo-health-export.yml/badge.svg) |
| **DSH NEXT** | DeepSeek Harness 桌面客户端 (Electron, Next 通道; Linux x64/arm64 AppImage/deb, Windows x64, macOS 通用包) | [anywhere-labs/dsh-desktop](https://github.com/anywhere-labs/dsh-desktop) | [`build-dsh-desktop.yml`](.github/workflows/build-dsh-desktop.yml) | ![DSH Desktop Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-dsh-desktop.yml/badge.svg) |
| **OneDriveGUI** | 支持多账号的 OneDrive Linux 图形客户端 (Python / PySide6; Linux x64 AppImage, deb, wheel) | [bpozdena/OneDriveGUI](https://github.com/bpozdena/OneDriveGUI) | [`build-onedrivegui.yml`](.github/workflows/build-onedrivegui.yml) | ![OneDriveGUI Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-onedrivegui.yml/badge.svg) |
| **DSH Go** | 内置 Linux 运行时的 DeepSeek Harness 移动端客户端 (Flutter; Android arm64 & x64 APK) | [ccch1mneyyy/dsh-Go](https://github.com/ccch1mneyyy/dsh-Go) | [`build-dsh-go.yml`](.github/workflows/build-dsh-go.yml) | ![DSH Go Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-dsh-go.yml/badge.svg) |
| **c001apk** | 轻量级 Flutter 第三方酷安客户端 (Android 3 架构, Windows x64, Linux x64, iOS 未签名 IPA) | [TG-Twilight/c001apk](https://github.com/TG-Twilight/c001apk) | [`build-c001apk.yml`](.github/workflows/build-c001apk.yml) | ![c001apk Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-c001apk.yml/badge.svg) |
| **Orion Store** | 原生 Kotlin / Jetpack Compose 开源 Android 应用商店客户端 | [RookieEnough/Orion-Store](https://github.com/RookieEnough/Orion-Store) | [`build-orion-store.yml`](.github/workflows/build-orion-store.yml) | ![Orion Store Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-orion-store.yml/badge.svg) |
| **APK Signer Pro** | 原生 Kotlin / Jetpack Compose Android APK 签名与包管理工具箱 | [ameermuawiya/apk-signer-pro](https://github.com/ameermuawiya/apk-signer-pro) | [`build-apk-signer-pro.yml`](.github/workflows/build-apk-signer-pro.yml) | ![APK Signer Pro Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-apk-signer-pro.yml/badge.svg) |
| **LibChecker** | 原生 Kotlin Android 应用架构与原生库查看工具 (FOSS 版) | [LibChecker/LibChecker](https://github.com/LibChecker/LibChecker) | [`build-libchecker.yml`](.github/workflows/build-libchecker.yml) | ![LibChecker Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-libchecker.yml/badge.svg) |
| **Round Sync** | 基于 Rclone 的 Android 云存储管理与同步客户端 (OSS 版, 4 架构 + universal) | [newhinton/Round-Sync](https://github.com/newhinton/Round-Sync) | [`build-round-sync.yml`](.github/workflows/build-round-sync.yml) | ![Round Sync Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-round-sync.yml/badge.svg) |
| **Shizuku** | 通过 ADB / Root 调用系统 API 的 Android 服务框架 (内置 `rish` 与原生启动器) | [RikkaApps/Shizuku](https://github.com/RikkaApps/Shizuku) | [`build-shizuku.yml`](.github/workflows/build-shizuku.yml) | ![Shizuku Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-shizuku.yml/badge.svg) |

---

## 💡 使用说明

- **错峰定时触发**：工作流每天错峰检测上游版本，避免 GitHub Actions 整点拥堵。
- **手动触发**：可以在 GitHub Actions 页面选择具体的工作流手动点击 **Run workflow** 触发构建（可传入 `force` 重新编译或指定 `tag`）。
- **干净源码归档**：每个 Release 都包含由固定上游提交通过 `git archive` 生成的 `[应用]-[版本]-source.tar.gz`，不会混入构建结果或构建时修改的文件。
- **发布完整性**：创建 Release 前会核对精确产物清单、生成 `SHA256SUMS`，并发布 GitHub 构建来源证明。
- **最小权限**：构建 Job 只有只读权限，外部 Checkout 不持久化凭据，只有最终发布 Job 获得写入与证明权限。

### Linux AppImage 兼容性

RSSH 的 Linux x86_64 AppImage 会在构建后针对 Debian 13 + KDE Wayland + Mesa 25 进行定向运行时修整：使用宿主图形栈、隔离不兼容的 GIO 模块，并保持 Wayland 优先、X11 回退。其他发行版、桌面环境和图形栈不作保证；如果系统环境不匹配，请改用原生 `.deb` 或其他构建产物。

---

## 📄 版权与声明

- 本仓库构建产物由 GitHub Actions 自动编译生成，仅供测试与个人参考。
- 所有上游项目的代码版权、商标及授权协议均归各自的原作者所有。
