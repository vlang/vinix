# Final G13 queue-record ownership

`v run tests/agx-file-close/run.v` runs the full existing file-close fixture plus
216 new close/detached/orphan cases with actual heap records and the production
disposer. It uses ASan/UBSan, `-gc none -manualfree`; enable fake stacks with
`ASAN_OPTIONS=detect_stack_use_after_return=1`. Cases vary manager availability,
captures before VM admission, backing refusal, already-released stopped queues
and one/three owners. Partial close and mapping failure retain metadata; final
owner removal poisons it. Repeated close must not replay disposal. Old stack/pool
fixtures use an asserted disposal token so their later observations remain valid.
The actual kernel helper is extracted for new heap records. Firmware, mappings,
manager backing release and VM services remain host instrumentation.

`MallocNanoZone=0 v run tests/agx-file-close/run.v --record-measure` measures three
10,000-close batches with one warmed, owned file. This isolates queue records
from a test-local file that V would otherwise promote to a leaked heap object.
The baseline retains 10,000 blocks / 1,600,000 fixture bytes; the fixed path is
flat. The preceding queue-unwind bundle retains the independent nano-accounting
control. Native slab rates and object sizes are not measured here.

`counterexamples.v CLOSE_RUNNER BASELINE_FILE FRESH_OUTPUT` requires seven
compiled baseline/mutations to fail designated missing-disposal, capture,
manager or duplicate-owner assertions. Compiler failures do not qualify.
`--file-source FILE` selects alternative production file logic. Existing output
variables `AGX_CLOSE_TEST_C` / `AGX_CLOSE_TEST_BINARY` retain artifacts externally.
The runner now returns through fixture cleanup before successful or failed exit.

`check.v --native CURRENT_ARM_C BASELINE_ARM_C` requires exactly three final-owner
call sites and one native free, exact close/capture/manager/pop and reaper changes,
four unchanged owning layouts and 31 unchanged backing/context/capture/pending/
heap bodies. Numbered loop, option, return and array temporaries are renamed
consistently and string IDs resolve by value. `--selftest` rejects eight disposal,
index, manager, capture, allocation, link and reference mutations. Production
builds omit debug assertions in the disposer; file-side conditional guards
remain present and are checked. `check-allocations.v CURRENT BASELINE` permits
only the newly verified queue-record site to leave ARM allocation diagnostics.

`qualify.v STATE` prepares a baseline worktree with two source overlays. Its
`--refresh STATE` mode retains the first ARM build, then copies the verified
`@[freed]` annotation for the final builds. `evidence.v --seal STATE` preserves
complete sources/results, checks the preceding bundle, records its typed
inventory and checks full archive restoration. After commit, `--bind STATE
COMMIT` checks paths/bytes; `--cleanup STATE` removes only the private worktree
and verified restore. See [the report](../../docs/m1-agx-queue-records.md).
