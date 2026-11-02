# Messenger ARM run blocked by ComponentName parcel contract

The Messenger Binder fixture failed on ARM because ComponentName lacks its
Parcelable CREATOR and writer. The failure occurs during the initial Message
payload roundtrip before request/reply transport assertions. There is no PASS,
READY, successful runtime receipt or fixture protocol archive. GMS was not
started; no manual Maps launch, Sign in, credentials or imagery check occurred.

Providers `2166f55d7`/`23296f853`, producer `147d9c296`, fixture `283faf15e`,
delivery `8f404d4a2`, [SDK/native pair](messenger-binder-pair-2026-11-02.md)
`d0403c8d0` and [media profile](maps-messenger-binder-stage.md) `55e59bb42`
are committed. The framework has 2,115 classes and retains the compatible
broadcast native bundle. Prepared manifest is
`e72282b9881ba4b82a053aa89c3e3b96383c7ee25cad637d5421b50717adff1a`.
Preparation passed in 319,701 ms at 92,176,384 bytes sampled RSS, both exits zero
and complete cleanup. Clone and frozen-kernel installation passed before boot
under original limits.

Complete evidence remains below `/Users/alex/.local/state/vinix/android`:
`maps-messenger-binder-runtime-audit-2026-11-02-r1` (`A`), matching live controls,
separate `maps-messenger-binder-preparation-2026-11-02-r1`, prepared
`maps-messenger-binder-r1`, stopped `maps-messenger-binder-vm-2026-11-02-r1` with
four clone sidecars, and `messenger-binder-api-transfer-live-2026-11-02-r1`.
`A/runtime-result.md` closes the pending plan without changing it or the
independent failure validation. Historical complete bundles and their original
auditors remain required.

The dedicated UID/GID 10150 invocation used signed r2 APK
`7295339e8b548f3d48091229eb31319be25bf7394a2091ebce6b26263693729a`.
Runner/APK downloads succeeded and matched their pins. Main.onCreate enters
messageControls/messagePayload; the inherited Parcelable writer prints a
ComponentName diagnostic, then Parcel.readParcelable raises BadParcelableException
caused by NoSuchFieldException: CREATOR. The stack passes through
VinixMessageCreator.createFromParcel, Main.messagePayload, messageControls,
tests and run. The fixture emits MESSENGER-BINDER-FAIL and activity startup fails.
Local/proxy delivery, reply routing and callback UID assertions lie after this
payload check and remain unqualified by this run.

The complete failed child is retained at `A/failed-child-diagnostic/child.log`,
10,125 bytes / 106 LF-terminated lines, SHA-256
`338cde88d1c52fca5e6089969fbda090d320151297cf1753cb5743dadb9f5434`.
The existing guest-length/hash-pinned canonical-base64 decoder and separate fresh
readback passed, with guard/child exits zero and complete cleanup. This is exact
diagnostic preservation without fixture-protocol qualification, byte repair or
relaxed health checks. Its immutable 14,874-byte UART interval hashes to
`e8c90b0cc0b34a8afcf3c6184c70ad5e12303b9c8ebf6d77e27966fe0e2fea3c`.

Independent `A/fixture-failure-validation.md` hashes to
`5e346f32f17bf4609444d0e162ec1fc91816b887e72b153e9ad5476942dcdfde`.
It binds the exact signed APK, sources, snapshots and original decoder. Read-only
inspection of the frozen SDK confirms ComponentName implements Parcelable but
has no CREATOR, Parcel constructor or write override. The inherited diagnostic
writer and public CREATOR lookup explain the observed payload failure. The
fixture supplies no platform class and can be reused unchanged for a complete
fresh replay; its caller UID assertions require unused UID/GID 10150. No
Messenger transport, GMS or Maps success follows from this failed run.

Owned exclusive 12 GiB/four-CPU VM 83482 started at 19:25:26 UTC and stopped
normally with one SIGTERM at 19:31:12. The qualified stop returned zero;
stop/gone receipts, QEMU signal 15 and an independent empty exit-1 ps query
confirm absence. Final UART equals the immutable after-failed-fixture full
snapshot, both SHA-256
`626ddd05348674c59c05e8b189614834e50d577a7362caa9fd7696a958ba794e`.
No compiler or Java ran while the VM was live. Original inputs, screenshots,
failed logs and historical checkers remain unchanged. Ten closed roots passed
complete sealing and a separate fresh-process readback of all 640 typed entries.
The manifest at
`maps-messenger-binder-runtime-sealed-2026-11-02-r1/sealed/manifest.json` hashes to
`42ed5e65555ecb2903eeabb3f12d7479599a0f5062a805c3942ef59bf0e9152b`.
Seal/readback took 8,262/3,133 ms at 15,400,960/24,002,560 bytes sampled RSS,
with 1,097,728/315,392 bytes observed shared growth and zero swaps. Both guards
and children exited zero with complete cleanup under the original 600 MiB RSS,
900-second, 64 MiB shared-growth and 1 GiB reserve limits. Evidence integrity
passed; the recorded fixture outcome remains failed before transport assertions.
