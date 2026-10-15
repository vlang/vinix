# Installed-version preference

Normal installs prefer the exact installed package when its metadata, repository
and public key still occur in the authenticated catalog. Previously, the resolver
prepended copies of matching candidates and then appended the complete catalog.
Each unrelated installed package with one available version became two identical
search alternatives. With 20 such packages, adding an application that required
a newer shared dependency hit the 100,000-step search limit despite a valid
closure. The retained baseline reproduces that failed install.

Preference now rotates the matching candidate to the front of its sorted
identity group in the resolver's private candidate array. Every original catalog
record remains once, and other versions/architectures retain their order.
Installed identities have one temporary index, avoiding the previous scan of the
entire catalog for each installed package. After sorting, grouping, matching and
rotation visit a linear number of candidate records; package equality still
checks the manifest fields. Neither the catalog nor installed state is mutated.

The current catalog's sequence is retained when metadata/repository/key match.
Changed metadata, changed/revoked keys or another repository cannot acquire this
preference. Existing repository ownership filtering, policy/pins, architecture
ordering, upgrade selection and the real search budget retain their behavior.
Genuine alternative versions can still require bounded backtracking; this
change removes the artificial duplicates introduced by installed preference.

Host regressions exercise the formerly blocked install and unrelated missing
requirements on both architecture configurations, exact versus changed
provenance/metadata, sequence refresh, stable fallback order, host/`all`
preference, version pins and explicit upgrades. A maximum-size fixture covers
32,768 variants and 4,096 installed identities. Existing resolver assertions
include exhaustive checks on 256 generated graphs, maximum chains, dense cycles,
runtime fallback, conflicts and direct search-limit propagation.

The tracked fixture prepares its inputs outside measurement, then runs 1,000
public multi-version install resolutions and single-version missing-requirement
refusals. It frees returned plans, errors and messages, and checks that borrowed
catalog/state inputs survive. Native and ASan/UBSan runners measure resolver and
configuration-validation scratch. Sanitizer leak detection is disabled, while
the explicit allocation tracker checks retained bytes. This is not a
whole-service memory or performance qualification.

The first tracked runs retained 800,000 bytes over 1,000 success/refusal pairs.
Generated C identified a pre-existing 400-byte heap promotion of the public
resolver's `Search` local on each call. The wrapper now owns that object
explicitly and frees it with its diagnostic on success and error. Returned
plans borrow catalog manifest fields and do not reference the retired search
object. Initial failing runs and generated C are retained; all final checks and
guest builds use the corrected lifetime.

The maintained `tests/packages/distribution-check.v` driver includes the new
tracked runner. To run it directly with the reviewed V toolchain:

```sh
V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1 /path/to/v \
  -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/preference-memory \
  tools/packages/pkgcore/resolve_preference_test.v
/tmp/preference-memory
```

The signed offline CLI fixture installs 21 packages, refreshes a second catalog,
and checks plan/review/install refusal for a missing app without changing catalog,
trust or activation. A reviewed install then upgrades the required shared
package, keeps an unrelated installed version despite a newer candidate, verifies
the generation and rolls back. Separate disposable AArch64 and x86_64 roots use
the same authenticated release. The full distribution CLI lifecycle also runs.

Both fresh administrator guests require the new late-version-backtracking marker
alongside the existing authenticated administration and resolver workflows. They
boot frozen kernels; no kernel source is rebuilt. These synthetic checks do not
qualify a real application catalog, graphical login or foreign runtime APIs.
Roadmap 14 remains open for the broader distribution acceptance work.

The initial AArch64 guest passed the resolver markers but failed the existing
disconnected-worker completion assertion after its 30-second polling interval.
The serial log retained the active generation and zombie worker diagnostics;
this run does not establish the cause. The initial x86_64 guest passed. Fresh
final runs rebuild all user programs after the lifetime correction and retain
the same completion checks and timeout.

## Recorded results, 2026-10-16

All **29 focused compile/run checks** passed: ten core compile/run pairs, a native allocation pair, two sanitizer pairs, and three signed CLI compile/run checks. All phases were refreshed after fixing public search-object ownership.

Both fresh QEMU TCG guests passed with clean shutdown and eight verified artifact hashes each: AArch64 **32.84 seconds**, x86_64 **43.909 seconds**. These are functional deadlines, not performance qualification.

- [baseline regression](results/2026-10-16/resolver-preference-baseline.txt)
- [host results](results/2026-10-16/resolver-preference-host.json)
- [host summary](results/2026-10-16/resolver-preference-host.txt)
- [core assertions](results/2026-10-16/resolver-preference-core.txt)
- [tracked allocations](results/2026-10-16/resolver-preference-memory.txt)
- [sanitizers](results/2026-10-16/resolver-preference-asan.txt)
- [signed CLI](results/2026-10-16/resolver-preference-cli.txt)
- [initial attempts](results/2026-10-16/resolver-preference-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/resolver-preference-toolchain.json)
- [aarch64 receipt](results/2026-10-16/resolver-preference-aarch64.json)
- [aarch64 report](results/2026-10-16/resolver-preference-aarch64.txt)
- [aarch64 serial](results/2026-10-16/resolver-preference-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/resolver-preference-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/resolver-preference-x86_64.json)
- [x86_64 report](results/2026-10-16/resolver-preference-x86_64.txt)
- [x86_64 serial](results/2026-10-16/resolver-preference-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/resolver-preference-x86_64.qmp.txt)
