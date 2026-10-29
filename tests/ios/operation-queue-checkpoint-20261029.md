# Operation queue executor prerequisite — 2026-10-29

Implementation and fixture source: `ebf40d77f`. NSOperationQueue now executes
copied blocks through an owned serial dispatch executor, with operation count,
idempotent suspension and waiting. Internal framework work can use the same
executor with a context cleanup callback. Each queued job keeps its queue and
captures alive; shutdown discards pending work and releases its ownership.
Capture destructors run outside the counter and scheduler locks. Sidecar
cleanup follows allocation ownership after an isa replacement.

Execution is serialized for this profile, including when the configured upper
bound permits more concurrency. Dependencies, priorities, NSOperation object
submission, and public `mainQueue`/`currentQueue` remain unsupported. Internal
callback queue identity is available to framework delivery code. This does not
implement NSURLSession task scheduling, response decisions, cancellation or
network callbacks. **Fortnite's last observed blocker remains
`-[NSURLSessionDataTask resume]`.**

Normal and deterministic ASan/UBSan host checks pass, including a native
Foundation comparison. Existing configured-session and task-delegate host
regressions also pass both sanitized runs. The fresh standalone ARM64 Vinix
guest fixture exits with wait status zero and `VINIX iOS OPERATIONQUEUE: PASS`.
Coverage includes 64 copied blocks, serial worker identity, eight producers
submitting 128 contexts, reentrant capture destruction, suspension/count/wait,
saved IMPs and selector scope, caller release during work, weak references,
isa replacement, and 32 discarded jobs per runtime lifetime. Two lifetimes
finish with zero live Objective-C objects and owned heap blocks. LeakSanitizer
is disabled; these counters do not prove absence of all leaks.

A persistent archive preserves the complete successful host, regression and
guest trees, including generated sources, binaries, boot media and logs. Fresh
extraction passes full byte/type/permission comparisons for all four trees.
Earlier failed test attempts are retained separately and are not qualification
evidence. The native test drains the submitting autorelease pool before
requiring capture retirement; native completed operations may retain their
captures until that pool drains.

```text
Cache: /Users/alex/Library/Caches/vinix-ios
Host root: /Volumes/VinixStoreKitObservers20261028
Host: operation-queue-host-20261029-r5
Regressions: operation-queue-session-regression-20261029
             operation-queue-delegate-regression-20261029
Guest: /Volumes/VinixStoreKitQueue20261028/operation-queue-guest-20261029-r1
Guest VM: operation-queue-31325401625 (4096 MiB, four virtual CPUs)
Archive: CACHE/operation-queue-evidence-20261029.tar.gz (106 MiB)
Archive SHA-256:
4e2236bfdec84f0cfd2d09f55523cebdc8fd3a29963dc840844555c5fc16de54
Guest fixture SHA-256:
260b71edfb8eb2352e1210df3750a9785464a52d3aa098f8ac7235db4fe28394
Guest serial SHA-256:
8997cbecf9b6370de5fbb8619d2c9d7121249686322a384ab995692ef392ebae
Host log SHA-256:
62893219d66e71a60a92d4337152c029485b05bc20d5a6a2275f1d75310d49df
Source: CACHE/audio-category-20261027-work/operation-queue-source-ebf40d77f.tar
Source archive SHA-256:
aff0a674b5e55faeb94117e84856d935817e1f3de8d6e92ee1ef0de94f04115b
Restored: /Volumes/VinixStoreKitQueue20261028/operation-queue-restored-20261029
Receipts: CACHE/audio-category-20261027-work/operation-queue-*.log
```

Reproduce with frozen `notification-checks operation-queue-host FRESH_HOST`;
run the guest with `notification-vm operation-queue FRESH_GUEST` under the
existing check-name/toolchain environment. The guest driver builds its fixture
and native init, selects and records the kernel, then stages and boots the VM.

This standalone check does not advance the game launch count. Progress remains
**4/8 observed gates**, with no verified frame, menu, login or playable match.
Earlier evidence is in the [task-delegate checkpoint](session-task-delegate-checkpoint-20261029.md)
and [HTTP transport checkpoint](http-transport-checkpoint-20261029.md).
