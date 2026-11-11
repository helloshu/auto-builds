# auto-builds — Agent Guidelines

`helloshu/auto-builds` 是公开的跨平台自动化构建与开源软件分发中心。在修改本仓库前请严格遵守以下工程与安全规范：

## 1. 公开仓库零敏感信息红线（必检）

- 本仓库包含两类工作流：
  1. **公开开源项目构建**（如 `RSSH`、`LibChecker`、`Round Sync`、`Shizuku`、`OneDriveGUI`、`DSH NEXT`、`DSH Go` 等），构建产物直接发布在本仓 GitHub Releases。
  2. **外部私有金库协同构建**（`build-passvault.yml`、`build-notesync.yml`、`build-cloudbox-android.yml`、`build-cloudbox-ios.yml`），通过 `.github/scripts/vault-api.sh` 与 `.github/scripts/transit-crypto.sh` 调度。
- **严禁**在本仓库的任何文件、注释或 Git Commit Message 中写入私有金库项目的真实上游仓库名、应用包名、内部客户端凭据或密钥。
- **每次提交前必须在仓库根目录运行脱敏检查脚本，确保退出码为 `0`**：
  ```bash
  bash .github/scripts/check-clean-public.sh
  ```

## 2. 安全构建与隔离签名架构

- **固定 40 位提交 SHA**：拉取第三方上游代码时，必须先将 Release Tag 解析为 40 位不可变 Commit SHA 再检出，并在独立干净任务中打包 `*-source.tar.gz` 源码归档。
- **Android 隔离签名**：运行第三方 Gradle 脚本的构建 Job **严禁**挂载正式签名 Keystore Secrets；构建 Job 仅产出未签名或一次性占位签名 APK，正式签名必须在独立的最小环境 `sign-android` / `sign-and-publish` Job 中通过 `apksigner` 完成并校验签名指纹。
- **GitHub Actions Runner 注意事项**：macOS 构建请使用 `macos-15` / `macos-latest`（`macos-14` 已下线）；涉及外部 Gradle / Maven 大体积依赖下载的步骤建议配置有限次数重试以规避偶发 `502/503`。

## 3. 双语文档与 Flatpak 联动规范

- 新增或调整公开构建项目时，必须**同步更新**英文 [`README.md`](README.md) 与中文 [`README_ZH.md`](README_ZH.md) 的应用列表及架构说明。
- 已接入 `helloshu/flatpak-hub` 的 Linux 应用（如 `RSSH`、`DSH NEXT`、`OneDriveGUI`）在发布 Release 后会通过 `repository_dispatch`（`event_type: upstream-release`）触发 Flatpak 软件源自动更新。
