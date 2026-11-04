#!/usr/bin/env python3
"""Verify that an unsigned iOS .ipa contains a device arm64 Mach-O binary and no _CodeSignature."""
from pathlib import Path
import plistlib
import struct
import sys
import zipfile

CPU_TYPE_ARM64 = 0x0100000C
MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE
FAT_MAGIC = 0xCAFEBABE
FAT_CIGAM = 0xBEBAFECA


def has_arm64_slice(header: bytes) -> bool:
    if len(header) < 32:
        return False
    magic_be = struct.unpack(">I", header[:4])[0]
    magic_le = struct.unpack("<I", header[:4])[0]
    if magic_le == MH_MAGIC_64:
        cputype = struct.unpack("<I", header[4:8])[0]
        return cputype == CPU_TYPE_ARM64
    if magic_be == MH_CIGAM_64:
        cputype = struct.unpack(">I", header[4:8])[0]
        return cputype == CPU_TYPE_ARM64
    if magic_be in (FAT_MAGIC, FAT_CIGAM):
        endian = ">" if magic_be == FAT_MAGIC else "<"
        nfat = struct.unpack(endian + "I", header[4:8])[0]
        offset = 8
        for _ in range(min(nfat, 16)):
            if offset + 20 > len(header):
                break
            cputype = struct.unpack(endian + "I", header[offset : offset + 4])[0]
            if cputype == CPU_TYPE_ARM64:
                return True
            offset += 20
    return False


def verify_ipa(ipa_path: Path) -> None:
    if not ipa_path.is_file() or ipa_path.stat().st_size <= 0:
        raise SystemExit(f"ERROR: invalid IPA file: {ipa_path}")
    with zipfile.ZipFile(ipa_path, "r") as zf:
        names = zf.namelist()
        forbidden = [
            n for n in names
            if "/_CodeSignature/" in n or n.endswith("/embedded.mobileprovision")
        ]
        if forbidden:
            raise SystemExit(f"ERROR: unsigned IPA contains signature files: {forbidden[:3]}")

        info_candidates = [
            n for n in names
            if n.startswith("Payload/") and n.count("/") == 2 and n.endswith(".app/Info.plist")
        ]
        if len(info_candidates) != 1:
            raise SystemExit(f"ERROR: expected 1 Payload/*.app/Info.plist, found {info_candidates}")

        info_entry = info_candidates[0]
        app_prefix = info_entry.rsplit("/", 1)[0]
        info_data = plistlib.loads(zf.read(info_entry))
        exe_name = info_data.get("CFBundleExecutable")
        if not exe_name:
            raise SystemExit("ERROR: CFBundleExecutable missing from Info.plist")

        platforms = info_data.get("CFBundleSupportedPlatforms") or []
        if platforms and "iPhoneOS" not in platforms:
            raise SystemExit(f"ERROR: IPA is not built for iPhoneOS (platforms={platforms})")

        exe_entry = f"{app_prefix}/{exe_name}"
        if exe_entry not in names:
            raise SystemExit(f"ERROR: executable {exe_entry} missing from IPA")

        with zf.open(exe_entry) as exe_fh:
            header = exe_fh.read(512)
        if not has_arm64_slice(header):
            raise SystemExit(f"ERROR: {exe_entry} does not contain an arm64 Mach-O binary")

    print(f"[verify-ipa] verified unsigned arm64 iPhoneOS IPA: {ipa_path.name}")


def main() -> int:
    if len(sys.argv) < 2:
        raise SystemExit("usage: verify-unsigned-ipa.py <file.ipa> [...]")
    for arg in sys.argv[1:]:
        verify_ipa(Path(arg))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
