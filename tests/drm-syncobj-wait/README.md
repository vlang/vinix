# Binary syncobj wait snapshots

Compile `run.v` with V into an external executable, then run it. Set
`DRM_SYNCOBJ_WAIT_TEST_BINARY` to retain the ASan/UBSan executable outside Git.

The runner executes the production create/wait ioctl handlers, syncobj module
and request definitions. It injects bounded user copies, locks, atomics,
monotonic time and scheduler steps. Repeated scenarios check empty/signaled
creation, upfront validation, stable fence and handle snapshots, submission
capture, destroy/reuse, timeout/flag behavior and WAIT_ANY/ALL completion.
Fixture-only cleanup follows all synchronous callers and scripted actions.

These deterministic interleavings do not exercise actual kernel threads, GPU
execution or kernel heap usage. Vinix still limits one wait to 64 handles and
polls through its scheduler; Linux uses dynamically sized, interruptible waits
and fence callbacks. Polling an empty object can miss a fence replaced between
polls; a captured fence stays stable. Timeline waits and deadline scheduling
hints remain separate work.
