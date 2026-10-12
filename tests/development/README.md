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
checks source/link preservation, private output directories and actual artifact
contents. The controller independently checks both native receipt hashes against
the expected bytes. Altering the pinned source must stop the next build before
execution. This tests runner behavior with a prebuilt payload; compiling all
Vinix layers inside an installed system remains open.

`receipt.json` records the architecture, UID, kernel/fixture/tool hashes,
QEMU argv, passing verdict and six native plan/state/build receipts. `serial.log`,
the ISO and compiled fixture remain beside it. Credential values do not enter
the receipts. The credential in this fixture is public synthetic test data.

On 13 October 2026 these workflows passed on x86_64 and AArch64 using the
previously staged commands and isolated production kernels. Receipts are in
`/tmp/vinix-development-guest-x86-20261013-e` and
`/tmp/vinix-development-guest-arm-20261013-e`.
The extended build-plan runs passed in
`/tmp/vinix-development-build-x86-20261013-b` and
`/tmp/vinix-development-build-arm-20261013-b`; both architectures produced
artifact hash `8f62334d280332417efb4876a0690270b65488e01a24a4752f6e512653bb4cc9`.

This qualifies the tested per-account job workflows in Vinix guests. Watcher
signal/deadline/interruption tests still have host coverage; installed service
and boot integration, server/SSH/CI projects, and complete self-hosted builds
remain open acceptance work.
