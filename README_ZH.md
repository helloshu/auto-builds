# Auto-Builds (自动编译打包中心)

这是一个用于自动同步上游开源软件最新发布 Tag、跨平台编译打包并发布至 GitHub Releases 的工具仓库。

---

## 📦 已集成的应用 (Apps Status)

| 应用名称 | 说明 / 架构 | 上游源码仓库 | 编译工作流 | 构建状态 |
| :--- | :--- | :--- | :--- | :--- |
| **RSSH** | Rust / Tauri 跨平台 Terminal / SSH 客户端 | [shihuili1218/rssh](https://github.com/shihuili1218/rssh) | [`build-rssh.yml`](.github/workflows/build-rssh.yml) | ![RSSH Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-rssh.yml/badge.svg) |
| **FlowZ** | Electron 工作流桌面端 | [dododook/FlowZ](https://github.com/dododook/FlowZ) | [`build-flowz.yml`](.github/workflows/build-flowz.yml) | ![FlowZ Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-flowz.yml/badge.svg) |

---

## 💡 使用说明

- **定时触发**：工作流每天在北京时间 03:00 (19:00 UTC) 自动检测上游是否有新版本发布。
- **手动触发**：可以在 GitHub Actions 页面选择具体的工作流手动点击 **Run workflow** 触发构建（可传入 `force` 重新编译或指定 `tag`）。

---

## 📄 版权与声明

- 本仓库构建产物由 GitHub Actions 自动编译生成，仅供测试与个人参考。
- 所有上游项目的代码版权、商标及授权协议均归各自的原作者所有。
