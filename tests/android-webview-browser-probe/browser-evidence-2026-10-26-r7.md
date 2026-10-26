# Browser diagnostic r7 — 2026-10-26

The CPU-renderer diagnostic stopped during its controlled-fault preflight,
before starting WebKit. The child exited zero and its complete retained log
contains every required marker, including the final success line. The parent
read the file before flushing its final buffered writes. The session now
flushes before validating the log; the host self-test exercises this same
buffered-file path and retains all negative context checks. Guest validation
of this fix and CPU rendering remains pending.

The run used source `50bc687fd`, the payload and stage recorded in
`browser-preparation-2026-10-26-r7.md`, and kernel `ee0d3b6ff`.
The Unix receive regression again passed all three socket types. The separate
authority fixture passed. Browser process cleanup recorded two descendants
and zero survivors. No credentials were entered, and no Google login or
browser rendering success is established.

Maps console output interleaved the original UART transfer, which the strict
collector rejected. After stopping that application, the unchanged guest
archive was retransmitted. The maintained `recover-export.v` recovered exactly
264,541 bytes matching the original header's SHA-256
`a8a20d2ec6382adb1dab4861dcabc87d167f24a7aa1f39d52e6934b313f3945b`.
The unchanged strict collector then validated all 355 entries. Recovery
self-tests also reject corrupt, truncated, duplicate-header and duplicate
payload inputs. Original serial bytes and recovery provenance are retained.

The complete seven-root, 5,168-entry evidence bundle is outside Git under
`/Users/alex/.local/state/vinix/android/`. Its seal directory is
`browser-probe-evidence-2026-10-26-r7-cpu`, with manifest SHA-256
`fb5a64ba6c4ec69af486b27edb84d290e5bc38ad7a8cd1326b18bf76f8da978d`.
It includes `browser-probe-vm-2026-10-26-r7-cpu`, the r9 build,
`browser-export-recovery-2026-10-26-r7`, restored results and both kernel/socket
fixture input bundles. Matching stop and disappearance receipts confirm the
owned VM is gone. Recheck the complete bundle with the retained seal tool;
raw results are not tracked.
