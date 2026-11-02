# First stable-display ARM assertion failure

The first signed stable-display fixture failed its physical-size assertion on
ARM. The API resolved and returned a Point, but the original fixture did not
print its coordinates. Neither physical-size success nor the cause of the
mismatch is established. Play Services and Maps were not retried in this run.

The [qualified SDK/native pair](stable-display-sdk-2026-11-02.md) and
[image tools](maps-stable-display-stage.md) passed host checks. Prepared image
manifest is `dc28d10922f90cea0081969562a85d7cf60c489e0684ad3cfaaf75b78e28edc7`.
The unchanged signed fixture expected physical 1024×768 and app surface 64×64.
Kernel UART independently reports simplefb 1024×768×32. Dedicated UID/GID10139,
read-only runtime mount and downloaded pins were checked before execution.

Evidence under `/Users/alex/.local/state/vinix/android` includes
`maps-stable-display-runtime-audit-2026-11-02-r1` (`A`), matching live controls,
the stopped `maps-stable-display-vm-2026-11-02-r1` and four clone sidecars,
prepared `maps-stable-display-r1` and the r1 fixture transfer root.

The failed runner produced no success receipt, PASS, READY or framed archive.
The complete 9,587-byte/98-line child was preserved through a bounded manual
Base64 envelope, then restored by the unchanged qualified V decoder and checked
again in a fresh process. Its SHA-256 is
`68a77a704b2eaf1fcf883a060bc4922a63daca35e92752a7dcaf663b819b55b6`.
Immutable before/after UART snapshots agree; no arbitrary repair or historical
collector change occurred. Detailed `A/fixture-failure-validation.md` hash is
`a920caf2a598747a66e210414d87ead8af64c2a84b0ec444eeff31377a425bb0`.

Read-only investigation identified an additional seat-access check in the
actual frozen kernel, independent of framebuffer mode0666. The terminal has
login session0; the isolated child inherits that session while dropping UID.
This suggests a permission-denied/empty-Point path, but actual coordinates were
not observed. No seat gate, device permissions or expected sizes were changed.
A diagnostic APK and separate trusted-root positive control are follow-up work.

Owned VM33164 ran 09:49:24–10:03:04 UTC with exclusive12GiB/fourCPU networking.
One SIGTERM stopped it cleanly; stop returned0 and absence/gone.json were checked.
Final UART matches the immutable full snapshot,
`04c4b524347af195567e83efa8bf629786a137f6c790ce0f8253572edce1b4a0`.
No host compiler or Java process ran while the guest was live. All original
memory, reserve, time, growth and file-size guards remain intact.

Nine closed roots passed complete sealing and separate fresh readback:573 typed
entries, manifest `maps-stable-display-runtime-sealed-2026-11-02-r1/sealed/manifest.json`,
SHA-256 `73681effba8cffce3e555ff79e43d8de00ff14ebfedc05c10d9a92bf70d6ecf3`.
Complete original evidence and unchanged auditors remain required. This failed
run establishes no Maps rendering, check-in or authentication result.
