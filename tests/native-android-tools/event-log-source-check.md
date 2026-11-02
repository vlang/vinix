# EventLog write contract without a binary sink

GMS reached a missing EventLog class through `clgt.e`. The new fieldless class
provides all five API-28 write overloads and the public constructor. This target
has no binary event sink: its installed host liblog silently discards binary
records while returning positive lengths. The adapter returns `-ENODEV` (-19)
for valid prepared payloads; it does not call that discard path, print payloads,
persist events, change identity or grant permissions. Read/store APIs are outside
this change.

The [API-28 JNI helper](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r3/core/jni/eventlog_helper.h)
accepts null arrays/elements, String, Integer, Long and Float, and examines at
most 255 array elements. Unsupported examined types throw the original
IllegalArgumentException without calling their `toString`. Array-null and
element-null preparation represent different strings, `[NULL]` and `NULL`.

[Payload preparation](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/android-9.0.0_r3/liblog/log_event_list.c)
starts at two bytes in a 4064-byte budget, with five-byte int/float and nine-byte
long items. Strings may truncate successfully while retaining the original
logical position. A previous encoding error (-EIO/-5) stops later validation and
overrides backend unavailability. Thus a large string followed by an unsupported
object still throws, while an intervening supported item can fail encoding and
suppress that later validation. Fresh scalar preparation never overflows.
[API-28 ART UTF counting](https://android.googlesource.com/platform/art/+/android-9.0.0_r1/libdexfile/dex/utf.cc)
uses two bytes for NUL, four for a valid surrogate pair and three per unpaired
surrogate. Counting is bounded at 4064 bytes without creating encoded buffers.

Independent reviews approved the provider, exact seven-method/class oracle,
narrow source-instruction evaluator and driver. First-attempt qualification
passed: three collision refusals, 19 semantic controls and 132 input checks on
generated source and each of two API-28 DEX roundtrips. The second roundtrip is
byte-stable. The evaluator rejects unknown operations, uninitialized reads,
external calls, excessive recursion and work; exact source/register checks and
DEX assembly establish the physical ABI. ARM remains a separate check.

Evidence: `/Users/alex/.local/state/vinix/android/event-log-source-check-2026-11-02-r1`,
including frozen sources, generated C, guarded receipts, input pins and both DEX
roundtrips. Proof receipt SHA-256:
`df048c3ff4d18ebf7abcb82a5ff1de5dbb69a91db613682fc4c49c7bd8461b6e`.
Recorded source parent: `3ab4d6a7ebce922d68c29f21188c3965df815fdc`.
Closed supporting bundles are `gms-event-log-audit-2026-11-02-r1` (manifest
`a1290a064a11dd5b3d2c58ce4b98c0b42a5c62d71d500fbcca449d51d571a4f7`)
and `event-log-backend-audit-2026-11-02-r1` (inventory
`e239e11d436bade327e33f86ba7e25c2619336a7724816a9d1c424c5abe24b7e`).
The parent 2116-class JAR stayed unchanged. The new class is outside native70;
complete SDK/native retention is a separate deployment gate.

All guards/children exited zero with cleanup complete and zero swaps. Proof
took 13.859 seconds, sampled 279,003,136 bytes aggregate RSS and recorded
182,763,520 detailed RSS. Split compiler sampled/detailed maxima were
257,884,160/279,150,592 bytes. Original limits remain 600 MiB RSS, 300 seconds,
512 MiB shared-volume growth, 1 GiB reserve, 4 MiB output and file cap 16777216.
