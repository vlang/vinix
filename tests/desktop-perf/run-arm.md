# ARM six-scenario preparation

`run-arm.v` implements the fixed `new=DESKTOP` workload
`ops,churn,cache,idle,apps,drag`, one round, settle 3 seconds, measure 5 seconds,
3072 MiB RAM and a 2400-second adapter deadline. It supports absolute ARM
flatness and allocation-site measurements. It does not supply an ARM baseline
or establish a paired delta. `measure.c`, `perf-init.sh`, `perfrunner` and the
foreground process owner are shared with the existing x86 path.

The adapter accepts `check|prepare REPO BASE_ARCHIVE KERNEL FRESH_STATE
new=DESKTOP` with the fixed options above and a required
`--base-manifest-sha256=SHA`. The maintained foreground supervisor selects
the typed tools and environment, inventories the complete compiler and
source roots, and owns preparation and its sampled live disk budget.
`check` does not stage or run a guest. `run STATE PREPARED_SHA256` requires
the unchanged prepared receipt. Generated C, build argv/logs, ELF inspection,
sources, manifests, media and eventual results stay in the external state.

Preparation compiles the V PID1 with `-nocache`, generates static AArch64
PID1 and measure ELFs, and retains readelf headers, segments and dynamic
sections. Its explicit clang argv disables default config, default headers
and default libraries; it selects GCC includes/crt/libgcc, musl headers/crt
and libc from the named sysroot and a named `ld.lld`. The entire sysroot is
hashed in place, with literal guest links. The installed host loader and
compiler dependency closure are not claimed hermetic. Runtime-name presence
in the base archive is checked for true, sleep, busybox, zsh, curl and the
musl loader; this is not a DT_NEEDED closure proof.

The FAT boot image uses the existing ARM UEFI layout (`EFI/BOOT/BOOTAA64.EFI`,
`boot/limine.conf`) and two ordered modules: unchanged base then overlay.
The reviewed native implementations in `hwhost/boot.v`,
`verifiedhost/runtime.v` and `systemhost/storage.v` use this firmware/media
layout and explicit PCI boot disks. The new command fixes the boot FAT as
read-only `virtio-blk-pci` and attaches only the ext2 workload disk through
`virtio-blk-device`. The kernel's `aarch64/virtio_blk/virtio_blk.v` scans
MMIO slots and names the first block device `vda`; a PCI boot disk is outside
that scan. PID1 therefore mounts `/dev/vda` at `/root`. The new exact command
has not yet been boot-qualified. Firmware variables are copied privately,
and no networking is enabled. The kernel receives no persistent-root/home
request; its blank workload volume cannot provide a bootable system root.

The candidate inputs observed on 2026-10-26 are listed below. These historical
observations supply no approved runtime authority; a fresh reviewed profile
and original complete kernel audit check are required before consumption.

| Input | Absolute path | SHA256 |
| --- | --- | --- |
| Atomic ARM ELF | `/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-kernel-20261026/kernel-aarch64/bin/vinix` | `1111f8d6451a0ab94361c3ebf006e9ceed62baea9dd395ac0a5c3caa7fb3a254` |
| Desktop | `/Users/alex/code/vinix/build/graphical-login-desktop-aarch64-5/vinix-desktop` | `a91d3f2cb738b6259205bc11d43850bc47054c152d3b64c489f5525dede975f6` |
| Base archive | `/Users/alex/code/vinix/build-support/init-aarch64/initramfs.tar` | `3744aa5d11c60d156eb0e545447b17c82ae1c79cdde9964b4eba9edf4fe41157` |
| Firmware code | `/Users/alex/code/vinix/boot-image/edk2-aarch64-code-2048x1536.fd` | `49e45a5d496944dd4f328cb662f889412c1fcae00698d334e16b39466fb57eac` |
| Firmware variables | `/opt/homebrew/share/qemu/edk2-arm-vars.fd` | `b3b855c5a80310168051164986855692d1bdb06e67619856177965cd87c6774f` |
| Limine | `/Users/alex/code/vinix/boot-image/limine-bin/BOOTAA64.EFI` | `3a23c79b75dd78fbacb6430472ce4aa5e90ef89089a4970459a0282cf44ccb4f` |

The selected sysroot is `/Users/alex/code/vinix/build-aarch64-userland/staging`;
GCC is its existing `usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0` directory.
Its `lib/ld-musl-aarch64.so.1` is regular; no guest-loader symlink exception is
required for this selection. The proposed linker alias is
`/opt/homebrew/opt/lld/bin/ld.lld`, whose referent is `lld`.

The projected ARM runtime reserve is 2,097,152 KiB: about a 1 GiB boot FAT,
64 MiB private variables, 256 MiB ext2 and overlay/build/log reserve. The
earlier retained-scope estimate 2,023,344 KiB plus that reserve and 131,072 KiB
growth totals 4,251,568 KiB, below the existing 4.5 GiB ceiling. This is a
proposal, not admission: all charged roots, existing usage, fresh df, exact
tool/source/input pins and the final profile require review before staging.
Space consumed by other active work must be included or coordinated.

Status: normal and production host adapters each passed eighteen controls;
host owners each passed the historical twenty-four and sixteen ARM controls.
Six limit admission controls also passed. The retained host-only bundle
passed the unchanged original full evidence seal, separate check and independent
root check. See `foreground-supervise-report.md` for exact receipts.
Guest PID1 and measure cross-compilation, a reviewed preparation profile,
staging, actual PCI firmware boot, all six scenario results and allocation-site
symbolization remain pending. Runtime disk admission remains held.
