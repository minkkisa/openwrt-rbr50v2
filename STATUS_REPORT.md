# Netgear Orbi RBR50 V2 — OpenWrt Port Status Report

**Date:** 2026-03-25
**Status:** FULLY WORKING — Squashfs + UBI overlay, persistent storage, all hardware functional
**First-ever OpenWrt installation on Netgear Orbi RBR50 V2.**

## Hardware Specifications (UART-verified)

| Feature | Value |
|---------|-------|
| **SoC** | Qualcomm IPQ4019 (4× ARM Cortex-A7, 96 BogoMIPS/core) |
| **RAM** | 512 MB DDR3L (672 MHz), ~503 MB available to kernel |
| **Flash** | 512 MB SPI NAND (Macronix MX30LF4G18AC-TI), 128KB erase, 2KB page, ONFI |
| **WiFi 2.4G** | IPQ4019 integrated (ath10k-ct, 2×2 MIMO, Board ID 20) |
| **WiFi 5G low** | IPQ4019 integrated (ath10k-ct, 2×2 MIMO, Board ID 21) |
| **WiFi 5G high** | QCA9984 PCIe (ath10k-ct, 4×4 MIMO, Board ID 6) — backhaul radio |
| **Ethernet** | QCA8075 5-port GbE switch (WAN + 3× LAN, DSA) |
| **USB** | None (V1 has USB 3.0 + 2.0; V2 has no ports) |
| **Bluetooth** | None (V1 has BT) |
| **U-Boot** | DNI V0.5 (based on 2012.07, Chaos Calmer 15.05.1) |
| **HW ID** | 29765913 |
| **machid** | 0x8010001 |
| **UART** | 115200 8N1, J01 header: VCC(1)/TXD(2)/RXD(3)/GND(4) |
| **NAND ID** | 0x9590dcc2, BCH ECC 4-bit |

## What Works

- [x] **Persistent installation** — Squashfs root + UBIFS overlay (23 MB writable)
- [x] **Kernel** — Linux 6.12.77, boots from NAND, 4 CPUs active
- [x] **UART console** — ttyMSM0 @ 115200, full boot log
- [x] **Ethernet** — QCA8075 DSA switch, WAN + 3× LAN, auto-configured, 1 Gbps
- [x] **WAN** — DHCP upstream connectivity tested and working
- [x] **Board detection** — `netgear,rbr50v2` recognized, LAN/WAN auto-bridged
- [x] **NAND** — Macronix 512MB, 24 partitions, MTD + UBI working
- [x] **UBI** — 344 PEBs, 0 bad blocks, rootfs (4.3 MB) + rootfs_data (27.1 MB)
- [x] **PCIe** — QCA9984 detected, Gen.2 x1 link UP
- [x] **WiFi AP mode** — All 3 radios tested in AP mode (2.4 GHz + 5 GHz client access, QCA9984 backhaul)
- [x] **WiFi monitor mode** — All 3 radios tested, 53M+ frames received, noise floor -110 dBm
- [x] **MAC addresses** — Read from boarddata1 NAND partition (LAN/WAN/WiFi)
- [x] **U-Boot env** — fdt_high and bootcmd saved permanently
- [x] **sysupgrade** — `nand_do_upgrade` works, tested from initramfs → squashfs
- [x] **Reboot persistence** — Password, configs survive reboot (overlay verified)
- [x] **LEDs** — GPIO 22–27 fully mapped + TLC59208F I2C ring LED under full control

## LED Controller

The top ring LED uses a **TLC59208F** I2C LED driver (8 channels), not GPIOs alone.

| LED | Controller | Address | Notes |
|-----|-----------|---------|-------|
| Power green | GPIO 22 | Direct | Near power button |
| Power red | GPIO 23 | Direct | Near power button |
| Status green | GPIO 24 | Direct | |
| Status red | GPIO 25 | Direct | |
| Status blue | GPIO 26 | Direct | |
| Status white | GPIO 27 | Direct | |
| Ring LED (all colors) | **TLC59208F** | I2C bus 0, addr 0x27 | 8-channel PWM controller |

**I2C bus:** blsp1_i2c3 (`i2c@78b7000`), GPIO 20 (SDA) / GPIO 21 (SCL)

**Kernel driver:** `kmod-leds-tlc591xx` (included in DEVICE_PACKAGES) provides sysfs LED control via `/sys/class/leds/`. Uses `ti,tlc59108` compatible in DTS (register-compatible with TLC59208F, matches kernel match table).

**Startup script:** `/etc/init.d/led_ring` (using `i2c-tools`) turns off the ring LED at boot. Without this, U-Boot's last LED state persists (blinking white).

**TLC59208F register map:**
- MODE1 (0x00) = 0x81 (auto-increment, normal mode)
- PWM0–PWM7 (0x02–0x09) = brightness per channel
- LEDOUT0 (0x0C) = LED0–3 output mode
- LEDOUT1 (0x0D) = LED4–7 output mode

## Known Issues

1. **fw_env.config missing** — `fw_printenv`/`fw_setenv` not working from Linux. U-Boot env partition is mtd8 (0:APPSBLENV), size 512 KB. Config file needs correct offset/size.

2. **bootcmd bypasses DNI validation** — Current bootcmd uses direct `nand read` instead of `load_chk_dniimg`. This skips Netgear's firmware integrity check and dual-boot mechanism. A DNI-compatible image would be better long-term.

## Critical Discovery: fdt_high

**The single root cause that prevented ALL modern kernels from booting on this device.**

**Problem:** DNI's modified U-Boot (2012.07) performs a 128 KB NAND read after `bootm`. If the device tree is loaded above address `0x87000000`, this read overwrites the FDT, causing a silent kernel crash (no output after "Starting kernel...").

**Solution:** U-Boot environment variable `fdt_high=0x87000000` forces FDT placement below the danger zone.

**Impact:** This blocked every OpenWrt kernel (including the official RBR50 V1 image) from booting on V2 hardware. Stock firmware's bootcmd included this setting, but it was absent in manual TFTP boot commands.

**Saved U-Boot configuration:**
```
bootcmd=nand read 0x84000000 0xa800000 0x800000; setenv fdt_high 0x87000000; bootm 0x84000000
fdt_high=0x87000000
```

## DTS Changes from Base IPQ4019

1. **stdout-path** — Added `stdout-path = "serial0:115200n8"` to chosen node (required for console output)
2. **serial0 alias** — Added `serial0 = &blsp1_uart1` to aliases (required for console output)
3. **USB disabled** — All USB nodes set to `status = "disabled"` (V2 has no USB ports)
4. **NAND partitions** — 24 partitions mapped from stock firmware's `/proc/mtd`, with "ubi" partition for OpenWrt rootfs
5. **No bootargs-append** — Removed; UBI root is discovered automatically by OpenWrt's preinit
6. **WiFi calibration** — Pre-cal data read from ART partition (0:ART at 0xB00000), offsets 0x1000/0x5000/0x9000
7. **MAC addresses** — Read from boarddata1 partition at offsets 0x0/0x6/0xC/0x12
8. **LEDs** — GPIO 22–27 active high + TLC59208F I2C ring LED on bus 0 addr 0x27
9. **PCIe QCA9984** — perst-gpio 38, wake-gpio 50, freq limit 5470–5875 MHz
10. **I2C pins** — SDA/SCL on GPIO 20/21 (V1 uses 58/59, which are QPIC NAND bus on V2)

## NAND Partition Table (24 partitions)

```
Offset      Size    Name              Notes
0x000000    1MB     0:SBL1            Read-only, primary bootloader
0x100000    1MB     0:MIBIB           Read-only, partition table
0x200000    1MB     0:BOOTCONFIG      Read-only
0x300000    1MB     0:QSEE            Read-only, TrustZone
0x400000    1MB     0:QSEE_1          Read-only, TrustZone backup
0x500000    512KB   0:CDT             Read-only, config data
0x580000    512KB   0:CDT_1           Read-only, config data backup
0x600000    512KB   0:BOOTCONFIG1     Read-only
0x680000    512KB   0:APPSBLENV       U-Boot environment (256KB used)
0x700000    2MB     0:APPSBL          Read-only, U-Boot
0x900000    2MB     0:APPSBL_1        Read-only, U-Boot backup
0xB00000    512KB   0:ART             Read-only, WiFi calibration — DO NOT ERASE
0xB80000    512KB   0:ART.bak         Read-only, WiFi cal backup
0xC00000    1MB     config            Read-only, Netgear config
0xD00000    512KB   boarddata1        Read-only, MAC addresses
0xD80000    256KB   boarddata2        Read-only
0xDC0000    1MB     pot               Read-only, first-use timestamp
0xEC0000    512KB   boarddata1.bak    Read-only
0xF40000    256KB   boarddata2.bak    Read-only
0xF80000    5MB     language          Read-only
0x1480000   512KB   cert              Read-only
0x1500000   147MB   ntgrdata          Netgear data (reclaimable)
0xA800000   7MB     kernel            OpenWrt kernel (FIT image)
0xAF00000   43MB    ubi               OpenWrt rootfs (UBI: squashfs + overlay)
```

**Total OpenWrt space:** 50 MB (kernel 7 MB + ubi 43 MB)
**Reclaimable:** ntgrdata (147 MB) + firmware2 area after 0xDA00000

## Build Environment

- **Docker**: `ubuntu:22.04` with `FORCE_UNSAFE_CONFIGURE=1`
- **Volume cache**: `openwrt-buildcache` (fast incremental builds)
- **OpenWrt branch**: main (snapshot, r0-17784ad)
- **Kernel**: 6.12.77
- **Build time**: ~10 min incremental, ~2h full
- **Script**: `build.sh`

### Build outputs
```
openwrt-ipq40xx-generic-netgear_rbr50v2-initramfs-zImage.itb    (12.1 MB)
openwrt-ipq40xx-generic-netgear_rbr50v2-squashfs-factory.img    (13.2 MB)
openwrt-ipq40xx-generic-netgear_rbr50v2-squashfs-sysupgrade.bin (13.2 MB)
```

Pre-built images are available on the [GitHub Releases](https://github.com/minkkisa/openwrt-rbr50v2/releases) page.

## Installation Guide

### Prerequisites
- USB-UART adapter (3.3V TTL — FTDI, CP2102, or CH340)
- Ethernet cable (host PC → Orbi LAN port)
- TFTP server on host machine
- Serial terminal (e.g., `picocom -b 115200 --flow none /dev/ttyUSB0`)

### UART Wiring (J01 Header)

```
USB-UART (3.3V TTL)     Orbi J01 Header
─────────────────────    ───────────────
GND                  →   Pin 4 (GND)
TXD                  →   Pin 3 (RXD)   [crossed!]
RXD                  →   Pin 2 (TXD)   [crossed!]
VCC                  →   NOT CONNECTED
```

**Note:** Some terminal programs (e.g., macOS `screen`) have flow control issues that block UART TX. Disable flow control or use `picocom --flow none`.

### Step 1: First-time U-Boot Setup (one-time only)

Power on Orbi, press any key within 1 second to stop autoboot.

```
setenv fdt_high 0x87000000
setenv bootcmd 'nand read 0x84000000 0xa800000 0x800000; setenv fdt_high 0x87000000; bootm 0x84000000'
saveenv
```

**WARNING:** Without `fdt_high=0x87000000`, NO OpenWrt kernel will boot on this device. This is the critical fix.

### Step 2: TFTP Boot Initramfs

Configure your host with a static IP (e.g., `192.168.1.10/24`) on the Ethernet interface connected to Orbi, and start a TFTP server serving the initramfs image.

In U-Boot:
```
setenv fdt_high 0x87000000
tftpboot 0x84000000 openwrt-ipq40xx-generic-netgear_rbr50v2-initramfs-zImage.itb
bootm 0x84000000
```

### Step 3: Install Persistent Firmware via sysupgrade

Once initramfs boots, serve the sysupgrade image via HTTP from your host:
```bash
# On host (in the directory containing the sysupgrade file):
python3 -m http.server 8080
```

On Orbi (via UART or SSH):
```bash
cd /tmp
wget http://192.168.1.10:8080/openwrt-ipq40xx-generic-netgear_rbr50v2-squashfs-sysupgrade.bin
sysupgrade -n /tmp/openwrt-ipq40xx-generic-netgear_rbr50v2-squashfs-sysupgrade.bin
```

Device reboots automatically into persistent squashfs + UBI overlay.

### Step 4: Verify

After reboot:
```bash
df -h                           # Should show /overlay (UBIFS, ~23 MB)
mount | grep overlay            # Should show overlayfs
passwd                          # Set root password (persists!)
reboot                          # Verify password survives reboot
```

## Recovery

1. **U-Boot prompt** — Power on, press any key within 1 second → TFTP boot initramfs
2. **NMRP recovery** — If firmware is corrupted, device enters TFTP recovery mode automatically. Use `nmrpflash` to restore.
3. **Stock firmware** — Can be restored via nmrpflash or U-Boot `nand write`
4. **firmware2 partition** — Stock firmware remains at 0xDA00000 (not overwritten by OpenWrt)

## Differences from RBR50 V1

| Feature | V1 | V2 |
|---------|----|----|
| Flash | 4 GB eMMC | 512 MB SPI NAND |
| USB | USB 3.0 + 2.0 | None |
| Bluetooth | Yes | No |
| LEDs (GPIO) | GPIO 53/54/57/60/63/64 | GPIO 22–27 |
| LEDs (I2C) | TLC59208F on GPIO 58/59 | TLC59208F on GPIO 20/21 |
| WiFi PA | Skyworks | Different (cost-reduced) |
| HW ID | 29765352 | 29765913 |
| fdt_high needed | No (eMMC boot) | **Yes (critical!)** |
| OpenWrt support | Official | **This port** |

## Repository Contents

```
openwrt-rbr50v2/
├── STATUS_REPORT.md              ← This file
├── PR_DESCRIPTION.md             ← GitHub PR description (English)
├── COMMIT_MESSAGE.txt            ← Prepared commit message for upstream PR
├── build.sh                      ← Docker build script (automated, builds all images)
├── dts/
│   ├── qcom-ipq4019-rbr50v2.dts ← Device tree source (578 lines)
│   └── generic.mk.patch         ← OpenWrt build definition
└── logs/
    ├── uart_boot_stock_20260324.txt  ← Stock firmware UART boot log
    └── v2_gpio_dump.txt              ← Stock firmware GPIO state dump
```

## Upstream Contribution Plan

### Required for PR — all complete
1. [x] Device tree source (DTS)
2. [x] Build definition (generic.mk entry, HW_ID 29765913)
3. [x] Platform upgrade script (platform.sh — nand_do_upgrade)
4. [x] Network board detection (02_network — LAN/WAN config)
5. [x] LED board detection (01_leds — power LED default on)
6. [x] WiFi tested (AP mode on all 3 radios + monitor mode scan)
7. [x] Commit message with hardware details and fdt_high documentation

### Files to submit
- **New:** `target/linux/ipq40xx/dts/qcom-ipq4019-rbr50v2.dts`
- **Patch:** `target/linux/ipq40xx/image/generic.mk` (add Device/netgear_rbr50v2 block)
- **Patch:** `target/linux/ipq40xx/base-files/lib/upgrade/platform.sh` (add nand_do_upgrade)
- **Patch:** `target/linux/ipq40xx/base-files/etc/board.d/02_network` (add LAN/WAN config)
- **Patch:** `target/linux/ipq40xx/base-files/etc/board.d/01_leds` (add power LED default)

## Timeline

- **2026-03-14** — Project started, stock firmware analyzed via telnet
- **2026-03-24** — UART connected, stock boot log captured, first OpenWrt build
- **2026-03-24** — fdt_high discovered, first-ever OpenWrt kernel boot on RBR50 V2
- **2026-03-24** — Initramfs flashed to NAND, boots without TFTP
- **2026-03-25** — Squashfs + UBI overlay installed, persistent storage confirmed
- **2026-03-25** — Board detection, sysupgrade, network auto-config all working
- **2026-03-25** — TLC59208F I2C LED controller discovered, ring LED under full control
- **2026-03-25** — WiFi AP mode tested (all 3 radios) and monitor mode scan confirmed working
