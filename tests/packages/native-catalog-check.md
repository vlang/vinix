# Native SDK catalog qualification

The [publisher profile](../../tools/packages/SDK.md#native-sdk-publisher-profile)
pins the six Hello/Counter/Memo variants in a canonical lock. The
[V builder](../../examples/package-catalog/build.v) compiles static executables
for both supported hosts, retains SDK/V/musl notices and creates one publisher
workspace without generating trust keys or enrolling repositories.

`pkgcore/native_profile_test.v` exercises deterministic locks, exact agreement
with all six existing example manifests, permissions and protocol declarations,
signed offline installation on both target configurations, registration removal
and rollback. It rejects missing/linked roots, wrong machines/interpreters,
nonexecutable/empty files, missing notices, noncanonical versions, insufficient
space, post-preflight executable/notice changes, substituted notice directories
and altered staged metadata.
An existing or concurrently created destination is preserved. Failed builds
remove unpublished profile staging directories. Structural fixtures use synthetic
headers; they are not executable runtime qualification.

The [guest controller](native-catalog-check.v) imports the real builder's prepared
roots and lock into fresh QEMU TCG guests. The guest regenerates the identical
1.0.0 lock, prepares 1.1.0 metadata over the same binary bytes and publishes two
complete signed releases with a fixture key. It uses authenticated enrollment
and reviewed CLI transactions to install the architecture-matching closure.
The checks require Hello to read an explicitly granted text document, Counter
to persist a click, and Memo to save/reopen literal UTF-8 text through protocols
1 and 2 under the isolated ordinary launch account. Private files must belong to
UID 1000. Installed manifests retain notices and publisher identity; launchers
are present only while installed.

Upgrade must expose version 1.1.0 through the SDK; rollback returns to 1.0.0.
Both retain and reopen the count and memo. After another upgrade, uninstall and
collection remove application registration while retaining private data. The
fixture then hides repository objects and requires reinstall from verified cache
with working apps and unchanged data. Required markers and guest-initiated clean
poweroff determine success; the receipt hashes the kernel, init, service,
account/session/sandbox programs, all inputs and serial/QMP logs.

Reproduce with a reviewed V compiler, both musl GCC compilers, target kernels
and target sandboxes:

```sh
V=/path/to/v /path/to/v -path '@vlib|@vmodules|.' run \
  examples/package-catalog/build.v 1.0.0 /build/new-native-inputs
/path/to/v -path '@vlib|@vmodules|.|tests/hardware-platform' \
  -o /tmp/native-check tests/packages/native-catalog-check.v
VINIX_HWTEST_TCG=1 V=/path/to/v VFLAGS=-nocache \
  VINIX_NATIVE_CATALOG_INPUTS=/build/new-native-inputs \
  VINIX_NATIVE_CATALOG_SANDBOX=/build/aarch64-root/usr/bin/vinix-sandbox \
  /tmp/native-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-native-aarch64
```

Repeat for x86_64 with its kernel/sandbox and a new short state path; select
`VINIX_AMD64_LIMINE_DIR` when needed by the hardware-platform controller.

This qualifies native stream/application maintenance, with headless Software
metadata inspection. Full graphical login/display interaction, public publisher
enrollment, legacy Alpine catalog migration and broader Windows/Apple runtime
coverage remain separate roadmap requirements. The builder's receipt pins actual
output; it does not promise hermetic or cross-toolchain binary reproduction.

## Recorded results, 2026-10-14

Six host core assertion runners passed: native profile, catalog, composition,
import, release and distribution. The final profile runner, including the
post-preflight directory refusal, passed again after the inventory guard and
source-location cleanup. Its clang ASan/UBSan run passed with leak detection
disabled and undefined behavior fatal; this is not a leak-freedom claim.

The full signed CLI lifecycle passed again with the final service. The new
CLI command regenerated the builder's exact catalog, and pinned import produced
the identical workspace lock. Missing arguments/invalid versions were refused.
The builder preserved existing output and removed partial output after a missing
musl notice. The initial six-app build retained generated-C compiler notices;
this is not a warning-free build claim.

Both final TCG guests passed all required markers and clean poweroff: AArch64
in 103.984 seconds and x86_64 in 141.776 seconds. They freshly built
init and the service from the final inventory-guard implementation and reused
the retained target kernels and production sandboxes, whose hashes are in the
receipts. No concurrently edited kernel source was rebuilt. The controller
checks each prepared input hash before staging both architectures as publisher
data. Earlier preboot controller attempts rejected the foreign binaries as
suite executables; the final controller uses a separate, pinned data import.

Retained evidence: [host checks](results/2026-10-14/native-catalog-host.txt),
[final CLI](results/2026-10-14/native-catalog-final-cli.txt),
[final profile](results/2026-10-14/native-catalog-profile.txt),
[sanitizer output](results/2026-10-14/native-catalog-sanitize.txt),
[build receipt](results/2026-10-14/native-catalog-build.json),
[catalog lock](results/2026-10-14/native-catalog-lock.json),
[AArch64 receipt](results/2026-10-14/native-catalog-aarch64.json),
[serial](results/2026-10-14/native-catalog-aarch64.serial.txt),
[QMP](results/2026-10-14/native-catalog-aarch64.qmp.txt),
[x86_64 receipt](results/2026-10-14/native-catalog-x86_64.json),
[serial](results/2026-10-14/native-catalog-x86_64.serial.txt),
[QMP](results/2026-10-14/native-catalog-x86_64.qmp.txt) and
[source/toolchain/artifact ledger](results/2026-10-14/native-catalog-toolchain.json).
