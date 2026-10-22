# Production init, installed login and Software

This fixture qualifies the production boot path on AArch64 and x86_64. It uses
the real freestanding ARM PID 1 and the real x86 `/sbin/init` shell script,
instead of a fixture PID 1 or a direct compositor launch. Both runs start with
a blank 4 GiB system disk and perform two cold boots of the same disk.

The optional `vinix-version-check` image hook is replaced by the declared
read-only observer in [observer/main.v](observer/main.v). Production init still
owns root selection, account bootstrap, the graphical supervisor, authentication
and shutdown. The observer reads identities and package state, runs only
read-only package proposal/verification commands, and writes its own checkpoint.
The host drives registration, login, Software and power controls with QMP input.
The fixture does not install or remove packages through a fixture CLI command.

The accepted runs are `build/normal-init-software-arm-12` and
`build/normal-init-software-x86-3`. The corresponding retained evidence is under
[`results/2026-10-23/aarch64`](results/2026-10-23/aarch64) and
[`results/2026-10-23/x86_64`](results/2026-10-23/x86_64).
Both native runs exited successfully. Independent retention admitted each
baseline and rejected all 32 controls before creating an output directory;
the complete outcomes are retained in the
[AArch64 controls](results/2026-10-23/aarch64/controls.json) and
[x86_64 controls](results/2026-10-23/x86_64/controls.json).

## Observed workflow

On boot 1, production init installs the image on the selected disk. The guest
requires `/dev/root` mounted as its ext2 root, production init and program bytes
matching the declared image, and a root graphical manager directly parented by
PID 1 with its private lock. A new image shows root registration, then an
ordinary greeter with UID 101. Real graphical registration creates the initial
administrator. Password login reaches the ordinary UID/GID 1000 compositor with
its private home, runtime directory and ready marker.

Software Refresh requests the administrator's own password. Install shows the
complete signed Counter 1.1.0 proposal before a separate approval; the observer
checks that review leaves package state and the approval count unchanged. The
host launches Counter, saves 2 using its controls, closes it and chooses desktop
shutdown. The observer records the actual UID/GID 1000 Counter and package
launch child PIDs and requires their `/proc/PID` entries to disappear, including
zombies, before permitting this checkpoint.

On boot 2, account, trust, catalog, package generation and private-data bytes,
ownership and modes must match the saved checkpoint. A new graphical login
opens Software. Uninstall and reinstall each require a read-only review followed
by a separate password approval. Uninstall removes the launcher while retaining
private value 2; reinstall restores the signed launcher and preserves that
value. Counter's reopened label must match the saved first-boot pixel region
exactly. The host increments and saves 3, closes the app and chooses shutdown.

Each boot requires both its terminal guest marker and exactly one independent
QMP `SHUTDOWN` event with `guest=true` and `reason=guest-shutdown`. The controller
also waits for QEMU to exit with code 0. A host quit, reset, panic, missing
event, process crash/restart, memory-root fallback or image-update mode refuses
qualification. There are 30 required 1024×768 screenshots per architecture.

## Input and output admission

[normalproof/admit.v](normalproof/admit.v) admits the previously qualified
assembled compositor and account/package stage using fixed receipt digests and
their exact historical source inventories. These reused outputs were built
from `a54cd7cf7b32d2aebd3df32e236522f3d614a4f0`. The complete current archived trees,
including hidden entries and literal symbolic links, are separately captured
before and after this run. Their historical source attribution remains limited
to the original receipt's inventory contract.

The manager is freshly built from the captured account source, including the
managed argument-array cleanup in `7e6ee4d80`. ARM init and the observer are also
built for the run. ARM reuses the captured staged volume helper. x86 uses the
captured production init script and builds the exact consumed volume-helper
ELF through `compile-v-module`, with the production ABI assertions and compiler
flags. That retained output is staged and booted; this fixture does not claim
that it invoked the volume stager itself.

The x86 input root is prepared by
[prepare-x86-input.v](prepare-x86-input.v): it copies the previous unbooted
maintenance root and adds the real staged musl loader needed by BusyBox's
production shell init. `.normal-init-input.json` identifies the original root,
loader and preparation-source hashes. The complete resulting input-root
inventory, including link targets, is captured before any copy or producer.

Other captured inputs include the selected publisher workspace, seed and image
configuration; kernel, BusyBox, QEMU, firmware and boot loader; the frozen V
compiler's full `vlib`/`thirdparty` trees; musl compiler/sysroot/linker trees;
observer driver; LLVM executables, headers and known shared libraries. Exact
input inventories and hashes are checked before boot and after both boots.
This records the known tools consumed by this macOS host; it is not a hermetic
capture of the host OS, SDK and every dynamically loaded host dependency.

Before boot, a separate generated inventory pins the frozen fixture sources,
required C/ELF/object outputs, literal compiler argv, producer logs, staged
programs/actions/configuration, signed repository, initramfs and boot media.
Those outputs must remain identical after both boots. Final QEMU argv is a
post-run receipt, independently checked against the exact frozen workflow and
selected executables/media; these runs do not claim a historical preboot hash
of that argv file. The system-disk digest describes the final disk.

[retain.v](retain.v) independently admits these inputs and outcomes before
creating an evidence directory. It requires every architecture-specific C,
ELF, object, compiler argv and log, binds staged programs and account actions to
their admitted producers, checks the observer declaration and Software alias,
and requires generated output hashes to match the preboot inventory. It checks
compiler identity, QEMU arguments, complete proposal identity and ordering,
serial outcomes, both QMP transcripts and the exact screenshot set. Compiled
controller, retainer and control sources are embedded and checked explicitly.
All admission uses returned errors: it does not depend on V assertions, which
the pinned compiler removes under `-prod`.

[evidence-check.v](evidence-check.v) runs an admitted baseline and 32 refusal
controls per architecture against disposable hard-link copies. It unlinks each
copy before rewriting it. Controls cover omitted source/compiler inputs;
omitted C, log and argv from all lists; output-only resealed C/argv; changed
compiler argv, frozen source, staged sandbox/action and observer declaration;
missing screenshots/digests; altered QEMU argv; missing, duplicated, forbidden
or out-of-order serial evidence; changed publisher; and missing, duplicate,
host-initiated, wrong-boot, string-boot, reset and panic QMP events. Every refusal
must happen before the evidence output directory is created.

## Reproduction

Build the tools from the frozen qualification checkout with the pinned V
compiler. Use `-prod` to embed sources and explicit error-based admission:

The accepted runs use
`build/package-https-runtime-work/toolchain/v` (SHA-256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`).
`V`, `VEXE` and `V_MACOS_V3_CALLER_VEXE` select that same absolute path;
`V_MACOS_V3_CALLER_VEXE_PRESENT=1`, `V_MACOS_V3_CALLER_VCHILD_PRESENT=0`,
`V_MACOS_V3_NO_FALLBACK=1` and `V_C_ERROR_BUG_REPORT_DISABLED=1` preserve the
captured driver selection. AArch64 sets `CC_AARCH64` to the captured
`build/graphical-login-fallback-work/clang` driver and `VINIX_AARCH64_SYSROOT` to
`/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/aarch64-linux-musl`. x86 leaves
`CC_AMD64` unset and sets `VINIX_PLAIN_ISO_LIMINE` to the captured
`build-amd64-iso/limine/limine-binary-12.9.3` directory.

```text
v -cc clang -nocache -prod -gc none \
  -path '@vlib|@vmodules|.|tools|tests/hardware-platform|build-support|build-support/native-compat-tools|tests/desktop-perf|tests/normal-init-software' \
  -o CHECK tests/normal-init-software/check.v
v -cc clang -nocache -prod -gc none \
  -path '@vlib|@vmodules|.|tools|tests/hardware-platform|build-support|tests/normal-init-software' \
  -o RETAIN tests/normal-init-software/retain.v
v -cc clang -nocache -prod -gc none \
  -path '@vlib|@vmodules|.|tests/normal-init-software' \
  -o CONTROLS tests/normal-init-software/evidence-check.v

CHECK --arch=ARCH --rootfs=INPUT_ROOTFS --stage=ASSEMBLED_STAGE \
  --desktop=ASSEMBLED_DESKTOP --kernel=KERNEL --publisher=PUBLISHER --out=RUN
RETAIN RUN INPUT_ROOTFS ASSEMBLED_STAGE ASSEMBLED_DESKTOP KERNEL \
  PUBLISHER CHECK NEW_EVIDENCE_DIRECTORY ARCH
CONTROLS RETAIN RUN INPUT_ROOTFS ASSEMBLED_STAGE ASSEMBLED_DESKTOP KERNEL \
  PUBLISHER CHECK NEW_CONTROL_DIRECTORY ARCH
```

The retained command receipts include literal producer argv and the selected
paths. AArch64 uses the explicit captured observer driver and sysroot; x86
uses its captured musl compiler and plain-USTAR ISO helper. Each run requires
its matching kernel, firmware and assembled outputs. Native deadlines are
bounded, and the controller owns and reaps its QEMU process on failure.

This is a fixture-signed Counter repository on an offline guest, not a
production publisher or default release catalog. It verifies the combined
production-init installed graphical boundary; separate first-run, maintenance,
HTTPS, hosted X11 and release-owner gates retain their own scope. No configured
extra-volume restore plan is present, so the observer reports the boot-restore
helper as present rather than claiming a configured restore succeeded. It
makes no heap-growth or complete section-14 release-acceptance claim.
