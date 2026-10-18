# M1 Air Wi-Fi

The experimental BCM4378 driver supports firmware loading, reversible radio
on/off, asynchronous scans and WPA2 association. An authenticated link attaches
to Vinix's IP stack, including DHCP. Physical firmware boot, scanning and
association still need validation after booting the patched kernel on the M1.

See [build, validation and hardware bring-up instructions](../tests/m1-wifi/README.md).

A failed boot-time probe now reports its error and stage alongside the
diagnostic-device message. The stages distinguish loader endpoint ownership, PHY
clocks, port/link readiness, PCI identity, interrupt capabilities, BAR sizing
and assignment, DART setup, protocol resources and chip/OTP discovery. This is
separate from firmware loading; a probe failure occurs before any bundle upload.

Hardware probing remains opt-in with `vinix.apple_wifi=1`; firmware is not
included. The normal `desktop` and `desktop-drivers` deployments now supply
that argument, and `scripts/kek.sh desktop-wifi` names the Wi-Fi-only choice explicitly.
Direct deployments can pass `scripts/deploy-m1-efi.sh --apple-wifi`. A boot without one
of those choices intentionally has no `/dev/wlan0`.

The desktop initramfs includes the target `wifi-ctl` utility. To make a locally
packaged, matching bundle available at boot, build with
`VINIX_WIFI_BUNDLE=/path/to/wifi-bundle ./scripts/build-desktop-aarch64.sh` or pass
`--wifi-bundle=/path/to/wifi-bundle`. The build requires all five package files,
and init runs `wifi-ctl load /usr/share/vinix/wifi` before starting the desktop.
The loader rechecks the bundle manifest against the detected chip and refuses a
mismatch. Without a bundle, Settings reports that firmware still needs loading.

Once matching firmware has loaded, the desktop's **Settings > Wi-Fi** pane can
turn the radio on or off, scan and list networks. Use `wifi-ctl join 'SSID'`
to associate; it prompts for the passphrase with terminal echo disabled.
`/dev/wlan0` remains the control/raw Ethernet ABI; applications use the IP stack
after association.

## Capture the running Mac's firmware selection

While the J313 is running macOS and its Wi-Fi firmware is loaded:

```sh
build-support/run-v-tool.sh tools/m1-wifi/capture.v \
  sergey@macbook-air-sergej.local /path/to/new-wifi-bundle
VINIX_WIFI_BUNDLE=/path/to/new-wifi-bundle ./scripts/build-desktop-aarch64.sh
```

The V capture tool reads the live `AppleBCMWLANCore` selection and the device
tree, then copies only the four requested files from `/usr/share/firmware/wifi`.
It checks the model, chip, silicon, board, module, vendor, module revision and
antenna against the selected filenames. It writes a manifest, payload hashes
and `macos-selection.json`; it does not synthesize a successful Vinix probe or
save SSIDs or credentials. It makes no changes to the running radio. Vendor
firmware remains local and must not be committed. The kernel independently
compares the manifest with the device's OTP and boot device tree.

## BCM4378 startup findings, 2026-10-18

The live MacBookAir10,1 reported B1 silicon, module RASP, revision 6.11, vendor
`m`, antenna X3 and board Shikoku. Its selected files were:

| Purpose | Path below `/usr/share/firmware/wifi` |
| --- | --- |
| Firmware | `C-4378__s-B1/shikoku.trx` |
| NVRAM | `C-4378__s-B1/P-shikoku-X3_M-RASP_V-m__m-6.11.txt` |
| Regulatory | `C-4378__s-B1/shikoku-X3.clmb` |
| Power limits | `C-4378__s-B1/shikoku-X3.txcb` |

The firmware is a 1,480,718-byte raw image, version
18.20.480.2.7.8.187, FWID 01-4030d7ca. Bytes 108..115 contain `0xfa`, not a
`RAMS` header. Vinix previously rejected it before upload. RAM size now defaults
to the discovered SYSMEM banks; an optional RAMS override remains subject to
the existing size, alignment, BAR and payload bounds checks. This agrees with
[upstream brcmf_pcie_adjust_ramsize](https://github.com/torvalds/linux/blob/master/drivers/net/wireless/broadcom/brcm80211/brcmfmac/pcie.c).

The active macOS kernel UUID was `527D5275-825C-3A45-AA90-5021F6817874`,
macOS build 25D771280a. The extracted AppleBCMWLANBusInterfacePCIe UUID was
`F80C97FE-5626-3640-8307-17113A61CFDF`, Mach-O SHA-256
`1f5a4d1c8b45606ab79747fc6a9b1f579175c53db6f9795f020c3df6d044d7a8`.
Its `AppleBCMWLANChipManagerPCIe4378::prepareHardware` at
`0xfffffe00095744a4` maps core ordinal 6, reads offset `0xe64`, clears bits
1:0 and writes mode 1, preserving the remaining bits. The core table at
`0xfffffe000730776c` maps ordinal 6 to PCIe at `0x18010000`.
Vinix now performs that preparation after the watchdog reset and checks that
the mode was retained before uploading firmware. No broader meaning for this
undocumented register field is assumed.

The same binary's memory table at `0xfffffe00073078a4` confirms RAM base
`0x352000`, size `0x1ce000`, matching Vinix's load address and the bank-based
layout. Proprietary kernel/firmware dumps and raw IORegistry captures are not
part of the repository.

Validation includes the existing 26 protocol groups and 100,000 parser
mutations under ASan/UBSan, ARM64 guest execution, eight PCIe/DART policy
groups, host packaging checks and both kernel architectures. Added cases cover
headerless firmware, invalid RAMS sizes, missing RAM banks, preservation of
unrelated PCIe bits and an ignored preparation write. These simulated tests
do not establish physical radio operation.
