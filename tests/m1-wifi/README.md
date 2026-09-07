# Experimental M1 Air Wi-Fi bring-up for Vinix

**This is not a claim of working Wi-Fi or Internet access.** This source bundle
implements an experimental BCM4378 FullMAC transport and a raw
Ethernet/control interface. Actual M1 firmware boot, WPA2 association, and DMA
operation have not been verified on hardware. The V integration and complete clean debug/production ARM64 kernel builds
are now verified. Do not replace your only working boot entry.

Vinix's existing socket implementation supports Unix-domain sockets, not an IP
network stack. Even an authenticated Layer-2 link from this driver does not make
AF_INET applications, DNS, DHCP, `curl`, or ordinary `ping` work. An IP stack and
its socket integration are separate unfinished work, not hidden dependencies
that this patch supplies.

## Source layout

* `kernel/c/brcm_wifi.{c,h}`: BCM4378 core inventory/OTP, firmware bootstrap,
  board NVRAM packing, CLM/TXCAP/calibration loading, PCIe message rings,
  completion ownership, firmware commands, WPA2-PSK/CCMP, and raw Ethernet.
* `kernel/c/brcm_m1.{c,h}`: Apple PCIe port reset/clock sequencing, BAR allocation,
  a bounded 4 MiB DART mapping, exact-width MMIO and cache maintenance, loader
  staging, diagnostics and a bounded receive queue.
* `kernel/modules/apple/wifi/wifi.v`: J313 device-tree validation, PMGR and MMIO
  setup, entropy expansion, `/dev/wlan0`, checked user copies and poll integration.
* `tools/m1-wifi/`: explicit firmware packager and control utility.
* `tests/m1-wifi/`: portable protocol tests, simulated platform policy tests,
  parser mutation tests and a sanitizer-enabled runner.

The implementation is limited to `apple,j313` / `apple,t8103`, PCI 01:00.0
(vendor 14e4/device 4425), and chip revisions 3 and 5. It requires the bootloader's
matching device tree, board calibration, actual MAC, antenna SKU and RNG seed.
No guessed register base, IOMMU bypass, generic NVRAM fallback, or deterministic
entropy fallback is used. Hardware initialization is disabled unless the kernel
command line contains the exact argument `vinix.apple_wifi=1`.

## Build milestone (completed)

The integration is based on master `d87e6fea15759f943072611ef357c2170e97f21b`.
Its entire pristine kernel subtree was verified against Git tree
`6425969a80617193a3c5eadc4848138265054850` before applying the changes. The
existing ANS/storage, SMC, desktop and keyboard work is preserved.

Both **debug and production** now complete the real kernel makefile's V-to-C,
freestanding C/assembly compilation and final `ld.lld` link. These are static
AArch64 executables, not relocatable objects. The verifier rejects unresolved
symbols, wrong architecture/type, dynamic-loader dependencies, missing Wi-Fi
symbols and missing console hooks. It checks 18 retained Wi-Fi symbols after
linker garbage collection, plus initialization and polling call sites. Ten
negative/positive verifier tests run against the linked production image.

Other validation: 24 protocol groups (including 100,000 parser mutations) and
7 simulated-platform groups pass with Clang ASan/UBSan and optimized GCC.
Both driver C files separately compile using the kernel's freestanding headers
with `-Wall -Wextra -Werror`. All 17 SPI keyboard regression groups pass. The
full kernel still emits existing V notices and third-party warnings; this is
not a claim that the whole tree is warning-free. The control utility is
host-compiled; target userspace execution has not been validated.

Build fixes include typed user-copy addresses in the V adapter, removal of
unavailable `strlen` dependencies, host tests using `-iquote` rather than
shadowing libc headers, and four minimal V compatibility fixes in the existing
ANS wrappers. No missing function was replaced with a success stub and no
existing subsystem was compiled out to obtain a passing build.

On Linux, with Clang, LLD, GCC, make, git, curl and Python 3 installed, use a
**clean disposable checkout** (the existing kernel dependency script resets
its dependency checkouts):

```sh
sh tools/m1-wifi/get-v.sh /tmp/vinix-wifi-v
(cd kernel && ./get-deps)
CC=clang SANITIZE=1 sh tests/m1-wifi/run.sh
CC=gcc SANITIZE=0 sh tests/m1-wifi/run.sh
CC=clang sh tests/apple-spi-keyboard/run.sh
V=/tmp/vinix-wifi-v/v JOBS=2 sh tests/m1-wifi/build.sh
```

`get-v.sh` pins V to `71437d263bfc57f99e27588781f34bfc91746910` and its bootstrap
C compiler source to `99e94ae6099edabce1c6d621eca4c4904e3c2324`. It refuses an
existing destination. Already having that compiler is sufficient: set `V` to
its executable. `kernel/get-deps` pins the kernel dependency revisions.

`build.sh` cleans kernel objects before each mode. It writes the two ELF files,
compiler versions, full build logs, verification output, strict driver objects
and `SHA256SUMS` under `tests/m1-wifi/out/`. A failed build exits nonzero and
never issues a success checksum manifest. Do not run simultaneous builds in
one checkout. Different compiler versions/absolute paths may change the debug
information and hashes; the script provides a repeatable procedure, not a
cross-host byte-identical-build guarantee.

The console source already contains the Wi-Fi initialization and polling
hooks. Do not apply the obsolete experimental bundle's `apply-console.py`.
There is no need to change source lists or paste integration snippets.

Build the control utility with the compiler for the target ARM64 **userspace**
sysroot, not the freestanding kernel compiler:

```sh
cc -std=c11 -O2 -Wall -Wextra -Werror -iquote kernel/c tools/m1-wifi/wifi-ctl.c -o wifi-ctl
```

Here `cc` must target the userspace you intend to run. Include the utility and
locally selected firmware in a test initramfs. The supplied ELF files are
kernel-only build artifacts, not an installed boot image or hardware test.
Keep your existing m1n1/U-Boot/Limine chain and a known-working boot entry.

## Firmware and association

No proprietary firmware is included or downloaded. Firmware, textual board
NVRAM, CLM and TXCAP must be extracted locally and explicitly selected for the
reported chip revision, `apple,shikoku` board, module, vendor, module revision,
and antenna. The per-device calibration blob comes from the device tree.
Do not substitute files from a different Mac or bypass power/regulatory limits.

1. Boot the experimental entry and run `wifi-ctl status`. A successful probe is
   `chip detected`, **not** a connected radio. Save `wifi-ctl status-raw status.bin`.
2. On the build host, run `tools/m1-wifi/package.py --status status.bin
   --firmware MATCHING.bin --nvram MATCHING.txt --clm MATCHING.clm_blob
   --txcap MATCHING.txcap_blob --output wifi-bundle`. Paths are explicit: the
   script does not guess a firmware filename hierarchy. Its identity manifest
   does not prove that the supplied files are appropriate; correct selection
   remains required. SHA-256 provenance records are provided for auditing.
3. Include the resulting directory in the test initramfs, then use
   `wifi-ctl load /path/to/wifi-bundle` and `wifi-ctl join 'SSID'`.
   The utility prompts with terminal echo disabled; it does not take a password
   through argv or write one to a configuration file.

`firmware ready` and `authenticating` are not success. `authenticated link`
requires a successful association event **and** firmware confirmation that WPA2
keys are established. There is no open-network or weaker-security fallback.

The receive/transmit ABI is raw Ethernet through `/dev/wlan0`; readers must
handle EAGAIN and preserve complete frames. It is not a socket/IP interface.
The fixed-size ioctl ABI is documented in `kernel/c/brcm_m1.h`; it exposes no
kernel pointers or arbitrary register access. Device permissions are 0600. Vinix does not yet have a complete credential/
capability model; the mode is not a substitute for enforcing a multi-user
security boundary. Use a controlled, single-user bring-up image.

## Failure and unsupported behavior

Timeouts, malformed completions, DART faults, link loss, unexpected deep-sleep
requests, unsupported firmware, or unsupported security stop the driver.
Bus mastering is disabled and the Wi-Fi DART stream is revoked; allocations are
quarantined for the rest of the boot rather than reusing memory that may have
outstanding DMA. Initialization is one-shot. Reboot to retry after a fatal error,
interrupted upload, disconnect, or stopped state.

This is not a suspend/resume implementation. Bluetooth shares the physical
combo-chip reset and may be affected; takeover is refused when it is observed
bus-mastering. Trackpad/keyboard drivers are unrelated. WPA3, enterprise Wi-Fi,
AP mode, scanning UI, roaming, reconnect, powersave, and IPv4/IPv6/socket support
are not implemented. These limitations are substantial: this bundle is a
bring-up contribution, not a completed answer to making normal networking work.

## Primary implementation references and licensing

Wire layouts and chip procedures were checked against OpenBSD `sys/dev/pci/
if_bwfm_pci.{c,h}` and `sys/dev/ic/bwfm{,reg}.{c,h}`. The core retains the ISC
notice. Apple PCIe sequencing follows U-Boot `drivers/pci/pcie_apple.c`;
DART formats follow Linux `drivers/iommu/apple-dart.c` and `io-pgtable-dart.c`.
FullMAC firmware download/security behavior also references Linux's
`drivers/net/wireless/broadcom/brcm80211/brcmfmac/` implementation. Apple machine
properties are from Linux `arch/arm64/boot/dts/apple/t8103*.dts*`. These are
protocol/register references, not evidence that this implementation works on
real hardware.
