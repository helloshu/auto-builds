# AI Agent Guide: 自动编译中心扩展规范 (中文版)

> **目标受众:** AI 助手、Coding Agents (Gemini, Claude, GPT, Cursor 等)
> **任务目标:** 当用户要求“帮我在此仓库增加 [AppX] 应用的自动编译”时，请严格按照本文档规定步骤与规范执行。

---

## 核心原则

1. **严格看齐上游**：不要自行改造或重新发明目标应用的编译、环境依赖安装、构建命令（如 `npm ci`, `cargo build`, `electron-builder` 等）。必须优先参考上游官方仓库 `.github/workflows/` 下自带的 build/release 脚本。
2. **三点跨仓库适配**：仅在上游工作流的基础上做以下 3 处必要适配：
   - **源码 Checkout 路径适配**：
     ```yaml
     - name: Checkout upstream source
       uses: actions/checkout@v4
       with:
         repository: 'upstream-owner/upstream-repo'
         ref: ${{ needs.check-version.outputs.latest_tag }}
         path: 'app-src'
     ```
   - **工作目录适配**：所有编译打包 Step 加上 `working-directory: ./app-src`。
   - **源码压缩归档打包**：添加一个步骤（`Archive source code`），将上游干净源码打包为 `.tar.gz` 压缩包（如 `[app-name]-[version]-source.tar.gz`），随二进制/安装包产物一并发布至 GitHub Release。
   - **版本检测与 Release 汇总发布**：使用 `check-version` Job 对比上游 Tag 与本仓库 Release，并通过 `softprops/action-gh-release` 汇总发布。

---

## 标准执行步骤

1. **命名规范**：在 `.github/workflows/` 下新建 `build-[app-name].yml`（全部小写，短横线命名，如 `build-demo.yml`）。
2. **复制与适配模板**：可参考模版 [`.github/workflows/template-app.yml.example`](../.github/workflows/template-app.yml.example)。
3. **更新 README 表格**：在仓库主页 `README.md` 与 `README_ZH.md` 的 [📦 已集成的应用 (Apps Status)] 表格中新增一行对应的应用与 Badge。
