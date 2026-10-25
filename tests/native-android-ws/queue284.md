# Main queue progress between frames

Attempt284 passes the targeted queue/frame regression. The qualified276
native library fails before its first frame can observe a pending callback
chain. The bounded pump renders a partial chain, completes all 1,024 callbacks
in order and completes its natural 90-second observation. This establishes
frame progress during queued work; it does not measure Maps response latency.

Production commit `016a50ea3cfd6ae2503b392fee13a0746170fb84` changes only
`build-support/android/nativews/runtime.v` and `queue.v`. Fixture, build driver,
host regression and final checker revisions are respectively `57ac6c771`,
`5dd310664`, `1f06bbfa5` and `22cd2ae70`.

The fixture posts a finite chain of 1,024 ordered main-Looper callbacks. Its
first pre-draw requires a strict partial count and a pending successor. After
the chain completes, a delayed callback checks exactly-once ordering, the
earlier partial frame and the elapsed delay before printing completion.

Both runs used the same new fixture APK, framework282 JAR, suite, configuration
apart from declared private paths/native overlay, and initial guest media.
Only the staged native library differed.

| Runtime | Requested / observed window | Targeted result | Observed app exit | QEMU alive at capture |
| --- | --- | --- | --- | --- |
| Baseline276 | 90 / 4 seconds | Expected first-pre-draw assertion, exit 1; no pass markers | Yes | Yes |
| Fixed284 | 90 / 90 seconds | All three pass markers once, in order | No | Yes |

The baseline assertion was `first pre-draw must run during pending chain:
0 < count < 1024`. Fixed284 emitted `BOOTSTRAP-QUEUE-PUMP-PASS`,
`BOOTSTRAP-QUEUE-PUMP-COMPLETE-PASS` and `BOOTSTRAP-READY`; its serial log has
no assertion, JNI, render failure or app-exit marker. Both backends were ready.
The capture proves QEMU liveness and no observed app exit, without a separate
app-PID liveness sample at the observation endpoint.

Both unchanged raw suite classifications remain `startup_failed`, with
`functional_passed=null`. In the fixed run the only failure markers are the
inherited Maps transition diagnostic's `NoSuchFieldError` for `Lnge;`/`bB`
and its `ClassNotFoundException: nge` cause. The checker preserves and
reconstructs those raw classifications independently of the targeted result.

The complete new source/build/run evidence is retained at
`/Users/alex/.local/state/vinix/android/compound284-2026-10-25`.
The checker consumes pinned small references to the sealed276 native inputs
and sealed282 framework inputs; it does not claim to revalidate either entire
historical bundle. The original preparation completed naturally with a full
2,676-entry readback; no resume finisher was used. The bundle contains all six
actual generation/build/suite receipt triplets, complete prepared inputs,
both raw runs and media, staged-runtime inventories, and frozen checker inputs.

SHA-256 pins:

| Artifact | SHA-256 |
| --- | --- |
| Original prelaunch manifest | `c90e705c8a03044dac321190f02a8678d6050f749fa17f800db786c45d084699` |
| Complete post-run manifest | `b503ca7ffa5bb81aed1a97639be94acd5a1ca80dda3895239a223b2c1962ac9a` |
| Same fixture APK | `ab203965d33323bd6f465a27cb4b12013cccab1a6d49f8254cf113bb82f28414` |
| Same framework282 JAR | `92b069b1dbb31b08960d00d4f33f84b068a3adf53af9339f2ef3c1a6478f0618` |
| Baseline276 native library | `5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca` |
| Fixed284 native library | `2687a6df361f3173499fcae7ffeeb9318d2c83363cee1fce0deedf17f9ee0585` |

The semantic seal and complete pinned check both passed with exit 0. The
wrong-pin negative exited 1 at `manifest pin mismatch`. Recheck the retained
bundle with its assertion-enabled frozen checker:

```sh
/Users/alex/.local/state/vinix/android/compound284-2026-10-25/checker/queue284-evidence check /Users/alex/.local/state/vinix/android/compound284-2026-10-25 b503ca7ffa5bb81aed1a97639be94acd5a1ca80dda3895239a223b2c1962ac9a
```

Post-seal validation logs remain outside the sealed bundle at
`/Users/alex/.local/state/vinix/android/queue284-validation-2026-10-25`.
Their three outputs and the explicitly transcribed invocation/status receipt
are pinned by `qualification-sha256.json`, whose SHA-256 is
`66af3c0109a76476fb1f3d22f808fecc3f75a02a805fcdc3d1385d4242c80dc8`.

Native generation uses a private copy of the exact retained276 V compiler
(`109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e`)
with the same generator V source closure. The new bundle retains its expanded
cross-compiler inputs. Historical276 pinned its GCC driver and explicit link
libraries; this comparison does not establish a complete historical default
toolchain closure.

The independent host regression at
`/Users/alex/.local/state/vinix/android/queue-pump-host-2026-10-25` built and
ran with exit 0. Its five PASS markers cover count/reset, deadline/progress,
timeout/null handling and worker pipes/destruction. Its receipt pins the
queue, runtime and test sources; this host run used the recorded shared
compiler selection, without a claim that it used the retained109a compiler.

The first fast-checker preflight rejected Java because the retained284 host
executable hashes to
`236c86402d47923ebc974f8237175038eedfcb3b8a7594b2a2dd8113249b99ea`,
while sealed282 retained
`9ef6c1a939343ac850811551a8b88d4b877630ab2c94ac38c541e25ccc8cf0a5`.
The unchanged suite uses Java, aapt2 and apksigner for host APK inspection and
signature verification. Fast3 checks their retained284 bytes before and after
each run and binds them to both run receipts. QEMU, firmware and the input
tool still require their historical282 pins. No historical Java equality is
claimed. The rejected preflight is retained in `workflow/preflight-fast2-rejected.log`;
its original frozen source, binary, compile receipt and passing hash tests
remain at
`/Users/alex/.local/state/vinix/android/queue284-evidence-tool-fast2-2026-10-25`.

Fast3 then rejected the exact configuration comparison because its constructed
`90` and the decoded JSON number used different `json2.Any` numeric variants.
Fast4 round-trips the complete expected object through JSON before the exact
comparison. Its regression test reproduces the mismatch and rejects changed
nested numbers and extra or missing nested fields. The original rejection is
retained in `workflow/preflight-fast3-rejected.log`, with its frozen checker
at `queue284-evidence-tool-fast3-2026-10-25` beside the other tool versions.

The first fast4 launch stopped before starting a guest: its wrapper expected
an `attempt.json` metadata file that the builder does not create. Fast5 uses
the builder's exact prepared-bundle path and exposes the same launch-metadata
construction through a command that starts no guest. The failed output and
original run-tool source and binary remain in the external validation history;
`workflow/run-baseline-fast4-rejected.log` records the failure in this bundle.

The maintained checker uses streaming CommonCrypto SHA-256 on macOS and keeps
the portable V implementation for byte-equivalence tests. Its assertion-enabled
109a compiler, selected C compiler, actual `cc -M` transitive SDK headers,
SDK settings and link stubs are retained and checked before and after the
actual checker compile. The recorded scope excludes a runtime dyld shared-cache
byte audit. Known vectors, block and chunk boundaries, a 64 MiB binary vector
through both backends, and the sealed276 4 GiB image pin qualify this hash path.
