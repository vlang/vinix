# Current Maps runtime work — 2026-11-12

Full Maps qualification is pending. Onboarding rendered in guest r12; map
tiles, search, routing and login have not passed. Guest r21 validates the
current read APIs and the caller-scoped account-query adapter. Maps rendered
onboarding in that guest but exited after Skip; native account ownership
checks remain enforced. Guest r22 tests the next user/broadcast additions.

Current V is `/Users/alex/code/v/v` (initially `0.5.2 f2edf66`, then
`0.5.2 596e18d` for the SystemProperties successor). Builds use the available
compiler at that path without requiring a historical revision. The new
`maps-current-guest.v` stages available boot media with selected framework and
native outputs, updating deployment input metadata from those actual files.
It uses fresh APFS clones and leaves the original media unchanged.
`maps-caller.v` disassembles selected classes across an APK's DEX files.

External work directory: `/Users/alex/.local/state/vinix/android`.
`maps-current-20261112-r1` retains the deployment-metadata refusal.
`maps-current-20261112-r2` booted with the default-network-active framework r5
and current-V native r4. The controller reached ready, then GMS exited10 with
`NoClassDefFoundError: android.bluetooth.BluetoothDevice` at `djsz.<clinit>`
source398. The retained caller at
`maps-bluetooth-caller-20261112-r1/classes2.dex/djsz.smali` registers class
literals for BluetoothDevice, BluetoothClass and ParcelUuid as intent extras.

`framework_bluetooth_values.v` adds passive BluetoothDevice/BluetoothClass
parcelables and creators to normal framework generation: address validation,
value equality/hash, parcel serialization and device/service-class masks.
It exposes no radio or discovery capability. Contracts are documented in the
[BluetoothDevice](https://developer.android.com/reference/android/bluetooth/BluetoothDevice)
and [BluetoothClass](https://developer.android.com/reference/android/bluetooth/BluetoothClass)
Android references.

`bluetooth-values-build.v` applied the additions to framework r5, assembled
the complete SDK and disassembled the four generated classes. Both guarded
builds passed. Final output is `framework-bluetooth-values-20261112-r2`;
its sibling log and guard JSON retain results under the original limits.
`maps-current-20261112-r3` booted that output, reached broker ready, and advanced
past both Bluetooth literals to `NoClassDefFoundError: android.os.ParcelUuid`
at `djsz.<clinit>` source430. Its serial log retains both crash traces and
controller result exports. Parcel method behavior has not yet been executed
by a dedicated regression APK. These results establish class resolution,
not full Maps functionality, search, rendering or account login.

The next SDK, `framework-parcel-uuid-20261112-r1`, adds ParcelUuid and its
creator through `framework_parcel_uuid.v`. It delegates string parsing,
equality and hashing to `java.util.UUID`, and writes/reads the most-significant
and least-significant long halves in order. The full SDK assemble and selected
DEX readback passed with guard/child 0/0 and complete cleanup in 3,948 ms,
sampled RSS471,220,224 and shared growth41,746,432 bytes. The unchanged native
library is reused because no consumed JNI class or native method changes.
Guest `maps-current-20261112-r4` reached broker ready with this SDK.
It advanced to `NoClassDefFoundError: android.nfc.Tag` in the same registry;
the complete broker log was exported to its serial log between
`UUID-FULL-LOG-BEGIN` and `UUID-FULL-LOG-END`.

`framework_peripheral_types.v` makes Tag, NdefMessage, UsbDevice and
UsbAccessory resolvable as Parcelable types for that registry. The services
still expose no hardware objects. Unsupported peripheral parcel creation and
serialization throw explicitly; these are type definitions, not NFC/USB data
or device implementations. The focused builder now checks all fourteen
added type/creator files in the actual assembled DEX readback.
Final combined SDK is `framework-intent-types-20261112-r2`. Its guard/child
passed 0/0 with complete cleanup in8,381 ms, sampled RSS456,736,768 and
growth66,068,480 bytes. The earlier r1 invocation used the previous executable
after a compiler failure, and does not qualify peripheral type generation.
The compilation failure was conflicting `C.poll` nfds declarations after
shared host tooling changes. The platform ABI correction passed the host
PTY suite (one file, 15,053 ms runtime) and is committed as `701ba90b5`.

Guest r5 advanced past the intent registry and then exited10 in Safe Browsing:
`AccountManager.getAccountsByTypeAndFeatures` was missing, called by `cxly.v`
source19 and `SafeBrowsingChromeSyncIntentOperation`. Its complete log is in
the serial interval `INTENT-FULL-LOG-BEGIN` through `INTENT-FULL-LOG-END`.
`framework_account_features.v` adds the query using the existing visible typed
account snapshot and future callback/Handler implementation. Null account
types throw; null/empty feature sets return that snapshot; zero candidates
complete with an empty array for any feature set. Nonempty candidates with
requested features complete with the existing unsupported-authenticator error
rather than inventing matches. The future gains a Java-only array completion
method; native registrations are unchanged.
`framework-account-features-20261112-r1` passed full SDK assembly and selected
DEX readback in5,489 ms, sampled RSS486,227,968, growth50,057,216, guard/child
0/0 and complete cleanup. Guest r6 uses this SDK. Dedicated nonempty-account
and callback regression execution remains pending.

Maps launch must come from the desktop app host, which owns the compositor
input pipe and fresh surface. Invoking `--launch` from a shell does not supply
that app-host identity and does not qualify Maps startup.

Guest r6 advanced past the account query and then recorded missing
`TelephonyManager.isVoiceCapable()Z` and `IntentFilter.addDataType(String)V`.
The former appears in `bizf.a` source41, the latter in `cizh.i` source10 on
service creation. Its full broker log is retained between
`FEATURES-FULL-LOG-BEGIN` and `FEATURES-FULL-LOG-END` in the serial log.
Maps has not reached a usable window or a functional pass.

`framework_intent_mime.v` adds unavailable voice capability plus MIME filter
storage, validation and matching. The match implementation checks MIME
wildcards, explicit schemes or default content/file schemes for typed filters,
actions and category subsets. Existing authority/path stubs remain outside
this change. Guest r7 advanced beyond those calls to a missing
`ContactsContract.AUTHORITY_URI` field during Icing service initialization.
Its full log is retained between `MIME-FULL-LOG-BEGIN` and `MIME-FULL-LOG-END`.
`framework_contacts_authority.v` adds `AUTHORITY` and the parsed
`content://com.android.contacts` URI independently of provider availability.

The final SDK for this checkpoint is `framework-contacts-mime-20261112-r1`.
It passed full assembly/readback under the original limits in3,670 ms,
sampled RSS500,662,272, growth28,094,464, guard/child0/0 and complete cleanup.
The earlier `framework-mime-voice-20261112-r1` retains the first MIME build;
the final SDK also fixes empty-filter mismatch classification and scheme/type
failure precedence.

The signed regression at `current-api-fixture-20261112-r2/probe.apk` passed
on ARM in `maps-current-20261112-r8` using the caller-selected
`onboarding-api-run --current-api` profile, isolated UID/GID10160,
`/opt/current-api-runtime` and `/var/lib/current-api-r1`. It exercised:

- MIME duplicate suppression, subtype wildcard matching, action/type/scheme/
  category rejection, malformed MIME exceptions and empty-filter rejection.
- ParcelUuid parcel roundtrip and typed creator arrays, BluetoothClass parcel
  masks/service bits, BluetoothDevice parcel address roundtrip.
- Empty account feature queries, nonempty queries without requested features,
  explicit authenticator errors for unsupported nonempty feature filtering.
- False voice capability on this guest without a modem.

The runtime runner observed exactly one pass and readiness marker, closed
input, drained through EOF and required clean child exit. It printed
`ONBOARDING-API-RUN-PASS`. Snapshot `current-api-uart-20261112-r1` preserves
the original full UART and its receipt; plan `current-api-plan-20261112-r1.json`
selects the complete fixture export without removals. The unchanged
`diagnostic-uart-reconstruct.v` independently passed against that snapshot
and plan, retaining the two-entry archive at `current-api-readback-20261112-r1`.
Its archive checksum is
`2dfe8244454aa819f9c7c0e0e8dbf92f0ef446cd2d9f1060e845d93574dcaf1c`.
The test mount was released before the GMS broker attempt in the same guest.
This verifies the selected API paths; it does not establish callback ordering,
full NFC/USB implementations, complete URI authority/path matching, or Maps
functionality. GMS still exited during the subsequent attempt.
The next fatal trace is missing `Intent.toUri(I)String` in `cuwy.b` source38,
used for an explicit MAIN intent with package, component and launcher category.
The retained caller at `maps-intent-serialize-caller-20261112-r1` shows both
URI_INTENT_SCHEME (1) and URI_ANDROID_APP_SCHEME (2) paths. Guest r8's complete
log is retained between `CONTACTS-FULL-LOG-BEGIN` and `CONTACTS-FULL-LOG-END`.

`framework_intent_to_uri.v` adds API-28 serialization and the deprecated
`toURI()` alias, adapted from AOSP Intent.java. It emits ordinary, intent and
android-app forms with action, categories, MIME type, flags, package,
component, bounds, selector metadata and supported primitive/String extras.
The complete SDK is `framework-intent-serialize-20261112-r1`; its guarded
assembly/readback passed in5,220 ms with RSS477,757,440, growth29,696,000,
guard/child0/0 and complete cleanup.

`current-api-fixture-20261112-r3` adds exact expected URI strings for GMS's
MAIN/component/package/category shape with flags1 and2. It also tests both
URI forms roundtripping encoded path/query/fragment data, component and
Unicode/delimiter String, integer, boolean and wide-long extras through the
existing parser, plus the missing-package exception for android-app URIs.
It passed on ARM in guest `maps-current-20261112-r9`, including every earlier
regression. The runner closed stdin after pass/readiness, drained to EOF and
required exit0. Snapshot `current-api-uart-20261112-r2`, plan
`current-api-plan-20261112-r2.json` and independent readback
`current-api-readback-20261112-r2` retain the result without byte removals.
The two-entry archive checksum is
`2ece7a6da7ce7692064f541f282961312f015ccfbef4da117808035df32efab2`.
Broader selector/source-bounds and all primitive-extra combinations have not
yet been separately exercised. GMS/Maps validation of this successor is ongoing.

Guest r9 advanced to missing `ConnectivityManager.isTetheringSupported()Z`
in `apra.b` source16. The complete broker log is retained between
`URI-FULL-LOG-BEGIN` and `URI-MAPS-LOG-BEGIN`; the following Maps log probe
confirmed no Maps log had yet been created.
`framework_tethering.v` adds the capability query returning false without
polling or claiming a tethering backend. SDK `framework-tethering-20261112-r1`
passed guarded assembly/readback in3,878 ms with RSS474,546,176,
growth28,536,832, guard/child0/0 and complete cleanup.
Signed fixture `current-api-fixture-20261112-r4` adds a direct capability check
and passed all earlier API tests in guest `maps-current-20261112-r10`, again
with pass/readiness, complete EOF drain and exit0. Snapshot
`current-api-uart-20261112-r3`, plan `current-api-plan-20261112-r3.json` and
independent readback `current-api-readback-20261112-r3` retain its two-entry
archive without removals, checksum
`7ef3f391c725dee81ec3f34f28469ab86914601c5fecf43a06d3c25724dc174c`.
The test bind mount was released before the subsequent broker attempt.

Guest r10 advanced to an ART verifier failure in GMS class `etag`, propagated
to subclass `etaj`. Its `m(...)` method at DEX offset0x9EF supplies
`UserHandle[]` where `Parcelable[]` is required. The framework UserHandle
had `describeContents` but no Parcelable interface or parcel writer/creator.
The retained caller is `maps-verifier-caller-20261112-r1`; the full broker log
is between `TETHERING-FULL-LOG-BEGIN` and `TETHERING-FULL-LOG-END` in r10 UART.

`framework_user_parcel.v` adds Parcelable, an integer identifier writer,
typed creator arrays and nullable static read/write helpers with USER_NULL
(-10000), preserving all existing identity methods and constants. SDK
`framework-user-parcel-20261112-r1` passed guarded assembly/readback in4,193 ms,
RSS470,859,776, growth52,391,936, guard/child0/0 and complete cleanup.
Fixture `current-api-fixture-20261112-r5` passed on ARM in guest r11, including
all prior API tests and the exact UserHandle[]→Parcelable[] invocation,
identifier/creator roundtrip, typed creator arrays and static nonnull/null
parcel roundtrips. Snapshot `current-api-uart-20261112-r4`, plan
`current-api-plan-20261112-r4.json` and independent readback
`current-api-readback-20261112-r4` preserve the unmodified two-entry export,
checksum `2f84085fb7f32ab87531df96c081901e748242c261894d1a2e27877e92fa1f8d`.

`parcel-type-audit.v` provides a read-only scan for other parcel-shaped classes
whose superclass chains lack Parcelable. Its diagnostic candidate output is
`parcel-type-audit-20261112-r2.json`; it makes no claim that those other
classes have complete parcel implementations, and changes no class definitions.

Guest r11 advanced to `IncompatibleClassChangeError` in `fbfh.a` source354:
GMS invokes `SystemProperties.getBoolean(String,boolean)` statically, while
the framework declared it virtual. The complete broker log is retained
between `USER-PARCEL-FULL-LOG-BEGIN` and `USER-PARCEL-FULL-LOG-END` in r11 UART.
`framework_system_boolean.v` replaces it with the static contract, accepting
the exact lowercase true/false tokens in Android's
[boolean property parser](https://android.googlesource.com/platform/system/libbase/+/refs/heads/main/parsebool.cpp)
and preserving the supplied default for missing/empty/unknown values.
It uses the existing property map and adds no property setter or backend.

SDK `framework-system-boolean-20261112-r1` passed guarded full assembly and
selected DEX readback in4,331 ms, RSS475,545,600, growth61,726,720,
guard/child0/0 with complete cleanup under the original caps.
Fixture `current-api-fixture-20261112-r6` passed on ARM in guest r12:
all earlier API checks, static invocation, all ten accepted boolean tokens
with both defaults, missing/empty/unknown/uppercase/whitespace fallbacks.
Reflection seeds only the fixture process's map, and removes its temporary key.
The runner completed its EOF drain, exited0 and emitted its complete export.
Snapshot `current-api-uart-20261112-r5`, plan `current-api-plan-20261112-r5.json`
and independent readback `current-api-readback-20261112-r5` preserve its two
entries without removals, archive checksum
`f0ccbfbbe03b9aa95067435eea5f16fcb5a94330643ac984ab439314ff7f4bb7`.
The fixture bind mount was released before the next broker attempt.

Guest r12 reached the real Maps onboarding UI through the normal account-aware
desktop launcher. `progress.png` shows its illustration, Sign in and Skip.
Clicking Skip exited the APK (`after-skip.png`). The complete Maps log is
retained between `BOOLEAN-MAPS-LOG-BEGIN` and `BOOLEAN-MAPS-LOG-END` in UART;
its first uncaught failure is the missing API29 four-argument
`DelegateLastClassLoader(String,String,ClassLoader,boolean)` constructor,
called by GMS Dynamite/Cronet in the Maps process. This is onboarding evidence,
not successful map rendering or search. Immutable snapshot
`maps-onboarding-uart-20261112-r1` has full SHA256
`19d99a05bbcb8983eaf4c6ec6e190110fb349eb1a178caef6cbf057c55f23b06`.
The proposed separate standalone diagnostic was unnecessary and was not added
to repository tooling or installed as the guest launcher.

`boot_delegate_last.v` backports the
[four-argument constructor and resource policy](https://developer.android.com/reference/dalvik/system/DelegateLastClassLoader)
to the actual selected core-libart boot JAR. Both earlier constructors retain
default delegation. The flag controls resource lookup/enumeration after boot
and local lookup; class delegation remains unchanged. `delegate-last-build.v`
assembles an unchanged control first, then compares every unrelated class in
the successor readback byte-for-byte with that control. This accounts for
smali's equivalent normalization of explicit false static field initializers,
which caused the initial r1 direct-source comparison to fail. No comparison
is skipped for unrelated classes. Final `core-delegate-last-20261112-r3`
retains1,689 classes (1,688 unrelated comparisons), input/output checksums and
compiler identity in its receipt; guard/child0/0, cleanup complete,
7,201 ms, RSS456,572,928, growth194,965,504 under the original caps.

`maps-current-guest.v` optionally stages `VINIX_CURRENT_CORE_LIBART`, retaining
its actual checksum in deployment metadata, and `VINIX_CURRENT_LOADER_FIXTURE`.
The current API runner now records and rechecks the actual core-libart input.
Historical profiles and their checkers are unchanged. Host runner `selftest`
currently fails at the pre-existing unfinished default-network profile with
empty framework/native fields; no historical values were fabricated to pass it.

Guest r13 passed both unchanged signed API fixture r6 and the signed
`delegate-last-fixture-20261112-r2`: all four constructors, true/false parent
resource policy, local resource priority, common-resource enumeration order,
boot class identity, local-vs-parent class collision and parent class fallback
even when resource delegation is disabled. Both processes reached readiness,
emitted exactly one pass marker, drained EOF and exited0. The fixture's child
DEX/resource JAR is generated by V tooling and embedded in the signed APK.
Broader null-parent and missing-class paths have not been separately tested.

Snapshot `core-api-uart-20261112-r1` retains both complete exports. The
`uart-fixture-intervals.v` selector records exact byte offsets and SHA256 of
untouched intervals in `core-api-intervals-20261112-r1`; it performs no repair
or removal inside either export. Original snapshots remain retained.
Plans `core-api-plan-20261112-r1-{0,1}.json` and independent readbacks
`core-api-readback-20261112-r1-{0,1}` passed the unchanged reconstructor,
two entries each, archive SHA256 respectively
`ab7f0b8afb487f4221ae895cfdb7f34e8ce8533969c1c400f0623a570c27cf12`
and `9c1ee1e275610614f1d8539c94fdff6188ec6afde37dcae69d02c9bcb9cc8e86`.
The fixture mount was released before the next broker/Maps attempt.

Guest r13 advanced to a main-looper `NoClassDefFoundError` for
`SubscriptionManager.OnSubscriptionsChangedListener` during
`EsimModuleInitIntentOperation.f` source29. The full Maps log is retained
between `DELEGATE-MAPS-LOG-BEGIN` and `DELEGATE-MAPS-LOG-END`; snapshot
`maps-delegate-uart-20261112-r1` has SHA256
`cfd873d9e3457df86ef5d0b0e6ee1b0ef15140eb1d309f8dc40fef85307eaf9e`.
The retained caller is `maps-esim-caller-20261112-r1`.

`framework_subscription_listener.v` supplies the listener's default and
Looper constructors, virtual callbacks and both registration forms. Following
the [API30 absent-registry implementation](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-11.0.0_r1/telephony/java/android/telephony/SubscriptionManager.java),
registration reports `onAddListenerFailed` through the listener's Handler or
supplied Executor. It emits no subscription snapshot and retains no successful
registration; removal is harmless when no telephony registry exists. Existing
subscription queries and zero-modem reporting remain unchanged. Normal SDK
generation applies this after the earlier subscription-service adapter.

Final SDK `framework-subscription-listener-20261112-r2` passed full guarded
assembly/readback in4,176 ms, RSS467,107,840, growth63,881,216,
guard/child0/0 and complete cleanup. Initial r1 had no failure callback and
was superseded before guest use. Signed fixture
`current-api-fixture-20261112-r9` passed on ARM in guest r14, including every
earlier API check, both listener constructors, subclass callback dispatch,
both registration forms, duplicate registration/removal, legacy null listener,
Executor null-argument rejection and absent-registry failure delivery.
The pass marker now comes from a queued main-looper fence after validating
two Handler callbacks and one Executor callback. Subscription-change count
stays zero until the test explicitly invokes the virtual callback; it remains
one at the fence, proving registration invented no change event. The runner
observed readiness/pass once, drained EOF and exited0. Broader executor
rejection and missing-Looper construction paths are not separately exercised.
Snapshot `subscription-api-uart-20261112-r1`, plan
`subscription-api-plan-20261112-r1.json` and readback
`subscription-api-readback-20261112-r1` preserve its unmodified two-entry
export, archive checksum
`cf63ba65dc6ec3caaeeb18526f5eb4fd92c6562d440dfd80741a606670ebf5e2`.
The test mount was released before the next broker/Maps attempt.

Guest r14 advanced to missing `ShortcutManager.getDynamicShortcuts()` in
GMS Nearby initialization (`dsew.a` source19). Full log delimiters are
`SUBSCRIPTION-MAPS-LOG-BEGIN` / `SUBSCRIPTION-MAPS-LOG-END`; retained snapshot
`maps-subscription-uart-20261112-r1` has SHA256
`2df097d717941c785d56154f36c1945b8c0d02a6e0807cf34f41c155d64e927d`.
`framework_shortcut_query.v` delegates this legacy query to existing
`getShortcuts(FLAG_MATCH_DYNAMIC)` (flag2), consistently returning a nonnull
empty list for the current backend. The
[Android contract](https://developer.android.com/reference/android/content/pm/ShortcutManager)
defines this as a query for the caller's published dynamic shortcuts.
This addition does not implement or validate shortcut publication, builders,
parcel transport or desktop integration; those existing methods are not
qualified by this read-only test.

SDK `framework-shortcut-query-20261112-r1` passed guarded assembly/readback
in4,554 ms, RSS476,725,248, growth260,780,032, guard/child0/0 with complete
cleanup. Signed API fixture `current-api-fixture-20261112-r10` passed in
ARM guest r15, adding a direct nonnull/zero-size query assertion to all
earlier checks including queued subscription-failure delivery. Runner
readiness/pass, EOF drain and exit0 were observed. Snapshot
`shortcut-api-uart-20261112-r1`, plan `shortcut-api-plan-20261112-r1.json`
and readback `shortcut-api-readback-20261112-r1` retain the two-entry export,
archive checksum
`e8cfa288e4cb833555e9d9307afb44f753db3f7b447c833568ac450b64676b56`.
The test mount was released before the next broker/Maps attempt.

Guest r15 advanced past that query to missing
`ShortcutManager.removeDynamicShortcuts(List)` in `dsew.c` source17, in the
same Nearby cleanup. Full log delimiters are `SHORTCUT-MAPS-LOG-BEGIN` /
`SHORTCUT-MAPS-LOG-END`; snapshot `maps-shortcut-uart-20261112-r1` has SHA256
`e5fca645c1b1bd1e79837e1005fd1916e3526493bc5e23a0154969f98913a3f2`.
The helper now accepts removal of unknown IDs from the empty backend without
modifying the caller's list. It rejects a null list and null/empty IDs rather
than silently accepting malformed input. This still does not qualify the
existing shortcut publication methods.

SDK `framework-shortcut-remove-20261112-r1` passed guarded assembly/readback
in5,513 ms, RSS492,306,432, growth28,418,048, guard/child0/0, cleanup complete.
Signed fixture `current-api-fixture-20261112-r11` passed on ARM in guest r16,
including all earlier checks, immutable empty-list input, repeated removal of
duplicate unknown IDs, preserved input size, empty resulting query, null-list
NPE and null/empty-ID IllegalArgumentException. Runner readiness/pass, EOF
drain and exit0 were observed. Snapshot
`shortcut-remove-api-uart-20261112-r1`, plan
`shortcut-remove-api-plan-20261112-r1.json` and readback
`shortcut-remove-api-readback-20261112-r1` preserve its two-entry export,
archive checksum
`1b45c2f333ae26536cd7ddc8d473c944ad67833ba793017955fa04e0127f0d62`.
The test mount was released before the next broker/Maps attempt.

Source commits for the current successors are `bd22fdcaf` (boolean properties),
`1c80302ca` (boot loader), `06c1b8639` (subscription failure dispatch) and
`abdfdaa40` (shortcut query). Removal is built from `abdfdaa40` plus the
helper/fixture changes in this report's commit. All named artifact directories
remain under the external work directory above; raw evidence is not in Git.

Guest r16 passed Nearby cleanup and later exited the main looper on a null
`restrictions` service dependency. Full log delimiters are
`SHORTCUT-REMOVE-MAPS-LOG-BEGIN` / `SHORTCUT-REMOVE-MAPS-LOG-END`; snapshot
`maps-shortcut-remove-uart-20261112-r1` has SHA256
`a16381bf8d1ac8e262c580cebacb818bce7df1ea4b7b61d7d415c6b4f0f29805`.
The exact `rsy.b` source1071 caller is in the Play Store companion, not the
same-named interface in Maps. Inspection
`vending-restrictions-caller-20261112-r1` shows `getSystemService("restrictions")`,
the RestrictionsManager cast, then `getClass()` on that result. Its
Application `rra.onCreate` was being started inside the Maps runtime.
The same log records Cronet's missing native library and explicit Java
networking fallback; that caught failure is separate from the fatal null.

`framework_restrictions_service.v` supplies cached named/typed service lookups
with explicit DEX monitor cleanup and an owning context. Its application
restriction query delegates to the existing UserManager with the owning
package name, preserving that backend's fresh unmanaged snapshots rather
than creating a separate policy store. `hasRestrictionsProvider` returns false.
The retained contextless constructor returns null for its unavailable query.
Normal generation installs this after the existing service-lookup adapters.
Permission requests, manifest restriction parsing, administration/enforcement
and concurrent cache construction are not separately qualified here.

SDK `framework-restrictions-service-20261112-r1` passed guarded assembly and
readback in3,942 ms, RSS474,234,880, growth28,905,472, guard/child0/0 and
complete cleanup. Signed fixture `current-api-fixture-20261112-r12` passed on
ARM in guest r17: named/typed nonnull service identity, absent provider, fresh
empty snapshots after caller mutation, consistent UserManager query and the
contextless null result, plus all earlier API checks. Runner readiness/pass,
EOF drain and exit0 were observed. Snapshot `restrictions-api-uart-20261112-r1`,
plan `restrictions-api-plan-20261112-r1.json` and independent readback
`restrictions-api-readback-20261112-r1` preserve its two-entry export, checksum
`668fa4c92ba3b383cb36db0351668201a20f5d92444849aaab88287f75b7487a`.
The test mount was released before the next broker/Maps attempt. This
successor uses `f99306da1` plus this commit's source changes.

Guest r17 passed the restrictions dependency and exited later in Play Store
ContentFiltersService startup: `NoSuchFieldError` for
`DisplayMetrics.DENSITY_DEVICE_STABLE` from `uud.j` source1. Complete log
delimiters are `RESTRICTIONS-MAPS-LOG-BEGIN` / `RESTRICTIONS-MAPS-LOG-END`;
snapshot `maps-restrictions-uart-20261112-r1` has SHA256
`359ed4fecf16435d56d8fd5b4e72b99c8dba63394b8953f6a43195b2bf843284`.

`framework_stable_density.v` adds the public static final field and captures
the existing `getDeviceDensity()` result during class initialization. This
matches the [stable-density contract](https://developer.android.com/reference/android/util/DisplayMetrics#DENSITY_DEVICE_STABLE):
the value stays fixed while current display metrics may change. The backend's
configured density remains 160; no physical-DPI measurement or display-mode
change is claimed. SDK `framework-stable-density-20261112-r1` passed guarded
assembly/readback in 4,905 ms, RSS 472,088,576, growth 29,085,696,
guard/child0/0 with complete cleanup.

Signed fixture `current-api-fixture-20261112-r13` passed on ARM in guest r18,
including all earlier checks and a runtime field read (not a compiled literal).
It verifies stable 160, changes the deprecated mutable device density to 240,
observes 240 in a fresh metrics object, changes that object's density to 320,
and verifies the stable field remains unchanged throughout. A catch-all
restores the original mutable field on either success or failure. Runner
readiness/pass, EOF drain and exit0 were observed. Snapshot
`stable-density-api-uart-20261112-r1`, plan
`stable-density-api-plan-20261112-r1.json` and readback
`stable-density-api-readback-20261112-r1` preserve its two-entry export,
archive checksum
`3388790193da65a6561f289ebaf12c5cf7ec6abb4833442f87fe00f548a50fd9`.
The test mount was released before the next broker/Maps attempt. This
successor uses `f6d35f515` plus this commit's source changes.

Guest r18 advanced past density initialization and exited later in Play Store
ContentFiltersService startup on missing `Settings.Secure.getLong` at
`alyh.g` source18. Full log delimiters are `DENSITY-MAPS-LOG-BEGIN` /
`DENSITY-MAPS-LOG-END`; snapshot `maps-density-uart-20261112-r1` has SHA256
`ecb61c05a3f56e4e55c43fb35b7b7fd59b580cdaa1a6ee852c1abc9893b6b623`.
Inspection `vending-secure-long-caller-20261112-r1` shows queries for mobile
download-size limits. Its strict-call branch catches SettingNotFoundException
and returns -1; another flag selects the default-value overload with -1.
These are optional settings rather than a request to generate an identifier.

`framework_secure_longs.v` supplies both public static overloads over the
existing String getter. Long conversion failure becomes the
[documented checked absence](https://developer.android.com/reference/android/provider/Settings.Secure#getLong(android.content.ContentResolver,java.lang.String))
or the caller's complete 64-bit default. Other getter exceptions propagate.
It does not change legacy String fallbacks, create settings values, provide a
settings store or qualify successful provider-backed numeric reads.
SDK `framework-secure-longs-20261112-r1` passed guarded assembly/readback in
3,819 ms, RSS 452,739,072, growth 29,515,776, guard/child 0/0 with complete
cleanup.

Signed fixture `current-api-fixture-20261112-r14` passed on ARM in guest r19:
the strict checked exception and key message for unavailable/nonnumeric data,
an unchanged positive wide default, Long.MIN_VALUE default for an empty value,
propagation of the existing getter's null-key NPE, and all earlier API checks.
Valid numeric strings cannot currently be supplied through this legacy getter
and are not claimed as an executed provider-backed case. Runner readiness/pass,
EOF drain and exit0 were observed. Snapshot `secure-long-api-uart-20261112-r1`,
plan `secure-long-api-plan-20261112-r1.json` and readback
`secure-long-api-readback-20261112-r1` preserve its two-entry export, checksum
`ab490eec7ffa2783245851647d1ce935edac6130cd050e6f72f60b7d1c75304e`.
The test mount was released before the next broker/Maps attempt. This
successor uses `c58ba2f59` plus this commit's source changes.

Guest r19 progressed further and exposed several independent failures:
missing `UserManager.getUserCount`, `UserManager.getUserForSerialNumber`,
`ConnectivityManager.getNetworkInfo(Network)` and `ApplicationInfo.isInstantApp`.
It also recorded an account target-query SecurityException; that authorization
path remains separate from these read APIs. Full log delimiters are
`SECURE-LONG-MAPS-LOG-BEGIN` / `SECURE-LONG-MAPS-LOG-END`; snapshot
`maps-secure-long-uart-20261112-r1` has SHA256
`a5de5911a56d00be4c0ba8171581cd01008d450b844ee899ce2719ef06e2ee2f`.

`framework_runtime_queries.v` adds the count and inverse serial lookup for
the configured single Android-user catalog (not the per-app Unix accounts).
The Network overload matches one native state observation to the requested
interface and returns null for null, unknown, expired or absent handles.
ApplicationInfo now has privateFlags; isInstantApp reads its 0x80 bit rather
than public flags, and the metadata copy constructor preserves that field.
This does not implement multiuser management, a disconnected-network catalog,
instant installation or ApplicationInfo parcel transport.

SDK `framework-runtime-queries-20261112-r1` passed guarded assembly/readback in
3,895 ms, RSS 478,232,576, growth 29,769,728, guard/child 0/0 with complete
cleanup. Signed fixture `current-api-fixture-20261112-r15` passed on ARM in
guest r20, including all earlier checks: user count/profile agreement,
current-user serial roundtrip, negative/unknown/above-32-bit serial rejection;
instant flag defaults, unrelated public/private bits, copied flags and copy
isolation, plus installed-fixture metadata; Network overload type/identity,
null/unknown/expired handles and no-link states through an overridden native
state boundary, plus a real backend query. That final observation does not
assert Internet reachability. Runner readiness/pass, EOF drain and exit0
were observed. Snapshot `runtime-query-api-uart-20261112-r1`, plan
`runtime-query-api-plan-20261112-r1.json` and independent readback
`runtime-query-api-readback-20261112-r1` preserve its two-entry export, checksum
`1ac2167c62b1fbbbcc8a122e5fbc93a1b4ba6026da4779f38ee41cd55a4dc88e`.
The test mount was released before broker preparation. A Maps retry awaits
the separately investigated package-query path; its native ownership check
has not been relaxed. This successor uses `bec488e01` plus this commit's sources.

The account failure in r19 came from GMS `cxly.q` / `ajrb.e` while running
inside the Maps process. Inspections `gms-package-account-caller-20261112-r1`
and `gms-target-package-caller-20261112-r1` retain those wrappers. Android's
[target-query service contract](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/accounts/AccountManagerService.java)
separates authenticated caller/op-package checks from the target package and
returns no accounts for denied target queries. The previous adapter passed
the target directly into a native caller-ownership guard.

`framework_account_package_query.v` defines the direct bridge's visibility
domain as the authenticated caller's own package. Its existing native
AppOps.checkPackage check gates delegation to getAccountsByType, whose broker
query retains the real process identity. A target outside this direct scope
returns a fresh empty Account array without querying account data. The catch
range contains only the ownership probe; account-backend errors propagate.
This grants no authenticator role or foreign-package visibility. Privileged
cross-package disclosure still requires the existing broker capability path;
this adapter does not implement arbitrary target filtering for owner calls.
Native store, mutation and AppOps guard code is unchanged.

SDK `framework-account-package-query-20261112-r1` passed guarded full assembly
and readback in 4,514 ms, RSS 479,297,536, growth 44,826,624,
guard/child 0/0 with complete cleanup. The unchanged native guard checker
passed its production closure and all 20 compiled negative mutations with
current V (`VEXE=/Users/alex/code/v/v`), retaining inputs and results at
`account-store-guard-check-20261112-r1`; its sha256.json checksum is
`3aa7860696c47c25ed8f4c546b91a4d8b1f01b2b41629d0beafb10fa24b35b53`.

Signed fixture `current-api-fixture-20261112-r16` passed on ARM in guest r21,
including all earlier checks. Real native AppOps verifies the primary package
and still rejects a foreign package. A fixture AccountManager subtype supplies
an own-scope snapshot and then a sentinel SecurityException: own queries see
the snapshot or the identical backend exception, while foreign queries return
empty without invoking that backend. This is a controlled query test, not a
Google account login or a new disclosure grant. Runner readiness/pass, EOF
drain and exit0 were observed. Snapshot `account-package-api-uart-20261112-r1`,
plan `account-package-api-plan-20261112-r1.json` and independent readback
`account-package-api-readback-20261112-r1` preserve its two-entry export,
checksum `e8630702d04e880a31754ee5e7752b51ef629a0c24a7bd5e2db27cbc761c56a2`.
The test mount was released before broker preparation and Maps retry. This
successor uses `9b706a845` plus this commit's source changes.

The r21 desktop launch rendered onboarding; selecting Skip exited the APK.
Its complete log (delimiters `ACCOUNT-PACKAGE-FINAL-MAPS-LOG-BEGIN` / `END`)
is retained in `maps-account-package-uart-20261112-r1`, full-log SHA256
`e441e83df333ff2bbedf6f643d7cdf8a5ad2ea6ae189958f05bd38df268b9c85`.
The next linkage failures were UserManager.isDemoUser and
Context.sendBroadcastAsUser(Intent,UserHandle). Play Store caller inspection
`vending-broadcast-user-caller-20261112-r1` shows bgel selecting serial0's
system user and sending a SingleUserSettingsReceiver intent to that user.

`framework_user_broadcast.v` reports the configured persistent user as not a
[demo user](https://developer.android.com/reference/android/os/UserManager#isDemoUser()).
The two-argument broadcast overload validates both arguments, requires the
target's identifier to equal the real process Android user, then delegates
to the existing broadcast transport. Foreign and all-user targets throw
SecurityException. This adds no cross-user privilege, user management or
cross-process broadcast transport; the native backend remains process-local.
Native code and JNI method descriptors are unchanged.

SDK `framework-user-broadcast-20261112-r1` passed full assembly/readback with
guard/child0/0 and complete cleanup in38,274ms, RSS469,417,984 and
shared growth195,080,192 bytes. Guest r22 stages this SDK and signed fixture
`current-api-fixture-20261112-r17` using current V.

The r22 ARM regression passed, including all earlier API cases. It registered
a real native broadcast receiver and observed exactly one asynchronous
own-user delivery with its action and integer payload intact. Foreign and
all-user targets raised SecurityException; null intent/user raised NPE and
caused no extra delivery. The callback count was checked at the existing
main-Handler completion fence. isDemoUser returned false. Runner readiness,
pass, EOF drain and exit0 were observed. Snapshot
`user-broadcast-api-uart-20261112-r1`, plan
`user-broadcast-api-plan-20261112-r1.json` and independent readback
`user-broadcast-api-readback-20261112-r1` retain the two-entry export, archive
SHA256 `87b35fa72b11adf9d330e3fa38d0d83157f953f010c0ac839332d97de149f32a`.
The fixture bind mount was released before broker preparation. This successor
uses `6746c6efa` plus this commit's source changes.
