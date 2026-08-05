# AI Agent Guide：自动编译中心扩展规范

> 新增应用自动构建工作流时必须遵守本规范。

## 必需设计

1. **构建固定的上游提交**
   - 使用只读 `github.token` 查询 GitHub API。
   - Tag 回退查询必须处理分页，并从有效的稳定语义版本中选择最高版本。
   - 把选中的 Tag 解析为 40 位提交 SHA。
   - 所有 Checkout 和源码归档都使用该 SHA，不直接构建可移动 Tag。

2. **最小权限**
   - 工作流级权限设置为 `permissions: contents: read`。
   - 只有最终发布 Job 获得 `contents: write`、`id-token: write`、`attestations: write`。
   - 所有外部 Checkout 必须设置 `persist-credentials: false`。
   - 工作流输入和 Secret 必须通过 Step 的 `env` 传入，禁止直接展开到 shell 源码中。

3. **所有 Action 固定完整提交 SHA**

   ```yaml
   - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
     with:
       repository: upstream-owner/upstream-repo
       ref: ${{ needs.check-version.outputs.upstream_sha }}
       path: app-src
       persist-credentials: false
   ```

4. **隔离源码和发布产物**
   - 在独立 Ubuntu Job 中用 `git archive HEAD` 创建源码包，禁止归档构建后的工作树。
   - 构建 Job 只把批准发布的二进制复制到 `release-assets/`。
   - 禁止上传通用的 `dist/*`、`target/*` 或 `build/*` 目录。
   - 上传前必须精确检查文件名、架构、数量和签名状态。

5. **所有必需构建成功后才能发布**
   - 发布 Job 禁止使用 `always()`。
   - `needs` 必须包含所有必需的构建和签名 Job。
   - 发布前核对精确清单，同时拒绝缺失文件和额外文件。
   - 生成 `SHA256SUMS` 和构建来源证明，并设置 `fail_on_unmatched_files: true`。

6. **错峰与并发控制**
   - 每个应用使用不同的 cron 分钟数，避免第 `0` 分钟。
   - 添加应用专属 `concurrency`，并设置 `cancel-in-progress: false`。

7. **与上游构建保持一致**
   - 从上游官方构建/发布工作流和依赖锁文件开始适配。
   - 只调整 Checkout 路径、安全边界、产物收集、签名隔离以及本仓库的 Release 命名。

## Release 与命名规则

- 工作流文件：`.github/workflows/build-[应用-id].yml`。
- `APP_ID`：全仓库唯一、小写、短横线分隔。
- `upstream_tag` 保存原始上游标签，`upstream_sha` 保存解析后的固定提交。
- `release_tag` 使用 `<应用-id>-<上游-tag>`。
- 查询经过 URL 编码的 `releases/tags/<release_tag>`，禁止用仓库级 Latest Release 比较应用版本。
- 每个二进制文件名都必须包含应用、版本、平台和架构。
- 从 [`.github/workflows/template-app.yml.example`](../.github/workflows/template-app.yml.example) 开始适配，并替换其中故意失败的占位构建步骤。

## 移动端签名

- 禁止用临时密钥签名最终发布的 Android APK。正式 keystore 存入 Actions Secrets，并在不 Checkout、不执行上游代码的隔离 Job 中完成签名。
- 未签名 iOS IPA 必须包含 `iphoneos` arm64 二进制、不包含 `_CodeSignature`，文件名和说明必须明确标注未签名。禁止把模拟器应用伪装成 IPA 发布。

最后同步更新中英文 README，并运行 YAML 解析、actionlint、ShellCheck 和 `git diff --check`。
