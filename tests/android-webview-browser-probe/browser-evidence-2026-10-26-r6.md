# Browser diagnostic r6 — 2026-10-26

The AArch64 guest passed the real Unix socket regression with the patched
kernel. WebKit progressed past the earlier unsupported IPC receive, then
failed while initializing EGL. DOM JavaScript, the browser PNG, Google Maps
rendering and Google account login remain unverified.

The run used kernel commit `ee0d3b6ff3d2586a0e5f35a27042643afaa298f3`
and kernel SHA-256
`ac90558eac4f2ea6b74c72c3f519370e98e9f88b0a5384aa82cc386bdd1876ce`.
The browser payload was unchanged from r5: its build receipt SHA-256 is
`bda7cfb62ab530ab5542d91054eab9ecfc0319dde3671550af3fe93d7903c979`.
The browser session ran from 13:14:11 to 13:14:46 UTC with WebKit 2.48.1 and
GTK 4.24.1. Retained receipts and logs show:

- The syscall fixture passed stream, sequenced-packet and datagram cases,
  including payloads, transferred descriptors, close-on-exec, nonblocking
  receives and rejection of an unsupported flag. UART lines 3317–3320 end
  with `UNIX-RECVMSG-FLAGS-PASS all=3`.
- Authenticated X11 accepted the correct cookie and rejected a wrong cookie.
  GLX absence and the deliberate fault-instrumentation preflight passed.
- The earlier `Error receiving IPC message ...: Not supported` did not recur.
  WebKit instead reported an unavailable injected bundle at its compiled-in
  `/usr/lib/webkitgtk-6.0/injected-bundle` path, then
  `Could not create surfaceless EGL display: EGL_NOT_INITIALIZED. Aborting...`.
  The DOM update timed out after 30 seconds and the browser exited 1.
- Temporary WebKit helper aliases were removed, and the pinned original
  loader and `xkbcomp` hashes remained unchanged. The separate authority
  fixture passed without account dispatch.

The WebKit sandbox remained disabled solely for this credential-free local
diagnostic. No credentials were used. The next diagnostic selects the
installed release's Skia CPU path and relocated injected-bundle directory;
these configuration changes require a fresh guest run for validation.

Complete original evidence is retained under
`/Users/alex/.local/state/vinix/android/`. The seal directory
`browser-probe-evidence-2026-10-26-r6-regression` binds eight roots and 5,354
entries. Its `manifest.json` SHA-256 is
`fd61389f92e7a39882d3bc13e346959a8067fc8ae3b8042a6d084296cbd83a0c`.
The strict UART collector restored 378 entries with archive SHA-256
`e741771d73f4775cef0a862b2280e0c77765a5850e95e6c8a928a672dd33c5da`.
The VM's matching stop and disappearance receipts record SIGTERM and confirmed
absence at 13:16:15 UTC. Recheck the full evidence with the retained seal
executable's `check DIRECTORY HASH` command; no raw artifacts are in Git.
