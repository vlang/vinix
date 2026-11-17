# Fake AGX fence contexts

Fake render workers can finish in any order, including on one queue. A shared
context incorrectly promises ordered retirement and lets fence merging drop a
pending job. Production `fake/fence.v` reserves an independent context for each
submission, with sequence 1 and no queue-dependency elision. Exhaustion returns
before fence allocation; submit unwinds any acquired VM/file pins before output
publication. Published metadata retention is unchanged.

Run without a GPU or guest:

```sh
v run tests/agx-fake-fences/run.v host /external/fresh-host
v run tests/agx-fake-fences/run.v negative /external/fresh-negatives
```

The maintained DRM host runner includes the production fake constructor and
workqueue implementation. It tests all 24 retirement orders of four jobs on one
or four queues, preserving all dependencies and propagating an error. It checks
nonzero unique contexts, the last usable context, 1,000 exhausted reservations
and absence of same-queue dependency elision. Sixteen transaction cases execute
the production admission/pin/constructor/publication block with modeled VM/file
plumbing and a borrowed output array (only its address expression is adapted).
They check busy-error precedence, saturation, exact rollback, unlock and unchanged
outputs. The complete DRM suite runs afterward under ASan/UBSan and `-manualfree`.
Four compiled mutants must fail designated assertions: shared contexts,
zero-context fallback, dependency elision and omitted VM-pin unwind.

Native checks use an isolated worktree pinned at
`0d7a4df5b598242f4f6bbb77a914426459054714` plus only `fake/driver.v` and
`fake/fence.v`. Create `/external/state` before preparation:

```sh
v run tests/agx-fake-fences/native.v prepare /external/state
v run tests/agx-fake-fences/native.v aarch64 /external/state
v run tests/agx-fake-fences/native.v x86_64 /external/state
v run tests/agx-fake-fences/native.v contracts /external/state
v run tests/agx-fake-fences/native.v allocations /external/state
v run tests/agx-fake-fences/check.v /external/prior-complete-bundle /external/state
```

Build the architectures sequentially. Allocation diagnostics deliberately expect
the existing allowance failure; the evidence validator also requires every
file/kind count to match the preceding bundle. The ARM checker verifies no hidden
helper allocations, pre-publication unwind and unchanged admission/work,
completion, close and queue bodies. Ten shared DRM bodies match the baseline on
ARM and nine on x86, where the fake backend and generic constructor are pruned.
Normalization covers only generated temporary variable numbers. These checks
qualify neither successful-publication reclamation nor native slab retention.

`evidence.v validate|seal|bind|cleanup STATE [COMMIT]` retains source, baseline
tests, full contracts, generated C/ELFs, sanitized binaries, mutants and lifetime
review outside Git. Seal requires a complete preceding bundle, checks archive
restoration and both complete named roots, and bind verifies committed feature
bytes after commit. Cleanup removes only this task's pinned build worktree after
binding; evidence and the restored archive remain intact.

This correction makes dependency merging safe for the fake backend's independent
workers. It does not reproduce Asahi's scheduler or qualify full M1 driver parity.
