# Binary syncobj wait snapshots

Compile `run.v` with V into an external executable, then run it. Set
`DRM_SYNCOBJ_WAIT_TEST_BINARY` to retain the ASan/UBSan executable outside Git.

The runner executes the production create/wait/reset/signal ioctl handlers, common
ioctl registration, syncobj module, pending-signal reader and request definitions.
It injects bounded user copies,
thread/process state, locks, atomics, monotonic time and scheduler steps.
Repeated scenarios check empty/signaled
creation, upfront validation, stable fence and handle snapshots, submission
capture, destroy/reuse, timeout/flag behavior and WAIT_ANY/ALL completion.
Registered empty waits preserve the first publication even across immediate
clearing/replacement before the next scheduler step. Private/shared signals
and thread exit interrupt pending waits; masked signals do not. Readiness and
timeout retain their precedence over interruption.
Fixture-only cleanup follows all synchronous callers and scripted actions.

Capture primitive checks cover multiple simultaneous registrations, intrusive
middle/head/tail removal, nil publication, duplicate registration, idempotent
cleanup and exact-lock publication/cancellation interleavings. The ioctl tests
check that no registrations survive validation failure, completion, timeout or
interruption, including publication after the ioctl has returned.

Large-wait cases cover the inline boundary at 64 handles, owned buffers for
65..4096 handles and a ready index of 4095. Geometry probes check aligned,
non-overlapping regions, wide counts and overflow. The allocator starts memory
with nonzero bytes, injects failures and tracks live buffers/bytes. Before each
free, a hook checks that no pending capture points into that allocation.
Every large request must return all owned bytes, including copy/lookup/prepare
errors, timeout and interruption. Huge requests use a fixture-only allocation
ceiling to test ENOMEM without exhausting the host.

Reset cases check the exact 16-byte request and ioctl encoding, zero-count/pad
rejection, one copied handle snapshot and complete lookup before effects.
Counts 1..4096 include duplicate handles, allocation/copy/namespace failures,
and handle destruction/reuse between lookup and replacement. Binary replacement
clears timeline lookup membership while previously captured fences remain valid.
Pending publication registrations survive a nil reset, capture the first later
fence and retain it across another reset. Every allocated reset owner is freed;
reset does not signal the old GPU fence or allocate wait capture nodes.

SIGNAL cases execute the production handler and private completion allocator.
They check fresh context/sequence-zero successes and timestamps for duplicate
handles, all identities before effects, sequential prefix preservation on OOM,
inline/owned failure cleanup and stable old GPU/timeline/first-publication
captures across replacement and handle reuse. The injected allocator counts
retained fence bytes separately from temporary request storage. Fixture-only
retirement frees those completions after all users and objects are gone;
production still retains published fence metadata. Ordinary first completion
timestamps survive later success/error attempts. Signaled CREATE still uses
its existing allocation path; its fallibility is separate work.

These deterministic interleavings do not exercise actual kernel threads, GPU
execution or kernel heap usage. Vinix still polls through its scheduler; Linux
uses sleeping waits and fence callbacks. Timeline waits and deadline scheduling
hints remain separate work. These tests do not qualify multi-CPU races or
syscall restart after actual userspace signal delivery.
