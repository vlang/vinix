# Stable display access controls and next GMS native gap

The unchanged diagnostic APK records `Point(0,0)` for the isolated nonroot
fixture, whose 1024×768 assertion remains failed. The same APK and runtime pass
all physical-size, fresh-Point and mutation checks as a separate trusted-root
control, against a 64×64 app surface. This distinguishes physical geometry from
the window size without changing framebuffer permissions or weakening the
isolated runner's UID rules.

The frozen kernel seat-gates framebuffer access independently of mode0666.
The nonroot child inherits login session0; root is permitted to query geometry.
The observed empty result is consistent with the implementation's unavailable
fallback. This does not establish physical-size availability for unprivileged
clients. No geometry handoff or seat-policy change was made.

Source and pair remain [the qualified stable-display build](stable-display-sdk-2026-11-02.md).
Only diagnostic APK/runner pins changed in `3ae622c27`/`987598644`; all original
assertions remained. Prepared image manifest is
`dc28d10922f90cea0081969562a85d7cf60c489e0684ad3cfaaf75b78e28edc7`.

Evidence is under `/Users/alex/.local/state/vinix/android`, in the r2
`maps-stable-display-runtime-audit-2026-11-02-r2` (`A`), matching live controls,
stopped VM and four clone sidecars, prepared `maps-stable-display-r1`, and
`stable-display-api-transfer-live-2026-11-02-r2`.
The complete failed child is 9,707 bytes; original SHA-256
`c702c5976deef1a4cb7c45073e82bac76f8073481b9889217b1668d0a8d1ca5a`.
Its manual Base64 import and fresh check preserve every byte. Independent
`A/fixture-failure-validation.md` hash is
`d89ff538920eee139df344084f6d70593e4376e591df49c34b0e8c67fb6b9e78`.

The separate root control used fresh private data/home/cache, clean environment,
the same six input hashes before/after, and FIFO-held stdin through PASS/readiness.
Native PID3333 ran as UID/GID0/session0 and exited0 after EOF. Its complete
9,464-byte/108-line log contains one PASS at93, READY at102 and teardown through108.
Four distinct returned Points retain physical1024×768 and caller mutations do
not escape. The initial shell-wrapper PID6654 failed before the app and remains
preserved separately. Independent `A/root-control-validation.md` hash is
`74f1f2fa12651f4b65f1cf0e54de058a40f4544d7cad27a22ba3eccf87cbb21b`.
This is an operator positive control, without a fabricated isolated-runner receipt.

The fixture mount was released before GMS. Actual controller receipt
`c2f47ca57f3ca42b297df944a4b13ef9cdc2174697866112f43e12e680a31805`
runs10:32:05–10:32:59UTC: broker33255, readiness true, failed/exit1, drainEOF
true/status1/87,335bytes/errno0, cleanup survivors0. Its bounded stack reaches
`bpcw.a` source764 and reports `UnsatisfiedLinkError` for the already-declared
native `AssetManager.getLocales()`. This is the next concrete implementation gap.
The unchanged strict account collector passed21entries/2,831chunks/1,449,100bytes,
archive `99d860090050caa53576a1316b6b4b0f03c0e0e5c761167a3a26e6fa6bad069b`.
Maps was not opened after broker failure. No sign-in, credentials, Next or trust
bypass occurred; imagery/check-in/authentication remain unverified for this pair.

Owned exclusive12GiB/fourCPU VM63104 ran10:19:29–10:38:58UTC; one SIGTERM stopped
it cleanly, with stop0/gone.json/independent absence checks. No host compiler or
Java process ran while it was live. Final UART matches the immutable snapshot,
`4336eedc8c91fe84b0d2b96a494fcf6020272305c69ca785d4e00a2ea32a0ad6`.
All original resource guards and complete historical evidence remain required.
The nine closed roots passed sealing and separate fresh-process readback,
688 typed entries, manifest
`maps-stable-display-runtime-sealed-2026-11-02-r2/sealed/manifest.json`, SHA-256
`c790fe65d6fc311ec56edc398cedb52cc5dc3b5e9d37925b3d5dd83c58536ab6`.
