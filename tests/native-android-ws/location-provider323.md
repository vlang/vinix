# LocationManager contracts without a provider

Source baseline: `14e5ebb74a288df4636d87f89a5fb31c96ef20d6`.
The native WS backend advertises no location providers, but the old framework
posted a fabricated GNSS status callback, retained update listeners before
calling an unbound native method, and never removed retained listeners.
The fix keeps provider discovery empty and rejects updates without entering
that native path. GNSS registration returns false and schedules no events;
removal releases the requested legacy listener while preserving other entries.

The contract is bounded to the existing legacy overloads and Android 10/API29.
Its immutable primary sources are
[LocationManager](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/57bb140be9e48cf08acba131f7463e461777bb8e/location/java/android/location/LocationManager.java),
[LocationManagerService](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/57bb140be9e48cf08acba131f7463e461777bb8e/services/core/java/com/android/server/LocationManagerService.java)
and [Handler](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/57bb140be9e48cf08acba131f7463e461777bb8e/core/java/android/os/Handler.java)
at revision `57bb140be9e48cf08acba131f7463e461777bb8e`.
Unknown nonnull providers have no last known location; update requests throw
IllegalArgumentException. Null arguments retain their API-specific validation,
and a caller without a Looper receives the original Handler exception before
provider lookup. Extra commands with a nonnull provider return true and leave
the extras unchanged even when the provider is absent; a null provider throws
NullPointerException. The GNSS result must not be generalized to all Android
versions or newer overloads. No new LocationManager APIs are added.

The Maps SDK29 value is a static inference from the exact consumed
Build.VERSION/EarlyParser implementation, Native315 options and the APK's
minSdkVersion29; it was not sampled in a Maps runtime log. The generic fixture
uses the same minSDK29 path and separately logs and asserts its runtime SDK.
The independent source bundle retains the selected framework inputs, the
original APK and eleven primary source files and tag receipts. It is at
`/Users/alex/.local/state/vinix/android/location322-independent-contract-2026-10-25`,
manifest SHA256
`3f50b9053bb437c6c0e525a634104b3a950770a67fcb36c1fc573f18b132b3f7`.
Its 30-file readback and independent contract review passed. The maintained
`location-provider-sourceproof.v` checker SHA256 is
`0bd8c70dede00554e02c657978834739fbc9656203a0555f7e24ce8c7ad91f90`.
Root independently reran it with the complete bundle; its receipt is
`/Users/alex/.local/state/vinix/android/location322-root-sourceproof-readback-2026-10-25.json`.
Reproduce with assertions enabled and a fresh receipt outside the bundle:

```sh
VROOT=/Users/alex/code/v build/android-maps/queue284-tools/v_old276 -o /tmp/location-sourceproof tests/native-android-ws/location-provider-sourceproof.v
/tmp/location-sourceproof /Users/alex/.local/state/vinix/android/location322-independent-contract-2026-10-25 /tmp/location-sourceproof-fresh.json
```

The production helper SHA256 is
`061ee25300a2b9eba087053731d0958526b0c194e9467b102c29100686cfbeb0`.
Framework322 freezes all 137 generators from the qualified318-v2 source set
with only this helper changed. Its source-map SHA256 is
`0d1d6e32594eb4b0de7f810d8cfbea4aac337162639540d3addf561ed821ad0b`.
The actual assembled DEX changes only LocationManager: 2,066 classes remain
identical, with no additions or removals. V checking, compilation and
independent review of the emitted methods passed. The complete 7,013-payload
build bundle is at
`/Users/alex/.local/state/vinix/android/location-provider322-framework-build-2026-10-25`,
manifest SHA256
`30b0765e61f5ec059b91a1066893c80bd63c5a655d13af36df6066ab13507402`.
Root independently checked the exact file set and all 7,013 payload hashes;
the receipt is
`/Users/alex/.local/state/vinix/android/location322-root-readback-2026-10-25.json`.
Framework JAR SHA256 is
`8f814c91a597f4c4fee0adde46789d144b4256586fc7816e0a60c2f3d661d7c8`.

The maintained V fixture source SHA256 is
`1e4bdbc88119978eb3d70371e31e987b393e4c07c7bbf59ee93e0348e9209035`.
It observes callbacks across two real 200ms main-queue gates, each preceded by
a sentinel and checked against its due time. It covers active, repeated and
unregistered GNSS callbacks, null callback/Handler combinations, empty
discovery, rejected update requests, and command return/extras semantics.
A fresh worker checks exact no-Looper exceptions and null-argument precedence.
Rejected requests must leave the legacy listener registry empty. A separate
compatibility test injects two entries into that registry to prove selective,
repeated removal; this is a cleanup regression for the old framework storage,
not a public Android reflection contract or a callback garbage-collection test.
V checking, host assembly, signing and independent source/emitted-APK review
passed. Both callback recorders count every supported event method.

Paired guest regression323 passed with the same signed APK SHA256
`c6cf049902784b78a47216d5f6afde1c078f097929525411f0d3ecbba5a5f8a4`.
Native315 SHA256
`54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab`,
clean283 launcher SHA256
`406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0`
and runtime/media inputs are common; only the framework JAR changes from
318-v2 SHA256
`6b826b2b7c37eb6b101d2627854064d1d06988f7c8bbdf1b94c1dea012e86b5d`
to322. Both guests observed SDK29 with trace variables absent. The old guest
fails at the first delayed assertion, `absent GNSS provider delivered a callback`,
before synchronous request tests, with one controlled exit1 and no success
groups. The fixed guest passes DISCOVERY, REQUESTS, REMOVAL, COMMANDS and ASYNC
in order, then PASS and READY; the raw classifier records `window_observed`,
backend ready and a live process without failure markers. Raw old
`startup_failed` is the expected baseline observation, separate from the
semantic regression verdict. Independent review of both raw logs, results
and suite receipts passed. The maintained runner source SHA256 is
`d05680c31ae2dd67dcbbe54e269f92bf2e34bdfeb87d7c73d04216e0258aa85d`.

The complete paired bundle is at
`/Users/alex/.local/state/vinix/android/location-provider323-fixture-2026-10-25`,
with 601 payload entries and manifest SHA256
`57e11dcfa834eda430ee84d6ee5f49a41df2601bc52e9a1c11cb415eccd7c82c`.
Sealing verified that both guests had stopped. Root independently checked
the exact file set and all 601 payload hashes; its receipt is
`/Users/alex/.local/state/vinix/android/location-provider323-root-readback-2026-10-25.json`.
No Maps replay is qualified by this report.
