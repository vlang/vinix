# xHCI halted input endpoint recovery

Run `v run tests/xhci-recovery/run.v` (or set `V` to the compiler path).
The V launcher compiles production `recovery.v`, actual driver types,
ring publication, event decoding, EP0 control submission and per-function key
release with fake MMIO, command/transfer waits
and a report sink. The fixture checks single-TD ownership, short reports,
deferred recovery, command ordering, dequeue address/cycle at Link wrap,
USB STALL halt clearing, failure gates, stale events, and other endpoints
completing or failing during waits. It also checks 40 full ring wraps (both
outgoing cycles), permanent-disable key release and repeat ownership, retained
enumeration EP0 failure blocking later submission, and stopping recovery after
the current command. The launcher respects nonempty `TMPDIR`. It neither boots nor contacts a VM.

This is a synthetic regression fixture for the demonstrated halted-endpoint
gap. It does not reproduce the reported roughly 20-minute input loss or
establish its cause. Kernel architecture builds and hardware/guest input
testing remain separate integration checks.
