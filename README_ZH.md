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

---

## 💡 使用说明

- **错峰定时触发**：工作流每天错峰检测上游版本，避免 GitHub Actions 整点拥堵。
- **手动触发**：可以在 GitHub Actions 页面选择具体的工作流手动点击 **Run workflow** 触发构建（可传入 `force` 重新编译或指定 `tag`）。
- **干净源码归档**：每个 Release 都包含由固定上游提交通过 `git archive` 生成的 `[应用]-[版本]-source.tar.gz`，不会混入构建结果或构建时修改的文件。
- **发布完整性**：创建 Release 前会核对精确产物清单、生成 `SHA256SUMS`，并发布 GitHub 构建来源证明。
- **最小权限**：构建 Job 只有只读权限，外部 Checkout 不持久化凭据，只有最终发布 Job 获得写入与证明权限。

---

## 📄 版权与声明

- 本仓库构建产物由 GitHub Actions 自动编译生成，仅供测试与个人参考。
- 所有上游项目的代码版权、商标及授权协议均归各自的原作者所有。
