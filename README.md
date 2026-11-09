# Auto-Builds

An automated workflow hub designed to track upstream open-source releases, trigger cross-platform builds, and publish GitHub Releases.

---

## 📦 Supported Applications

| Application | Description / Architecture | Upstream Repository | Workflow | Status |
| :--- | :--- | :--- | :--- | :--- |
| **RSSH** | Rust / Tauri Cross-platform Terminal & SSH Client | [shihuili1218/rssh](https://github.com/shihuili1218/rssh) | [`build-rssh.yml`](.github/workflows/build-rssh.yml) | ![RSSH Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-rssh.yml/badge.svg) |
| **FlowZ** | Electron Workflow Desktop Client | [dododook/FlowZ](https://github.com/dododook/FlowZ) | [`build-flowz.yml`](.github/workflows/build-flowz.yml) | ![FlowZ Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-flowz.yml/badge.svg) |
| **MuffinStore** | iOS App Store downgrader / installer (TrollStore) | [mineek/MuffinStore](https://github.com/mineek/MuffinStore) | [`build-muffinstore.yml`](.github/workflows/build-muffinstore.yml) | ![MuffinStore Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-muffinstore.yml/badge.svg) |
| **Geranium** | iOS LocSim, Daemon Manager, Cleaner & Superviser (TrollStore) | [c22dev/Geranium](https://github.com/c22dev/Geranium) | [`build-geranium.yml`](.github/workflows/build-geranium.yml) | ![Geranium Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-geranium.yml/badge.svg) |
| **ChatGBeFree** | iOS jailbreak tweak — bypass ChatGPT forced sunset upgrade | [liamschwie/ChatGBeFree](https://github.com/liamschwie/ChatGBeFree) | [`build-chatgbefree.yml`](.github/workflows/build-chatgbefree.yml) | ![ChatGBeFree Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-chatgbefree.yml/badge.svg) |
| **Asspp** | Swift multi-region App Store manager (iOS + macOS) | [Lakr233/Asspp](https://github.com/Lakr233/Asspp) | [`build-asspp.yml`](.github/workflows/build-asspp.yml) | ![Asspp Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-asspp.yml/badge.svg) |
| **OPPO Health Export** | Android LSPosed module — export encrypted health data to AI agents | [foxlesbiao/oppo-health-export](https://github.com/foxlesbiao/oppo-health-export) | [`build-oppo-health-export.yml`](.github/workflows/build-oppo-health-export.yml) | ![OPPO Health Export Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-oppo-health-export.yml/badge.svg) |
| **DSH NEXT** | Electron desktop client for DeepSeek Harness (Next channel; Linux x64/arm64 (AppImage, deb), Windows x64, macOS universal) | [anywhere-labs/dsh-desktop](https://github.com/anywhere-labs/dsh-desktop) | [`build-dsh-desktop.yml`](.github/workflows/build-dsh-desktop.yml) | ![DSH Desktop Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-dsh-desktop.yml/badge.svg) |
| **OneDriveGUI** | Python / PySide6 Linux GUI for OneDrive with multi-account support (Linux x64 AppImage, deb, wheel) | [bpozdena/OneDriveGUI](https://github.com/bpozdena/OneDriveGUI) | [`build-onedrivegui.yml`](.github/workflows/build-onedrivegui.yml) | ![OneDriveGUI Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-onedrivegui.yml/badge.svg) |
| **DSH Go** | Flutter Android client for DeepSeek Harness with bundled Linux runtime (Android arm64 & x64 APK) | [ccch1mneyyy/dsh-Go](https://github.com/ccch1mneyyy/dsh-Go) | [`build-dsh-go.yml`](.github/workflows/build-dsh-go.yml) | ![DSH Go Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-dsh-go.yml/badge.svg) |
| **c001apk** | Lightweight Flutter CoolApk client (Android 3 ABIs, Windows x64, Linux x64, iOS unsigned IPA) | [TG-Twilight/c001apk](https://github.com/TG-Twilight/c001apk) | [`build-c001apk.yml`](.github/workflows/build-c001apk.yml) | ![c001apk Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-c001apk.yml/badge.svg) |
| **Orion Store** | Native Kotlin / Jetpack Compose open-source Android app store client | [RookieEnough/Orion-Store](https://github.com/RookieEnough/Orion-Store) | [`build-orion-store.yml`](.github/workflows/build-orion-store.yml) | ![Orion Store Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-orion-store.yml/badge.svg) |
| **APK Signer Pro** | Native Kotlin / Jetpack Compose Android APK signing & package toolkit | [ameermuawiya/apk-signer-pro](https://github.com/ameermuawiya/apk-signer-pro) | [`build-apk-signer-pro.yml`](.github/workflows/build-apk-signer-pro.yml) | ![APK Signer Pro Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-apk-signer-pro.yml/badge.svg) |
| **LibChecker** | Native Kotlin Android app library & architecture inspector (FOSS edition) | [LibChecker/LibChecker](https://github.com/LibChecker/LibChecker) | [`build-libchecker.yml`](.github/workflows/build-libchecker.yml) | ![LibChecker Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-libchecker.yml/badge.svg) |
| **Round Sync** | Android Rclone cloud storage manager & sync client (OSS edition, 4 ABIs + universal) | [newhinton/Round-Sync](https://github.com/newhinton/Round-Sync) | [`build-round-sync.yml`](.github/workflows/build-round-sync.yml) | ![Round Sync Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-round-sync.yml/badge.svg) |
| **Shizuku** | Android system API access framework via ADB / root (with bundled `rish` & native starter) | [RikkaApps/Shizuku](https://github.com/RikkaApps/Shizuku) | [`build-shizuku.yml`](.github/workflows/build-shizuku.yml) | ![Shizuku Build Status](https://github.com/helloshu/auto-builds/actions/workflows/build-shizuku.yml/badge.svg) |

---

## 💡 Usage

- **Scheduled Triggers**: Workflows use staggered daily schedules to avoid GitHub Actions' top-of-hour congestion.
- **Manual Triggers**: Manually trigger builds on demand via the GitHub Actions UI with custom options (`force` re-builds or specific tags).
- **Clean Source Archives**: Every Release includes an `[app]-[version]-source.tar.gz` created with `git archive` from the immutable upstream commit, without build outputs or modified files.
- **Release Integrity**: Workflows validate an exact artifact manifest, generate `SHA256SUMS`, and publish GitHub build-provenance attestations before creating a Release.
- **Least Privilege**: Build jobs are read-only, external checkouts do not persist credentials, and only the final release job receives write and attestation permissions.

### Linux AppImage compatibility

The RSSH Linux x86_64 AppImage receives a targeted post-build runtime repair for Debian 13 on KDE Wayland with Mesa 25. The repair keeps the host graphics stack, isolates incompatible GIO modules, and preserves Wayland-first/X11-fallback behavior. Other distributions, desktop environments, and graphics stacks are not guaranteed; use the native `.deb` or another build when this target does not match your system.

---

## 📄 License & Disclaimer

- Build artifacts generated by this repository are automatically compiled via GitHub Actions for testing and personal reference.
- All original copyrights, trademarks, and code licenses belong to their respective upstream maintainers.
