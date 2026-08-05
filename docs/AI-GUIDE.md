# AI Agent Guide: Workflow Extension Specification

> Follow this guide when adding a new application to the auto-build hub.

## Required Design

1. **Track an immutable upstream commit**
   - Query GitHub with the read-only `github.token`.
   - Paginate the tag fallback and select the highest stable semantic version.
   - Resolve the selected tag to a 40-character commit SHA.
   - Use that SHA, not a mutable tag, for every checkout and source archive.

2. **Use least privilege**
   - Set workflow-level `permissions: contents: read`.
   - Give `contents: write`, `id-token: write`, and `attestations: write` only to the final release job.
   - Every external checkout must set `persist-credentials: false`.
   - Pass workflow inputs and secrets through step `env`; never interpolate them directly into shell source.

3. **Pin every Action to a full commit SHA**

   ```yaml
   - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
     with:
       repository: upstream-owner/upstream-repo
       ref: ${{ needs.check-version.outputs.upstream_sha }}
       path: app-src
       persist-credentials: false
   ```

4. **Keep sources and release assets isolated**
   - Create the source archive in a separate Ubuntu job with `git archive HEAD`; never archive a post-build working tree.
   - Build jobs must copy only approved binaries into `release-assets/`.
   - Never upload a generic project directory such as `dist/*`, `target/*`, or `build/*`.
   - Add exact file-name, architecture, count, and signature checks before uploading.

5. **Gate the Release on all required jobs**
   - Do not use `always()` on a publishing job.
   - The final job must list every required build and signing job in `needs`.
   - Verify an exact manifest and reject both missing and unexpected files.
   - Generate `SHA256SUMS`, create a build-provenance attestation, and set `fail_on_unmatched_files: true`.

6. **Make schedules and concurrency deliberate**
   - Assign every application a different cron minute; avoid minute `0`.
   - Add an application-specific `concurrency` group with `cancel-in-progress: false`.

7. **Stay aligned with upstream**
   - Start from the upstream project's official build/release workflow and dependency lockfiles.
   - Only adapt checkout paths, security boundaries, artifact collection, signing isolation, and this hub's release naming.

## Release and Naming Rules

- Workflow file: `.github/workflows/build-[app-id].yml`.
- `APP_ID`: unique, lowercase, hyphen-separated.
- Preserve the upstream value as `upstream_tag` and its resolved commit as `upstream_sha`.
- Build `release_tag` as `<app-id>-<upstream-tag>`.
- Check the exact encoded `releases/tags/<release_tag>` endpoint; do not compare against the repository-wide latest Release.
- Name every binary with application, version, platform, and architecture.
- Use [`.github/workflows/template-app.yml.example`](../.github/workflows/template-app.yml.example) as the starting point and replace its intentionally failing placeholder build step.

## Mobile Signing

- Never generate a throwaway key for a published Android APK. Keep the production keystore in Actions secrets and use it in an isolated signing job that does not checkout or execute upstream code.
- An unsigned iOS IPA must contain an `iphoneos` arm64 binary, have no `_CodeSignature`, and be clearly named and documented as unsigned. Simulator bundles must never be published as IPAs.

Finally, update both README files and run YAML parsing, actionlint, ShellCheck, and `git diff --check`.
