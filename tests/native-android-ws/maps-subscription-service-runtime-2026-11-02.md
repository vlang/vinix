# Subscription-service ARM pass and AutofillManager linkage failure

The signed subscription-service regression **passed on ARM** with unchanged
health checks. GMS advanced beyond the absent subscription-service failure,
attached its authenticator, then exited after a missing AutofillManager method.
No manual Maps launch, Sign in, credentials or imagery check occurred in this
run; current map rendering and authentication remain unverified.

Core `bf4a357a6`, fixture `1d2a2ec4d`, producer `8dd3331d1`, delivery
`49b32a12d`, [SDK/native pair](subscription-service-pair-2026-11-02.md)
`5e78f8f7e` and [media profile](maps-subscription-service-stage.md) `64d50e93a`
are committed. The 2,110-class SDK preserves all 70 native-consumed classes and
the exact retained locale DSO. Prepared image manifest is
`eb4f5508749dfd15968abebfd997f70ab9877b61fbd8b6c6cfc24aae4f258284`.

Complete evidence remains below `/Users/alex/.local/state/vinix/android`:
`maps-subscription-service-runtime-audit-2026-11-02-r1` (`A`), matching live
controls, stopped VM `maps-subscription-service-vm-2026-11-02-r1` and clone
sidecars, prepared `maps-subscription-service-r1`, and the subscription-service
transfer root. Preserve the earlier disk-refused/guard-stopped preparation
attempts and failed preparation-seal preflight alongside the successful retry.
The [original disk checkpoint](subscription-service-runtime-blocked-2026-11-02.md)
remains historical evidence. Preparation resumed with the original 4 GiB outer
allowance and 1 GiB reserve; all internal checks and the 512 MiB stager write
budget remained. It passed in 273.632 seconds at 90,521,600 bytes sampled RSS,
89,784,320 bytes detailed RSS and zero swaps. Clone and frozen-kernel installation
then passed before boot.

Unused UID/GID 10143, fresh output and protected read-only runtime were verified.
Actual child 18379 exited zero with six exact input identities and eleven checks.
Runtime receipt SHA-256 is
`7f18643e49dfc335ed050b30afe7ef9e1079ca3f838790227c04c353c0cfbcff`.
The complete 9,920-byte, 108-line child hashes to
`a0f73a3c5ddf9547d3b6cb03660bec9ec4ee182c22103baa07c933733dfa30a2`:
one exact PASS at line 93, readiness at 102 and normal teardown through 108.
Independent receipt/log/source review in `A/fixture-validation.md` confirmed
the real cached service, null data, exact unavailable-number exception, zero
modems, fresh bound wrappers and guarded unresolved getter references. No fake
subscription data, platform APK stub or diagnostic whitelist was supplied.
That independent report hashes to
`9737a815a30780293f8fb297fcbc1b57c74c6822ae41061f0d1ed64d72f3078b`.
Unchanged zero-removal diagnostic import preserved all 32 chunks of the
16,018-byte archive. This is not new strict fixture-protocol qualification.

After releasing the fixture mount, the GMS controller ran from 14:41:55 to
14:42:45 UTC. Receipt
`9ab526f6369eb5ef8c182b86a22185e6fe62b576f9115efc11be1dd7a69291bf`
records broker 16085, service readiness true, failed/exit 1, drain EOF true,
status 1, 230,762 captured bytes, errno zero and zero cleanup survivors.
The uncaught exception is NoSuchMethodError for
`AutofillManager.getAutofillServiceComponentName()Landroid/content/ComponentName;`,
through `ami$$ExternalSyntheticApiModelOutline0.m` source 22, `ayrh.a` source 4,
and `AutofillModuleInitIntentOperation.b` source 351. GMS then calls System.exit
with status 10 and records `ANDROID-WS-VM-EXIT status=10`. Readiness establishes
transport attachment, not successful startup or Google authentication.

The full exact private broker log was separately retained as
`A/broker-log-diagnostic/child.log`, 230,762 bytes, SHA-256
`b738bebc89454dec57bd9bacf9a739ea63c367bc750cb6cdaedb1b5a64d96042`.
The existing canonical-base64 decoder and separate fresh readback passed against
the guest-pinned length/hash. Original UART and encoded bytes remain untouched;
this diagnostic extraction does not change or extend the account protocol.

The automatic account export completed with guest input idle. Before VM stop,
the unchanged strict collector passed 21 entries, 2,831 chunks and 1,449,192 bytes,
archive `b2126680b790124ab4a90bc30ac1ccd65af98efcd604b521d6cc1da0a7792e5c`.
Import took 271 ms at 27,885,568 bytes sampled RSS, guard/child exits zero and
complete cleanup. Private logs remain outside that archive except their hashes;
the separate full broker diagnostic is retained in the private external bundle.
The existing desktop launcher requires a live protected broker session, which
cleanup removes, so this failed session did not provide a supported Maps launch.

Owned exclusive 12 GiB/four-CPU VM 77109 started at 14:37:53 UTC and stopped with
one SIGTERM at 14:45:21. Stop returned zero; `gone.json` and a separate empty
exit-1 ps query confirm absence. QEMU records signal 15. No compiler or Java
process ran while the VM was live. Final UART exactly equals the immutable
after-private-log full snapshot; both hash to
`3e8129c7e3d6eb595397f3da8213547577a2cc181dd893517fc7829454b7eb17`.
All image/import checks retained their resource limits. The ten-root complete
evidence seal and separate fresh-process readback passed all 677 entries,
including the original failed preparation attempts and failed seal preflight.
The manifest at `maps-subscription-service-runtime-sealed-2026-11-02-r1/sealed/manifest.json`
hashes to `ba526b00a9c60676e0bf95a20dccf8aca36874d2b647ce92d5ddff5b4f205731`.
Both guard/child exits are zero with complete cleanup under the original
600 MiB RSS, 900-second, 64 MiB shared-growth and 1 GiB reserve limits.
