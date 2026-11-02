# Secure settings/Tile ARM pass and usage-stats linkage failure

The signed Secure settings and API-28 TileService regression **passed on ARM**.
GMS advances beyond the previous missing Secure.putString call, then exits after
missing `UsageStatsManager.isAppInactive(String)Z`. No manual Maps launch,
Sign in, credentials or imagery check occurred; current map rendering and
authentication remain unverified.

Core `2af821249`, producer `ecd559062`, fixture `a6e4192e2`, delivery `07775bda7`,
[SDK/native pair](secure-settings-pair-2026-11-02.md) `749cb77be` and
[media profile](maps-secure-settings-stage.md) `770958288` are committed.
Only Secure changes and TileService is added, growing membership to 2,112.
The retained native pair remains compatible, with all 70 consumed canonical
classes equal and the two pinned raw formatting changes recorded separately.
Prepared manifest is
`f5583243199173123a39498c8e461c139c7bd8878283f763613d0f98bf1f7cde`.
All 52 module readbacks and complete input rechecks passed in 299,036 ms at
92,749,824 bytes sampled RSS; guard/child exits are zero and cleanup complete.
Clone and frozen-kernel installation passed before boot under original limits.

Complete evidence remains below `/Users/alex/.local/state/vinix/android`:
`maps-secure-settings-runtime-audit-2026-11-02-r1` (`A`), matching live controls,
separate `maps-secure-settings-preparation-2026-11-02-r1`, prepared
`maps-secure-settings-r1`, stopped `maps-secure-settings-vm-2026-11-02-r1` with
four clone sidecars, and `secure-settings-api-transfer-live-2026-11-02-r1`.
`A/runtime-result.md` closes the pending runtime-plan without changing it or the
independent validation note. Historical complete bundles and original auditors
remain required.

The initial download failed because /opt/input was absent; the original
fixture-inputs.png remains. Creating that directory and retrying through the
same healthy transfer succeeded before fixture launch. This setup correction
was not an ARM test failure; both downloaded identities matched their pins.

The isolated UID/GID 10148 child 59175 exited zero with six exact input identities
and eleven unchanged checks. Receipt SHA-256 is
`0d041cdac030fc27bbf9ee315ece77432d79138b0b56049f4959e1ee02d082fa`.
The complete 10,321-byte, 122-line child hashes to
`c6e4d5912b71c923aa8b161bca6d6265c6849756b1877a5ff61ba40c3e8c5d5f`:
one exact PASS at line 105, readiness at 116 and normal teardown through 122.
Independent `A/fixture-validation.md` hashes to
`adab2e6891fbcdb52b69c2ffc9a4f2012d4ae939b2c4af27fb87eeb1cdb04dba`.
Thirteen recording-resolver insert paths check secure URI, exact nullable values,
provider booleans, SQLException false and other-exception propagation. Real
absent-provider false results do not establish persistence or a write grant.
Five recording tile requests check the API-28 action/package, explicitly present
nullable component, permission, fresh Intents and exception behavior. Actual
TileService/adapter construction, onBind-null and inherited static resolution
passed. No SystemUI delivery, tile backend or dormant Tile-return invocation is
inferred. Unchanged zero-removal diagnostic import preserved all 33 chunks of
the 16,603-byte fixture archive, without new strict fixture-protocol qualification.
No health rule was relaxed.

After releasing the fixture mount, the controller ran from 17:53:40 to 17:54:33
UTC. Receipt
`066e963652b9c84c1af3c1bd36c8b1eb6b9ca78498785a9d9cb81a78b28c04bc`
records broker 38462, readiness true, failed/exit 1, drain EOF true/status 1,
330,756 bytes, errno zero and zero cleanup survivors. The next uncaught
NoSuchMethodError reaches `esqc.a` source 915 → `esqr.a` 664 →
`esqf.handleMessage` 165 on netscheduler-queue-handler. GMS calls System.exit(10)
and records native VM status 10. Readiness alone is transport evidence, not
successful initialization or Google authentication.

Automatic export finished with guest input idle. Before stopping the VM, the
unchanged strict collector passed 21 entries, 2,831 chunks and 1,449,111 bytes,
archive `fbe99c37a22ecc69149296dc4a0ba5ceefaf0325f7b69d374fc041c7155abf5d`.
Import took 280 ms at 27,852,800 bytes sampled RSS; both exits are zero with
complete cleanup. The separate full private broker log,
`A/broker-log-diagnostic/child.log`, is 330,756 bytes, SHA-256
`8cefb6978a009a41788d8ce3ec1237da7e7893b3d0f9b1451537bad08e8372ff`.
The existing guest-pinned canonical-base64 decoder and fresh readback passed
without modifying original UART or payload bytes. Private logs stay outside the
strict account archive apart from their hashes. Failure cleanup removed the live
protected broker session required by the supported Maps desktop launcher.

Owned exclusive 12 GiB/four-CPU VM 5790 started at 17:48:28 UTC. One SIGTERM was
requested at 17:56:41 and QEMU records signal 15. The first stop returned 1 on an
ownership race; no second signal was sent. Qualified reconciliation returned
zero at 17:56:49; gone.json and an independent empty exit-1 ps query confirm
absence. Final UART equals the immutable after-private-log full snapshot, both
SHA-256 `812b7b26c15e0954eca11086778de0820812889b2f39de203f9abea80c008ad7`.
No compiler or Java ran while the VM was live. Ten closed roots passed complete
evidence sealing and a separate fresh-process readback of all 692 typed entries.
The manifest at
`maps-secure-settings-runtime-sealed-2026-11-02-r1/sealed/manifest.json` hashes to
`c13bbc2fb818bb70cb16891a0304b86f6e5ab2d6eb2f00713edc32c1171aab84`.
Seal/readback took 8,045/3,269 ms at 15,548,416/12,500,992 bytes sampled RSS;
all guard/child exits are zero with complete cleanup. The original 600 MiB RSS,
900-second, 64 MiB shared-growth and 1 GiB reserve limits remained enforced.
