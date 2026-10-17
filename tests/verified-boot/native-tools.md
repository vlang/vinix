# Native verified-root and verified-boot tooling

The maintained builders, pinned Limine loader builder, host checks and guest
controllers now run V directly. This stage retires ten Python files, totaling
55,350 original bytes. The native algorithms already used by the old bridges
remain the shared `verityimage` and `bootpolicy` implementations; Python import,
JSON request and ctypes adapters are no longer needed by these commands.

| Former command | Native command |
| --- | --- |
| `tools/verified-root/build.py` | `tools/verified-root/build` |
| `tools/verified-boot/build.py` | `tools/verified-boot/build` |
| `tools/verified-boot/get-loader.py` | `tools/verified-boot/get-loader` |
| `tests/verified-root/test.py` | `tests/verified-root/test` |
| `tests/verified-root/run-host.py` | `tests/verified-root/run-host` |
| `tests/verified-root/runtime.py` | `tests/verified-root/runtime` |
| `tests/verified-boot/test.py` | `tests/verified-boot/test` |
| `tests/verified-boot/runtime.py` | `tests/verified-boot/runtime` |

Both `_native.py` import bridges are retired with their last callers. Shell
entry points select V with the repository bootstrap and compile outside the
checkout. `build-support/sparse-file` replaces the inline Python example for
creating a new filesystem image; exclusive `open(2)` prevents replacement of
an existing file or dangling symlink.

The bundle builder enrolls the configuration digest before signing a genuine
unsigned PE loader. Verification checks its signature against a separately
supplied certificate, the canonical configuration, exact artifact inventory,
architecture, every artifact hash and optional verified-root image geometry.
Publication follows verification in a private directory on the destination
filesystem. Negative cases never publish a completed bundle. Private keys and
certificates are not bundled.

The loader builder authenticates the pinned 12.9.3 source archive before
extraction, rejects unsafe tar members, applies the existing ARM base-revision
patch and builds the requested UEFI architecture. The source SHA-256 is
`b28b9c9f614f4252cae79580d6cbbc09f4d764a541ec01d586b5c385e3776c99`.

The host verifier test copies the unchanged production V verifier and SHA
implementations into a private directory, emits isolated C, and invokes their
C ABI. The dynamic library explicitly matches the controller architecture on
macOS, including Rosetta. Its `int` return uses the C-width `i32` ABI. The test
checks 267 SHA inputs against independent V crypto, 139 geometry inputs and
the maximum supported data count of 2,234,207,627,640,830 without allocating an
enormous image. The input generator is a stable local xorshift stream seeded
with 734; it replaces the Python random stream while preserving the boundary
lengths and independent oracle. The production object must have no allocator
imports. Normal and ASan/UBSan C harnesses verify six actual image sizes.

Guest controllers retain separate raw serial and QEMU diagnostic logs, and
own a process group per emulator. Return, rejection, timeout and interrupt
close the group before removing its private variable-store copy. Root probing
waits for the complete READY marker and the independently located ext2 block,
then flips and synchronizes one byte. A negative case that reaches init or
launches the boot fixture fails even if the expected rejection text also
appears. Secure test keys are removed on every outcome.

Secure Boot enrollment uses a bounded native V editor for private EDK II
authenticated variable-store templates. It preserves unrelated live records
and bytes outside the store, installs the temporary X.509 anchor in PK, KEK
and db, enables Secure Boot and checks capacity before publication. It does
not edit host firmware. Layout and GUID authorities are the upstream EDK II
[variable format](https://github.com/tianocore/edk2/blob/master/MdeModulePkg/Include/Guid/VariableFormat.h),
[image authentication](https://github.com/tianocore/edk2/blob/master/MdePkg/Include/Guid/ImageAuthentication.h),
[authenticated-variable definitions](https://github.com/tianocore/edk2/blob/master/SecurityPkg/Include/Guid/AuthenticatedVariableFormat.h)
and [SecurityPkg GUID declarations](https://github.com/tianocore/edk2/blob/master/SecurityPkg/SecurityPkg.dec).
An explicit `--virt-fw-vars` override must select a native executable.

## Qualification

Qualification on 2026-10-11 used pinned V 0.5.2 `81be246`, ARM and Rosetta x86
host executables, plus ARM ASan/UBSan. Thirty cold builds cover eight maintained
commands, the native contract checker and sparse-file command. The corrected
host-library architecture was rebuilt and checked on all three profiles.
All nine public shell launchers compile and pass their help checks.

The root suite, production verifier host suite, bundle parser/tamper suite
and genuine loader signature integration pass through all three host
profiles. Signature checks use real `osslsigncode`, temporary RSA certificates
and both architecture loaders, including rejection with a different trusted
certificate and after modifying the signed field. Synthetic PE bytes are
parser fixtures only. Real pinned Limine builds pass for both target
architectures, including an x86 host controller; all three profiles reject a
wrong source digest before publishing output.

Native contract checks cover decimal parsing and error status, repeated
initramfs arguments, malformed firmware stores, durable byte mutations and
100 repeated success/file-error/geometry-error cycles with flat descriptor
counts. Sparse-file checks on all three profiles cover size, exclusivity,
dangling symlinks, missing parent directories and invalid or oversized sizes.
Twelve complete controlled QEMU observer runs cover acceptance and forbidden
launch rejection. Six interrupt runs return 130. Every recorded observer PID
is retired, per-scenario variable copies are gone and test keys are absent.
These controlled runs establish controller behavior; the actual guest
results below provide boot and kernel evidence.

| Actual QEMU guest | Passed cases |
| --- | --- |
| ARM verified-boot fixture, firmware Secure Boot disabled | valid launch, altered config, kernel and initramfs rejected |
| x86 verified-boot fixture, firmware Secure Boot enabled | the four cases above; a signed unhashed profile rejected by Limine; unsigned and modified loaders rejected by firmware |
| ARM frozen production kernel, verified root | valid read-only root and live data corruption; metadata, init data, top and leaf tree, truncation, wrong root, duplicate/conflicting/malformed policy, missing mountpoint rejected |
| x86 frozen production kernel, verified root, firmware Secure Boot enabled | all eleven root cases above; unsigned and modified loaders rejected by firmware |

The valid production-kernel scenario includes 1,000 repeated reads and 1,000
mmap cycles with slab retention checks, and live backing-image corruption
after cached reads. The frozen ARM kernel SHA-256 is
`8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`.
No kernel was rebuilt and no Python was run. ARM firmware trust enrollment
and optional Linux `veritysetup` interoperability were not qualified in this
stage. Supply an actual `--veritysetup` executable to run that optional test.

Retained original bytes, cold-build logs, full host-suite output, controlled
observer receipts and final loader-build output are under
`/Users/alex/.cache/vinix-python-zero-process-20261011`, which resolves to the
private scratch volume. Actual guest logs, signed bundles and fixture
manifests are under `/Volumes/VinixPythonDotaScratch/verified-runtime-arm`,
`verified-runtime-x86-secure-3`, `verified-root-runtime-arm` and
`verified-root-runtime-x86-secure`. Their raw serial/QEMU logs are actual
guest evidence. Directories prefixed `verified-model-` or
`verified-interrupt-` contain controlled-observer evidence only. These scratch
volumes subsequently detached on 2026-10-11, so those local receipts are no
longer available. The recorded results above describe the completed checks;
they do not imply the scratch artifacts still exist. Later Minecraft checks
retain their fresh receipts on disk as described in
[native-tools.md](../../build-support/minecraft/native-tools.md).

Run the host checks with:

```sh
tests/verified-root/test
tests/verified-root/run-host
tests/verified-boot/test --backend osslsigncode \
    --aarch64-loader /path/to/BOOTAA64.EFI \
    --x86_64-loader /path/to/BOOTX64.EFI
build-support/run-v-tool.sh tests/verified-boot/check-native.v
```
