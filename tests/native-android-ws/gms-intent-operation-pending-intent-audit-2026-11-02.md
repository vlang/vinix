# PendingIntent mismatch in IntentOperation recovery

The deployed SDK always creates a token for `PendingIntent.getService`, ignoring
`FLAG_NO_CREATE`, and its `send(Context,int,Intent)` overload delivers nothing.
These are concrete framework defects. GMS has a recovery path that can wait for
an intent those methods falsely claim to request. The [account timeout](maps-preflight-runtime-2026-11-02.md)
motivates this audit; a corrected ARM run must still establish its effect on Maps.

Source baseline is `ba6b79d58`. The exact admitted SDK manifest is
`bef486d060754858d51612b9c4bb8a24f7c2fdf8f37cc3565101e24a049bf52f`.
Its canonical PendingIntent class is
`84a6c096009bf0173f7dd70461c7d97337a9b5a3a2785402dc818a3638b8a38a`;
the baseline provider is
`fc82b5a784c2de8a2fde88d77f46d01a6c4734ae4ec7479e295b4fbaece83b57`.
Both source snapshots are retained. No Google APK, trust check or credentials
were changed, and this audit contains no framework implementation change.

The exact retained GMS root DEX supplies PersistentIntentOperationChimeraService
and GmsIntentOperationChimeraService, their base `bjin`, common service `aefr`
and worker `aefp`. In `aefr.k()`, `getService` receives `FLAG_NO_CREATE` at
offset `0x13`. A nonnull token is sent a `SAVED_INTENT` request carrying
`uniqueid` through the context overload at `0x2a`; normal return yields true.
The deployed SDK manufactures the token, then performs no send.

When recovery is enabled, `aefp.run()` stores `k()`'s result in `g` at `0x11`.
While true, it retains queued intents and looks only for `SAVED_INTENT` with
the matching ID. Without that intent, its backedge at `0x70` returns to the
queue wait and normal operation dispatch is bypassed. Recovery is conditional:
`onCreate()` clears `g` for names in a static set updated by
`onDestroy()`. The set initializer and actual live membership were not captured.
The API defects are unconditional; live check-in causality remains unverified.

Although the framework supplies start ID zero, the inspected GMS
`onStartCommand` enqueues and notifies before using that ID for bookkeeping;
no zero-ID queue-discard guard was found. Likewise, “Callback added” does not
identify the check-in branch: both the IntentOperation path and the queued
worker constructor register it before execution.

Complete evidence remains under `/Users/alex/.local/state/vinix/android` (`S`):
`gms-preadd-preflight-method-2026-11-02-r4` and its matching control root.
Detailed `audit.md` SHA-256 is
`d639d98334998f344776b534b1ff2b1c9357243d8a3d885cb67f5084c97341c2`;
the five-member inventory is
`f6c745c812e8362b40f454febf3f4ae5fec4631d95d71fc56b30f29f872c34e0`.
Four guarded sparse extractions, exact input/JAR readbacks, member hashes and
regular-file/mode/size checks passed. Maximum sampled RSS was 100,630,528 bytes,
elapsed time 206 ms and shared growth 126,976 bytes; all exits were zero with
complete cleanup and zero swaps under original 600 MiB/300-second/512 MiB-growth/
1 GiB-reserve/file caps. Independent source review passed.

Both roots are closed. The complete two-root seal and separate fresh-process
readback passed 84 typed entries. Manifest
`S/gms-intent-operation-pending-intent-sealed-2026-11-02-r1/sealed/manifest.json`
has SHA-256 `93dcddeee431aef1e4280dec43da77ac14e8cbf2288aa8d4dc67d059cd652419`.
Seal/readback took 57/350 ms with both exits zero, cleanup complete and zero
swaps under unchanged 600 MiB/900-second/64 MiB-growth/1 GiB-reserve/file caps.
Retain every original bundle and unchanged auditor. This preservation does not
establish successful check-in or authentication.
