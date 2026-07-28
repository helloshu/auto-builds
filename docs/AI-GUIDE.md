# AI Agent Guide: Workflow Extension Specification

> **Target Audience:** AI Assistants, Coding Agents (Gemini, Claude, GPT, Cursor, etc.)
> **Task Target:** Follow this guide when requested to "add a new auto-build workflow for [AppX]".

---

## Core Principles

1. **Strict Upstream Alignment**: Do NOT alter or reinvent the application's build steps, dependency installation, or compilation commands (e.g., `npm ci`, `cargo build`, `electron-builder`). Always mirror the official `.github/workflows/` scripts from the target upstream repository.
2. **Cross-Repo Adaptations**: Only apply the following 3 necessary adaptations:
   - **Source Checkout**:
     ```yaml
     - name: Checkout upstream source
       uses: actions/checkout@v4
       with:
         repository: 'upstream-owner/upstream-repo'
         ref: ${{ needs.check-version.outputs.latest_tag }}
         path: 'app-src'
     ```
   - **Working Directory**: Add `working-directory: ./app-src` to all compilation and build steps.
   - **Source Code Archiving**: Include a step (`Archive source code`) to package clean upstream source code into a `.tar.gz` archive (e.g., `[app-name]-[version]-source.tar.gz`) alongside binary releases.
   - **Version Checking & Release**: Use a `check-version` job to compare upstream tags against local releases, and publish via `softprops/action-gh-release`.

---

## Standard Execution Workflow

1. **File Naming**: Create `.github/workflows/build-[app-name].yml` (lowercase, hyphen-separated, e.g., `build-demo.yml`).
2. **Template Reference**: Refer to [`.github/workflows/template-app.yml.example`](../.github/workflows/template-app.yml.example).
3. **Update README**: Register the new application entry and status badge in `README.md`.
