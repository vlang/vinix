# Browser diagnostic r8 — 2026-10-26

The real WebKit process still fails before the local document's JavaScript
updates its DOM. The controlled-fault preflight now passes, confirming the
buffered-log fix from `6cfad7f38` in this guest. WebKit starts with the pinned
injected bundle and CPU rendering settings, then aborts with
`Could not create surfaceless EGL display: EGL_NOT_INITIALIZED. Aborting...`.
The probe reports its 30-second DOM timeout. Rendering and Google login remain
unverified; no credentials were entered.

The r10 preparation receipt records source base `a8a5c2dde` and exact source
copies, including the corrected session. Its build receipt SHA-256 is
`0b29f77db1afaec95b96e7e452a5fb8ca94c908bc2fb42edd47a737db8498b61`.
The VM uses the separately pinned Unix socket kernel build, with kernel SHA-256
`ac90558eac4f2ea6b74c72c3f519370e98e9f88b0a5384aa82cc386bdd1876ce`.
Authenticated X11 accepted the valid cookie and rejected the wrong cookie;
the session verified GLX was absent. The independent account authority fixture
passed. Browser cleanup recorded seven descendants and zero survivors.

After stopping the noisy Maps process, the original UART transfer arrived
intact. The strict collector verified all 378 entries and its 569,330-byte
archive with SHA-256
`4f0ce6dff92ffad15a1b7a8805dfeda4a73b4ba083cfe68cefae14bca8804b57`.
The requested stop and disappearance receipts confirm the owned VM is gone.

The complete seven-root, 5,219-entry bundle is outside Git under
`/Users/alex/.local/state/vinix/android/`. Its seal directory is
`browser-probe-evidence-2026-10-26-r8-cpu`, with manifest SHA-256
`9ea4470a079af4a97dddea1656e66626c2a948734a7b824b5be757a981afc41d`.
It binds the r8 VM, r10 build, restored results, kernel, authority and socket
fixture bundles. Recheck the complete original trees with the retained seal
tool; generated evidence is not tracked.
