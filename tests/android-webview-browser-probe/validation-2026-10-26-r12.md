# Browser diagnostic r12 — 2026-10-26

The r12 credential-free browser replay still fails. With the P_PIDFD kernel
fix, the earlier `waitid(..., pidfd=...)` EINVAL warning is absent. WebKit
reports CRASHED for its web process just after committing the local page;
the JavaScript DOM check subsequently times out. This is neither browser
completion nor evidence of Android WebView integration or Google account login.

The probe and helper diagnostics come from source revision
`223ef9355c0306a69de7084648d990f8b8808023`. UI process 14800 completes the
asynchronous add-cookie operation and requests the local HTML load. The helper
wrapper identifies NetworkProcess PID 63434 and WebProcess PID 45547. The
bounded event log records load values 0 at 1,233 ms and 2 at 1,246 ms, then
process termination value 0 at 1,261 ms. In the exact
[WebKit 2.48.1 header](https://raw.githubusercontent.com/WebKit/WebKit/webkitgtk-2.48.1/Source/WebKit/UIProcess/API/glib/WebKitWebView.h.in),
these mean STARTED, COMMITTED and CRASHED respectively. The termination enum
does not identify the exit signal or fault location. Three `g_close(fd:12)`
EBADF criticals belong to the distinct NetworkProcess. Their relationship to
the later WebProcess crash is unproven. The retained UART has no accompanying
WebProcess fault, assertion or signal record.

The outer command runs from 20:03:35 to 20:04:09 UTC, exits 1 and does not
reach its outer timeout. Its seven descendants report zero cleanup survivors.
The separate authority fixture passes with zero descendants and survivors.
Authenticated X11, wrong-cookie rejection, the known-fault preflight and actual
GLX absence pass. The session uses llvmpipe software rendering. Its sandbox
disablement remains confined to this local credential-free diagnostic; the
production authentication browser and its sandbox requirements are unchanged.

The unchanged strict collector accepts 403 entries, 3,376,546 bytes and 6,595
chunks from the exact UART. Archive SHA-256 is
`7a9e05420e8cf28bfe40a27d98438426ec598a10f5551b0abea11dc2384c864c`.
A fresh strict collection into a second directory also passes; its output is
retained in `browser-r12-quiet-events-collect-recheck.log`. The first collection
has no retained host stdout log; its original archive and import receipt remain
available. No UART salvage or collector relaxation was used.

The guest uses frozen ARM kernel ELF SHA-256
`a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`,
built from baseline `ecbd3964aff243304e16df45271c7de8dee4d2da` with the
retained P_PIDFD patch. The owned runner stops QEMU PID 44997 and records its
absence at 20:09:24 UTC. The later reconcile command refuses to overwrite that
existing disappearance receipt; both command outputs are retained.

Preserve the complete bundles beneath
`/Users/alex/.local/state/vinix/android/`:

| Bundle or receipt | SHA-256 |
| --- | --- |
| `browser-probe-build-2026-10-26-r13/build.json` | `8dd8596888e313d407d3ef868ecf670e806d16b4274c68c85da4e352f0c61c3b` |
| `browser-probe-build-2026-10-26-r13-inventory.json` | `edf73c8cdd90fe5b6d43b4f6bef29fd04e0f8b15759fb5611f7e2db4e1126e87` |
| `browser-events-build-2026-10-26-r1-inventory.json` | `3158167d5918de8fdbab6705602da84ebf852be859206de2e01d114e89df7c9b` |
| `browser-probe-vm-2026-10-26-r12-quiet-events/stage.json` | `0237978f6b3782735ffa66ae1bb7c653a14d86aae427fb559f027f52ccc3be27` |
| `browser-probe-vm-2026-10-26-r12-quiet-events/serial.log` | `caf46eaacf303a1e00fe33e05ecc693ed47be8e89ecc3911593d5f6674f2fbb3` |
| `browser-probe-evidence-2026-10-26-r12-quiet-events/manifest.json` | `d3be8b550da77b51c276d7713e974341ca3c7d35c1c79ba2aefbdcee6b52e2d9` |

The seal covers 29 roots and 6,000 entries, including the stopped VM, both
complete collections, prepared runtime, kernel, authority/recvmsg fixtures,
quiet PID1 and event builds, host tools, their inventories and lifecycle/build
logs. Seal creation's check and a separate full recheck pass. The latter output
is retained as `browser-r12-quiet-events-independent-recheck.log`. This binds
complete deployment evidence, not the recursive historical SDK/compiler closure.
Historical checkers still require the original complete bundles.

The next diagnostic should capture the WebProcess exit status or a fault
context before changing rendering or descriptor behavior. This run establishes
the process failure and its timing, not its cause. Production namespace support
remains a separate prerequisite documented in `namespace-design-2026-10-26.md`.
