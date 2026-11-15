# Binary syncobj wait snapshots

Compile `run.v` with V into an external executable, then run it. Set
`DRM_SYNCOBJ_WAIT_TEST_BINARY` to retain the ASan/UBSan executable outside Git.

The runner executes the production create/wait ioctl handlers, syncobj module,
pending-signal reader and request definitions. It injects bounded user copies,
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

These deterministic interleavings do not exercise actual kernel threads, GPU
execution or kernel heap usage. Vinix still limits one wait to 64 handles and
polls through its scheduler; Linux uses dynamically sized sleeping waits and
fence callbacks. Timeline waits and deadline scheduling hints remain separate
work. Deterministic interleavings do not qualify multi-CPU races or syscall
restart after actual userspace signal delivery.
