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

- **错峰定时触发**：工作流每天错峰检测上游版本（FlowZ 03:07、RSSH 03:17），避免 GitHub Actions 整点拥堵。
- **手动触发**：可以在 GitHub Actions 页面选择具体的工作流手动点击 **Run workflow** 触发构建（可传入 `force` 重新编译或指定 `tag`）。
- **干净源码归档**：每个 Release 都包含由固定上游提交通过 `git archive` 生成的 `[应用]-[版本]-source.tar.gz`，不会混入构建结果或构建时修改的文件。
- **发布完整性**：创建 Release 前会核对精确产物清单、生成 `SHA256SUMS`，并发布 GitHub 构建来源证明。
- **最小权限**：构建 Job 只有只读权限，外部 Checkout 不持久化凭据，只有最终发布 Job 获得写入与证明权限。

### Release 标签规范

本仓库使用 `<应用 ID>-<上游 Tag>` 作为发布标签，例如：

- FlowZ `v4.3.0` → `flowz-v4.3.0`
- RSSH `v0.2.15` → `rssh-v0.2.15`

每个工作流按自己的完整发布标签判断版本是否已经构建，不依赖整个仓库唯一的 `releases/latest`。新增应用时，请复制 [工作流模板](.github/workflows/template-app.yml.example)，并设置一个唯一的小写 `APP_ID`。

### Gear Lever 更新

由于 GitHub 每个仓库只能有一个 Latest Release，在 Gear Lever 中使用本仓库时需要开启 **Allow pre-releases**，让它扫描多个 Release，再填写应用专属文件名模式，例如 `FlowZ-*-linux-x86_64.AppImage` 或 `rssh-*-linux-x86_64.AppImage`。

### RSSH 移动端与 IDE 插件构建

- Android Release 必须使用一套长期不变的签名。请在仓库 Actions Secrets 中配置 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。正式密钥只会在不检出、不运行上游代码的隔离签名 Job 中使用。
- iOS 产物是 **未签名的 iPhoneOS arm64 IPA**，其中是真机二进制而非模拟器二进制；安装前仍需使用你自己的证书/描述文件或侧载工具进行签名。
- JetBrains 插件会分别为 macOS aarch64、macOS x86_64、Linux x86_64 和 Windows x86_64 构建，因为每个插件都内置与平台和架构匹配的原生 `rssh-server`。

---

## 📄 版权与声明

- 本仓库构建产物由 GitHub Actions 自动编译生成，仅供测试与个人参考。
- 所有上游项目的代码版权、商标及授权协议均归各自的原作者所有。
