# Build ABI ARM pass and missing WebView package-query failure

The signed Build ABI regression **passed on ARM**, measuring `os.arch=aarch64`
and `Process.is64Bit()=true`. GMS attaches its authenticator, then exits on the
missing static `WebView.getCurrentWebViewPackage()` method. No manual Maps launch,
Sign in, credentials or imagery check occurred; current map rendering and
authentication remain unverified.

Core `0f443cf3b`, producer `0d6272593`, fixture `7e34880a7`, delivery `9132f29a5`,
[SDK/native pair](build-abis-pair-2026-11-03.md) `626910ebb` and
[media profile](maps-build-abis-stage.md) `2de660c94` are committed. Class membership
stays 2,117; only Build and SystemProperties change. All other 2,115 canonical
classes, Build.VERSION and the retained native bundle remain unchanged.
Prepared manifest is
`48aec518f620a1684c7ff471ac62b2e3744fc071b307ea584d10059be3170f51`.
All 57 module readbacks and complete input rechecks passed in 376,082 ms at
91,897,856/90,636,288 bytes sampled/detailed RSS, zero swaps, both exits zero and
complete cleanup. Clone/kernel installation passed in 8,883/45,303 ms before
boot under the original limits.

Complete evidence remains below `/Users/alex/.local/state/vinix/android`:
`maps-build-abis-runtime-audit-2026-11-03-r1` (`A`), matching live controls,
separate `maps-build-abis-preparation-2026-11-03-r1`, prepared `maps-build-abis-r1`,
stopped `maps-build-abis-vm-2026-11-03-r1` with four clone sidecars, and
`build-abis-api-transfer-live-2026-11-03-r1`. `A/runtime-result.md` closes the
pending plan without changing it or the independent validation note. Historical
complete bundles, failed attempts and their original auditors remain required.
The [preceding EventLog run](maps-event-log-runtime-2026-11-02.md) remains intact.

The isolated UID/GID 10152 child 57727 exited zero with six exact input identities
and eleven unchanged checks. Receipt SHA-256 is
`bdff04e641203335466793bad231ede14ab2eea44b8e61b9dcf98a9431d9caa2`.
The complete 12,362-byte, 177-line child hashes to
`7f105e250b4fd003b9f38dcb214494b584bb881971c38b3edd8d26eee6493695`:
one architecture observation at line 95, exact PASS at 162, readiness at 171
and normal teardown through 177. Independent `A/fixture-validation.md` hashes to
`a7ef003c5d4e9b238f48b46c90870885e960dc762f2f42b5a9753acdff3b701e`.
Its source-bound coverage includes three field metadata probes, three baseline
passes, two public-array element mutations with restoration and independence
checks, and six custom-property states through sixteen explicit reflective helper
calls. These exercise missing/empty lists, ordering, interior empty elements,
trailing-empty removal, whitespace, alternate delimiters and fresh arrays.
Cleanup verifies prior custom-key presence and the exact raw Object. Real ABI
properties, os.arch and SDK state are untouched. Failure/suppression branches and
the host's seventeen controls are not claimed as ARM fault-injection results.
This fixture does not exercise 32-bit execution or native-library loading.
Unchanged zero-removal diagnostic import preserved 38 chunks of the 19,199-byte
fixture archive, without strict fixture-protocol extension or health waiver.

After releasing the fixture mount, the controller ran from 21:54:02 to 21:54:58
UTC on November 2. Receipt
`9732a1465c8b7736030d938ebbf94986ca0a268a09031593620ddcccdf28d861`
records broker 59789, readiness true, failed/exit 1, drain EOF true/status 1,
214,965 bytes and zero cleanup survivors. An uncaught NoSuchMethodError on
`lowpool[0]` reports missing
`WebView.getCurrentWebViewPackage():android.content.pm.PackageInfo`, reached via
`alu$$ExternalSyntheticApiModelOutline0.m` source 24 → `bmpx.c` 3 → `bmps.c` 29.
GMS calls System.exit(10); the native VM records status 10. Readiness does not
establish successful startup or Google authentication.

Automatic export finished with guest input idle. The unchanged strict collector
passed 21 entries, 2,831 chunks and 1,449,035 bytes, archive
`d9db14b75e1376125fb8d72c40a16744127cb7a1c2818e0e11c149a48f8d6771`.
Import took 297 ms at 29,229,056 bytes sampled RSS; both exits are zero with
complete cleanup. The full private broker log remains separately at
`A/broker-log-diagnostic/child.log`, 214,965 bytes, SHA-256
`065363554bd7a0b63636e2a2c46eaa8743aaf4a12e45a469d8291f3d690d4cb1`.
The existing guest-pinned canonical-base64 decoder and fresh readback passed
without modifying original UART or payload bytes. Private logs stay outside the
strict account archive apart from hashes. GMS exited before a manual Maps open;
cleanup removed the live protected session required by the supported launcher.

Owned exclusive 12 GiB/four-CPU VM 28637 started at 21:51:11 UTC. One SIGTERM was
requested at 21:59:14; QEMU records signal 15. The first stop returned 1 on an
ownership race; no second signal was sent. Qualified reconciliation returned
zero, with gone.json at 21:59:23 and an independent empty exit-1 ps query
confirming absence. Final UART equals the immutable after-broker-log full
snapshot, both SHA-256
`174c2629ad6101b6e068f7c4e60a14dc382f5e766864b5498e1827db680415ab`.
No compiler or Java ran while the VM was live. The first seal stopped at the
original shared-growth limit: guard 125/child 137, complete cleanup, 4,440 ms,
13,254,656 bytes sampled RSS and 127,164,416 bytes observed growth. All failed
output remains at `maps-build-abis-runtime-sealed-2026-11-03-r1`.

The unchanged-cap retry sealed the ten runtime roots and that failed-attempt
root, 749 entries total. Manifest at
`maps-build-abis-runtime-sealed-2026-11-03-r2/sealed/manifest.json` hashes to
`7bc0347cb687d8bc52c33902e21d5da96823c967a26927009a771cd2ad4c3298`.
Seal guard/child exited zero with complete cleanup in 7,587 ms at 15,679,488
bytes sampled RSS, 22,310,912 bytes shared growth and zero swaps. The separate
fresh-process readback stopped at the same growth limit: guard 125/child 137,
complete cleanup, 2,747 ms, 22,953,984 bytes sampled RSS and 87,240,704 bytes
observed growth. Its original check log and receipt are preserved.

After the compiler lane was released, a new fresh-process `check-r2` passed all eleven
roots and 749 entries against the same manifest. Both exits are zero, reason
empty and cleanup complete: 3,141 ms, 13,451,264/20,643,840 bytes sampled/detailed
RSS, 1,486,848 bytes observed growth and zero swaps. The 600 MiB RSS, 900-second,
64 MiB shared-growth and 1 GiB reserve limits remained unchanged for every
attempt. The failed seal is included as root eleven; both readback attempts
remain with the r2 control files outside the audited subtree. All runtime and
seal roots are now closed.
