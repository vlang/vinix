# G13 firmware context retirement

`v run tests/agx-context-retire/run.v` runs the production context-command builder,
retirement gate, queue teardown, deferred heaps and TX channel with ASan/UBSan,
`-gc none -manualfree`. Set `ASAN_OPTIONS=detect_stack_use_after_return=1` for
fake-stack checking. The timer, doorbell, UAT and physical release are host
services; the fixture does not run GPU firmware.

An independent byte oracle checks all 48 message bytes in 24 cases, including
both firmware ABIs, raw firmware IDs, packed pointers and zero padding. Another
69 cases reject unsupported ABIs, short context storage and missing pointers.
The 3,672 queue/heap/channel cases cover immediate/delayed acknowledgement,
publication followed by failed doorbell, timeout, state/fault transitions,
full/corrupt rings, invalid context inputs and three ring positions. They vary
each heap's captured count, inject later releases and check live pins. Successful
retirement followed by refused UAT cleanup poisons context storage before retry:
the retry must neither read it nor send or collect again. Published failures
remain quarantined even after a late acknowledgement. Stopped teardown and
unpublished initialization bypass the gate; backing releases once.

`AGX_CONTEXT_C` and `AGX_CONTEXT_BINARY` retain artifacts externally.
`--source CONTEXT`, `--wire-source CHANNELS` and `--queue-source G13` select
alternative production inputs. Temporary fixtures are removed before exit.
`counterexamples.v RUNNER BASELINE_QUEUE_SOURCE FRESH_OUTPUT` requires 11 compiled
counterexamples to reach their designated ABI, lifetime or retry assertion;
compiler errors do not qualify.

`check.v --native CURRENT_ARM_C BASELINE_ARM_C` checks stack-only new helpers,
the context-before-UAT gate, one scalar queue field/default and 52 unchanged
heap, backing, cache, queue-owner, channel and stopped-drain bodies. String IDs
resolve by value and numbered temporaries are renamed consistently. `--selftest`
rejects seven publication, count, ABI, gate, allocation and state mutations.
`--allocations CURRENT_LOG BASELINE_LOG` requires identical per-file/per-kind
allocation counts and exactly one added ARM source file. The original strict
x86 whole-C checker and allocation allowances remain unchanged.

`qualify.v --prepare STATE` verifies and reuses the preceding complete bundle's
preparation source, then overlays the three production files in a private
worktree. Its `--refresh` mode preserves the earlier build made before splitting
the helper into its own file. `evidence.v --seal STATE` retains complete sources,
results and diagnostics, verifies the typed inventory and restores the complete
archive. After commit, `--bind STATE COMMIT` checks exact paths and bytes;
`--cleanup STATE` removes only the private worktree and verified restoration.

See [the report](../../docs/m1-agx-context-retire.md) for retained evidence,
conservative published-failure retention and remaining scheduling/parity gaps.
