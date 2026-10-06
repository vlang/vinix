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

* `kernel/apple/wifi/wificore/core.v` and `kernel/c/brcm_wifi.h`: BCM4378 core inventory/OTP, firmware bootstrap,
  board NVRAM packing, CLM/TXCAP/calibration loading, PCIe message rings,
  completion ownership, firmware commands, radio control, network scanning,
  WPA2-PSK/CCMP, and raw Ethernet.
* `kernel/apple/wifi/m1core/` and `kernel/c/brcm_m1.h`: Apple PCIe port reset/clock sequencing, BAR allocation,
  a bounded 4 MiB DART mapping, exact-width MMIO and cache maintenance, loader
  staging, diagnostics and a bounded receive queue.
* `kernel/apple/wifi/wifi.v`: J313 device-tree validation, PMGR and MMIO
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

Current V core validation: 26 protocol groups (including 100,000 parser
mutations) and seven simulated-platform groups pass with Clang ASan/UBSan
and no allocator imports. Both architecture builds and QEMU boot/syscall
checks pass. Physical firmware boot, association and DMA remain unverified.
The SPI keyboard and touchpad regression groups also pass. The
full kernel still emits existing V notices and third-party warnings; this is
not a claim that the whole tree is warning-free. The control utility is tested
on the host and cross-built as a static AArch64 binary for the desktop image;
target userspace execution has not been validated on hardware.

The independent protocol machine and its 98 assertions now live in
`protocolfixture/` as V. `run-protocol.py` compares all 26 groups and
100,000 parser mutations against immutable C fixture bytes from
`09e70d945ca7d63ebc4969213994afab9e7e1dbe` on ARM and x86 hosts. Both
native model guests require every original group marker. These results
cover injected firmware/ring behavior; physical Wi-Fi remains unverified.
The platform fixture and all 29 assertions now live in `platformfixture/`.
`run-platform.py` compares the eight original simulated MMIO policy groups
against the same immutable revision; ARM and x86 native guests exercise every
group using the unchanged production cores and injected platform hooks.

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
python3 tools/m1-wifi/compile-v.py /tmp/wifi-ctl.c --arch arm64
cc -std=gnu11 -O2 -fwrapv -fno-strict-aliasing -Wall -Wextra -Werror \
  -Itools/m1-wifi -iquote kernel/c /tmp/wifi-ctl.c -o wifi-ctl
```

Here `cc` must target the userspace you intend to run. Include the utility and
locally selected firmware in a test initramfs. The supplied ELF files are
kernel-only build artifacts, not an installed boot image or hardware test.
Keep your existing m1n1/U-Boot/Limine chain and a known-working boot entry.

`python3 tests/m1-wifi/run-ctl.py` runs the maintained V utility against an
independent native device fixture with ASan/UBSan. The same 11 scenarios run
in ARM and x86 QEMU using `run-ctl-vm.py --arch aarch64|x86_64
--kernel-dir <isolated-kernel> --state-dir <new-directory>`. These fixtures
check control messages, polling, terminal restoration, credential wiping and
file validation; physical firmware/association remain unverified.

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
3. For a desktop image, run `./scripts/build-desktop-aarch64.sh
   --wifi-bundle=/path/to/wifi-bundle`; the image includes `wifi-ctl`, stages
   the bundle, and runs its identity-checked loader before the desktop. For a
   different test image, include the utility and bundle yourself, then use
   `wifi-ctl load /path/to/wifi-bundle`. Use `wifi-ctl scan` to start a bounded
   asynchronous scan and `wifi-ctl networks` to show its results. `wifi-ctl off`
   and `wifi-ctl on` reversibly control the firmware radio. To associate, run
   `wifi-ctl join 'SSID'`.
   The utility prompts with terminal echo disabled; it does not take a password
   through argv or write one to a configuration file.

`firmware ready` and `authenticating` are not success. `authenticated link`
requires a successful association event **and** firmware confirmation that WPA2
keys are established. There is no open-network or weaker-security fallback.

The receive/transmit ABI is raw Ethernet through `/dev/wlan0`; readers must
handle EAGAIN and preserve complete frames. It is not a socket/IP interface.
The fixed-size status, radio, scan and network-list ioctl ABI is documented in
`kernel/c/brcm_m1.h`; it exposes no kernel pointers or arbitrary register
access. Device permissions are 0600. Vinix does not yet have a complete
credential/capability model; the mode is not a substitute for enforcing a
multi-user security boundary. Use a controlled, single-user bring-up image.

The desktop's **Settings > Wi-Fi** pane uses the same bounded ABI. It can turn
the radio on or off, request a scan and list the strongest result for each
SSID/security pair. Firmware loading and WPA2 credential entry intentionally
remain in `wifi-ctl`.

## Failure and unsupported behavior

Timeouts, malformed completions, DART faults, link loss, unexpected deep-sleep
requests, unsupported firmware, or unsupported security stop the driver.
Bus mastering is disabled and the Wi-Fi DART stream is revoked; allocations are
quarantined for the rest of the boot rather than reusing memory that may have
outstanding DMA. Initialization is one-shot. `wifi-ctl off` is reversible;
reboot to retry after a fatal error, interrupted upload, disconnect, or the
one-way `wifi-ctl stop` command.

This is not a suspend/resume implementation. Bluetooth shares the physical
combo-chip reset and may be affected; takeover is refused when it is observed
bus-mastering. Trackpad/keyboard drivers are unrelated. WPA3, enterprise Wi-Fi,
AP mode, joining from Settings, roaming, reconnect, powersave, and
IPv4/IPv6/socket support are not implemented. These limitations are
substantial: this bundle is a bring-up contribution, not a completed answer to
making normal networking work.

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
