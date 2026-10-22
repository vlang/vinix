# Signed Neovim qualification

The native profile packages Neovim 0.12.5 (upstream commit
`5885a30e1e1225349079e7a1c4a3848aa8e43e42`) and its complete installed runtime
as `org.neovim.editor` plus `org.vinix.neovim-runtime`, for AArch64 and x86-64.
`neovim-build.v` pins eight upstream source archives and retains their licenses,
build commands, source inventories, generated adapter C and target ELF digests.
Static GCC runtime helpers also carry the pinned upstream GCC 14.2.0
`COPYING.RUNTIME` exception and `COPYING3` license notices. It uses host Lua
generators and target musl builds; target generators and Python
are not executed. Each target output extracts fresh source trees.

For Vinix, the builder selects libuv 1.52.1's existing no-io_uring branch with
the libuv-only `VINIX_LIBUV_NO_IO_URING=1` define. `UV_USE_IO_URING=0` is
insufficient: upstream probes an io_uring ring for epoll batching before
consulting that variable for SQPOLL. Vinix's package sandbox refuses that
syscall. The V helper requires one exact original branch, refuses drift and
duplicate application, and changes only its preprocessor condition. The
upstream archives retain their original SHA pins; separate upstream/patched
inventories and `source-patches.json` bind both file digests and exact changed
bytes. The signed runtime carries the helper and patch receipt. This leaves
the sandbox policy unchanged and uses libuv's existing epoll/poll fallback.

The editor includes Lua 5.1, luv, LPeg, UTF-8 processing and the tree-sitter core
library. Grammar parser DSOs, LuaJIT, external providers and language servers are
not bundled. The native gate checks Lua/LPeg, Vimscript syntax and the absence of
a Lua grammar, rather than claiming grammar parsing was exercised.

`neovim-catalog` imports prepared roots through captured descriptors, rejects
symlink architecture roots and invalid inventories, confines nested aliases,
bounds recursive data import, pins archive
bytes, and runs the shared ELF metadata parser before and after packing. The
editor and adapter must be static ELF files, without an interpreter or dynamic
metadata. Direct editor execution preserves `/proc/self/exe` for Neovim's
terminal UI subprocess. The fixed manifest invokes the static Neovim adapter,
which supplies sealed `VIMRUNTIME`, removes
ambient `VIM` and preserves user arguments literally; it never invokes a shell.
The explicit `files` and `process` permissions permit private local Unix IPC
and subprocesses; neither network nor display access is requested.

Build the V tools with the selected compiler's C backend:

```text
v -backend c -prod -gc none -manualfree -path '@vlib|tools/packages|@vmodules' -o neovim-build tools/packages/neovim-build.v
neovim-build --cache=SOURCE_CACHE --arch=aarch64 --out=NEW_BUILD --root=REPOSITORY --prepared=PREPARED_ROOTS
neovim-build --cache=SOURCE_CACHE --arch=x86_64 --out=OTHER_NEW_BUILD --root=REPOSITORY --prepared=PREPARED_ROOTS
vinix-package neovim-catalog 1.0.0 PREPARED_ROOTS NEW_CATALOG
vinix-package pack-catalog NEW_CATALOG/catalog.json PREPARED_ROOTS NEW_PUBLISHER_ROOT
```

The builder records the local cross-tool paths it uses. The retained executable
and helper/header pins, commands, generated C and ELFs bind the tested outputs;
they do not establish a hermetic or reproducible build of every imported
compiler library and transitive host dependency, including the host LuaJIT and
header tools used while configuring generators. When using the relocated V
snapshot, set `VEXE`, `V_MACOS_V3_CALLER_VEXE_PRESENT=1`,
`V_MACOS_V3_CALLER_VEXE=VEXE`, `V_MACOS_V3_CALLER_VCHILD_PRESENT=0`,
`V_MACOS_V3_NO_FALLBACK=1` and `V_C_ERROR_BUG_REPORT_DISABLED=1`.

`neovim-runner-check.v` exercises actual child argv/environment and refusal
paths. `pkgcore/neovim_profile_test.v` exercises source pins, inventories,
architecture admission, symlinks, bounds and failure cleanup. Direct `_test.v`
compilation with the qualification compiler requires `-no-skip-unused`; retain
assertions by omitting `-prod` for that suite.
`nvimcompat/libuv_test.v` checks the exact branch replacement and refuses
changed, missing, duplicated and already-patched input.

From the repository root, run the focused host checks with fresh output paths:

```text
v -backend c -gc none -manualfree -no-skip-unused -path '@vlib|.|tools/accounts|@vmodules' -o PROFILE_TEST tools/packages/pkgcore/neovim_profile_test.v
PROFILE_TEST
v -backend c -gc none -manualfree -no-skip-unused -o LIBUV_TEST tools/packages/nvimcompat/libuv_test.v
LIBUV_TEST
v -backend c -prod -gc none -manualfree -o RUNNER tools/packages/neovim-runner.v
v -backend c -gc none -manualfree -o RUNNER_CHECK tests/packages/neovim-runner-check.v
RUNNER_CHECK ABSOLUTE_RUNNER NEW_TEST_DIRECTORY
```

The profile suite is also run with Clang's `-fsanitize=address,undefined` and
`-fno-omit-frame-pointer`, retaining assertions. That run uses
`ASAN_OPTIONS=detect_leaks=0` and makes no allocation-retention claim.

The native controller is built with `-backend c -prod -gc none -manualfree` and
the repository, account modules and `tests/hardware-platform` in its module
path. It accepts only these literal options:

```text
neovim-native-check --arch=ARCH --out=NEW_RUN --kernel=KERNEL --sandbox=SANDBOX --sysroot=SYSROOT --gcc=GCC_DIRECTORY --repository=SIGNED_RELEASE_1 --update-repository=SIGNED_RELEASE_2 --public-key=PUBLIC_KEY_FILE
```

The second signed release has runtime version 1.1.0 and the same actual editor
and runtime payload as version 1.0.0. This exercises signed version selection and
rollback compatibility. Publisher secrets are excluded from the guest and its
admitted inputs. The guest checks actual ordinary UID 1000, private data HOME,
fixed generation-specific runtime, Lua/LPeg and Vimscript syntax, an ordinary-owned
RPC socket inside private `HOME/tmp`, refused file writes and socket binding
outside the sandbox, absent display authority, real PTY input/resize/save with exact file bytes/ownership,
live generation lease through uninstall/reinstall and GC, natural child exit,
offline runtime update/rollback with exact document reopen, and data retention
after uninstall. Piped terminal invocation must fail.

The target kernels include the PTY epoll pin-release correction: releasing a
temporary slave reference must not signal readiness. Without it, Neovim's TUI
loops in epoll scans before UI attachment; headless execution still succeeds.
The kernel regression separately checks finite epoll waits, actual PTY input,
last-descriptor close and master hangup. The editor gate requires the real TUI
save and natural exit as well as headless runtime checks.
The accepted editor runs use the correction committed on main as `a83652ec9`.

The pinned kernels boot raw USTAR fixture initramfs media, using the
isolated `plainiso` helper on x86-64. This does not qualify the current release
gzip image path. The controller stops QEMU after the complete PASS sequence;
the outcome is not a guest shutdown or a production image acceptance claim.

Retain only successful native evidence with the self-bound production validator:

```text
neovim-retain RUN ARCH KERNEL NATIVE_CONTROLLER SANDBOX NEW_RECEIPT_DIRECTORY
neovim-evidence-check RETAINER RUN ARCH KERNEL NATIVE_CONTROLLER SANDBOX NEW_CONTROLS_DIRECTORY
```

Both validators use explicit errors, including in production mode. Retention
rehashes admitted inputs and outputs, checks frozen sources and boot-admitted
generated C/ELFs, requires exactly one of each of five native PASS lines, and
rejects failed/interrupted outcomes or forbidden serial messages before creating
an output directory. The control driver validates the real baseline, then
refuses twelve private-copy corruptions with resealed output hashes: failed,
interrupted or reason-bearing outcome; missing or duplicated marker; forbidden
serial marker; input mismatch; missing admitted source; altered frozen source;
missing raw archive; missing compiler argv; and changed guest ELF.

The qualification compiler's default Boehm host mode produced a package-index
decode error in the controller before boot. The same exact signed index was
accepted by the package CLI and the controller compiled with explicit
`-gc none -manualfree`; the native gate and its receipts cover those explicit
flags. No broader compiler/GC compatibility claim is made.

The accepted paired results are retained under
[`results/2026-10-23`](results/2026-10-23): `neovim-aarch64.json` and
`neovim-x86_64.json` bind the actual native artifacts and their serial logs;
the matching `.controls.json` reports accept each real baseline and refuse all
twelve corruptions. Both guests passed all five exact native markers. The
`neovim-host-*` files retain the focused ordinary and sanitizer checks with
source, compiler, binary and command pins. The two `neovim-build-*.json` receipts
independently rehash 5,002 patched source files and 2,125 prepared files per
target, as well as the retained commands and inventories.
`neovim-evidence-pins.json` binds these copied reports and their V collection
helpers. Earlier ARM runs, including the first complete execution with an
omitted compiler-argv admission entry, remain diagnostic and are excluded from
these accepted receipts.
