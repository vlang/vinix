# Authenticated UEFI boot

This optional build path authenticates the EFI loader, its complete boot
configuration (including the command line), the kernel, every initramfs overlay,
and an optional device tree. It boots the root supplied by those authenticated
archives in memory. It refuses the current disk root and persistent home
selectors, which would bring unauthenticated disk contents into the boot path.
The normal ISO and desktop builders still produce development images.

The trust chain is:

1. UEFI Secure Boot accepts only an EFI executable authorized by its firmware
   signature databases.
2. The signed Limine executable contains the BLAKE2b-512 hash of the exact
   `limine.conf` bytes. Configuration enrollment happens **before signing**.
3. That configuration contains BLAKE2b-512 digests for the kernel, each root
   archive/overlay in order, and any supplied DTB. Limine verifies them before
   handing control to the kernel.

The hashes are not themselves trust anchors. Authentication requires Secure
Boot enabled outside Setup Mode and the signing certificate authorized in the
firmware's `db`, with appropriate `PK`/`KEK` administration. Signing an
unenrolled Limine loader alone does not authenticate its configuration or root.
The tool always enrolls the configuration and verifies the resulting PE
signature against a certificate supplied separately from the output tree.

## Build

Python 3.9+, Clang, LLVM (`ld.lld`, `llvm-ar`, `llvm-objcopy`), make and patch
are needed to obtain a loader. `get-loader.py` downloads the same repository
pinned Limine 12.8.0 source archive as `build-limine-aarch64.sh`, checks its
SHA-256 before extraction, and builds the UEFI port for either architecture.
For aarch64 it applies the existing Vinix protocol base revision 2 patch.
An offline archive may be supplied with `--source-archive`.

```sh
python3 tools/verified-boot/get-loader.py --arch x86_64 --output build/verified-limine-x86_64
python3 tools/verified-boot/get-loader.py --arch aarch64 --output build/verified-limine-aarch64
```

Use a privately held PEM signing key and a PEM X.509 certificate. The operator
must arrange firmware trust enrollment; these tools never change firmware keys.
Build the Vinix kernel and root archive with the existing architecture builder,
then assemble a new bundle:

```sh
python3 tools/verified-boot/build.py build --arch x86_64 \
    --loader build/verified-limine-x86_64/BOOTX64.EFI \
    --kernel build-amd64-kernel/bin/vinix \
    --initramfs build-amd64-userland/initramfs.tar \
    --key /private/signing/db.key --certificate /private/signing/db.crt \
    --output build/verified-boot-x86_64

python3 tools/verified-boot/build.py verify build/verified-boot-x86_64 \
    --arch x86_64 --certificate /private/signing/db.crt
```

The default signature backend is `sbsign`/`sbverify` from sbsigntools.
`--backend osslsigncode` uses real Authenticode signing and verification on
macOS or Linux instead; use the same backend when verifying. Additional
authenticated overlays are specified with repeated `--initramfs` arguments.
`--dtb` adds a file whose contents are pinned; `--cmdline` pins literal hardware
options. Root/disk/persistence options and configuration/macro injection are
rejected. All loaded paths carry hashes even when Secure Boot is disabled.
The private key and certificate are never copied into the bundle.

The output is an EFI system partition tree with `EFI/BOOT/BOOTX64.EFI` (or
`BOOTAA64.EFI`) and `boot/limine.conf` plus its authenticated payloads. Copy that
tree to a FAT EFI system partition, or attach it to QEMU as a read-only FAT
drive. Preserve every file byte after signing; rebuild and sign a new bundle
when changing an archive, kernel, command line, or loader. The verifier rejects
symlinks, missing files, unexpected files, unsigned input in signed mode,
architecture mismatches, unsafe root selectors, and every digest mismatch.

`--developer-unsigned` is an explicit unauthenticated mode for local testing.
It still checks enrolled configuration and artifact hashes; anyone who can
replace the EFI executable can replace those hashes. It does not establish
boot authentication.

## Verification

Host policy regressions:

```sh
python3 tests/verified-boot/test.py
```

Real signature regressions, with actual built Limine executables:

```sh
python3 tests/verified-boot/test.py --backend osslsigncode \
    --x86_64-loader build/verified-limine-x86_64/BOOTX64.EFI \
    --aarch64-loader build/verified-limine-aarch64/BOOTAA64.EFI
```

These generate temporary RSA test keys and verify accepted signatures, rejection
with an unrelated certificate, a modified signed configuration hash, and changes
to configuration, kernel and initramfs bytes. They never use simulated signing.

The QEMU runtime test compiles a small Limine protocol fixture kernel that
requires the module response, then boots the real loader. It tests successful
handoff and rejection of modified config, kernel and initramfs. It is a
bootloader enforcement test; the fixture is not the Vinix kernel.

```sh
python3 tests/verified-boot/runtime.py --arch x86_64 \
    --loader build/verified-limine-x86_64/BOOTX64.EFI \
    --firmware-code /path/to/edk2-x86_64-secure-code.fd \
    --firmware-vars /path/to/edk2-i386-vars.fd \
    --logs /tmp/vinix-verified-x86_64 \
    --secure-boot --virt-fw-vars /path/to/virt-fw-vars --backend osslsigncode
```

`--secure-boot` generates a temporary certificate, enrolls it into a **copy** of
the VM variable store's PK, KEK and db, and boots through Secure Boot firmware.
It also checks that firmware rejects unsigned/modified EFI loaders and that
Limine rejects an intentionally signed configuration with an unhashed module,
even when that config requests relaxed hash handling. This last case verifies
that Limine observes Secure Boot being enabled. The template and host firmware
are never modified. `virt-fw-vars` is supplied by the `virt-firmware` package.
For aarch64 use `--arch aarch64`, its loader and `edk2-aarch64-code.fd` with
`edk2-arm-vars.fd`; omit `--secure-boot` if that firmware does not implement
Secure Boot. The test states when firmware authentication was not exercised.

## Scope

The initial root contents are authenticated; they remain writable tmpfs after
unpacking. This path does not implement dm-verity, ongoing disk integrity,
runtime MAC policy, antirollback, attestation, firmware certificate enrollment,
or production key/revocation management. A signing key authorizes all bundles
signed by it; preventing rollback to an earlier signed bundle needs a separately
deployed version/revocation policy. Trusted firmware, signing infrastructure,
local build inputs and the deployed trust databases are part of the boundary.
BIOS boots and the Apple Silicon m1n1/U-Boot deployment do not gain firmware
authentication from this UEFI signing path. Application launchers must still
apply their sandbox and operational policy.

Limine's [12.8.0 Secure Boot documentation](https://github.com/Limine-Bootloader/Limine/blob/v12.8.0/USAGE.md)
describes enrolled configuration hashes, required file hashes, forced failure
on mismatches, and disabled configuration editing under Secure Boot.
The enrolled configuration hash is checked even when Secure Boot is disabled
in [its configuration loader](https://github.com/Limine-Bootloader/Limine/blob/v12.8.0/common/lib/config.c).
