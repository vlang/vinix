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

The maintained [V compiler stager](../../tools/development/stage-v.v) prepares
that matching installation from committed compiler/library sources:

```
v -cc cc run tools/development/stage-v.v aarch64 /path/to/v-checkout /path/to/new-native-v
```

This copies and hashes the V root with Python helpers excluded, installs the
compiler beside its matching library at `/usr/lib/vlang`, checks V/BusyBox ELF
architectures and records both executable hashes. The V project uses the
explicit Vinix/musl target, serial V3 workers and the native C compiler. It
must compile, write/read a file and execute its resulting binary. These runs
receive 3 GiB of RAM. Failed qualification retains bounded command-log excerpts
in the serial transcript as well as the native report.

V runs export this repository's committed `fetch`, `mount`, `chsh`, `lscpu`,
`init` and package-CLI sources from one full Git commit. Each immutable blob is
verified; dirty/untracked files and Python helpers are excluded, and selected
symlinks are refused. `SOURCE_REVISION` and the host receipt record that commit.
The controller generates a build plan pinning those sources, V, GCC, the shell and
the complete SDK/V/runtime trees. UID/GID 1000 builds them in two fresh
workspaces with private HOME/temporary directories, then executes each recorded artifact's
`--version` entry point. The fixture checks ownership, executable ELF headers
and expected utility output. `lscpu` also runs its CPU inspection path; the
fixture independently counts `/proc/cpuinfo` processor records and checks the
reported architecture. The controller independently checks both build
receipts, their input pins, step order, complete executed argv and matching
binary hashes. The native plan and both receipts are retained alongside the
compiler report. Version entry points provide execution smoke coverage;
filesystem mounting and account-changing workflows have their own gates.
The rebuilt `init` runs its version entry point before setting environment
variables, changing directory, setting the hostname or entering its login loop.
This checks native compilation and safe execution; booting it as PID 1 and
qualifying its login workflow remain separate acceptance work.
The ARM CPU backend reports the kernel's raw IDs and common feature names;
it does not infer a model or independently qualify the kernel's hardware IDs.

The same plan compiles the package CLI with the documented Linux/musl ABI target,
checks both V and package help entry points, packs the freshly compiled `lscpu`
as a native package and publishes a signed consumer repository. Both workspaces
must complete all 19 steps and produce identical executable, manifest, index,
signature and payload-copy hashes. A pinned BusyBox supplies the payload
directory/copy commands. The public synthetic signing seed lives outside the
source closure as an additional pinned input, owned by UID 1000 with mode 0600.

The source closure also includes a generated V assertion-failure project. Both
workspaces compile it to matching binaries; each must exit 1 and report its
relative source filename, line, expression and panic diagnostic. This verifies
that workspace-independent binaries retain working assertion failures. The
matching compiler stager normalizes project assertion paths when the build
runner sets `SOURCE_DATE_EPOCH`; it preserves explicit logical source names.

The fixture checks the exported object's ownership/mode, size and SHA-256
against the compiled executable and checks that `publisher.seed` and `.publisher`
are absent from the release. The controller separately verifies the
Ed25519 signature, repository identity, sequence, current expiry, package
architecture and exact executable payload metadata against both build receipts.
It retains the two signed indexes and signature/object proofs. This tests
native compilation, packing and publication under ordinary account permissions;
repository enrollment, package installation and sandboxed installed-app launch
remain separate qualification gates. No production signing key is used.
The full compiler/package gate uses 600-second command deadlines and a
2400-second guest deadline. The selected qualifier command budget is recorded
and independently checked in its report; other guest runs retain 900 seconds.

For prepared compiler startup/help coverage without a GCC SDK, set
`VINIX_DEVELOPMENT_V_SMOKE_ROOT` to the complete matching installation root:

```
VINIX_DEVELOPMENT_V_SMOKE_ROOT=/path/to/x86-vlang tests/development/run-guest x86_64 /path/to/kernel /tmp/development-x86 /tmp/new-v-smoke
```

The controller copies and pins the root and executable; UID 1000 executes help
and version and compares the reported revision with `VERSION`. The receipt
records `v_smoke_root_sha256` and `v-smoke`; the version output stays in the
transcript. This option is separate from the native V build gate and cannot be
combined with its V-root argument. Startup/help coverage does not qualify native
project compilation.

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
executable pins, `native_source_revision`, the build plan, two native build
receipts and four signed-release proofs, for 14 native receipt records.
Once the initramfs archive is complete, its duplicate staging tree is removed
before ISO assembly. The standalone archive is removed once the ISO is complete.
The ISO, compiled fixture, receipts and transcripts remain; obsolete
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

The init-extended native rebuild passed in
`/tmp/vinix-development-init-arm-20261013-a`, using the same staged commands
and SDK/V/runtime pins. Both workspaces compiled and executed all four
utilities and `init`, completed all 11 steps and reverified every input pin.
The source pin is
`658a5fc75c5cd5fa7a07afa63a776cd5a6881927a9ca3ea2250fbb5ac7e4da0b`.
This includes the current `fetch` color and x86 CPU-count source changes.
Both workspaces produced `init-bin` hash
`f8b6c9a30c3cfcd5cc6e4eeda2facb00d77afb6fb15c935ee7601403ce02a05c`
and updated `fetch-bin` hash
`c4995938f7b4c73c9eb78540b760c944709fc1ad3e2cf84b509a7a5b51e87b46`;
the `mount`, `chsh` and ARM `lscpu` artifact hashes remained unchanged.
The x86 controller/fixture regression passed without a native compiler SDK in
`/tmp/vinix-development-init-x86-base-20261013-a`.
Both architectures also passed after moving duplicate staging-tree retirement
before ISO assembly, in `/tmp/vinix-development-prune-arm-20261013-a` and
`/tmp/vinix-development-prune-x86-20261013-a`.

The committed-source, native package and assertion-failure gates passed on
13 October 2026 with V source revision
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, staged with `VINIX_V_COPT=-O0`, and
the GCC/G++ 11.2.1 SDK. The AArch64 HVF run retained a passing 14-record receipt
and all 19 successful build steps per workspace in
`build/development17-20261013/guest-arm-package-assertions`. Its source revision
is `49070d4e39f4d4c64c7658a7f1e03492297b2ea0`, prepared-source pin is
`08e2fa118cb5eefd23ed5d13a096e55527d7f02d34c26dd88b155419da59f2d5`, copied
SDK pin is `ad1baf20e589e88e753cccbe863127d5e8e1cc9782d228dc956eaaff79ab8717`
and V installation pin is
`45468219a77a74bfb970078509adc707c46fc6df067483f828f0434c9cff55da`.
Both workspaces produced package-CLI hash
`481b5f11b1865ee462cb02cb9d5353bbc04ba8167606a8aac0b7ae9fede02a2d`, `lscpu`
payload hash `8c2ba41f687c66f6b3602860f09bae79c19739ae81fc7453cdcd932c19b01f5f`
and release-index hash
`9eee3b494a6e92353520db3dd27f00a7fc06b3a1dbc8004ff10292bf91ba672b`.
The real assertion project exits 1 with its relative source filename and
line 2 in both workspaces, and its binary hash also matches. The x86 TCG
prepared-compiler help/version and account/job/build regression passed in
`build/development17-20261013/guest-x86-v-assertions`. That run pins V compiler
`1ca3d612caf39e057b18ffe78be4d4c1f790e272aa82d8e9276ab37f9b340326` and
installation `4d83946b8ab4d99ac938c96da5d72668835abbaca7d18d8dc63f1b689e7d1853`;
it does not run native compiler projects without an x86 SDK.

This qualifies the tested per-account job workflows in Vinix guests. Watcher
signal/deadline/interruption tests still have host coverage; installed service
and boot integration, server/SSH/CI projects, and complete self-hosted builds
remain open acceptance work.
