# PendingIntent lookup and context-send

Source baseline: `50bd1227e18d88af0027e314d0f05fbc2f59a947`.
The [GMS recovery audit](gms-intent-operation-pending-intent-audit-2026-11-02.md) identified
two deployed failures: `getService(..., FLAG_NO_CREATE)` created an operation,
and `send(Context, int, Intent)` returned without dispatching it. The successor
uses a process-local weak registry keyed by creator UID/package, operation
type, request code, persistent flags and `Intent.filterEquals`. Query-only
lookup, cancellation, extras updates, immutable operations and one-shot sends
share the same operation identity, including local parcel aliases.

Both existing send overloads now snapshot their operation and dispatch through
the captured creator Context. Context metadata getters run before the registry
monitor, so an application-context getter can reenter a factory without creating
duplicate canonical operations. Registry creation, cancellation and snapshots
use explicit DEX class monitors with exceptional cleanup; the non-native
`synchronized` access flag would not supply that locking. Component dispatch
runs after releasing the monitor. Fill-in merges preserve creator extras, honor
immutability, require explicit component/selector permission and clone source
bounds. Local Binder token identity, foreign-token refusal and the account
interaction accessor remain unchanged.

Only `android.app.PendingIntent` changes: twelve existing methods, seven private
static helpers and seven private fields. Its three existing capability helper
classes remain byte-identical. The full provider applies this same pure source
transform before writing its PendingIntent file. Foreground-service factory
identity is distinct; dispatch retains this SDK's existing `startService` path
because it has no separate `Context.startForegroundService` API. This is local
capability transport, without a new remote Binder protocol or callback overloads.

The focused V checker passed 54 malformed/repeated-input refusals before writes
and six deliberately broken output controls covering missing dispatch,
query-only lookup, component/source-bounds permissions, one-shot locking and
creator-context resolution. API-28 assembly and two DEX roundtrips passed for
PendingIntent and its three capability classes. All retained PendingIntent
methods and fields were preserved; the second canonical output was stable.
Independent source review covered registers, monitor ranges, weak references,
creator authority and fill-in behavior. These are source/ABI/assembly checks;
the separate signed ARM behavior fixture and live Maps flow remain required.

Complete frozen sources, commands, tool/input hashes, malformed inputs, generated
Smali/DEX, logs and guard receipts are outside Git at
`/Users/alex/.local/state/vinix/android/pending-intent-source-check-2026-11-02-r2`.
The input/output receipt SHA-256 is
`958e90936ae10b7abd8fcec14fd433347242fb220c08a71c1f21bd23ad5045c9`.
The complete bundle FINAL_SHA256SUMS digest is
`a25c71b3fc2a7eae823e52a546d7233f42978e3c8bb4ba23e12934109fb08bf8`.
The receipt records the checked integration source as
`1d1431172d6366f68dc91fdb5827dbddfa9e943fcf1eaec0e6472c9a1c1a0fc4`.
After that run, its extra blank line at EOF was removed so `git diff --check`
passes. Both versions and the exact one-line whitespace diff are retained in
the bundle. The committed integration source is
`e7f3b2d5010afbe76793f707dcde24fe004aa6138b3a69d38b936dc00f1102ae`;
its instructions and successor registration are unchanged. The provider and
both checker sources still match the final run's pins exactly.

| Artifact | SHA-256 |
| --- | --- |
| Successor provider | `7f0d36643ca45c4820b54df76d8762eb9c16ff1ba5a9288914d7297995fd5ea2` |
| Patched raw PendingIntent | `c71a0c7525e430ec0a492c5f03f290ef753065bd378974d680e8b1db17bf08d4` |
| Patched canonical PendingIntent | `a4692e2521f22789d2f785c5aa83413ccb708eff97a5ae213664bd10f800b93e` |
| Four-class DEX | `a9bb92c705d9d29ef2b43f3fc9f2d90c4dcd238bea67f820d8d0cee2b98843cd` |

The final check took 7.038 seconds, peaked at 227,311,616 bytes sampled aggregate
RSS and observed 21,487,616 bytes shared-volume growth. Its orchestrator compile
peaked at 312,934,400 bytes sampled aggregate RSS. Both exited zero, reported
complete cleanup and zero process swaps. Limits stayed 600 MiB aggregate RSS,
300 seconds, 512 MiB growth, 1 GiB reserve, 4 MiB output and shell file cap
16777216. Earlier failed checker compilations and the pre-final monitor check
are retained in the sibling r1 directory; no VM or full SDK build ran here.
