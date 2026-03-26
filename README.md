# Netgear Orbi RBR50 V2 — OpenWrt Port

> **NOTE:** A more complete and community-reviewed OpenWrt port for both RBR50v2 (router) and RBS50v2 (satellite) is available at:
>
> **https://github.com/openwrt/openwrt/pull/22321**
>
> That PR (by cptpcrd) includes proper DTS hierarchy inheriting from `qcom-ipq4019-orbi.dtsi`, support for both router and satellite, correct LED polarity, full NAND partition utilization (~103 MB vs our 43 MB), and nmrpflash installation without UART. We recommend using that PR as the primary source for flashing OpenWrt on RBR50v2/RBS50v2.

---

This repository contains our independent first-ever OpenWrt port for the Netgear Orbi RBR50 V2, developed via UART console access.

## What this repo offers beyond PR #22321

- **UART boot logs** from stock firmware (`logs/`)
- **fdt_high=0x87000000** discovery — required for U-Boot UART boot
- **GPIO dump** from stock firmware 3.14.77
- **TLC59208F ring LED** channel identification (RGBW)
- **Build script** for reproducing the image (`build.sh`)

## Files

| File | Description |
|------|-------------|
| `dts/qcom-ipq4019-rbr50v2.dts` | Device tree (monolithic, standalone) |
| `dts/generic.mk.patch` | Image build definition |
| `build.sh` | Full OpenWrt build script |
| `COMMIT_MESSAGE.txt` | Prepared upstream commit message |
| `PR_DESCRIPTION.md` | Prepared upstream PR description |
| `STATUS_REPORT.md` | Detailed hardware/software status report |
| `logs/uart_boot_stock_20260324.txt` | Stock firmware UART boot log |
| `logs/v2_gpio_dump.txt` | Stock firmware GPIO state dump |

## Known issues in our DTS (fixed in PR #22321)

- LED polarity should be `GPIO_ACTIVE_LOW` (we had `ACTIVE_HIGH`)
- Missing `gpio52` in NAND pullups
- Partition layout should use single `firmware` partition (not kernel+ubi split)
- Compatible string should be `netgear,rbr50-v2` (with hyphen)

## Authors

- **Sami Minkkinen** — hardware, UART, testing, fdt_high discovery
- **Claude (Anthropic)** — DTS, build system, documentation

## License

GPL-2.0-or-later OR MIT (matching OpenWrt)
