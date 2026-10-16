# Apple package launch and container qualification

Apple package launch plans now supply `VINIX_IOS_DOCUMENTS` and
`VINIX_IOS_KEYCHAIN` under the admitted private app-data directory. The current
iOS runtime uses these overrides rather than the immutable bundle's parent for
its Foundation container paths and private keychain files. The planner adds no
paths or sandbox promises. Normal, literal-command and terminal modes use the
same derived values; unrelated package kinds receive no iOS overrides.

`apple-runtime-check.v` builds the actual static V iOS runtime, stages the
production package/account/session tools and boots an AArch64 guest with a
supplied production sandbox. It generates two unencrypted ARM64 iOS Mach-O
executables directly in V, with `LC_MAIN` code returning 23 and 24 respectively.
They use neither an Apple SDK nor proprietary payloads. Both application and
runtime are packed, signed, enrolled and installed by the normal package tools.
The runtime contains a signed native fixture launcher and `run-ios`.

The native launcher runs as the ordinary user inside the same production
sandbox. It validates SDK context, exact Documents/keychain/HOME/TMPDIR paths,
zero supplementary groups, hidden host paths and an explicitly granted literal
document. It writes private counter/container fixtures with mode 0600, then
execs its generation's real `run-ios` with its signed Mach-O application. It
creates files with their private modes directly; no chmod/fattr grant is added.
The account and package supervisors keep the normal generation lease throughout
execution. The exact Mach-O return status must propagate back through the CLI.

The guest checks five successful launches:

| Step | Required result |
| --- | --- |
| Initial launch, Alex | Mach-O status 23; private counter 1 and literal document read. Ambient forged iOS paths remain unused. |
| Initial launch, Sam | Status 23; separate private counter 1. Sam cannot use Alex's document grant or data. |
| Reviewed app/runtime upgrade | Status 24 from the newer image; Alex's private counter 2. |
| Reviewed rollback | Status 23 from the older image; Alex's private counter 3. |
| Remove and cached reinstall | Removal retires the entire app/runtime closure and launcher, retaining private files. With repository payloads removed, reinstall uses verified cache; status 24 and Alex's counter 4. Sam's counter remains 1. |

Tampering with the installed runtime must refuse before the native launcher can
change its counter. Restoring the signed bytes permits maintenance to continue.
Both users' files retain their ordinary ownership, private file modes and
private directory permissions; neither root's home nor ambient override paths
become app data.

## Reproduction

Use the [hardware controller toolchain](../hardware-platform/README.md) and a
reviewed V compiler. The default runtime builder requires native
`aarch64-linux-musl-gcc` (or `VINIX_MUSL_CC_AARCH64`). It generates C from the
existing V compatibility runtime, links its existing ARM64 ABI assembly and
uses section collection to discard unused V shell-capture helpers. A prebuilt
static runner may instead be supplied through `VINIX_APPLE_RUNTIME`; its actual
staged bytes are pinned in the receipt. No host-global runtime path is unveiled.

```sh
v -no-skip-unused -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/apple-runtime-check tests/packages/apple-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  VINIX_APPLE_SANDBOX=/build/aarch64-root/usr/bin/vinix-sandbox \
  /tmp/apple-runtime-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-apple-state
```

The state directory must be new. The controller copies the kernel before
building, records staged tool/runtime/sandbox and both Mach-O hashes, retains
serial/QMP logs and writes a passing receipt only after all required markers
and guest-initiated poweroff. `--list` creates no image. The current iOS runner
executes only on AArch64: x86-64 is omitted from its runnable scenario list and
an attempted x86-64 run fails before building or booting. Generic Apple package
launch-plan construction remains available on both hosts for explicit runtimes.

## Qualification, 2026-10-16

The AArch64 guest passed in **15.1 seconds** with the freshly built static
runtime and the retained isolated kernel from the
[installed-system qualification](software-installed-check.md). No kernel code
changed. Eight host build/run checks passed: Apple context, existing SDK context,
launch ownership with heap tracking, and clang ASan/UBSan. The ownership matrix
ran 1,000 plan/close cycles in each of 36 architecture/kind/mode cases, retaining
zero bytes. Sanitizers check exercised memory/undefined behavior with leak
detection disabled. Controller listing, unsupported-target and missing-input
refusals were also checked. Production package-tool staging passed on x86-64.

- [AArch64 receipt](results/2026-10-16/apple-runtime-aarch64.json), [serial log](results/2026-10-16/apple-runtime-aarch64.serial.txt), [QMP log](results/2026-10-16/apple-runtime-aarch64.qmp.txt)
- [Host checks](results/2026-10-16/apple-runtime-host.json), [ownership measurements](results/2026-10-16/apple-runtime-ownership.txt), [x86-64 build](results/2026-10-16/apple-runtime-x86_64.json)
- [Source/artifact ledger](results/2026-10-16/apple-runtime-toolchain.json)

This tests the package launch/container boundary and real Mach-O instructions.
The native launcher writes the counter and keychain-container fixture; the
Mach-O programs only return their distinct statuses. It does not qualify
Foundation/keychain API operations, arbitrary iOS/macOS applications, graphical
or audio sessions, translated execution, persistent-device reboot/crash behavior
or account credential-store protection. The guest root is an initramfs. The
broader Apple/Wine/graphical catalog acceptance gates remain open.
