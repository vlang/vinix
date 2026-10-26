# TimingLogger ART regression367

The [framework367 build](timing-logger367-framework-build.md) adds only
`android.util.TimingLogger` to qualified framework365. Fixture
`22c520345bee9e271196cc938c181ed8ea444cab` isolates that class in a three-class
APK. It checks virtual constructor/reset dispatch, elapsed-time bounds, ordered
nullable split labels, reused lists, reset state and unchanged repeated dumps.
Deterministic timestamps produce 7 ms and 9 ms splits and a 16 ms total, twice.

The pinned `Log.isLoggable` implementation always returns true. Disabled no-op
behavior is tested by reflectively setting `mDisabled`; reset recomputes logging
policy and re-enables the logger. This does not test a naturally false logging
policy. Maps behavior is covered by a separate replay.

Harness `ca0914b9826120e93ffa2f00d5cd78af0bfdea88` retains the complete qualified
framework chain, frozen compiler, generated C, host tools, actual command exits
and source closures. Its semantic self-test rejects missing, duplicated,
reordered or altered markers, tag/message pairs, old exception frames and raw
result fields. The same signed APK and native351/launcher353 runtime are used
for old365 and new367; only the framework JAR differs. Original startup
classification remains unchanged.

The complete 647-file harness bootstrap is retained at
`/Users/alex/.local/state/vinix/android/timing-logger367-run-bootstrap-build-2026-10-26`,
manifest `c066198d7e6f7450a450ac1353b95015594605afd35da152fdedbc7a45a02708`.
Compilation, semantic self-test and recorded complete checker exited 0. Root
and independent peer complete readbacks passed every file hash and the exact
file set; the peer also checked all 270 frozen V inputs before/after/current,
the committed source and actual compile command. The exact executed bootstrap
recorder is retained in Git at `92d1bf687`.

Preparation exited 0 from 02:24:27 to 02:33:12 UTC on 2026-10-26 at
`/Users/alex/.local/state/vinix/android/timing-logger367-fixture-2026-10-26`.
The earlier interrupted prepare had no completed host exit or result. Recovery
`e480de213` preserved its entire partial root and original before receipt under
the adjacent `-interrupted-prepare-01` and `-before.json-interrupted-01` paths.
All 91,350 file/directory/mode inventory entries matched before and after the
renames. The external recovery receipt is
`timing-logger367-prepare-recovery-2026-10-26.json`. The fresh retry used the
unchanged frozen harness and original capacity, integrity and semantic gates.

| Prepared input | SHA-256 |
| --- | --- |
| Fixture source | `8a470914003708b89beca57f7f5b10d20c062a3da0206549d77a50bbbe4a1ded` |
| Harness source | `a20ba298109f6a4edbcc4774b6665fd62a23d85375493ad50862c93b9b3d483a` |
| Bootstrap executable | `f5d40c0f39cdf0a36d1fc60d47d5fdb8a2a2dbf4cbbccbb2d6b4eab6a394a1da` |
| Checked runner | `a33a93cb8c8d21b244e92eca86a5d3dac8e23dd0142364db441b338ddcdd03a4` |
| Signed APK | `301c622cf8e986632b4797c0b63f366cbabfc99b3ed5d7d42ec401d908afb534` |

Both actual ART suite commands exited 0. Old365 ran from 02:42:16 to 02:42:42
UTC and failed the reflective class lookup as expected, before any successful
fixture phase. Its serial has one outer `ClassNotFoundException` for
`android.util.TimingLogger`, six ordered lookup/probe/activity frames, the same
class as its cause, `... 6 more`, and guest exit 1. The original host validator
exited **1**, because its speculative guard expected only one occurrence of
`ClassNotFoundException`. That failed attempt and all raw evidence are retained.

New367 ran from 02:48:13 to 02:49:02 UTC. The original host validator exited
**0** at 02:50:24 UTC. All six successful fixture markers appeared in order;
the complete tagged dump contained the initial 0 ms total and both exact
7/9/16 ms sequences. Raw classification was `window_observed`, process exit
false, QEMU alive, observation 35 seconds and no failure markers. The original
`functional_passed` field remains null.

Correction `eb15eaa93fc36043cdf78079142f011aa7990eff` accepts only the observed
12-line failure block and exact four raw failure markers. Negative self-tests
reject changed/missing/duplicated causes, frames, collapsed-frame counts,
positions, interposed output and suppressed exceptions. Independent source
review passed against the complete actual old serial and raw result.
The original prepared source, executable, APK, raw results, original failed old
invocation and successful new invocation remain unchanged. Fresh observed
qualification receipts use a separately built validator and repeat the same
full framework, native, APK and stable input checks before sealing.

The corrected validator's complete 649-file build is retained at
`/Users/alex/.local/state/vinix/android/timing-logger367-validator-build-2026-10-26`,
manifest `e8c12e1253ef246f1e7df1567ca8ae489963e0eca6f7fbd21438e1f5b9180116`.
Source SHA-256 is `2fb71f7be68319affe0d0fe2a9fbd07e62d8883a9d66dd125205d5e38bbfcf79`;
executable SHA-256 is `095ad9ad09f9a0a145f5cd4d24913514447ad6adde8fe24277abd26d3b00e72b`.
Compilation, expanded semantic self-test and original290 own complete readback
exited 0. All 270 frozen V input hashes matched before and after compilation;
the actual C command contains no mutable checkout path.
Independent reader `ff6cb9754` checked those inputs, the exact compile argv,
eleven successful commands and the self-test log, then ran the original290
auditor at 03:08:14–03:08:15 UTC. All 649 files passed, with the exact file set
and unchanged manifest. The retained peer directory is
`timing-logger367-validator-peer-readback-2026-10-26`; its complete receipt is
SHA-256 `08afd060e133b9ad5fe9e60f12dff682efc5cfb23ec7e157ddb03e171285caf7`.

Recorded observed qualification and sealing both exited 0. Fresh old/new
qualification and seal receipts match, including the corrected checker hash.
The unchanged prepared input manifest is
`7116f91f15ba29f61bdbd9e5026d08b6d2a4174636e200e6f14dc4f69c049216`.
The sealer inventoried and read back all **43,779 files**. The complete bundle
is the prepared fixture root above, final manifest
`e66d6d17e5552b7d909abdcadd0ce68dba4cf72adc34c4484cd59ff14cc2a9cf`.
Its `qualification` subtree retains the corrected validator build, source,
binary, generated C and compile evidence; original failed old and successful
new invocations; prepare/recovery receipts; and fresh observed checks. Actual
seal command/output evidence remains adjacent under prefix
`timing-logger367-fixture-observed-seal-2026-10-26`, with `-command.json` and
`.log` suffixes.

Independent ART reader `d30949f2f` verified the actual failure and successful
phase/dump sequences, unchanged signed APK and runtime, sole framework-JAR
difference, original invocation statuses, observed receipts and all 413 frozen
inputs. Its original290 complete readback exited 0 at 03:15:45–03:19:53 UTC,
checking every one of the 43,779 files and the exact file set without changing
the manifest. The receipt is
`timing-logger367-art-peer-readback-2026-10-26/complete-receipt.json`, SHA-256
`a0759e060cafbdedb832fef2aabc21d993b72bd08ddd62eca7dbcc0f94fc7836`.

The reader's initial preflight used the inherited runner filename for the
corrected validator source. It failed before the full readback; that attempt
is retained under `timing-logger367-art-peer-preflight-2026-10-26`. Correcting
the reader to the retained `timing-logger367-validator.v` path required no
runtime change or guest rerun. The successful wrapper is retained separately
under `timing-logger367-art-peer-qualified-2026-10-26`.
