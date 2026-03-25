## ipq40xx: add support for Netgear Orbi RBR50 V2

### Summary

Adds OpenWrt support for the **Netgear Orbi RBR50 V2** (NAND variant). This is a cost-reduced version of the RBR50 V1 — same SoC and WiFi chipsets, but NAND flash instead of eMMC, no USB, no Bluetooth.

This is the first-ever OpenWrt port for this device.

### Hardware

| Feature | Specification |
|---------|--------------|
| SoC | Qualcomm IPQ4019 (4× ARM Cortex-A7) |
| RAM | 512 MB DDR3L |
| Flash | 512 MB SPI NAND (Macronix MX30LF4G18AC) |
| WiFi 2.4 GHz | IPQ4019 integrated (2×2 MIMO) |
| WiFi 5 GHz (low) | IPQ4019 integrated (2×2 MIMO) |
| WiFi 5 GHz (high) | QCA9984 PCIe (4×4 MIMO, backhaul) |
| Ethernet | QCA8075 5-port GbE switch (WAN + 3× LAN, DSA) |
| LEDs | GPIO 22–27 + TLC59208F I2C LED controller (ring LED) |
| USB | None |
| Bluetooth | None |
| UART | 115200 8N1, J01 header (4 pins: VCC/TXD/RXD/GND) |

### Key differences from RBR50 V1

- **NAND** (512 MB SPI NAND) instead of **eMMC** (4 GB)
- LED GPIOs relocated to 22–27 (V1 uses 53/54/57/60/63/64)
- I2C SDA/SCL on GPIO 20/21 (V1 uses 58/59 which are now QPIC NAND bus)
- No USB, no Bluetooth
- Different NETGEAR_HW_ID: `29765913` (V1: `29765352`)

### Critical: fdt_high=0x87000000

**This is the key discovery that enables OpenWrt on this device.**

DNI's modified U-Boot (2012.07) performs a 128 KB NAND read after `bootm`. If the device tree is loaded above address `0x87000000`, this read silently overwrites the FDT, causing the kernel to crash with no output after `Starting kernel...`.

The fix is a one-time U-Boot environment variable:
```
setenv fdt_high 0x87000000
saveenv
```

Without this, **no** modern kernel (including OpenWrt) will boot on V2 hardware.

### Installation

1. Connect USB-UART adapter to J01 header (115200 8N1, 3.3V TTL)
2. Stop U-Boot autoboot, set `fdt_high=0x87000000`, `saveenv`
3. TFTP boot initramfs image
4. `sysupgrade` to persistent squashfs + UBI overlay

Detailed installation guide: [will be added to wiki after merge]

### Tested

- [x] Kernel boot (Linux 6.12)
- [x] NAND flash (24 partitions, MTD + UBI)
- [x] UBI overlay (persistent storage, survives reboot)
- [x] Ethernet (WAN + 3× LAN, DSA, 1 Gbps)
- [x] WiFi — all 3 radios (2.4 GHz AP + 5 GHz AP + QCA9984)
- [x] PCIe (QCA9984 Gen.2 x1)
- [x] sysupgrade (nand_do_upgrade)
- [x] LEDs (GPIO direct + TLC59208F I2C ring LED via kmod-leds-tlc591xx)
- [x] Board detection (network + LED auto-config)

### Files changed

- **New:** `target/linux/ipq40xx/dts/qcom-ipq4019-rbr50v2.dts`
- **Modified:** `target/linux/ipq40xx/image/generic.mk` — add Device/netgear_rbr50v2
- **Modified:** `target/linux/ipq40xx/base-files/lib/upgrade/platform.sh` — add nand_do_upgrade
- **Modified:** `target/linux/ipq40xx/base-files/etc/board.d/02_network` — add LAN/WAN config
- **Modified:** `target/linux/ipq40xx/base-files/etc/board.d/01_leds` — add power LED default
