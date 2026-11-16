
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$ROOT_DIR/work"
OPENWRT_DIR="$WORK_DIR/openwrt"
OUT_DIR="$ROOT_DIR/out"

OPENWRT_REF="${OPENWRT_REF:-v25.12.6}"
JOBS="${JOBS:-2}"

echo "========================================"
echo " ELECOM WRC-X3200GST3 OpenWrt Builder"
echo " OpenWrt: $OPENWRT_REF"
echo " KEXEC: enabled"
echo " Partition: DEFAULT"
echo "========================================"

mkdir -p "$WORK_DIR" "$OUT_DIR"

# 1. Download official OpenWrt source
if [ ! -d "$OPENWRT_DIR/.git" ]; then
    git clone \
        --depth 1 \
        --branch "$OPENWRT_REF" \
        https://git.openwrt.org/openwrt/openwrt.git \
        "$OPENWRT_DIR"
fi

cd "$OPENWRT_DIR"

# 2. Update feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 3. Load build configuration
cp "$ROOT_DIR/config.seed" .config

# 4. Generate final configuration
make defconfig

echo "Checking OpenWrt configuration..."

grep -q '^CONFIG_TARGET_mediatek=y' .config
grep -q '^CONFIG_TARGET_mediatek_mt7622=y' .config
grep -q '^CONFIG_KERNEL_KEXEC=y' .config
grep -q '^CONFIG_PACKAGE_kexec=y' .config

# 5. Download sources
make -j"$JOBS" download

# 6. Compile Linux kernel first
make -j"$JOBS" target/linux/compile

# 7. Verify actual Linux kernel configuration
KERNEL_CONFIG="$(
    find build_dir/target-* \
        -type f \
        -path '*/linux-*/.config' \
        | head -n 1
)"

if [ -z "$KERNEL_CONFIG" ]; then
    echo "ERROR: Kernel config not found"
    exit 1
fi

echo "Kernel config: $KERNEL_CONFIG"

if ! grep -q '^CONFIG_KEXEC=y' "$KERNEL_CONFIG"; then
    echo "ERROR: CONFIG_KEXEC is not enabled in Linux kernel"
    exit 1
fi

echo "KEXEC kernel support verified."

# 8. Build firmware
make -j"$JOBS"

# 9. Locate firmware
IMAGE_DIR="bin/targets/mediatek/mt7622"

SYSUPGRADE="$(
    find "$IMAGE_DIR" -maxdepth 1 -type f \
        -name '*elecom_wrc-x3200gst3*sysupgrade.bin' \
        | head -n 1
)"

INITRAMFS="$(
    find "$IMAGE_DIR" -maxdepth 1 -type f \
        -name '*elecom_wrc-x3200gst3*initramfs*' \
        | head -n 1
)"

if [ -z "$SYSUPGRADE" ]; then
    echo "ERROR: sysupgrade image missing"
    ls -lh "$IMAGE_DIR"
    exit 1
fi

if [ -z "$INITRAMFS" ]; then
    echo "ERROR: initramfs image missing"
    ls -lh "$IMAGE_DIR"
    exit 1
fi

# 10. Export firmware
rm -f "$OUT_DIR"/*

cp "$SYSUPGRADE" "$OUT_DIR/"
cp "$INITRAMFS" "$OUT_DIR/"

cp "$IMAGE_DIR"/*manifest "$OUT_DIR/" 2>/dev/null || true
cp "$IMAGE_DIR"/config.buildinfo "$OUT_DIR/" 2>/dev/null || true
cp .config "$OUT_DIR/openwrt.config"
cp "$KERNEL_CONFIG" "$OUT_DIR/kernel.config"

# 11. Generate checksums
cd "$OUT_DIR"
sha256sum *.bin > sha256sums.txt

echo "========================================"
echo " BUILD SUCCESS"
echo "========================================"
ls -lh "$OUT_DIR"
