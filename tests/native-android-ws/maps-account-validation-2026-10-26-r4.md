# Maps account deployment: browser transport failure

The real Maps/GMS controller observed the GMS authenticator attach, then its
browser transport disconnected. The r4 receipt has no account initialization
failures (`auth_init.failures=[]`, `truncated=false`), unlike the r3 stage-8
failure. A fixed-path metadata screenshot also records creation of
`/var/lib/vinix/apps/10013/data/accounts/accounts.sqlite`: 40,960 bytes, owner
`vinix-gms-account`, mode 0600, inside an account directory with mode 0700.
This advances account store startup, but Google account login remains unverified.
No credentials were supplied.

The receipt records 20:13:30–20:15:25 UTC on 2026-10-26, broker PID 30586,
`service_ready=true`, broker exit 1 and zero cleanup survivors. Readiness means
authenticator transport attachment. After the initial automatic launch hit the
SQLite hardlink guard, the controller was started explicitly through the guest
Terminal with `/opt/vinix-maps-account/bin/maps-account-guest --broker`.
The retained `sqlite-dealias.json` records both library paths becoming separate
single-link files while preserving their SHA-256 values.

The startup-only private broker tail was inspected locally in the guest,
recorded in `broker-startup-failure.png`. After the service attachment, it shows
`ANDROID-WS-FAIL browser transport`, `run-android browser: client disconnected`
and `ANDROID-ACCOUNT-BROKER-FAILED account input disconnected`. This is a
transport failure observation; it does not identify the failing browser
operation. Private broker and Maps logs were excluded from the archive; the
export retains their hashes. `store-created-metadata.png` records metadata
without account contents. Neither screenshot establishes a signed-in Maps UI.

The unchanged strict collector accepted 21 entries, 1,438,706 archive bytes
and 2,810 chunks, archive SHA-256
`5313b91e7efddb8580e594a6b50dc6ecaab957ca78eb230ee11ef55f519df47a`.
The original final collection remains in
`maps-account-collected-final-2026-10-26-r4`. A separate post-stop collection
in `maps-account-collected-recheck-2026-10-26-r4` accepted the same archive from
the complete final UART, SHA-256
`822cd623a8655835b3f303e074bb19633ec09fbb001ce7db88b95d2138f5498c`.
The original final import binds its earlier UART snapshot, SHA-256
`cdaa725403587e7f860da155b1cfa63a20097e79a77df2a9d3d9198b96a97545`.
Collection integrity passed; the actual guest result remains failed.

Only the exact 1,911-file `maps-account-vm-r4` clone was patched and booted.
Original `maps-account-r4`, complete manifest
`d8b601b131af4f5f1212d4e093bc2d028231a49846636549dff88b236d2bfcf0`,
remains intact. [Staging provenance](maps-account-stage.md) at source
`8643274d0` records the r4 request and clone. Runtime inputs were descriptions
framework r1 (2,104 classes), JNI r16, account r7, launcher r13, Maps controller
r5, browser deployment r7, signed token fixture r7, token controller r2 and
standalone UI stage r3. Account r7 uses canonical SQLite path fix `c318d84f2`.

The AArch64 kernel includes P_PIDFD wait support from retained source
`ecbd3964aff243304e16df45271c7de8dee4d2da` plus its recorded patch.
The complete kernel build is
`pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2`, build receipt SHA-256
`1e9077779aaed08188e6f8111ca9ceb27b479517ece736a58157049f004fb36d`,
kernel ELF SHA-256
`a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`.
Its build receipt's `guest_executed=false` describes the build step; this
separate deployment records the subsequent boot.

The retained native-SHA host tools patched and managed owned QEMU PID 21037.
SIGTERM was requested at 20:40:41 UTC; matching ownership, stop and absence
receipts confirm absence at 20:40:46 UTC. The first stop command reported an
ownership race; the runner's reconciliation passed. Both logs are retained.
The complete VM root preserves final UART, screenshots, packet capture and
original booted media. No VM mutation was performed for the post-stop
collection and sealing.

All artifact paths are below `/Users/alex/.local/state/vinix/android/`.
The deployment evidence seal is
`maps-account-evidence-2026-10-26-r4/manifest.json`, SHA-256
`1b70ffcb2a112c1cd07b61c9c1f1c3993e07a3bf7acbb7dbbc387a5f18c0c1bd`.
It binds 63 roots and 60,849 entries: complete original and booted media, both
collections, selected producers and upstream inputs, request lineage, kernel
build, clone helper source closure, host tools and lifecycle logs in place
without copying images.
Its creation check and independent full recheck passed, recorded in adjacent
`-seal.log` and `-check.log`. Preserve every bound root; concise pins do not
replace complete bundles. This binds deployment evidence and does not certify
a recursively complete historical host-tool rebuild closure.
