# Browser diagnostic r5 — 2026-10-26

The credential-free WebKit diagnostic reached authenticated Xvfb setup, then
failed its JavaScript DOM update after 30 seconds. Google Maps rendering,
screenshots, cookies and Google account login remain unverified.

The run used build base revision `b81dd5c8c702b278f3e57fe7143804c5a570bea9`
and build receipt SHA-256
`bda7cfb62ab530ab5542d91054eab9ecfc0319dde3671550af3fe93d7903c979`.
It ran from 12:00:04 to 12:00:36 UTC with WebKit 2.48.1 and GTK 4.24.1.
Retained `session.json` and logs record:

- Authenticated X11 accepted the correct cookie and rejected a wrong cookie.
  The authenticated GLX extension absence check passed for the CPU diagnostic.
- The deliberate known-fault preflight passed, preserving handler queries,
  restoration and chaining. This validates the fault instrumentation.
- WebKit reported `Error receiving IPC message ...: Not supported`, followed by
  `JavaScript DOM update timed out after 30 seconds`; the browser exited 1.
  The supervisor observed eight descendants and zero cleanup survivors.
- The separate account-authority fixture passed its launch, ownership, digest,
  Unix peer and forged-identity checks, with no account dispatch.

The WebKit sandbox was disabled for this local diagnostic. These checks do not
qualify a browser for credentials or establish Android integration.

Kernel commit `ee0d3b6ff` subsequently permits inert `MSG_NOSIGNAL` alongside
`MSG_CMSG_CLOEXEC` on Unix receives. Its extracted production-mask check passed
124 cases, the previous mask failed the negative control, and the AArch64
syscall fixture compiled. Guest syscall regression and the browser retest are
pending; the IPC failure's resolution has not been demonstrated.
These kernel check artifacts are retained separately in
`/Users/alex/.local/state/vinix/android/unix-recvmsg-flags-build-2026-10-26-r2`.

The complete original evidence remains under
`/Users/alex/.local/state/vinix/android/`. The seal directory
`browser-probe-evidence-2026-10-26-r5` binds eight roots and 1,147 entries,
including the VM, results, build and host-check trees. Its `manifest.json`
SHA-256 is
`e5ce5a67898429a0bbab34069adbf20762dd0c7fa47b1cae68eb021fbd12dacf`.
Recheck it with the retained `seal` executable's `check DIRECTORY HASH` command.
The imported UART archive contains 369 entries and has SHA-256
`3d235296598df97377b8cdce0984780a433856aedd92297d4dfaa10cb8105e3d`.
No raw evidence was copied into Git.
