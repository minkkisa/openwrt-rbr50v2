#!/bin/bash
# ============================================================
# OpenWrt build script for Netgear RBR50 V2
# Run this INSIDE the Docker container
#
# Authors: Sami Minkkinen & Claude (Anthropic)
# ============================================================
set -e
export FORCE_UNSAFE_CONFIGURE=1
export DEBIAN_FRONTEND=noninteractive

echo "=== [1/8] Installing build dependencies ==="
apt-get update -qq
apt-get install -y -qq \
    build-essential clang flex bison g++ gawk \
    gettext git libncurses5-dev libssl-dev \
    python3-setuptools rsync swig unzip zlib1g-dev file wget \
    python3-dev libelf-dev autoconf automake libtool pkg-config \
    xz-utils patch quilt diffutils curl ca-certificates \
    libfuse-dev libacl1-dev 2>&1 | tail -3
echo "Dependencies installed."

echo ""
echo "=== [2/8] Cloning OpenWrt source ==="
if [ ! -d /build/openwrt/.git ]; then
    git clone --depth 1 https://github.com/openwrt/openwrt.git /build/openwrt
else
    echo "Already cloned, using cached source."
    cd /build/openwrt && git pull --ff-only || echo "Pull failed, using existing."
fi
cd /build/openwrt

echo ""
echo "=== [3/8] Installing feeds ==="
./scripts/feeds update -a 2>&1 | tail -5
./scripts/feeds install -a 2>&1 | tail -3
echo "Feeds installed."

echo ""
echo "=== [4/8] Copying RBR50 V2 DTS ==="
cp /mnt/project/dts/qcom-ipq4019-rbr50v2.dts \
    target/linux/ipq40xx/dts/qcom-ipq4019-rbr50v2.dts
echo "DTS copied."

echo ""
echo "=== [5/8] Adding build definition to generic.mk ==="
if ! grep -q "netgear_rbr50v2" target/linux/ipq40xx/image/generic.mk; then
    # Insert after netgear_rbs50 definition
    sed -i '/^TARGET_DEVICES += netgear_rbs50$/r /dev/stdin' \
        target/linux/ipq40xx/image/generic.mk <<'BUILDDEF'

define Device/netgear_rbr50v2
	$(call Device/DniImage)
	SOC := qcom-ipq4019
	DEVICE_VENDOR := NETGEAR
	DEVICE_MODEL := RBR50
	DEVICE_VARIANT := v2
	KERNEL_SIZE := 7340032
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	UBINIZE_OPTS := -E 5
	NETGEAR_BOARD_ID := RBR50
	NETGEAR_HW_ID := 29765913+0+512+512+2x2+2x2+4x4
	IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
	DEVICE_PACKAGES := ath10k-firmware-qca9984-ct kmod-leds-tlc591xx
endef
TARGET_DEVICES += netgear_rbr50v2
BUILDDEF
    echo "Build definition added."
else
    echo "Build definition already present."
fi

echo ""
echo "=== [6/8] Patching platform scripts ==="

# --- 6a. Patch platform_do_upgrade for NAND sysupgrade ---
PLATFORM_SH="target/linux/ipq40xx/base-files/lib/upgrade/platform.sh"
if [ -f "$PLATFORM_SH" ] && ! grep -q "rbr50v2" "$PLATFORM_SH"; then
    python3 << 'PYEOF'
with open("target/linux/ipq40xx/base-files/lib/upgrade/platform.sh") as f:
    lines = f.readlines()

new_lines = []
in_do_upgrade = False
inserted = False

for i, line in enumerate(lines):
    if "platform_do_upgrade()" in line:
        in_do_upgrade = True

    # Insert before the default *) case inside platform_do_upgrade
    if in_do_upgrade and not inserted and line.strip() == "*)":
        new_lines.append("\tnetgear,rbr50v2)\n")
        new_lines.append('\t\tnand_do_upgrade "$1"\n')
        new_lines.append("\t\t;;\n")
        inserted = True

    new_lines.append(line)

if not inserted:
    # Fallback: insert before the closing esac of platform_do_upgrade
    new_lines2 = []
    in_do_upgrade = False
    for line in new_lines:
        if "platform_do_upgrade()" in line:
            in_do_upgrade = True
        if in_do_upgrade and line.strip() == "esac":
            new_lines2.append("\tnetgear,rbr50v2)\n")
            new_lines2.append('\t\tnand_do_upgrade "$1"\n')
            new_lines2.append("\t\t;;\n")
            in_do_upgrade = False
        new_lines2.append(line)
    new_lines = new_lines2

with open("target/linux/ipq40xx/base-files/lib/upgrade/platform.sh", "w") as f:
    f.writelines(new_lines)

print("platform_do_upgrade patched for rbr50v2")
PYEOF
else
    echo "platform.sh already patched or not found."
fi

# --- 6b. Patch 02_network for board detection ---
NETWORK_SH="target/linux/ipq40xx/base-files/etc/board.d/02_network"
if [ -f "$NETWORK_SH" ] && ! grep -q "rbr50v2" "$NETWORK_SH"; then
    python3 << 'PYEOF'
with open("target/linux/ipq40xx/base-files/etc/board.d/02_network") as f:
    lines = f.readlines()

new_lines = []
inserted = False

for line in lines:
    # Insert after rbr50 or rbs50 network config
    if not inserted and "netgear,rbr50" in line and "rbr50v2" not in line:
        new_lines.append(line)
        # Skip ahead to find the ;; for this case and insert after it
        # Actually, let's just mark that we found the anchor
        pass
    else:
        new_lines.append(line)
        continue
    new_lines.append(line)

# Alternative: find the case statement and insert before *)
new_lines = []
in_ipq40xx_setup = False
inserted = False

for line in lines:
    if "ipq40xx_setup_interfaces" in line:
        in_ipq40xx_setup = True

    # Insert before *) default case in the setup_interfaces function
    if in_ipq40xx_setup and not inserted and line.strip() == "*)":
        new_lines.append("\tnetgear,rbr50v2)\n")
        new_lines.append('\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"\n')
        new_lines.append("\t\t;;\n")
        inserted = True

    new_lines.append(line)

with open("target/linux/ipq40xx/base-files/etc/board.d/02_network", "w") as f:
    f.writelines(new_lines)

print("02_network patched for rbr50v2")
PYEOF
else
    echo "02_network already patched or not found."
fi

# --- 6c. Patch 01_leds for LED board detection ---
LEDS_SH="target/linux/ipq40xx/base-files/etc/board.d/01_leds"
if [ -f "$LEDS_SH" ] && ! grep -q "rbr50v2" "$LEDS_SH"; then
    python3 << 'PYEOF'
with open("target/linux/ipq40xx/base-files/etc/board.d/01_leds") as f:
    lines = f.readlines()

new_lines = []
inserted = False

for line in lines:
    # Insert before *) default case or before esac
    if not inserted and line.strip() == "esac":
        new_lines.append("netgear,rbr50v2)\n")
        new_lines.append('\tucidef_set_led_default "power" "Power" "green:power" "1"\n')
        new_lines.append("\t;;\n")
        inserted = True

    new_lines.append(line)

with open("target/linux/ipq40xx/base-files/etc/board.d/01_leds", "w") as f:
    f.writelines(new_lines)

print("01_leds patched for rbr50v2")
PYEOF
else
    echo "01_leds already patched or not found."
fi

# --- 6d. Show patched sections for verification ---
echo "--- platform.sh rbr50v2 entry ---"
grep -A2 "rbr50v2" "$PLATFORM_SH" 2>/dev/null || echo "NOT FOUND"
echo "--- 02_network rbr50v2 entry ---"
grep -A2 "rbr50v2" "$NETWORK_SH" 2>/dev/null || echo "NOT FOUND"
echo "--- 01_leds rbr50v2 entry ---"
grep -A2 "rbr50v2" "$LEDS_SH" 2>/dev/null || echo "NOT FOUND"

echo ""
echo "=== [7/8] Configuring build ==="
cat > .config <<'EOF'
CONFIG_TARGET_ipq40xx=y
CONFIG_TARGET_ipq40xx_generic=y
CONFIG_TARGET_ipq40xx_generic_DEVICE_netgear_rbr50v2=y

# WiFi drivers
CONFIG_PACKAGE_ath10k-firmware-qca9984-ct=y
CONFIG_PACKAGE_kmod-ath10k-ct=y

# Web UI
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-app-statistics=y

# Packet capture & analysis
CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_aircrack-ng=y

# WiFi security tools
CONFIG_PACKAGE_hostapd-utils=y
CONFIG_PACKAGE_wpa-cli=y

# Network analysis
CONFIG_PACKAGE_nmap=y
CONFIG_PACKAGE_arp-scan=y
CONFIG_PACKAGE_socat=y

# Traffic monitoring
CONFIG_PACKAGE_iftop=y
CONFIG_PACKAGE_p0f=y
CONFIG_PACKAGE_dnstop=y

# Kernel modules
CONFIG_PACKAGE_kmod-leds-tlc591xx=y
CONFIG_PACKAGE_kmod-br-netfilter=y

# I2C tools (LED diagnostics)
CONFIG_PACKAGE_i2c-tools=y
EOF

make defconfig 2>&1 | tail -5
echo "Configuration ready."

echo ""
echo "=== [8/8] Building firmware ==="
echo "Using $(nproc) CPU cores"
make -j$(nproc) FORCE_UNSAFE_CONFIGURE=1 V=s 2>&1 | tee /build/build.log | \
    grep -E "^(make\[|Compiling|Installing|Generating)" | tail -50

BUILD_EXIT=$?

echo ""
echo "=== BUILD COMPLETE (exit code: $BUILD_EXIT) ==="
echo ""
echo "Firmware images:"
ls -la /build/openwrt/bin/targets/ipq40xx/generic/*rbr50v2* 2>/dev/null || \
    echo "WARNING: No RBR50v2 images found."

if [ $BUILD_EXIT -ne 0 ]; then
    echo ""
    echo "=== BUILD FAILED — Last 30 lines of build.log ==="
    tail -30 /build/build.log
fi
