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
executables directly in V, with chained imports from Foundation, CoreFoundation,
Security, libSystem and libobjc. Successful `LC_MAIN` code returns 23 and 24
respectively. They use neither an Apple SDK nor proprietary payloads. Both
application and runtime are packed, signed, enrolled and installed by the normal
package tools.
The runtime contains a signed native fixture launcher at `bin/run-ios` and the
actual compatibility runtime at `libexec/run-ios`. Both application/runtime
versions now pass through [`apple-catalog`](../../tools/packages/SDK.md#apple-ios-arm64-publisher-profile)
and `pack-catalog` before signing and installation. `Info.plist` and the literal
bundle executable argument satisfy that publisher profile. Separate
[publisher receipts](apple-profile-check.md) retain this integration; earlier
receipts below predate it.

The native launcher runs as the ordinary user inside the same production
sandbox. It validates SDK context, exact Documents/keychain/HOME/TMPDIR paths,
zero supplementary groups, hidden host paths and an explicitly granted literal
document. It writes a private boundary counter with mode 0600, then
execs its generation's real `run-ios` with its signed Mach-O application. It
does not create Documents, keychain directories or framework result files.
No chmod/fattr grant is added.
The account and package supervisors keep the normal generation lease throughout
execution. The exact Mach-O return status must propagate back through the CLI.

The Mach-O program itself checks `NSHomeDirectory`, `NSTemporaryDirectory` and
`NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)`
against the admitted environment. It converts the returned Foundation strings
through CoreFoundation and writes real document/temporary files at those paths.
It creates a generic-password credential, reads and updates its binary launch
counter, checks duplicate insertion and deletion of a second item, and rejects
an ungranted access group. Returned data is released; an autorelease pool is
drained on success or failure. Every failed check returns a distinct status. The
guest requires the Mach-O success marker and exact credential counter on every
successful launch, so resetting the store cannot pass update, rollback or
reinstall checks.

The guest checks five successful launches:

| Step | Required result |
| --- | --- |
| Initial launch, Alex | Mach-O status 23; boundary and keychain counters 1, framework file writes and literal document read. Ambient forged iOS paths remain unused. |
| Initial launch, Sam | Status 23; separate counters 1. Sam cannot use Alex's document grant or data. |
| Reviewed app/runtime upgrade | Status 24 from the newer image; Alex's counters 2. |
| Reviewed rollback | Status 23 from the older image; Alex's counters 3. |
| Remove and cached reinstall | Removal retires the entire app/runtime closure and launcher, retaining private files. With repository payloads removed, reinstall uses verified cache; status 24 and Alex's counters 4. Sam's counter remains 1. |

Tampering with the installed runtime must refuse before the native launcher can
change its counter. Restoring the signed bytes permits maintenance to continue.
Boundary counters and keychain files retain ordinary ownership and private file
modes under private data directories; neither root's home nor ambient override paths
become app data. `Info.plist` supplies the keychain bundle identity. Both users'
key/store files have mode 0600 under 0700 keychain directories. The store uses
the runtime's authenticated encrypted envelope and a local private key file,
as described in [the runtime contract](../../docs/ios.md); this is not hardware
key protection or an account credential service.

After cached reinstall, the guest corrupts one ciphertext byte and attempts
another launch. The Mach-O must return a check failure without a success marker,
an owned-object warning or a runtime panic, and the corrupt store must remain
byte-for-byte unchanged. The fixture restores the original bytes only after
checking refusal. This final failed attempt advances the native boundary counter
to five; the last successful keychain counter is four.

The first extended run found that `NSTemporaryDirectory` recursively attempted
to create ancestors outside the unveiled private-data grant. The runtime now
returns the already prepared directory after checking that it is a directory;
standalone creation remains available when it is absent. This adds no sandbox
grant and leaves existing directory modes intact.

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

## Foundation and Security qualification, 2026-10-16

The extended AArch64 package guest passed in **28.2 seconds** with a fresh
static runtime and the same isolated kernel/sandbox as the baseline below.
All five Mach-O successes and counters 1/1/2/3/4 appear in the serial log.
The guest checks the framework-written files, both users' private keychain
storage, runtime tamper refusal, maintenance lifecycle and damaged-store refusal
before powering off normally. No kernel or sandbox code changed.

Seven host build/run checks passed: the Mach-O fixture's imports and 4K/16K
mapping plans, controller build, the existing Foundation temporary-directory
ABI/ownership/path/concurrency tests and those tests under clang ASan/UBSan.
Sanitizer leak detection is disabled; the tests separately assert drained
runtime object ownership. Four controller checks cover both architecture lists,
x86-64 execution refusal and missing-input refusal. There is no x86-64 runtime
or new x86-64 production-tool qualification in these receipts.

- [AArch64 receipt](results/2026-10-16/apple-framework-aarch64.json), [serial log](results/2026-10-16/apple-framework-aarch64.serial.txt), [QMP log](results/2026-10-16/apple-framework-aarch64.qmp.txt)
- [Host checks](results/2026-10-16/apple-framework-host.json), [Foundation tests](results/2026-10-16/apple-framework-temporary-directory.txt), [sanitizer tests](results/2026-10-16/apple-framework-sanitizer.txt), [controller checks](results/2026-10-16/apple-framework-controller.json)
- [Original temporary-directory failure](results/2026-10-16/apple-framework-before.serial.txt), [source/artifact ledger](results/2026-10-16/apple-framework-toolchain.json)

The failure run used generated runtime C identical to the baseline's pinned
source; both generated C and resulting binary hashes are recorded. Its replacement
passes the existing-directory check inside the real sandbox; missing-directory,
invalid-path, boundary-length and autorelease behavior remain covered by the
host regression tests. The new receipts supersede the minimal instruction
fixture only for the bounded Foundation/Security subset described above.

## Launch/container baseline, 2026-10-16

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

Those original receipts qualify only the package launch/container boundary and
minimal Mach-O return instructions. The extended framework fixture above has
separate receipts, so historical evidence keeps its original scope.

The guest root is an initramfs. Neither check qualifies arbitrary iOS/macOS
applications, graphical or audio sessions, translated execution,
persistent-device reboot/crash behavior or account credential-store protection.
The broader Apple/Wine/graphical catalog acceptance gates remain open.
