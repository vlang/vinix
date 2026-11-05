# Linux iOS runtime checkpoint — 2026-11-01

## Outcome and qualification

The maintained iOS compatibility runner now has a Linux test path that builds
real ARM64 GNU/glibc ELF executables and runs them through QEMU user emulation
on the Linux x86_64 host. The ARM64 ABI assembly is compiled and executed.
The accepted HTTP, reachability and Network-path captures exercise the final
worker-registration retirement fixes with ASan and UBSan.

**Fortnite remains at the historical 4/8 launch gates.** Loading/binding,
`+load`, initializers and application entry were previously established.
There is no newly verified frame, menu, login, match or gameplay.
The required Fortnite application and prepared Vinix guest inputs were
unavailable here; this work did not execute a fresh Fortnite or Vinix VM probe.
The Linux fixtures do not establish that the disabled-cookie correction
advances the game past its previously observed cookie-policy failure.
The maintained `probe-no-ads` mode continues to skip advertising.

Native Apple Foundation was not executed in this Linux environment.
Runtime fixture messages that mention native ABI/oracle expectations retain
their historical wording; they are not evidence of a new Foundation run.

## Source and implementation

| Published commit | Change |
| --- | --- |
| `9c09556a093ca010fb76d8e49fadc707205f9c03` | Numeric IPv6 scope support for Linux resolver behavior |
| `7b0d6341b27641d8af50fed3667e77b025a2d75f` | Linux/macOS host-tool selection for the existing VM helper |
| `cfe42c97f311de866223158f03fc7a6856adf8b3` | Guarded Linux ARM64 runtime checks, maintained checker and documentation |
| `afeb4b2601cce7ff17fb37f42b6c425816750cfe` | Retirement of registrations after joined dispatch/monitor workers |
| `9a32d37a26564fb57391f728c3f2714e141e91d2` | Recorded optional GCC memory setting for constrained hosts |

The memory-option publication corresponds to local commit
`df8c5d23dc49a71b287c8a9fa50c812c04128c47`; both have tree
`74fbe15a59a0e83beee503bd56dae8c54ea10f4f`. Its source-policy check passed.

The earlier cookie-policy correction is `fcee5f780796f6df200eb4a44430741b16c80d8e`.
It distinguishes an unset request policy from an explicit request override.
An unset request inherits the configuration's disabled policy while preserving
its public getter; explicit request values take precedence. Manual Cookie
headers remain caller-owned. Automatic cookies and partitioned cookies remain
unsupported. No cookie jar, automatic response-cookie replay or persistence
was added. Method normalization retains OPTIONS and preserves lowercase trace.

Linux execution exposed joined workers whose runtime registrations remained
live. The dispatch pool, reachability monitor and Network monitor now join
through the runtime adapter that retires the registration on successful join.
The HTTP regression inspects the retained registration identities after
shutdown without refreshing the thread table, so owner-death discovery cannot
hide a missing retirement.

The HTTP fixture compares already-buffered body spans in bulk while leaving
refills, TLS, EOF and deadlines to the existing stream reader. It retains
byte comparisons and mismatch/short-body/deadline controls. Production network
deadlines were not relaxed to accommodate emulation.

## Host profile and pinned inputs

`STATE=/workspace/scratch/6384ba2a563f/ios-linux-state`

`REPO=/workspace/scratch/6384ba2a563f/vinix`

| Input | Recorded value |
| --- | --- |
| Host | Ubuntu 24.04.3 LTS, Linux x86_64; qualification field `linux-amd64` |
| Target | `aarch64-linux-gnu`, 64-bit little-endian ARM64 ELF |
| V source | `c6bb06f5c04d78f9f6d22a57c257d27e835ba40a` |
| V version | `V 0.5.2 c6bb06f` |
| GNU compiler | `aarch64-linux-gnu-gcc-13`, Ubuntu 13.2.0-23ubuntu4 |
| QEMU | `qemu-aarch64-static`, 8.2.2, Debian 1:8.2.2+ds-0ubuntu1 |
| Compiler sysroot | `STATE/cross` |
| Loader/library prefix | `STATE/cross/usr/aarch64-linux-gnu` |
| Runtime build | C `-O1`, debug information, retained V assertions |
| Fixture instrumentation | ASan/UBSan; LeakSanitizer disabled |
| Execution pair | Ordinary environment and `SWIFT_DETERMINISTIC_HASHING=1` |

| Pinned executable/input | SHA-256 |
| --- | --- |
| Frozen V executable | `cbf760262480fcc4566bea1a8c1bc53d503883e248c5df3ecded72d89a016a2e` |
| AArch64 GCC executable | `8487ff08df4a785d6f596663a0b1416afe18638c75cf5fa34f036e3d51324515` |
| QEMU executable | `10675c4a3df1b2ab279a4ff808fac00e158eede951884a3094c796e41e64e685` |
| ARM64 dispatch assembly | `d3eacfc727fce47db915bade8d5bed26f50e1ff8557dc5681ce60b1bb44b35ea` |
| HTTP/monitor driver `linux-checks-v7` | `4de00700cd6cf4cc803f8a0c914bce6e0ebabfeb44a84bb0b464fe5354423892` |
| Final-capture driver `linux-checks-v8` | `7f48671e170e0f1b010212795e4388018e0b5d86b6c11a8525d8bf8ef2ed72ca` |
| Built wrapper `notification-checks-linux-v8` | `2a62ae5a6e0bd3d5bfccefd3e6e85ed32749814ba7794f8b5c93551195d3cd0c` |
| Earlier driver `linux-checks-v4` | `5b6fc828d9afc554bea4e7cbba1a65b910b172994cdd8c40294d189a4398d1b7` |

Optional video, C++, SQLite, GLES and text backends are disabled; this profile
requires GNU/glibc. The separate VM route preserves ARM64 musl guest inputs.
Direct Linux ARM64 execution is supported but was not run here. The V 0.5.2
release archive is older than the required source pin; its version is insufficient.

## Accepted runtime captures

The following completed captures have successful runtime receipts and complete
file-inventory audits. Durations are from saved receipts, rounded to milliseconds.
Each sanitized fixture pair exited 0 and retained its coverage markers.
The unsanitized synthetic runner uses the expected exits recorded below.

| Capture under STATE | Scope | Seconds (fixture pair) / exits (runner) |
| --- | --- | --- |
| `http-r4` | Full HTTP/TLS, URL-session policy, transfers and shutdown | 407.284 / 441.438 |
| `reachability-r1` | Reachability monitor ownership and joined shutdown | 10.635 / 10.085 |
| `network-path-r1` | Network-path monitor ownership and joined shutdown | 22.036 / 15.420 |
| `request-r6` | Request policies, copies, headers, method spelling/rejections | 219.732 / 205.916 |
| `storekit-r2` | Purchase/queue/observer coverage and selector-growth regression | 399.563 / 357.254 |
| `netdb-r7` | Numeric IPv6 resolver scope behavior; low-memory compiler option | 0.901 / 0.741 |
| `runner-r3` | Real ARM64 synthetic Mach-O loading, entry and argument forwarding | Help/inspect 0; entry 37; extra argument 99 |

Netdb-r7's exact runtime durations are 0.901094504 / 0.741309611 seconds;
its generated-C compiler completed in 223.472153648 seconds. Both new captures
record `gcc_low_memory=true` and the v8 driver. The synthetic runner requires
no Fortnite or Apple framework assets and establishes no Fortnite result.

These two originals completed under `/tmp/vinix-ios-linux-20261101.Br5goD/`.
Each passed strict isolated audit, V copying into STATE, the unchanged
`evidence-delta` typed comparison, and a workspace inventory audit. The copied
trees remain byte/type/mode matches of the originals; no inventory was resealed.

The first three are the final relevant captures for the worker-join changes.
Request and StoreKit are applicable earlier regression captures: their fixtures
do not exercise the changed pool/monitor joins. They are not presented as
post-fix coverage for those lifetimes.

HTTP emits exactly **25 required runtime coverage markers in each run**.
Its disabled-cookie fixture performs **24 transfers per run** across request-off,
both-off and inherited-off policies, manual-header presence/absence, repeated
sessions and two drained runtimes. It checks copied policy isolation, preserved
manual headers, no replay of duplicate response cookies, callback ordering,
request getters and complete object/block cleanup.

The HTTP worker marker includes retirement of delegate-thread registrations.
The two monitor fixtures each exercise two runtime cycles. Reachability retains
its explicit exclusion of generic DNS monitoring. Network-path checks include
retained immutable snapshots, readers, suppression/coalescing, queued
cancellation, in-flight handler replacement and owned dispatch cleanup.

The accepted fixture runs and synthetic runner commands have clean guard receipts:
`reaped=true`, `cleanup_complete=true`, and `residual_descendants=0`.
The command guard has a 600-second limit and a 16 MiB output limit; the complete
nested TLS build is guarded as a worker, including its subprocesses.

### Captured source identity

A capture's Git base is not the complete source identity: it also preserves
the working diff, copied fixture/runtime sources and copied driver used.
Do not relabel these captures as builds of a later clean commit.

| Capture | Recorded Git base | Driver |
| --- | --- | --- |
| `http-r4` | `7b0d6341b27641d8af50fed3667e77b025a2d75f` | `linux-checks-v7` |
| `reachability-r1`, `network-path-r1` | `cfe42c97f311de866223158f03fc7a6856adf8b3` | `linux-checks-v7` |
| `request-r6`, `storekit-r2` | `de976a770221a39b89686927f1574ec9b8aead72` | `linux-checks-v4` |
| `netdb-r7`, `runner-r3` | `afeb4b2601cce7ff17fb37f42b6c425816750cfe` | `linux-checks-v8` |

`source-provenance-r1.log` and `source-provenance-r2.log` establish the exact
production/selected-fixture relationship to current source: HTTP, both monitor
captures and netdb-r7 each match 608 input hashes; runner-r3 matches 607.
Request and StoreKit each match 605 and differ only in the three documented
join fixes: `compat/ios/runner/dispatch_queues.c.v`, `network_path.c.v` and
`reachability.c.v`. Their selected fixtures do not exercise those changed joins.
This input comparison does not relabel their preserved drivers or Git bases.

### Accepted inventory pins

| Capture | Files / directories / file bytes | inventory.json SHA-256 |
| --- | --- | --- |
| `http-r4` | 1,418 / 24 / 369,483,402 | `1fa6bd89eb2d0f053edfa72e47a56384ea8f70464e3dd484edac1ec6e8d28f4d` |
| `reachability-r1` | 1,411 / 24 / 253,284,903 | `1a54320d5db5b665947377d12f1bac0cacd4892be5ffd3d74d27c04791720f2f` |
| `network-path-r1` | 1,410 / 24 / 181,585,913 | `47b99e044bde1a292bfb2cf8a78ad9d0ee237619173102c98d2e65f3581e7151` |
| `request-r6` | 1,409 / 24 / 180,259,211 | `5c23ba5327e0d7466fb86a0c358e6967b778953e5f8b4b349687b83167b83890` |
| `storekit-r2` | 1,409 / 24 / 180,607,356 | `575873c6ade0a36310b2c4bc8ad07849a1477cabfce8fa745d42f5073f6cdfa7` |
| `netdb-r7` | 1,409 / 24 / 180,101,055 | `18c3b6c3ab2b7d38aa2649beb20ad80c1ced7a99aaaa4c92e56bdbf8ab09280a` |
| `runner-r3` | 1,420 / 24 / 75,412,959 | `4014fd8e3b324713e6cd6f5dfee9f514d75eb44616d7c9e2673b7a1b2cf2d265` |

Counts/bytes exclude the inventory itself and include the final result receipt.
`final-capture-audit.log` re-audits all seven captures above and the earlier
accepted `request-r5`, `netdb-r2` and `runner-r1`, after all runtime writers
stopped. Individual audit and copy-comparison receipts remain under STATE.

## Rejected and incomplete evidence

A runtime PASS and an accepted complete evidence tree are separate requirements.
The following attempts remain preserved as failures; they were not resealed,
repaired in place or substituted into the accepted inventory table.

| Capture | Recorded disposition |
| --- | --- |
| `netdb-r3` | Runtime pair exited 0; complete audit rejected a SHA mismatch for `tmp/cciLH8Qs.s` |
| `runner-r2` | Synthetic entry exits were 37/99; complete audit rejected unlisted `tmp/cciwNHfL.s` |
| `netdb-r4` | Generated-C compiler exited 1: `Killed signal terminated program cc1`; runtime qualification did not complete |
| `netdb-r5` | Runtime pair exited 0; complete audit rejected unlisted `tmp/ccMFDWfT.s` |
| `netdb-r6` | Runtime pair exited 0; complete audit rejected unlisted `tmp/ccyQtOgT.s` |
| `http-r2` | Runtime failed on POST, 65,540-byte body, TLS=false |
| `http-r3` | Runtime failed with `iOS: active thread at image shutdown` |

For netdb-r3, the recorded expected SHA is
`ed0b32fd4023ed8d7d7fd42ffb2c83809284454bde6dcc9a19103fb137c7d56b`;
the audited SHA is
`0466ea6955a5f6cd693542f956e9228ab24cefe4c5a4156a44f840b272b20470`.
The rejection receipts are `evidence-review-captures-r2.log`, `netdb-r5-audit.log`
and `netdb-r6-audit.log`. This report does not assign a cause to the integrity
discrepancies. The complete rejected trees remain evidence.

Netdb-r5's ordinary/deterministic runtime durations were 0.463 / 0.472 seconds.
Its optional low-memory compiler run completed in 309.129269586 seconds.
These execution successes do not override its failed inventory audit.
Netdb-r6 likewise passed both runtimes in 0.782561001 / 0.577535627 seconds;
its compiler completed in 256.537424755 seconds. Its failed complete audit
also excludes it from the accepted capture table.

The published optional GCC memory setting accepts only 0/1 overrides for
`VINIX_IOS_LINUX_GCC_LOW_MEMORY` (unset defaults to 0); 1 adds
`--param=ggc-min-expand=10` and `--param=ggc-min-heapsize=16384`, recorded in
qualification/command receipts.
It retains assertions, -O1, debug data, sanitizers and runtime deadlines.
Netdb-r7 and runner-r3 are its accepted captures. The earlier runtime successes
do not erase their integrity rejections. Netdb-r4's compiler/memory logs survive.

## macOS compatibility checks

The notification-checks wrapper's macOS-target V-to-C generation passed
(`notification-checks-macos-v6-generation.log`). This is a source-generation
check, not a macOS link, execution or native Foundation comparison.

The HTTP fixture's macOS-target V-to-C generation failed in both the baseline
and final source with the same duplicate `C.mach_timebase_info` signature:
`vlib/time/time_darwin.c.v:18` conflicts with
`compat/ios/runner/proc_rusage.c.v:14`.
Receipts: `http-baseline-macos-generate.log` and
`http-final-macos-generate.log`. The baseline reproduces the failure, but
this does not make the final fixture a native-oracle pass. Native comparison
assertions were retained; no new native execution result is claimed.

## Harness and evidence controls

The final process-guard log reports 5 passing tests and 16 assertions, covering
normal/nonzero exits, orphan retirement, closed stdin, deadline/output bounds
and parent-signal cleanup (`guard-checks/build-final.log`).
The inventory unit log reports 5 passing tests and 15 assertions, including
hidden-file coverage and FIFO rejection (`linux-inventory-unit-r1.build.log`).

Host-tool controls pass 6 tests / 21 assertions (`hosttools-checks/hosttools-build-r2.log`).
The wrapper's isolated-environment control passed through the actual guarded
hop, stripping inherited compiler/test controls while preserving explicit
inputs; receipts: `vm-wrapper-checks/environment-control-r2-run.log`
and `vm-wrapper-checks/environment-wrapper-r2.log`.

The maintained `tests/ios/linux-evidence-check.v` accepted one valid synthetic
tree and rejected 19 corruption controls. It verifies every listed file hash,
complete hidden-file coverage, safe/unique relative paths and strict file types.
Its self-test and accepted-capture receipts are
`linux-evidence-controls-r1.log` and `linux-evidence-captures-r1.log`.
An optimized build of the identical checker source, with V `-nocache` and C
`-O3`, passed the same one-valid/19-corrupt control set again
(`linux-evidence-optimized-controls.log`). V assertions remain enabled.
Deliberately invalid control trees contain symlinks/FIFOs and must be retained
separately as nested archives, rather than treated as valid capture trees.

Source-policy receipts for the completed harness and worker fixes report PASS:
`source-policy-harness-r2.log` and `source-policy-worker-fix.log`.
The published memory option also passed the source-policy gate.
The published five-commit code range passes `git-source-policy` against
`fcee5f780796f6df200eb4a44430741b16c80d8e` (`source-policy-published-code.log`).
Historical auditors and their original complete-bundle requirements are unchanged.
The prior 46 guest fixtures and 339 corruption controls were not rerun as part
of this separate Linux qualification.

## Reproduction, preservation and final publication

Use `tests/ios/linux-host.md` for the frozen-toolchain build, standalone modes,
external output layout and maintained inventory checker. Each capture must use
a fresh external output directory. Retain its source copy, commands, compiler
products, input hashes, logs, guards, statuses, qualification and inventory.

The separate VM instructions are `tests/ios/hosttools/README.md`.
They document Linux TCG/KVM versus macOS HVF, tool/input overrides, private EFI
variables and the Linux CA bundle. VM helper source support does not qualify
a boot or game capture without its required kernel, SDKs, app and content.

### Complete archive and restoration

The selected evidence payload contains **40,012 files / 6,996,561,083 bytes**.
The outer tree also includes `SELECTION.txt`. It preserves complete accepted
and rejected captures, source snapshots, generated C/objects/binaries,
diagnostics, receipts, and the selected frozen V, GNU ARM64 SDK/QEMU and
bootstrap inputs. Negative controls with intentional symlinks/FIFOs remain in
nested archives. No removed macOS RAM volume or historical parent is required
for this standalone collection.

| Artifact | Recorded value |
| --- | --- |
| Archive | `vinix-ios-linux-evidence-20261101.tar.zst` |
| Complete archive bytes | `861792432` |
| SHA-256 | `958b3f61e5e1bb0ed6a1ee938f1903c5e2bcdc91f471321dfca9a8a2b80b772d` |
| Compression | Zstandard `--long=28 -T2 -12` |
| Staged tree | `/workspace/scratch/6384ba2a563f/vinix-ios-linux-evidence-20261101` |
| Fresh restored tree | `/workspace/scratch/6384ba2a563f/vinix-ios-linux-restored-20261101` |
| Final audit receipts | `/workspace/scratch/6384ba2a563f/vinix-ios-linux-audit-20261101` |

The complete fresh restoration passed the unchanged `evidence-delta`
byte/type/mode comparison, including empty directories. All ten accepted
capture inventories passed again from the restored tree. The nested frozen V,
SDK/QEMU and bootstrap archives were fully extracted and compared with their
recorded payloads. Their source payload comparisons had passed before sealing.

An optimized build of the unchanged typed auditor used V `-nocache` and C
`-O3`, without V `-prod` or disabled assertions. Its same-tree positive
control passed and its changed-file control was rejected. The original auditor
binary is retained; the two isolated-copy comparisons used that original
binary. The final restored inventory checker likewise uses unchanged source
and passed the same one-valid/19-corrupt controls. Exact source/binary pins are
in `archive-tool-hashes.txt`.

Final receipts include `staging.log`, `restore-typed-compare.log`,
`restored-capture-audit.log`, and the three `restored-*-compare.log` files.
The archive hash and post-restoration receipts are recorded separately from
the already sealed archive, avoiding a self-reference.

### Numbered delivery parts

The complete archive exceeds the attachment service's 512 MiB file limit.
Two numbered parts were saved successfully; concatenating them preserves
the exact complete-archive bytes and SHA-256 above. A V streaming splitter
verified the ordered part stream before delivery.

| Suffix appended to the archive name | Bytes | SHA-256 |
| --- | --- | --- |
| `.part01` | `471859200` | `d2366d9f847b0edfb339dac458cac71a01fada12005a2fd816ddd9f75918c130` |
| `.part02` | `389933232` | `912835b96a66767d10aa506718ca876c0cb2459bab717dbe255363f7d46a56c4` |

Reassemble and restore in a fresh directory:

```sh
cat vinix-ios-linux-evidence-20261101.tar.zst.part01 \
    vinix-ios-linux-evidence-20261101.tar.zst.part02 \
    > vinix-ios-linux-evidence-20261101.tar.zst
sha256sum vinix-ios-linux-evidence-20261101.tar.zst
mkdir restored
tar --same-permissions --use-compress-program='zstd --long=28' \
    -xf vinix-ios-linux-evidence-20261101.tar.zst -C restored
```

The accompanying audit-receipt bundle retains the final comparison logs,
part manifest, delivery receipts and checkpoint source-policy result. The
complete deliverable remains outside Git; this repository contains the V
implementation, maintained checks, documentation and this qualified report.

The next game qualification still requires the original application,
frameworks, resources and cooked content, plus the prepared musl/GLES guest
dependencies, kernel, firmware and bootloader. A fresh guarded `probe-no-ads`
capture must establish whether the cookie-policy correction advances Fortnite.
