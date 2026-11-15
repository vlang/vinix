Compile `run.v` to an external executable and run it with `--sanitize` from
the repository root. Set `V_C_ERROR_BUG_REPORT_DISABLED=1`, `V` to select the
compiler, and `AGX_G13_TEST_BINARY` to retain the host executable outside Git.

The V runner copies the production channel implementation and extracts the
production compute/render publishers, retirement, recovery, event handler, health check, worker and
shutdown functions into a temporary host build. It uses the real firmware
layouts. The fixture replaces
privileged locks, atomics, MMIO and manager hardware services; it executes no
GPU commands. Address/undefined-behavior sanitizers check malformed indices
against small actual buffers. The fixture records shutdown service order and
rejects recursive lock acquisition.

The tests cover both supported firmware ABIs, corrupt and wrapped ring
pointers, sticky errors, firmware-control pointer placement, log subchannels,
fatal-event drain termination, halt without a notification, and stopping
firmware before failing pending work. Malformed inner/outer submission indices
must leave all command buffers untouched and release every reserved lock;
successful submissions require barriers at both publication stages. Success
paths still reap normally.

The recovery fixtures also cover both pending-stamp encodings, the final
pending-array entry, fault versus killed attribution, completed-work preservation,
fault diagnostics, channel recovery commands and acknowledgments, a missing
halt acknowledgment, and wakeup error codes. A queued error reaches its recovery
handler before the worker treats the halt as unreported. Recovery never releases
job backing: the normal completion stamps still govern retirement and teardown.
Workqueue free pointers retain monotonic logical ordering across ring wrap and
reverse reaper traversal. TVB growth acknowledgments carry the halt counter.

The production TVB feedback policy is also executed with allocation replaced by
a recorded request. Tests cover the exact no-growth threshold, rounded 3x
headroom, resetting firmware statistics, the non-memoryless cap, maximum raw
page-count arithmetic and allocation failure. They do not exercise real TVB
allocation or GPU page consumption.

Source-bound Apple instruction checks live in `tools/agx-re/g13failure`;
`g13contract` independently checks the older FWStatus wire layout against
m1n1. A native test pass on macOS does not validate Vinix firmware execution.

Prefix tests cover one or two firmware barriers before compute and vertex
commands, wrapped rings, exact/insufficient capacity, outer-ring refusal,
unready setup and retry, conditional TVB binding and retirement sequences.
Invalid counts must be rejected before any ring write. Compute prefixes use
fixed three-entry storage; notifications are assigned directly into the rings.

Compile `check-prefix-storage.v` to an external executable. Its `--selftest`
rejects hidden allocation calls, missing/duplicate helper definitions and lost
stack storage. Passing an isolated ARM `kernel/obj/blob.c` checks twenty-two production
helpers, including initial capture/selection/compaction, registration, publishers
and the host ring admission, scheduler/input dependency scan and private fence provenance check.
It rejects temporary allocations and structural queue copies.
Fixed stack arrays are required for publication, queue gates, acceptance and
resolution. This catches
V moving an addressed local into a `memdup` allocation under `-gc none`. It does
not measure the whole kernel or qualify native GPU execution.

Host ring admission executes the production capacity helper at 5,120 boundaries,
then drives the actual compute and paired render publishers with firmware rings
consumed but host retirement withheld. Exact remaining capacity is refused to
preserve Asahi's spare entry. One host retirement permits atomic retry, including
wrapped zero/one/two-prefix commands with and without TVB binding. Corrupt and overflowing logical counters fail
before any publication; these tests introduce no new allocation or freeing path.
