# Browser diagnostic r13 — 2026-10-26

The r13 credential-free browser replay still fails. Its native child-status
record identifies SIGABRT termination of WebKitWebProcess PID 19893. The run
does not establish the abort's origin, browser completion, Android WebView
integration or Google account login.

The diagnostic implementation is committed as
`dae438571` ([implementation checks](validation-2026-10-27-waitid.md)). The
prepared r16 bundle freezes those sources over base revision
`1c6a46a51dcb1b342c3d6aaea4f0f532a28e6adc`. The pinned, no-builtin interposer
observes the UI process's existing waits; helpers do not load it. Exactly one
populated status appears:

```text
BROWSER-WAITID idtype=3 id=26 options=5 pid=19893 code=2 status=6
```

Retained AArch64 musl headers define P_PIDFD=3, WEXITED=4, WNOHANG=1,
CLD_KILLED=2 and SIGABRT=6. Thus the existing nonblocking wait on descriptor 26
reports SIGABRT for the verified WebProcess child. The frozen deployed kernel
maps signaled exits to CLD_KILLED and keeps the core bit clear; this record
does not distinguish different origins of that signal or establish that libc's
`abort()` was called.

UI process 37023 completes add-cookie and requests the local HTML load. The
bounded WebKit events record STARTED at 2,339 ms, COMMITTED at 2,360 ms and
CRASHED at 2,398 ms. The wait record follows them in the log but has no own
timestamp. Three `g_close(fd:14)` EBADF criticals belong to NetworkProcess
58261 before the local load request. Their relationship to the later
WebProcess termination remains unproven. The DOM check times out after 30
seconds; the outer command exits 1 without reaching its outer timeout.

The retained UART has no accompanying exception dump, syscall-ring dump,
assertion or fatal-signal context. Inspection of the exact frozen kernel finds
several SIGABRT paths, including signal delivery, syscall-origin rejection,
pledge violations and an undefined-instruction exception. The exception path
would print fault context and the 64-entry syscall ring; their absence does
not identify which other path ran. Fatal status encoding explicitly provides
no core dump, so changing a core-size limit alone cannot recover the missing
caller. A separate, bounded WebProcess-only abort-call diagnostic is the next
narrow probe; direct syscalls, hidden libc calls and kernel fatal paths would
remain outside an exported `abort()` interposer's coverage.

The browser command runs from 21:19:48 to 21:20:22 UTC. Its eight descendants
have zero cleanup survivors. The authority fixture passes with zero
descendants and survivors. Authenticated X11, wrong-cookie rejection,
known-fault preflight and actual GLX absence pass. Rendering uses llvmpipe;
sandbox disablement remains confined to this credential-free local probe.
Production authentication and its namespace requirements are unchanged.

The initial strict collection refuses a UART that changed size while being
read; its failure output is retained as
`browser-r13-quiet-waitid-collect.log`. After archive completion and the owned
VM stop, strict collection passes with 403 entries, 3,377,314 bytes and 6,597
chunks. Archive SHA-256 is
`01e0944de505682fcae53a13f85f0bf1861bd981c1685d523f7cff2a6dfec6f1`.
A separately compiled, unchanged collector from frozen r16 source accepts the
same UART into a fresh directory with the same archive hash. Its build exits
zero with empty output; no separate compiler stdout log was retained. Both
collections and the replay stdout are preserved; no salvage or relaxed
collector was used.

The qualified P_PIDFD kernel replacement is the same ARM ELF used in r12,
SHA-256 `a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`.
The runner records SIGTERM for owned QEMU PID 87644 and its absence at
21:25:17 UTC.

Preserve the complete bundles beneath
`/Users/alex/.local/state/vinix/android/`:

| Bundle or receipt | SHA-256 |
| --- | --- |
| `browser-probe-build-2026-10-26-r16-waitid/build.json` | `5a11abcd134f2eb4f83d2adb131fad01e8bddf56be601e1d4809c65737e2c4fb` |
| `browser-probe-build-2026-10-26-r16-waitid.inventory.json` | `66afe6e6bc17a012acf7efadc326dfe2ff52eebbb6833e58a67d58dd8afe3763` |
| `browser-probe-vm-2026-10-26-r13-quiet-waitid/stage.json` | `6a4d5c9f0125652de62595b87edaf5d63750006143d73847e25ac86624fc5d3d` |
| `browser-probe-vm-2026-10-26-r13-quiet-waitid/serial.log` | `2399003655a576589fbe3d6198894576586cc81681af820402c6c291ef6dd139` |
| `browser-probe-evidence-2026-10-26-r13-quiet-waitid/manifest.json` | `e441db6a38048b330918e8935f3ee2abde7acd3dc643d1228ea257a297556de2` |

The in-place seal binds 29 roots and 6,040 entries: the stopped VM, both
complete collections, prepared r16 and its inventory, waitid build and test
artifacts, quiet PID1, authority/recvmsg/event/kernel builds, host tools and
their inventories, lifecycle and collection logs, and the exact status
headers with their source-path receipt. Seal creation's full check and an
independent full recheck pass. The latter stdout is retained as
`browser-r13-quiet-waitid-independent-recheck.log`. The seal binds complete
deployment evidence, not the recursive historical SDK/compiler closure.

Historical checkers continue to require the original complete bundles. The
complete r12 evidence remains unchanged. Production namespace support remains
a separate prerequisite documented in
[the namespace design](namespace-design-2026-10-26.md).
