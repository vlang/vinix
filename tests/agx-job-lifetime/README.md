Compile `run.v` with V to an external executable, then run it with
`V_C_ERROR_BUG_REPORT_DISABLED=1`.
Set `AGX_LIFETIME_TEST_BINARY` to retain the executable outside Git.

The V runner extracts the production job records, backing-release helpers,
public discard methods, completion callbacks, reapers and firmware-stopped
cleanup. It uses the real event manager. UAT invalidation, driver allocations,
ring retirement and shared-buffer backing are injected host services.

Published-job tests exercise 64 commands and 127 prepared commands per subqueue
using the production event manager and reapers. At the latter boundary, only
126 publish initially; the 127th remains prepared until a real host retirement
opens capacity, then resumes. Reverse traversal must retire all
compute jobs and paired render scenes; vertex-only completion retains every
render scene until its fragment stamp advances. These include multiple batches'
worth of live jobs without executing a GPU.

Scene tests execute the production TVB lease and GrowTVB owner selector.
They cover pool exhaustion, overlapping completion, final-owner release,
unchanged and displaced slot hints, oldest-free selection, canceled first bindings, and stale or
mismatched growth ownership. The firmware GrowTVB ACK transport itself is
covered separately by the failure fixture; these checks execute no GPU work.

Sanitizer checks cover caller-owned prepared jobs, cancellation failure and
retry, per-job retirement on a shared stamp, callback ownership and shutdown.
The event fixture separately covers publication order, cancellation rollback,
the separate preparation/publication windows and physical-slot reuse. Neither fixture executes a GPU.

TPC tests use the production cache allocator/reference helpers and render-buffer
cleanup with kernel allocator semantics (`-gc none`). They cover 500 same-size
reuses, UAT page rounding, growth while older scenes retain backing, last-owner
invalidation, metadata/GPU allocation failure, failed invalidation and retry,
stopped firmware, and zero retained cache metadata after teardown. Queue cleanup
also runs the real public release method to verify quarantine permits teardown
retry without permitting new submissions.

Barrier tests execute the production setters and job cleanup with the real
event manager. An independent byte oracle and canaries verify the records stay
after the logical command/microsequence, with both type fields at their reference
offsets. Four hundred eighty cycles cover real producer/consumer reaping, duplicate
physical pins, partial setup, failed flush, quarantine retry and stopped cleanup,
including consumer callbacks before producer callbacks after both stamps advance;
each returns all 128 physical slots. The separate event fixture checks 1,000
producer-owner/pin/reuse cycles and overflow/invalid-slot guards. These checks
measure event ownership and injected backing, without native GPU execution.

Initial-event tests run production acceptance/capture/resolve/release paths and
the real event manager. They cover 140 lifecycle cycles, byte-exact fallback
after canceled-target ABA, idle/retired sources, atomic rejection of an invalid
vertex ticket, distinct queues with equal contents, partial capture overflow,
unused pipes and snapshot release after the owning manager's event reset.
Two-source tests omit the first record, wait for the second, compact to one
record while retaining two pins, and preserve both through flush retry and
quarantine. All 128 physical slots return after cleanup.

Batch admission runs the production preflight, ring helper and event windows.
With 63 older publications and 64 prepared commands on the same pipe, no new
command is admitted until an actual host reaper returns capacity. Raw GPU
progress is insufficient. Mixed-batch tests check strict ring equality on all
three pipes, zero/one/two prefixes, initial-prefix compaction and flush retry,
TVB first binding and growth without changing live binding state, physical queue
identity, invalid tickets and corrupt logical counters. Ownership and all 128
physical slots return through the real cleanup paths.
Canceled-predecessor tests admit two events after 125 stamp gaps on both compute
and render, then publish and reap both without an intermediate retirement. An
unused grant is cleared on canceled-ticket reuse; ordinary publication retains
the strict single-event spare check.

Native batch publication executes the actual manager method with real channels,
ring buffers, events and reapers; wake, MMIO notification and UAT services are
injected. Seventy-five transactions cover compute/render/mixed batches of
1/2/63/64 jobs, wrapped inner/outer rings and signed/zero stamp boundaries,
canceled stamp gaps, a byte oracle for every prefix and TVB binding, one available
notification slot per pipe, and notifier/pending counter accounting. Every late
preparation refusal leaves all rings, pointers and accounting unchanged, including
an omitted unpublished middle ticket and a malformed workpipe write offset.
Capacity retry succeeds intact; failed wake restores pending accounting. Doorbell
failure after visibility returns the entire ownership mask and retains backing
through error quarantine until injected firmware stop. Every final event slot
returns. Native batches never return the partial masks injected by async tests.

Prepared-backlog checks create 512 actual compute or render job records before
publication. Eight native 64-command batches remain bound by hardware event
credit and host retirement. Initial captures span all blocks; failed invalidation
retains ticket/block ownership until quarantine retry. Stopped cleanup distinguishes
manager-owned published metadata from caller-owned prepared records, and a partial
render preparation fails its second overflow allocation after vertex succeeds.
Every overflow allocation and physical stamp returns through production cleanup.
