# Cancellation before data-task resume — 2026-10-29

Implementation and captured source: `f7309fc71`.

Session-created data tasks now implement `cancel` before their first resume.
One owned operation delivers `URLSession:task:didCompleteWithError:` on the
session's delegate queue. It publishes completed state (3) and an
`NSURLErrorDomain` error with code -999 before invoking application code.
Repeated, concurrent and reentrant cancellation cannot enqueue another
completion. Per-selector lookup prefers the task delegate, falling back to
the session delegate. The task delegate remains visible during the callback
and is cleared afterward, matching the native comparison and breaking a
delegate-to-task ownership cycle.

The queued operation pins the task, its session, queue and error independently
of the submitting autorelease pool. Result getters retain/autorelease their
objects, including the native error field at offset 240. Queue shutdown
discards pending completions without delivering callbacks, publishes their
terminal result and releases their references. Destructing pending storage or
shutting the runtime down from a task callback fails explicitly before unsafe
retirement or worker joins. Unconfigured public base records still reject
cancellation; they are not usable session-created transfers.

Final validation passes:

- Shared native Foundation/runtime cases: session delegate, task delegate,
  per-selector fallback, eight concurrent callers (256 cancellations),
  delegate replacement while queued, one completion, queue/thread identity,
  completed state, error domain/code and delegate clearing.
- Normal and deterministic ASan/UBSan runs, including nil URLs, default
  delegate queues, direct typed IMP invocation, error getter lifetime,
  reentrant constructors/callbacks, task isa replacement, ownership-cycle
  retirement, 32 suspended jobs discarded at shutdown and two clean runtime
  lifetimes. Both lifetime rejection controls pass. LeakSanitizer is disabled.
- Fresh ARM64 Vinix guest: the same runtime cases and rejection controls pass;
  child wait status zero, 4096 MiB RAM and four virtual CPUs.
- Both existing base-task and session-created-task regression suites pass
  their normal and deterministic sanitizer runs with the final implementation.
- Complete ARM64 GLES runtime cross-build passes.

Foundation may supply distinct NSError objects to the callback and task
getter; the shared test compares their domain/code rather than pointer
identity. These fixtures never resume a task or exercise an Epic endpoint.

The complete five evidence trees, driver receipts and source snapshot are
preserved in a persistent 116 MiB archive. Fresh extraction passes all five
complete byte/type/permission comparisons using the maintained V evidence
tool. Original trees and historical Fortnite bundles remain intact.

```text
CACHE: /Users/alex/Library/Caches/vinix-ios
DRAM: /Volumes/VinixTaskDelegate20261029
QRAM: /Volumes/VinixStoreKitQueue20261028
Host: DRAM/session-cancel-20261029-r7
Base regression: QRAM/session-cancel-base-task-regression-20261029-r2
Data-task regression: QRAM/session-cancel-data-task-regression-20261029-r2
Guest: QRAM/session-cancel-guest-20261029-r2
VM: session-cancel-46429278833
Runtime: QRAM/session-cancel-runtime-20261029-r1
Archive: CACHE/session-cancel-evidence-20261029.tar.gz
Archive SHA-256:
4cb76be59b75a67976bb54723fcbd1d7e83efb2f41be21b865942d1708342252
Guest source.tar SHA-256:
47e3703a8ee5356f3bf8dba37a4548bb7da4342f1891f4db2d3c7d9b64849e08
Guest fixture SHA-256:
2d1de8a0fd5bae2148ba7622b232a416841a4b8c58f03da098f3014ddd0ed5ff
Guest serial SHA-256:
2f5de8065fb3fb2e12648a5cdbf51d164cde56c2fcbc04eb688770ab3e3ac905
Runtime SHA-256:
ea4741af6759233192d9c5d8e03983816f4f6c5241cc24a4bdaf2b5695d413ea
Restored: QRAM/session-cancel-restored-20261029
Receipts: CACHE/audio-category-20261027-work/session-cancel-*.log
```

Reproduce with frozen V 0.5.2 (`c6bb06f`) and maintained
`notification-checks session-cancel-host FRESH_HOST`,
`notification-vm session-cancel FRESH_GUEST`, and
`notification-vm build-run-ios-gles FRESH_RUNTIME`. Use the recorded
check-name/toolchain environment and kernel selection from the driver logs.

Fortnite's last verified boundary remains `-[NSURLSessionDataTask resume]`
from the [task-delegate checkpoint](session-task-delegate-checkpoint-20261029.md).
`resume`, active transfers and suspension still fail explicitly. This change
adds the cancellation/completion ownership path; it does not connect the
HTTP/TLS transport to session tasks. No fresh game launch is claimed. Progress
remains **4/8 observed gates (50% of the checklist, not of remaining effort)**:
loading/binding, `+load`, initialization and entry. No frame, menu, login or
match is verified; no reliable ETA follows from that fraction. Advertising
remains skipped in the recorded game probe. Next is the network worker and
response-decision lifecycle needed for real `resume`.
