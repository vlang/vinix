# Software hosted X11 qualification

On 2026-10-23 both installed native guests passed this framebuffer scenario.
The final uninstrumented runs are `build/software-hosted-x11-arm-16` and
`build/software-hosted-x11-x86-16`. Each architecture has an independently
accepted native baseline, an accepted private-clone baseline, and forty
refusals before retained output creation. All eight canonical screenshots
were also viewed manually.

| Target | Receipt and admission | Actual child paint | ButtonPress repaint | Closed window |
| --- | --- | --- | --- | --- |
| AArch64 | [receipt](results/2026-10-23/aarch64/qualification.json), [retention](results/2026-10-23/aarch64/retention.json), [40 controls](results/2026-10-23/aarch64/controls.json) | [pink/green](results/2026-10-23/aarch64/02-painted.png) | [blue/green](results/2026-10-23/aarch64/03-pointer.png) | [desktop](results/2026-10-23/aarch64/04-closed.png) |
| x86_64 | [receipt](results/2026-10-23/x86_64/qualification.json), [retention](results/2026-10-23/x86_64/retention.json), [40 controls](results/2026-10-23/x86_64/controls.json) | [pink/green](results/2026-10-23/x86_64/02-painted.png) | [blue/green](results/2026-10-23/x86_64/03-pointer.png) | [desktop](results/2026-10-23/x86_64/04-closed.png) |

[Source hashes](results/2026-10-23/source-inputs.json),
[evidence hashes](results/2026-10-23/evidence-pins.json), and
[host regressions](results/2026-10-23/host-checks.json) accompany those receipts.
The host checks execute both pointer factory/pipe tests normally and with
ASan/UBSan, plus three inventory/archive admission tests; assertions are enabled.

This fixture drives the real framebuffer Software interface in an installed
ordinary-account session. It stages a locally signed native Xlib client and
clicks its catalog Launch control. The client authenticates to the private
Xvfb display, paints an actual child window, and changes that window's color
after a real pointer ButtonPress. The observer checks effective IDs, no
supplementary groups, signed application context, private authority ownership,
the exact owned socket and the installed generation lease.

Closing the outer Software window must reap the bridge and Xvfb and remove
their authority/socket while the deliberately retained signed child still
holds its lease. The observer then releases that child, requires its natural
exit and actual reap, and verifies lease release. Finally the fixture stops
its compositor, requests guest poweroff, and requires an independent QMP
`SHUTDOWN` event with `guest=true`, `reason=guest-shutdown`, followed by a
reaped QEMU exit status of zero. This is fixture-controlled poweroff, not
acceptance of the desktop shutdown menu.

The application is preinstalled by the host publisher fixture. This test does
not qualify acquisition, arbitrary X11 applications, or a production
publisher. Missing/wrong authority and cross-account controls belong to the
separate authenticated hosted-X11 qualification. The compositor is rebuilt at
`2018514db9fc4a258cd86fb26baad724a9e1083a`, which enables Software's remote
pointer transport. The initial stage retains the assembled snapshot at
`a54cd7cf7b32d2aebd3df32e236522f3d614a4f0`. Fixed manifest and build-metadata
SHA anchors, every archived source/ELF digest and the desktop build's input
paths/hashes are admitted independently. `source/` build inputs are checked
against the exact retained `desktop/source/` bytes, with traversal and ambiguous
relative paths refused; the original input-path manifest remains anchored.
Other build inputs retain their recorded absolute paths and hashes. Fresh
account, package, session, bridge and guest builds are pinned separately from
`58031b4fc`. The kernels are the retained PTY-fixed binaries in
`build/pty-kernels/{aarch64,x86_64}/vinix`. This does not qualify every
source file in the current repository.

Earlier ARM attempts 13–15 were diagnostics and are excluded from admission.
An instrumented worker recorded the same target UID, display, authority and
successful private-object checks before and after inherited-descriptor cleanup.
No production retry or admission relaxation was added in response. The final
matching pair removes that instrumentation and exercises the ordinary path.

Build with the pinned V compiler; `-prod` enables embedded source capture.
All validators use explicit errors, so their checks remain active with this
flag. Run the proof unit tests without `-prod` so their assertions execute.

```sh
V=build/package-https-runtime-work/toolchain/v
export V_C_ERROR_BUG_REPORT_DISABLED=1 V_MACOS_V3_NO_FALLBACK=1
"$V" -prod -enable-globals \
  -path '@vlib|.|tools|build-support|tests/software-hosted-x11|tests/hardware-platform|tools/accounts|@vmodules' \
  -o build/software-hosted-x11-tools/check tests/software-hosted-x11/check.v
"$V" -prod -enable-globals \
  -path '@vlib|.|tools|build-support|tests/software-hosted-x11|tests/hardware-platform|tools/accounts|@vmodules' \
  -o build/software-hosted-x11-tools/retain tests/software-hosted-x11/retain.v
"$V" -prod -path '@vlib|.|tests/software-hosted-x11|@vmodules' \
  -o build/software-hosted-x11-tools/evidence-check tests/software-hosted-x11/evidence-check.v
"$V" -path '@vlib|.|tests/software-hosted-x11|@vmodules' \
  -o build/software-hosted-x11-tools/collect tests/software-hosted-x11/collect.v
"$V" -path '@vlib|.|tests/software-hosted-x11|@vmodules' \
  -o build/software-hosted-x11-tools/proof-test tests/software-hosted-x11/proof/admit_test.v
build/software-hosted-x11-tools/proof-test
```

The controller requires explicit `--arch`, `--out`, `--kernel`, `--rootfs`,
`--desktop`, `--stage`, `--sysroot`, `--userland`, `--x11` and `--shell`
arguments. Set `VINIX_ROOT` to this checkout. The complete consumed compiler,
backend, linker, sysroot, archived source and source-selection trees are
captured before any producers, rechecked immediately before boot and again
after QEMU is reaped. Added files, changed literal symlinks and changed
resolved file aliases are included. The receipt binds generated C, runtime C,
ELFs, command arguments and logs to their preboot inputs and staged binaries.
Only the declared `source:*` trees may select source extensions; compiler,
sysroot, stage, staged files and archives require complete inventories. Cheap
semantic refusals precede expensive hashing, but every inventory and byte check
must pass before any evidence is admitted.

The qualified native commands, from this isolated checkout, are:

```sh
export VINIX_ROOT="$PWD" V="$PWD/build/package-https-runtime-work/toolchain/v"
ROOT=/Users/alex/code/vinix
build/software-hosted-x11-tools/check --arch=aarch64 \
  --out="$ROOT/build/software-hosted-x11-arm-16" \
  --kernel="$ROOT/build/pty-kernels/aarch64/vinix" \
  --rootfs="$ROOT/build/software-maintenance-installed-arm-3/rootfs" \
  --desktop="$ROOT/build/software-hosted-x11-desktop-aarch64/vinix-desktop" \
  --stage="$ROOT/build/package-assembled-stage-aarch64/root" \
  --sysroot="$ROOT/build-aarch64-x11/sysroot" \
  --userland="$ROOT/build-aarch64-userland/staging" \
  --x11="$ROOT/build-aarch64-x11/staging" \
  --shell="$ROOT/build-aarch64-userland/staging/bin/busybox"
build/software-hosted-x11-tools/check --arch=x86_64 \
  --out="$ROOT/build/software-hosted-x11-x86-16" \
  --kernel="$ROOT/build/pty-kernels/x86_64/vinix" \
  --rootfs="$ROOT/build/software-maintenance-installed-x86-3/rootfs" \
  --desktop="$ROOT/build/software-hosted-x11-desktop-x86_64/vinix-desktop" \
  --stage="$ROOT/build/package-assembled-stage-x86_64/root" \
  --sysroot="$ROOT/build-amd64-x11/sysroot" \
  --userland="$ROOT/build/session-amd64-sysroot" \
  --x11="$ROOT/build-amd64-x11/staging" \
  --shell="$ROOT/build-amd64-userland/staging/bin/busybox"
```

Output directories must be new when replaying. AArch64 uses HVF and x86_64
uses TCG; both use an offline installed VJFS disk and a 1024×768 display.

```sh
build/software-hosted-x11-tools/retain --work=ABSOLUTE_NATIVE_RUN --out=NEW_RETAINED_DIRECTORY
build/software-hosted-x11-tools/evidence-check \
  build/software-hosted-x11-tools/retain ABSOLUTE_NATIVE_RUN NEW_CONTROL_DIRECTORY
```

The control runner first admits the original native run, then admits a private
APFS clone with rebased run-owned metadata. Every corruption must refuse
before creating retained output. It does not modify the native evidence.
The forty controls cover all ten exact ordered lifecycle markers, duplicate
identity and panic, QMP event/binding/guest/reason failures, failed or unreaped
QEMU exit, required screenshots and paint phases, generated C/argument/preboot
bindings, verified inputs, missing archives, fixed metadata anchors, resealed
archived-source changes, and reduced or incorrect tree selection modes.

`collect.v` takes the two finished control directories, the retained host
pointer test directory printed by `desktop/tools/test-app-selection.v`, and a
new output directory. It checks the baseline/control/retainer receipt binding,
reexecutes the pinned host tests, and copies the receipts, transcripts and
screenshots while recording their hashes. Retained native receipts contain
the complete input/output ledger; replay additionally needs those original
build inputs, which are not vendored here.
