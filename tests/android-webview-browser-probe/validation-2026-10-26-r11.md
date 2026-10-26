# Browser diagnostic r11 — 2026-10-26

The quiet r11 replay exported its complete credential-free diagnostic archive,
but the real WebKit probe failed: its JavaScript DOM update timed out after
30 seconds. The outer guest command did not time out. This run does not prove
browser completion, Android WebView integration or Google account login.

The unchanged strict collector accepted 403 entries, 3,376,206 bytes and
6,595 chunks, with archive SHA-256
`c1e0c1025fe9051d3b070026beab6819c15d977c1b427fdd2e881769a0c852b5`.
Unlike r10, the exact UART required no edits or salvage. The diagnostic PID1
from `45ad8f3f2` starts Terminal while suppressing unrelated Maps/GMS autolaunch;
the stage from `873f41e19` preserves the original boot modules and records the
init definitions it overrides. This is a separate diagnostic boot path.

`results/browser/session.json` records authenticated X11, wrong-cookie rejection,
the known-fault preflight and actual GLX absence as passing. Software rendering
selected llvmpipe with `LIBGL_ALWAYS_SOFTWARE=1`; the prepared runtime includes
`76a8df84f`. The complete bounded `probe.log` contains no EGL initialization
failure. The probe passed its asynchronous add-cookie step and called the local
HTML load API, but reached neither the expected DOM title nor the missing-cookie title
before its deadline. Load lifecycle and web-process termination signals were
not recorded, so the timeout's immediate cause remains unresolved.

The log instead records three `g_close(fd:22)` EBADF criticals in process 9635,
and `waitid(pid:21435, pidfd=34)` EINVAL in UI process 31289. The retained kernel
source implements `pidfd_open` but accepts only P_ALL, P_PID and P_PGID in
`syscall_waitid`; P_PIDFD is rejected with EINVAL. That is a definite
compatibility gap consistent with this warning. Its contribution to the DOM
timeout and the EBADF errors is unproven. The isolated authority fixture passed.
The browser command's seven descendants and the authority command's zero
descendants both report zero cleanup survivors.

The guest ran from 18:46:54 to 18:47:39 UTC on frozen kernel revision
`577a2d8c29ba6d4a95a655d507ef38414d3b8c77`, binary SHA-256
`ee6aa1acb31f11b8abf16c4001149ccb92e8f8fe35d0106342bbdbad6e7e57fd`.
Both the initial stop attempt's ownership refusal and the later reconciled
owned stop are preserved. The latter requested SIGTERM for PID 59623 at
18:54:20 UTC; its matching absence receipt records disappearance at 18:54:27.
The VM used the native-SHA runner from `222f80c93`; the earlier kernel patch
tool remains pinned separately in its own receipt.

Preserve the complete bundles under
`/Users/alex/.local/state/vinix/android/`:

| Bundle or receipt | SHA-256 |
| --- | --- |
| `browser-probe-build-2026-10-26-r12/build.json` | `33d92e97c5621d092b195551a1c3689b4bfdc5290697495b66a660265593a271` |
| `browser-boot-build-2026-10-26-r1/build.json` | `54047c711491500353c15bada86512998281e88ce4550f588bf0de3ba0f744d0` |
| `browser-probe-vm-2026-10-26-r11-quiet/stage.json` | `e74e7102230cd4da4720443dc09889ca002eced78f1c5a2a83ed57dbb705e56f` |
| `browser-probe-vm-2026-10-26-r11-quiet/serial.log` | `47ed40bafcf444f1fdbc9f9f000b57bd6f196607529df4d10b99f6239f4d423f` |
| `maps-account-collect-r2` | `f1245b715d75ab41a6f1c8b3c0d45e1aed9158bfe3cd097c939ee845a3b1b29e` |
| `browser-probe-evidence-2026-10-26-r11-quiet/manifest.json` | `bc9d8c028db7f84e611e22c93b4db35a5ef83d3e3cbf0da1790db0ef414d04f3` |

The seal binds 17 roots and 5,580 entries: the original VM, complete collection,
prepared r12 runtime, frozen kernel bundle, authority and recvmsg fixtures,
quiet PID1 build, both optimized host-tool bundles and their sibling inventories,
the strict collector executable, all four host lifecycle/collection logs and
the seal itself. Seal creation's check and the separate full recheck passed;
their logs are retained beside the seal directory. This binds the complete
deployment evidence, not the recursive historical compiler/SDK rebuild closure.
Historical checkers still require every original complete bundle.
