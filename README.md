# RSSH All-Platform Auto Builder 🛡️
[![Build Status](https://github.com/helloshu/rssh-auto-build/actions/workflows/build-upstream.yml/badge.svg)](https://github.com/helloshu/rssh-auto-build/actions)

An automated, secure, and transparent standalone builder for **RSSH** (Tauri 2 + Svelte 5 + Rust). 

This repository does not host the core source code; instead, it utilizes GitHub Actions to monitor the upstream repository, compile everything safely from source in clean cloud environments, and automatically publish the binaries to its own Releases.

---

## 🔍 Why This Repository Exists?

To mitigate **supply chain attacks** and security risks associated with downloading pre-compiled binaries from unverified or third-party pipelines. By building directly from the raw source code on trusted GitHub-hosted runners, you can ensure that the final applications are 100% clean and tamper-proof.

- **Upstream Project**: [shihuili1218/rssh](https://github.com/shihuili1218/rssh)
- **Tech Stack**: Tauri 2 + Svelte 5 + Rust (russh 0.60.1)

---

## ✨ Features

* **🔒 Supply-Chain Safe**: Compiles entirely in pure, ephemeral GitHub virtual environments.
* **🔄 Fully Automated Synchronicity**: A daily cron job automatically checks for new Git tags/releases from the upstream repository.
* **🔧 Auto Version Patching**: Dynamically fixes and bumps internal version configuration mismatches (`0.0.1` vs tag version) before compiling.
* **🌍 True Cross-Platform Releases**:
  * **Linux**: Native binary, `.deb`, `.rpm`, and standalone `.AppImage`.
  * **Windows**: `rssh.exe` (with automatic NSIS setup packaging and `WebView2Loader.dll`).
  * **Android**: Optimized multi-architecture debug APKs (`arm64-v8a` & `universal`) compiled via `cargo-ndk`.
  * **macOS**: Universal `.dmg` installers supporting both Intel and Apple Silicon (M1/M2/M3) chips.

---

## 🚀 How It Works

1. **Check**: The workflow runs daily (or via manual trigger) to fetch the latest upstream tag.
2. **Verify**: It checks if that specific tag already exists in this repository's Releases. If it's already there, the job skips to save resources.
3. **Build (Ubuntu Runner)**: Sets up Node 22, Rust, MinGW-w64, and Android SDK/NDK to compile Linux, Windows, and Android artifacts.
4. **Build (macOS Runner)**: Provisions a macOS environment to build dual-architecture Universal Mac apps.
5. **Publish**: Bundles all outputs and uploads them seamlessly to a brand-new GitHub Release matching the upstream version.

---

## 🛠️ Manual Trigger

If you know the upstream author just pushed an update and you don't want to wait for the daily automation schedule:
1. Navigate to the **Actions** tab of this repository.
2. Select **Auto Build Upstream RSSH (All Platforms)** from the left sidebar.
3. Click the **Run workflow** dropdown button on the right and confirm.

---

> **Disclaimer**: This is a personal security utility builder. All upstream code rights and licenses belong to the original author of RSSH.
