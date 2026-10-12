# Native development workflow checks

Stage the four development commands with the maintained V stager, then run
the guest controller against an already-built isolated production kernel:

```
v -gc none -cc cc run tools/development/stage.v aarch64 /tmp/development-arm
tests/development/run-guest aarch64 /path/to/kernel /tmp/development-arm /tmp/new-arm-state

v -gc none -cc cc run tools/development/stage.v x86_64 /tmp/development-x86
tests/development/run-guest x86_64 /path/to/kernel /tmp/development-x86 /tmp/new-x86-state
```

The V controller validates the completed staging manifest, each tool's SHA-256
and ELF architecture, copies the input kernel, compiles the V fixture and owns
QEMU without networking. AArch64 selects HVF on macOS by default; set `USE_TCG=1`
to use TCG. Each state directory must be new. No Python executes.

The fixture requires the Vinix kernel identity and runs the public CLIs as
UID/GID 1000. It checks all four help entry points, schedule/account binding,
a real scheduled job, selected credentials and environment, private plan/state
ownership and modes, interval coalescing, and refusal of public or symlinked
credential files. The payload deliberately writes the synthetic credential to
both stdout and stderr; the controller fails if it appears in the serial log.
Successful jobs produce a file, and rejected jobs must produce none.

The same ordinary account then runs a pinned build plan in two new workspaces.
Its prebuilt V payload reads through a copied internal symlink, checks the fixed
build epoch and sanitized environment, and writes an artifact. The fixture
checks source/link preservation, account-owned private output/HOME/temporary directories and actual artifact
contents. The controller independently checks both native receipt hashes against
the expected bytes. Altering the pinned source must stop the next build before
execution. This tests runner behavior with a prebuilt payload; compiling all
Vinix layers inside an installed system remains open.

To compile and execute the C/C++ reference projects in the guest, supply a
prepared native musl GCC SDK for the selected architecture:

```
tests/development/run-guest aarch64 /path/to/kernel /tmp/development-arm /tmp/new-sdk-state /path/to/aarch64-linux-musl-native
```

The controller copies the SDK to `/opt/native`, installs its runtime libraries
in the guest's `/lib`, and supplies `cc`/`c++` aliases to its native drivers.
It validates the drivers' ELF architecture and records a deterministic closure
hash over copied paths, permission bits, file bytes and links, including the
runtime copy. Relative links must stay inside the SDK; `/lib/libc.so` is the
only accepted absolute link target. Unused `.py`, `.pyc` and `.pyo` helpers are
excluded before copying. The SDK is prepared input, not downloaded or built by
this controller. Compiler workloads receive 2 GiB of guest RAM.
The musl loader link is normalized to its adjacent `libc.so`, so the copied
SDK and runtime are portable closures that `vinix-build` can pin.

As UID/GID 1000, the fixture invokes `vinix-qualify --require-vinix` for `c,cpp`.
Both projects must compile with symbols, create/join a thread, write/read a
file and execute their exact resulting binary. The controller independently
checks the native report's kernel, architecture, account, runner and compiler
hashes, both successful command statuses and the executed artifact paths.
Compiler versions remain in the serial transcript. A missing compiler or
failed project fails the run.

For the native V reference project, append a prepared V installation root
(containing `v`, its matching `vlib`, `thirdparty` and `cmd`) and a native
BusyBox executable with its shell applet. A static BusyBox avoids additional
loader dependencies:

```
tests/development/run-guest aarch64 /path/to/kernel /tmp/development-arm /tmp/new-v-state /path/to/aarch64-linux-musl-native /path/to/vlang /path/to/native-static-busybox
```

This copies and hashes the V root with Python helpers excluded, installs the
compiler beside its matching library at `/usr/lib/vlang`, checks V/BusyBox ELF
architectures and records both executable hashes. The V project uses the
explicit Vinix/musl target, serial V3 workers and the native C compiler. It
must compile, write/read a file and execute its resulting binary. These runs
receive 3 GiB of RAM. Failed qualification retains bounded command-log excerpts
in the serial transcript as well as the native report.

V runs also copy this repository's `fetch`, `mount`, `chsh` and `lscpu` sources and
generate a build plan pinning those sources, V, GCC, the shell and the complete
SDK/V/runtime trees. UID/GID 1000 builds them in two fresh workspaces with
private HOME/temporary directories, then executes each recorded artifact's
`--version` entry point. The fixture checks ownership, executable ELF headers
and expected utility output. `lscpu` also runs its CPU inspection path; the
fixture independently counts `/proc/cpuinfo` processor records and checks the
reported architecture. The controller independently checks both build
receipts, their input pins, step order, complete executed argv and matching
binary hashes. The native plan and both receipts are retained alongside the
compiler report. Version entry points provide execution smoke coverage;
filesystem mounting and account-changing workflows have their own gates.
The ARM CPU backend reports the kernel's raw IDs and common feature names;
it does not infer a model or independently qualify the kernel's hardware IDs.

To run the CPU inspection check with a separately prepared `lscpu` ELF, set
`VINIX_DEVELOPMENT_CPU_BINARY` to its host path. The controller checks the
architecture, pins and copies the binary and records its hash as `lscpu-smoke`.
The same UID/GID 1000 procfs check runs without requiring a native compiler SDK:

```
VINIX_DEVELOPMENT_CPU_BINARY=/path/to/x86_64-lscpu VINIX_QEMU_CPU=Nehalem tests/development/run-guest x86_64 /path/to/kernel /tmp/development-x86 /tmp/new-cpu-state
```

`VINIX_QEMU_CPU` also selects the x86 QEMU model; the default remains `max`.
A prepared ELF check is execution coverage, separate from the native rebuild
gate above. The receipt records the actual QEMU argv and prepared binary hash.

`receipt.json` records the architecture, UID, kernel/fixture/tool hashes,
QEMU argv, passing verdict and six native plan/state/build receipts. SDK runs
also retain the SDK hash and native compiler report. `serial.log`,
the ISO and compiled fixture remain beside it. Credential values do not enter
the receipts. The credential in this fixture is public synthetic test data.
V runs additionally record `v_root_sha256`, `native_source_sha256`, the `v`/`sh`
executable pins, the utility build plan and two native build receipts.
Once the ISO is complete, its duplicate staging tree and standalone initramfs
are removed. The ISO, compiled fixture, receipts and transcripts remain; obsolete
images from earlier runs may be pruned independently of their retained evidence.

On 13 October 2026 these workflows passed on x86_64 and AArch64 using the
previously staged commands and isolated production kernels. Receipts are in
`/tmp/vinix-development-guest-x86-20261013-e` and
`/tmp/vinix-development-guest-arm-20261013-e`.
The extended build-plan runs passed in
`/tmp/vinix-development-build-x86-20261013-b` and
`/tmp/vinix-development-build-arm-20261013-b`; both architectures produced
artifact hash `8f62334d280332417efb4876a0690270b65488e01a24a4752f6e512653bb4cc9`.
The optional SDK run passed on AArch64 with GCC/G++ 11.2.1 (20211120) as
UID/GID 1000, including both reference project compile/run workflows. Its
receipt and compiler-version transcript are retained in
`/tmp/vinix-development-compilers-arm-20261013-c`.
Comparison with the fresh guest in `...-20261013-b` found matching SDK,
compiler and compiled-project hashes for the same project paths and build
epoch. The copied SDK hash is
`5286f56cfe9f709635fa20f38325376e541cc4283376887ed6abc67d3d3eb279`.
The extended controller's x86 job/build regression passed in
`/tmp/vinix-development-compilers-x86-base-20261013-a`.
No native x86 GCC SDK was supplied for a compiler-project run.

The C/C++/V run passed on AArch64 as UID/GID 1000 in
`/tmp/vinix-development-v-arm-20261013-a`, using the updated staged commands in
`/tmp/vinix-dev-aarch64-20261013-v-a`, GCC/G++ 11.2.1 and V 0.5.2. The prepared V
tree's `VERSION` identifies revision `9bfa1dc3f3455d5733d5c226662b6aaba8544f2c`;
its copied closure hash is
`f2a67e54f237e64cefba4f1935ca301f305a4186488677e68b926bf5ff1dc2ea`.
The receipt records the actual V executable and BusyBox hashes separately.
The x86 controller/fixture regression passed in
`/tmp/vinix-development-v-x86-base-20261013-a` without a compiler SDK.
This compiles a reference V project; rebuilding the V compiler itself and all
Vinix layers remains open.

The private build HOME/temporary-directory checks passed as UID/GID 1000 on
both architectures in `/tmp/vinix-development-home-arm-20261013-a` and
`/tmp/vinix-development-home-x86-20261013-a`, with the updated commands staged
in `/tmp/vinix-dev-aarch64-20261013-home-a` and
`/tmp/vinix-dev-x86_64-20261013-home-a`.

The utility rebuild run passed on AArch64 in
`/tmp/vinix-development-userland-arm-20261013-g`, with commands staged in
`/tmp/vinix-dev-aarch64-20261013-buffer-a`. Both fresh workspaces compiled and
executed `fetch`, `mount` and `chsh` as UID/GID 1000, retained complete receipts
and produced matching artifact hashes. This includes successful SDK/V/runtime
pin verification before and after each build. The extended x86 controller and
fixture regression passed without a compiler SDK in
`/tmp/vinix-development-userland-x86-base-20261013-a`.
The copied utility source hash is
`7640e3bca2b9b35861843fb5ee7ad453ac7d39ff1568379f3901e5060cc34b52`.
Both workspaces produced these artifact SHA-256s:

| Artifact | SHA-256 |
| --- | --- |
| `fetch-bin` | `516190cc02a02176ad45633c8cb3e30c8e98942015e3a5eea90525f2fd79cf7a` |
| `mount-bin` | `0808686c516603edbe08c1863727387b8e326c9d55d7ebb3a5298416093a2c2d` |
| `chsh-bin` | `45ca2c0c495d8d972ea094fceb9dfeb86197c7a00515bf7a449ccd447f63ff5d` |

Earlier diagnostics exposed Darwin/Vinix symlink-mode differences and retained
64 KiB stream buffers under `-gc none`. Canonical link modes and explicit
buffer release fix those runner failures; input pins are still verified.

The extended four-utility native rebuild passed on AArch64 in
`/tmp/vinix-development-lscpu-arm-20261013-a`, with the same staged commands
and SDK/V/runtime pins. Its source pin is
`1c2fead1fefb5b59f86f743202c719b4969865297feeb3ce400ef9a1e9e2c1c3`.
Both workspaces produced `lscpu-bin` hash
`82fbb5b623eabc581482befebc0dcb19f3b5b63ddd9a028e5f8c7b2d028fd9cf`
and retained the three other artifact hashes listed above. CPU inspection
matched the one online processor reported by this kernel's procfs; the boot
has no usable device tree and therefore does not enable ARM SMP. This source
snapshot precedes the separate `fetch` color and x86 CPU-count fixes.

Prepared ELF CPU checks passed as UID/GID 1000 on AArch64 in
`/tmp/vinix-development-lscpu-arm-smoke-20261013-a`, and on x86 with the AMD
`max` and Intel `Nehalem` QEMU models in
`/tmp/vinix-development-lscpu-x86-amd-20261013-a` and
`/tmp/vinix-development-lscpu-x86-intel-20261013-a`. The x86 checks each match
two online processor records and pin binary hash
`44d43664cdc98a20d7c57141e59ed00534e422d72eed2eab2d85042bb5b137a9`.
The old CPUID package-count implementation failed the same Intel CPU-count
gate in `/tmp/vinix-development-lscpu-intel-before-20261013-a`; using the OS
online CPU count fixes it. These x86 checks execute a cross-built ELF;
native x86 compiler qualification still needs a prepared native SDK.

This qualifies the tested per-account job workflows in Vinix guests. Watcher
signal/deadline/interruption tests still have host coverage; installed service
and boot integration, server/SSH/CI projects, and complete self-hosted builds
remain open acceptance work.
