# Native SDK publisher metadata ownership

The native SDK profile now gives its six fixed templates, packed manifests and
canonicalization metadata one explicit owner. Templates borrow declaration
strings while owning notice selectors and collection buffers; imported manifests
are independent decodes. Catalog wrappers borrow selectors until encoding
finishes. Partial import, validation refusal and publication failure retire those
owners. Transfer between template arrays moves headers rather than triggering
V's implicit deep copy. The local publisher encoder frees its buffer, and the
canonical validation decode is retired after encoding.

`pkgcore.native_catalog` returns independently owned `NativeProfileInfo` fields.
Call `info.close()` after use. Repeated close is safe, caller arguments may be
freed after return, and close does not remove the saved catalog. The CLI encodes
and closes that reply. Package identities, target coverage, permissions,
associations, protocols, notices, canonical lock bytes and publication checks
retain their existing behavior.

The [ownership fixture](../../tools/packages/pkgcore/native_profile_ownership_test.v)
measures zero retained metadata bytes and allocations in nine warmed cases:
zero through six imported manifests, late duplicate identity refusal and empty
catalog refusal. Each runs 128 times under `-d track_heap -gc none -manualfree`,
for **1,152 measured cycles**. Canonical output and replies remain readable
after plan retirement; independent replies survive freed caller strings and
sibling close. Ordinary builds run four cycles per case.

A complete build is measured separately. The original implementation retained
**461,873 bytes / 1,827 allocations** after releasing its original reply. The new
host implementation retains **332,731 bytes / 1,353 allocations**, a reduction
of **129,142 bytes (28%)** for this fixture. The bounded metadata owner above
retains zero; the complete build still includes unqualified import, packing and
filesystem helper scratch. No kernel code changes or complete-profile allocation
freedom are claimed. The test preserves the original canonical SHA-256
`249d6bfb150918c4586f86d68da6b6394800d150f7385c3654fadb7ab19a3fce` and can also compare
the exact pre-change bytes using `VINIX_NATIVE_OWNERSHIP_GOLDEN`.

The [host controller](native-profile-ownership-check.v) performs 31 build/test
checks: production CLI, ten core suites, literal CLI maintenance, tracked
ownership, two clang ASan/UBSan suites and the full native profile staging
fixture. Existing suites check signed offline installation, registration,
removal, rollback, declarations, source changes and architecture/license
refusals. The native staging fixture retains all 64 substitutions in one
process plus three saved-output failures and exact retries. ASan leak detection
is disabled; zero-retention evidence comes from the separate tracker.

The [guest controller](native-profile-ownership-runtime-check.v) builds the
tracked owner fixture, existing signed native profile suite and complete native
staging fixture for each target. It stages the six reviewed example manifests
used by the existing suite's compile-time source paths. The owner and signed
lifecycle programs each run once; staging uses four fresh sixteen-case processes,
including all three saved-output failures in the first. It requires every
ownership/substitution/process marker before poweroff. It
uses unchanged qualification kernels and a 300-second functional deadline;
receipts pin the kernel, init, three executables, six manifest files and serial
output. Structural fixture executables are admitted and packaged, never launched.
Actual native application execution has separate section 14 qualification.

The first guest attempts reached the zero-retention checks, then stopped because
the harness omitted the six reviewed manifests. Staging those fixture inputs
fixed that harness failure. The next unsplit native staging run passed AArch64
in **68.4 seconds**, but x86_64 refused a prepared-payload read at substitution
case 37. Its resource observation reports **60,495,378 owner bytes** against a
**60,618,496-byte allowance**, with a further **131,200-byte** scratch request
denied. Global charge stayed below its limit, memory pressure was zero and open
descriptors were 0–3. File objects and mappings remained charged. This does not
identify a kernel leak or establish complete-builder allocation freedom. The
final guest driver uses the existing sixteen-case process boundary and retains
every substitution. Earlier fixture failures and the unsplit results remain
recorded alongside final passes.

```sh
v -o /tmp/native-profile-ownership-check tests/packages/native-profile-ownership-check.v
V=/path/to/reviewed/v /tmp/native-profile-ownership-check /build/new-native-owner-host

v -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/native-profile-ownership-runtime-check tests/packages/native-profile-ownership-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/native-profile-ownership-runtime-check --arch aarch64 \
  --kernel /build/aarch64-kernel --state-dir /build/new-native-owner-arm
```

Repeat the guest command for `x86_64` with its matching kernel and a fresh state
directory. Cross compilers, sysroot and Limine follow the
[hardware controller requirements](../hardware-platform/README.md).
Production publisher/catalog migration, graphical integration, wider runtimes
and the remaining section 14 acceptance gates stay open.

## Recorded results, 2026-10-17

All **31 host build/test checks** passed, including both ASan/UBSan suites,
exact pre-change catalog comparison, signed maintenance, the production CLI
and the 64-case native staging matrix. All nine metadata cases retained zero
bytes and allocations in the tracked host and both target runs.

Fresh QEMU TCG runs passed AArch64 (**82.7 seconds**) and x86_64
(**56.1 seconds**), each completing all 1,152 tracked metadata cycles, signed
native profile maintenance, 64 substitutions and three saved-output cases.
These are headless publisher/lifecycle checks. Other profiles' metadata
ownership, complete-builder retention, production catalog migration, graphical
sessions and broader compatibility-runtime acceptance remain open.

- [Baseline](results/2026-10-17/native-profile-ownership-baseline.txt),
  [baseline pins](results/2026-10-17/native-profile-ownership-baseline.json),
  [original fixture](results/2026-10-17/native-profile-ownership-baseline.v),
  [original catalog](results/2026-10-17/native-profile-ownership-golden.json).
- [Host receipt](results/2026-10-17/native-profile-ownership-host.json),
  [summary](results/2026-10-17/native-profile-ownership-host.txt),
  [tracked memory](results/2026-10-17/native-profile-ownership-memory.txt),
  [functional assertions](results/2026-10-17/native-profile-ownership-core.txt),
  [ownership sanitizer](results/2026-10-17/native-profile-ownership-asan.txt),
  [signed lifecycle sanitizer](results/2026-10-17/native-profile-ownership-native-asan.txt),
  [literal CLI](results/2026-10-17/native-profile-ownership-cli.txt),
  [native staging matrix](results/2026-10-17/native-profile-ownership-exports.txt).
- Final AArch64 [receipt](results/2026-10-17/native-profile-ownership-aarch64.json),
  [report](results/2026-10-17/native-profile-ownership-aarch64.txt),
  [serial](results/2026-10-17/native-profile-ownership-aarch64.serial.txt),
  [QMP](results/2026-10-17/native-profile-ownership-aarch64.qmp.txt).
- Final x86_64 [receipt](results/2026-10-17/native-profile-ownership-x86_64.json),
  [report](results/2026-10-17/native-profile-ownership-x86_64.txt),
  [serial](results/2026-10-17/native-profile-ownership-x86_64.serial.txt),
  [QMP](results/2026-10-17/native-profile-ownership-x86_64.qmp.txt).
- Earlier AArch64 [fixture failure](results/2026-10-17/native-profile-ownership-fixture-aarch64.txt)
  and [unsplit pass](results/2026-10-17/native-profile-ownership-unsplit-aarch64.txt);
  earlier x86_64 [fixture failure](results/2026-10-17/native-profile-ownership-fixture-x86_64.txt)
  and [unsplit owner-budget refusal](results/2026-10-17/native-profile-ownership-unsplit-x86_64.txt).
  Matching raw serial and QMP logs are retained for all four attempts.
- [Source/compiler/artifact ledger](results/2026-10-17/native-profile-ownership-toolchain.json)
  and [V retention/verifier](results/2026-10-17/native-profile-ownership-retain.v).
  Run the latter with `--verify` from the repository to check all retained local
  artifact hashes. Verbatim earlier failure reports preserve framework spaces
  and terminal blank lines; whitespace checks exclude those three raw reports
  and recognize CR at the end of raw serial lines with `core.whitespace=cr-at-eol`.
