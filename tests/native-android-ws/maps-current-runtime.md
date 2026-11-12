# Current Maps runtime work — 2026-11-12

Full Maps qualification is pending. Onboarding rendered in guest r12; map
tiles, search, routing and login have not passed. Guest r21 validates the
current read APIs and the caller-scoped account-query adapter. Maps rendered
onboarding in that guest but exited after Skip; native account ownership
checks remain enforced. Guest r22 passed user/broadcast checks, then Maps
exited on the missing platform-module query. Guest r23 passed that addition
and rendered onboarding, then exited after Skip on missing sandbox metadata.
Guest r25 passed the sandbox metadata regression, then Maps exited on an
inaccessible package-delete observer placeholder; BASE_OS was also missing.
Guest r27 tests the corresponding observer types and build-field fixes.
Its ARM regression passed. Maps then rendered onboarding but killed itself
after SQLiteFullException as RAM-backed storage reached zero. Guest r31
passed disk write/readback and the unprivileged SQLite regression on a
separate app-data disk under the unchanged guest memory budget.
Maps rendered onboarding in r31, then exited after Skip on Play Store code
passing the null system shared-library catalog into Arrays.asList.
Guest r32 passed that regression and advanced to a missing staged-install
session query, with missing job-property getters also logged.
Guest r33 passed those regressions and rendered the Explore/search/control
screen, then lost its main looper on missing JobParameters.getJobId. Tiles
were not rendered before that failure.
Guest r34 passed the scheduled callback regression and loaded Explore content,
then exited on missing TelephonyManager.getImei in GMS check-in. Search did
not produce a result before that exit.
Guest r36 repeated the same SDK and reached onboarding without the r35
app-host transport failure, then lost its main looper on the missing optional
StorageStatsManager type. No map/search/route/login result is qualified.
Guest r38 passed that repair's complete API regression, then Maps exited on
missing Build.getSerial in GMS check-in; an SSLSessionCache context constructor
was also missing in an asynchronous Play Store initialization path.
Guest r39 passed those regressions but was stopped for host disk pressure.
Guest r40 rendered Explore after Skip, then hit a View.forceLayout/TableLayout
requestLayout recursion and StackOverflowError on the main looper. Its
disk-retained private log also records the missing secure Android socket
factory overload; neither tiles nor search/routes/login are qualified.
Guest r41's log records the next uncaught GMS check-in query, isGuestUser.
Guest r44 passes the complete API suite plus secure socket-factory tests,
trusted HTTP, three invalid-host/chain rejection pairs and a stalled-peer
handshake timeout. Its actual Maps retry is still pending.
That retry exited after Skip on a Play Store secondary-service DI class cast.
Guest r45 passes scoped service-creation failure and ResultReceiver callback
regressions; its actual Maps retry is pending.
Guest r45 rendered Explore/Local vibe and stayed alive past the contained
Play Store creation failure. During a Louvre search attempt, uncaught GMS
Bluetooth/Contacts-directory linkage failures ended the process. Search,
tiles, routing and login remain unqualified.

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

Guest r22's Maps attempt exited with an uncaught
PackageManager.getInstalledModules(int) linkage error in Play Store's
FinskyEventLog. Its complete final log delimiters are
`USER-BROADCAST-FINAL-MAPS-LOG-BEGIN` / `END`; immutable snapshot
`maps-user-broadcast-uart-20261112-r1` has full-log SHA256
`e8a5a0d75d77c7100a8336af0a08df063439652304e5bf3b46e2ccaf54e78be0`.
`vending-module-catalog-caller-20261112-r1` shows ammm calling the API with
MATCH_ALL (0x20000) and collecting a stream of its entries.

`framework_module_catalog.v` returns a fresh empty list for the configured
deployment, which has no Android platform module installer or module metadata
catalog. Installed apps, Chimera APKs and host libraries are not advertised as
system modules. This follows the documented
[empty module catalog result](https://developer.android.com/reference/android/content/pm/PackageManager#getInstalledModules(int));
it does not implement APEX installation or nonempty ModuleInfo transport.
SDK `framework-module-catalog-20261112-r1` passed guarded full assembly/readback
in10,454ms, RSS484,065,280 and shared growth77,758,464 bytes, guard/child0/0
with complete cleanup. Fixture r18 checks empty results for0/MATCH_ALL and
isolation from mutations of a previous returned list.

The same r22 log records ENOSPC writing GMS preferences during startup.
After Maps exited, df reported8.3GiB total/6.0GiB used/2.3GiB available and
MemFree2587200KiB. That later observation cannot establish the startup peak.
`maps-storage-watch.v` reads real meminfo and filesystem availability every
250ms for at most ten minutes, reporting minima every5s or64MiB drop. It does
not write guest data, grant storage or change resource limits. Current-V
host parser selftest passed; the static ARM executable is
`maps-storage-watch-arm-20261112` (SHA256
`c19b5a8956434d2b302eb1baab126eccbc4601450c08f6fccc022a269aaaa03e`).
Both probe builds use -gc none -autofree. The guest staging tool optionally
includes it through VINIX_CURRENT_STORAGE_WATCH. Guest r23 retains the same
12GiB/4CPU configuration.

Fixture r18 passed on ARM in r23, with all earlier cases, runner readiness,
pass, EOF drain and exit0. Snapshot `module-catalog-api-uart-20261112-r1`, plan
`module-catalog-api-plan-20261112-r1.json` and independent readback
`module-catalog-api-readback-20261112-r1` preserve the two-entry export, archive
SHA256 `a9171fe7623d142d4fd7b9296458f5b2b39fc869ae836364a486f6566e701359`.
The ARM storage parser selftest also passed. The first observer invocation
failed because it preceded broker provisioning of /var/lib/vinix/apps; it
was restarted after that directory and broker readiness were observed.
Its real samples report filesystem availability and MemFree (for example,
at14046ms available2964226048 bytes, minimum2941861888 and MemFree3091264KiB).
This verifies the observer can run on this kernel, not a completed startup
measurement. The next desktop Maps launch is in progress. This successor
uses `3c5e891f7` plus this commit's source changes.

Guest r23 passed the platform-module query and rendered onboarding. After
Skip, it exited on ApplicationInfo.targetSandboxVersion in Play Store aqxh.l
(FinskyEventLog). The full log delimiters are `MODULE-CATALOG-MAPS-LOG-BEGIN`
/ `END`; snapshot `maps-module-catalog-uart-20261112-r1` has full-log SHA256
`08b0ca81452f6c09d43a4f7f75078e06e437799f52b8ea28b2361f90a5a4984e`.
No ENOSPC occurred in this attempt's exported Maps log. The observer sampled
available storage down to142770176 bytes (MemFree336000KiB), followed by a
recovery after Maps exited. A250ms sampler cannot exclude shorter troughs.

`framework_sandbox_metadata.v` adds the public integer field with its normal
zero object default and preserves it in ApplicationInfo copies. PackageParser
reads the existing AndroidManifest TypedArray before recycle, using its
targetSandboxVersion attribute and default1, following Android's
[metadata field/copy](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r1/core/java/android/content/pm/ApplicationInfo.java)
and [manifest parser](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r1/core/java/android/content/pm/PackageParser.java).
This exposes requested metadata; it does not add Android sandbox-version
enforcement, installation policy or parcel transport.

SDK `framework-sandbox-metadata-20261112-r1` passed full assembly/readback in
4730ms, RSS485081088 and shared growth156983296 bytes, guard/child0/0 with
complete cleanup. The fixture checks object default0, copies of value2 and
copy isolation, installed omitted-manifest default1, and parsing literal2
and a resource-backed2 from distinct metadata-only APK assets. Those archives
have hasCode=false and are parsed without installation or application startup.
An initial fixture link using -R rejected the new resource as an overlay;
the producer now supplies its compiled resource archive as a normal link input.
Fixture r19 is a retained failed build, not ARM evidence. r20 uses a shared
cache filename; the final successor uses distinct paths for independent reads.
Guest r24 was staged with r20 but was not booted or used for qualification.

The r23 storage observer completed at600203ms, retaining the same minimum
142770176 bytes / MemFree336000KiB. Full snapshot
`maps-storage-complete-uart-20261112-r1` has SHA256
`0f6c0bbacf43b403adaf07919e54978b66984862eb0a57ebe89852bef6deefe5`.
Only the verified r23 QEMU was stopped. Guest r25 stages fixture r21, whose
two metadata assets are copied to distinct cache paths; its ARM checks follow.

Signed fixture r21 passed on ARM in r25, including both metadata-only archive
parses and all earlier checks, runner readiness/pass, EOF drain and exit0.
Snapshot `sandbox-metadata-api-uart-20261112-r1`, plan
`sandbox-metadata-api-plan-20261112-r1.json` and independent readback
`sandbox-metadata-api-readback-20261112-r1` retain the two-entry export, archive
SHA256 `66e6384ddf5793c31253d136ecf6ef2b3d19b94f5e15588aa3b22bdad674fc2e`.
Caller inspection `vending-sandbox-metadata-caller-20261112-r1` confirms
aqxh.l reads that field directly after its platform-version gate. The test
bind mount was released before broker preparation and the next Maps attempt.
This successor uses `d5adecec5` plus this commit's source changes.

Guest r25's Maps attempt exited before onboarding. It reported a missing
Build.VERSION.BASE_OS in a failed GMS-compliance future, and an uncaught
IllegalAccessError in Play Store amli when referencing the package-private
IPackageDeleteObserver placeholder. Its full log delimiters are
`SANDBOX-METADATA-MAPS-LOG-BEGIN` / `END`; snapshot
`maps-sandbox-metadata-uart-20261112-r1` has full-log SHA256
`aa632a8b32ba3de3d3ac0e3299f4a4dd2257ca052e7fcb68c8120e27d7fc4383`.
`vending-delete-observer-caller-20261112-r1` retains amli's reflective method
lookup and biwu's BASE_OS read. No ENOSPC occurred in the exported Maps log;
the observer sampled available storage down to162136064 bytes. This run's
observer was stopped with its verified VM after the app exited, rather than
waiting for another ten-minute diagnostic completion.

`framework_build_base.v` adds public static final BASE_OS, initialized once
from SystemProperties.get("ro.build.version.base_os", ""), matching the
[Android build-field contract](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r1/core/java/android/os/Build.java).
No base OS build is invented when that property is absent.
`framework_package_observers.v` replaces the inaccessible concrete placeholders
for IPackageDeleteObserver and IPackageDataObserver with public interfaces
extending IInterface and declaring packageDeleted/onRemoveCompleted, following
the [delete callback](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r1/core/java/android/content/pm/IPackageDeleteObserver.aidl)
and [data callback](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r1/core/java/android/content/pm/IPackageDataObserver.aidl)
contracts. The retained amli constructor references both types in adjacent
reflective lookups, so both are included in the same successor.
It adds no package-delete authority, remote observer protocol or uninstaller.
The existing deletePackage stub is unchanged and is not qualified as deletion.

SDK `framework-build-observer-20261112-r1` passed full assembly/readback in
4296ms, RSS460488704 and shared growth85291008 bytes, guard/child0/0 with
complete cleanup. Signed fixture r22 checks field visibility/modifiers and
property agreement, public interface access, a fixture Binder implementation,
queryLocalInterface/asBinder identity and a manually invoked callback's
arguments/count. No package-deletion request is made. This narrower
intermediate was not qualified on ARM. Guest r26 booted it but ran no API regression
or broker retry; it was stopped after verifying its QEMU identity. The final
successor adds both observer types, fixture r23 and guest r27, retaining the
same core/native/VM resource configuration.

SDK `framework-build-observers-20261112-r2` (plural observers) passed guarded
full assembly/readback in5104ms, RSS478134272 and shared growth50933760 bytes,
guard/child0/0 with complete cleanup. Fixture r23 adds a separate data-observer
Binder implementation and tests its interface access, local descriptor and
Binder identity, callback package, false result and count. Both callback
tests are manual local calls; they claim no deletion, data removal or remote
service operation. Guest r27 stages this final SDK/fixture pair.

Fixture r23 passed on ARM in r27 with all earlier checks, runner readiness,
pass, EOF drain and exit0. Snapshot `build-observers-api-uart-20261112-r1`, plan
`build-observers-api-plan-20261112-r1.json` and independent readback
`build-observers-api-readback-20261112-r1` retain its two-entry export, archive
SHA256 `3e67d0ae409ed667bed78dd450e1f0f72b7a42617c5508fa000035da2dc72726`.
The fixture bind was released before broker preparation and another desktop
Maps launch. This successor uses `ac898f13c` plus this commit's source changes.

Guest r27 rendered onboarding with the observer fixes. After Skip, its actual
Maps database writes failed with SQLiteFullException; DeviceDoctor logged the
error and the app called killProcess on itself (the bridge emitted VM-EXIT0).
The observer completed at600033ms with minimum filesystem availability0 and
MemFree81856KiB. The full Maps log has no prior linkage failures; delimiters
are `BUILD-OBSERVERS-MAPS-LOG-BEGIN` / `END`. Immutable snapshot
`maps-build-observers-uart-20261112-r1` has SHA256
`c1c0dda440d682c3888e8b32c0b32155384016ad4f327bae237b3e1476c3a93f`.

The guest stager now optionally creates an8GiB sparse ext2 app-data image,
records its initial full checksum, UUID, formatter command and executable
identities, and attaches it as a separate virtio block device. The file is
0600; root ownership and the ext2 feature set follow the existing ARM desktop
test formatter. Launch verifies the initial image checksum. Host hashing
reuses the existing streaming CommonCrypto/portable implementation; there is
no compiler revision requirement. VINIX_CURRENT_APP_DATA_DISK=1 selects this
path and VINIX_CURRENT_DATA_VOLUME_PROBE supplies the current ARM probe.

`maps-data-volume.v` selects the disk by UUID/size rather than enumeration
order. Its root-only mount path refuses to hide an existing device/mount or
nonempty app-data directory. It verifies ext2 and rw/nosuid/nodev/wxallowed,
root-owned0755 directories and fresh capacity, then writes, flushes, syncs,
renames, reads back and removes a1MiB probe. It mounts only
/var/lib/vinix/apps, preserving the broker's paths and identity checks.
`--inspect` supplies read-only host identity checking; the stager's `--hash`
mode retains mutable-image audit checksums after shutdown.

The first r28 staging attempt rejected a valid formatted image because the
new helper incorrectly combined seek with read_bytes, which reads from the
file beginning. Both host and ARM readers now use explicit-offset reads.
r28 was not booted; its guard/child1/1 and complete cleanup are retained.
Its empty data image checksum is
`10e6c3e2fae596f0b0bae36b12524d7600721959dd00993323767c8da25a4f53`.
Guest r29 rejected the probe's buffered raw-device read before mounting.
Vinix requires sector-aligned block reads; the probe now uses direct pread
of512 bytes at offset1024. Host inspection accepts the selected UUID and
rejects another image. Guest r30 then mounted the selected disk and wrote,
synced and renamed its1MiB file, but the helper failed during readback despite
MemFree8421600KiB and7.9GiB disk availability. Guest wc and sha256sum read the
complete file successfully. Snapshot `data-volume-readback-uart-20261112-r1`
SHA256 `681cfd704f1783f342db68ed6908c96d8658682c21a08d06f162c5c4a6409a5c`
retains the failure and independent reads. The leftover file is retained in
r30's image, final SHA256
`25ab38b3320c83afb47daf0e71a70b89e217559e59df824da4142afb864fce06`.

Final volume probe r7 uses a bounded byte-for-byte pread loop and a literal
disk_usage path: current V's os.disk_usage frees its path argument, so passing
the decoded metadata string invalidates borrowed storage. This short-lived
probe uses -gc none without autofree, closes its descriptors and explicitly
frees the large buffers. Stager r5 and both host/ARM probes compiled with
current V0.5.2 596e18d. No SDK/native/core change was required.

Guest r31 staging passed the original guard limits: child/guard0/0, cleanup
complete,10197ms, RSS36995072 and shared growth233627648 bytes. Read-only
e2fsck and UUID inspection passed; the wrong-volume input was rejected.
Its initial image SHA256 is
`12285ce681d6100c9ba2bc7d43f7806af55886bb0162be8c59741db451adabca`.
ARM mounting passed exact flags/ownership/capacity and write/flush/fsync/
rename/readback/removal with8522207232 bytes available.

Signed fixture r24 adds a native SQLite1MiB write, database close/reopen,
length/file-size readback and cleanup. The complete regression passed as
UID/GID10160 with private data at /var/lib/vinix/apps/current-api-r1 on the
new disk, ready/pass once, drained EOF and exit0. Immutable snapshot
`data-volume-api-uart-20261112-r1`, plan `data-volume-api-plan-20261112-r1.json`
and current-source independent readback `data-volume-api-readback-20261112-r1`
retain its two-entry export, archive SHA256
`69353619f3c986d24390fbe0e6ff4e9df0d1abde9aa1c320ff3e9112de080bc3`.
An older reconstructor correctly rejected the newer plan format; the current
source accepted it without byte removals. The fixture bind was released
before the next broker run. These checks establish disk and SQLite behavior,
not Maps tiles, search, routes or login.

Guest r31 rendered onboarding on the disk-backed data path. After Skip,
Play Store code loaded inside Maps called getSystemSharedLibraryNames and
immediately Arrays.asList on the result: `wtt.a` source514, via `anag.a`,
`anam.b`, `anal` and background executor `tqv`. The null catalog caused an
uncaught NPE and the GMS crash handler killed the process. The complete log
is between DISK-DATA-MAPS-LOG-BEGIN/END in immutable snapshot
`maps-disk-data-final-uart-20261112-r1`, SHA256
`4180ee0f79eda3bc664220ffcedb3b36376ff3a63416b944b5635057c52f60ab`.
Minimum observed disk availability was7953289216 bytes. Memory was tight
(minimum MemFree35600KiB), but this exit has a specific Java exception;
it is not evidence of an OOM kill. The observer was stopped with the owned
VM before its600-second deadline. Caller readback is retained at
`vending-package-state-caller-20261112-r1/classes3.dex/wtt.smali`.
The synced, stopped r31 data image has final SHA256
`0c691b38695dbbb35411308d3c2113bb6ecea864b04c58ef83c055637ceefa4f`.

`framework_shared_library_catalog.v` deliberately normalizes the empty
Android shared-library catalog to a fresh empty String array, allowing direct
enumeration by this caller. It advertises no host ELF libraries, APK-private
modules or nonexistent Android library. This is a Vinix compatibility choice:
[Android's API permits null for an empty catalog](https://developer.android.google.cn/reference/android/test/mock/MockPackageManager#getSystemSharedLibraryNames()),
and [AOSP returns null for an empty name/path map](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/pm/IPackageManagerBase.java).
The normal SDK generator and current additive builder both install it.

SDK `framework-shared-libraries-20261112-r1` passed full assembly and selected
DEX readback under the original caps: guard/child0/0, complete cleanup,
3661ms, RSS471629824 and shared growth45236224 bytes. Signed fixture r25
checks the actual Arrays.asList call, zero size and fresh array identity,
alongside all earlier regressions. Its build/sign/verify guard passed0/0
with complete cleanup,974ms, RSS126861312 and growth364544 bytes. Guest r32
stages this SDK and fixture with the unchanged native/core and disk probe r7.

Guest r32 passed the complete signed fixture r25 as UID/GID10160, with its
private directory on the selected disk: readiness/pass once, EOF and exit0.
Snapshot `shared-library-api-uart-20261112-r1`, plan
`shared-library-api-plan-20261112-r1.json` and independent strict readback
`shared-library-api-readback-20261112-r1` retain the two-entry export, archive
SHA256 `e4858cc2d9345d59859d469830712e80fabea3aafef026ca59963ff85c6a4a84`.
The fixture bind was released before broker startup. Actual Maps qualification
continues with this SDK; no map-rendering claim follows from the fixture.

Guest r32 rendered onboarding, then exited10 after Skip on
PackageInstaller.getStagedSessions, called by `aukd.e` through an API outline.
The prior null-library-catalog exception is absent. It also logged missing
JobInfo.getMinLatencyMillis in `assk.b` source193. Caller inspection shows the
same sequential path immediately reading maximum execution delay, charging,
idle and network type; the successor supplies all five metadata getters.
Readback is at `vending-job-stage-caller-20261112-r1/classes.dex/assk.smali`
and `classes4.dex/aukd.smali`. An earlier disassembly invocation selected
mistyped class names and supplies no caller evidence.

The complete log is between SHARED-CATALOG-MAPS-LOG-BEGIN/END in immutable
snapshot `maps-shared-catalog-final-uart-20261112-r1`, SHA256
`e145dc4b3f3f08a6956e088dddcf9369b137112738e4e9c9a3f22af95fb1b280`.
The read-only observer sampled minimum disk availability7952793600 bytes and
MemFree33680KiB before verified shutdown at roughly473 seconds. No complete
600-second observation is claimed. The synced, stopped data image has SHA256
`f7c88391f680cab40c5f37eb410f5075e9719ed269c6f52cb3ef641b7dccf3b3`.

`framework_job_install_queries.v` returns a fresh empty staged-session list
for the deployment with no installer session service. It adds no install
operation. This matches the non-null query shape in the
[PackageInstaller reference](https://developer.android.com/reference/android/content/pm/PackageInstaller#getStagedSessions()).
JobInfo.getMinLatencyMillis reads existing builder storage. The four adjacent
getters retain the values passed to the corresponding existing builder setters
instead of fixed answers. Zero/false defaults follow the
[JobInfo builder fields](https://android.googlesource.com/platform/frameworks/base/+/4123f9587dc6eb4dfadc7d9910d822afced1c13e/core/java/android/app/job/JobInfo.java).
These are metadata reads, not qualification of scheduler constraint enforcement,
periodic validation, parcels or builder snapshot immutability.

The narrower SDK r1 and fixture r26 built but were not run on ARM. SDK
`framework-job-install-20261112-r2` adds the full observed getter sequence and
passed full SDK assembly/selected DEX readback under the original caps:
guard/child0/0, complete cleanup,5088ms, RSS514752512, growth60370944 bytes.
Signed fixture r27 checks empty-session mutation isolation, zero defaults,
64-bit latency/deadline values, distinct builder values and boolean/network
updates. Its build/sign/verify passed guard/child0/0, complete cleanup,
1208ms, RSS142213120 and growth286720 bytes. Guest r33 stages that final pair,
with the unchanged native/core, volume probe and VM resource budget.

The complete signed r27 fixture passed on ARM in r33 as UID/GID10160 with
private disk-backed data, readiness/pass once, drained EOF and exit0.
Snapshot `job-install-api-uart-20261112-r1`, plan
`job-install-api-plan-20261112-r1.json` and strict independent readback
`job-install-api-readback-20261112-r1` retain its two-entry export, archive
SHA256 `154ef88682a03c9d6c802c3e42aaf7f9cd2025200034387407b79119824171c5`.
The fixture bind was released before broker startup and the next Maps retry.

Guest r33 advanced past onboarding to the real Explore screen with Search
here, map controls, Local vibe and navigation tabs (`maps-after-skip.png`).
The map region remained empty. The process then failed its main looper on
JobParameters.getJobId in Play Store `asuf.onStartJob`, called from the
existing JobScheduler callback. The bridge disconnected; there is no clean
Maps exit or map-tile qualification. Prior job getter and staged-session
linkage failures are absent. Caller readback is retained at
`vending-job-parameters-caller-20261112-r1/classes.dex/asuf.smali`.

Immutable snapshot `maps-job-install-final-uart-20261112-r1` has SHA256
`0842e579f0551212605e2bf06cf104d348c0e6f4ebf5e86775bd5c7a2cc6e140`.
Full app log markers are JOB-INSTALL-MAPS-LOG-BEGIN/END. The watcher sampled
minimum disk7952642048 bytes and MemFree33792KiB before verified shutdown at
about359 seconds; no600-second stability result is claimed.
Its synced, stopped data image has SHA256
`ef87c2be044c1ca686be1bb6835b624f0662e9b61d0b08a9f824b5bf6cdcfac8`.

`framework_job_parameters.v` returns the ID from the JobInfo already carried
by the scheduler's JobParameters object. It changes no scheduling behavior.
The signed fixture now declares a non-exported BIND_JOB_SERVICE service in
its own generated manifest, schedules a zero-latency one-shot job and checks
the real onStartJob callback's ID, extras and exactly-one count before its
existing main-queue pass fence. It also checks that the callback is queued,
not inline. There is no reflective constructor access or undeclared service.

SDK `framework-job-parameters-20261112-r1` passed guarded full assembly and
DEX readback: guard/child0/0, complete cleanup,4768ms, RSS464896000 and shared
growth29405184 bytes. Signed fixture r28 build/link/sign/verify passed0/0,
complete cleanup,1737ms, RSS138297344 and growth25059328 bytes. Guest r34
stages that pair under the unchanged native/core, volume probe and VM budget.

The complete signed r28 fixture passed on ARM in r34 as UID/GID10160,
including the real scheduled callback, ready/pass once, drained EOF and exit0.
Snapshot `job-parameters-api-uart-20261112-r1`, plan
`job-parameters-api-plan-20261112-r1.json` and strict independent readback
`job-parameters-api-readback-20261112-r1` retain its two-entry export, archive
SHA256 `1c2746eb7b06924d8fef255c6b1a9c10abf97c8b7d1bc5b14c6136fdda556999`.
The fixture bind was released before the broker retry.

Guest r34 loaded Explore and Local vibe's "The foodie drop" content after
Skip (`maps-after-skip.png`), then exited10 while the Louvre search was being
entered. The fatal exception is missing TelephonyManager.getImei in GMS
check-in `biyz.a` source180, not the search UI. It also logged a missing
JobParameters.isOverrideDeadlineExpired query in Play Store's job controller.
The prior getJobId main-looper failure is absent. Caller readback at
`gms-checkin-identifiers-caller-20261112-r1/classes.dex/biyz.smali` shows slot
enumeration followed by the no-argument IMEI fallback, wrapping its result in
an optional. No identifier was supplied or manufactured.

Immutable snapshot `maps-job-parameters-final-uart-20261112-r1` has SHA256
`e9702441c164b0b56fa49d716a2404817be91bb2d56040b5c9e0d906ea5e1bc2`;
log markers are JOB-PARAMETERS-MAPS-LOG-BEGIN/END. The observer sampled
minimum disk7951372288 bytes and MemFree42688KiB before verified shutdown at
about374 seconds. The synced, stopped image SHA256 is
`885866a812d48ef196f08f449767b8746ed028afa0713fe6e2c5adbe43a5df09`.

`framework_modem_identifiers.v` provides IMEI/MEID query overloads returning
null for this runtime without modem or SIM slots, consistent with the
[unavailable identifier result](https://developer.android.com/reference/android/telephony/TelephonyManager#getImei()).
No hardware feature or identifier backend is added. JobParameters' deadline
query returns false because the current scheduler dispatches on minimum
latency and has no deadline-forced execution path. This describes the
[reason for dispatch](https://developer.android.com/reference/android/app/job/JobParameters#isOverrideDeadlineExpired()),
not a wall-clock comparison or deadline-enforcement implementation.

SDK `framework-modem-job-20261112-r1` passed guarded full assembly and DEX
readback: guard/child0/0, cleanup complete,4672ms, RSS465272832 and shared
growth33198080 bytes. Signed fixture r29 adds zero-phone/absent-feature and
null identifier checks for no-argument and slots-1/0/1, plus false deadline
reason during its real latency-triggered callback with a future deadline.
Its build/sign/verify passed0/0, cleanup complete,1540ms, RSS117227520 and
growth21749760 bytes. Guest r35 stages that final pair with unchanged
native/core, volume probe and VM resource budget.

Signed fixture r29 passed on ARM in r35 as UID/GID10160 with disk-backed data,
including the real callback's false deadline reason and absent modem queries,
readiness/pass once, drained EOF and exit0. Snapshot
`modem-job-api-uart-20261112-r1`, plan `modem-job-api-plan-20261112-r1.json`
and strict independent readback `modem-job-api-readback-20261112-r1` retain
the two-entry export, archive SHA256
`81ff2036558ae93b3dae7966ad3c65a7a519c9981660fd87e3f4c6bb6693ceee`.
The fixture bind was released before broker startup.

Guest r35's actual retry ended before onboarding when the native app host's
response pipe closed. Desktop logged a failed poll after49ms and app-host
status0, then the account controller detected changed ancestry and cleaned up
its owned processes. The final receipt reports failed status and2 cleanup
survivors, so no complete controller cleanup is claimed. The complete Maps
log has no new uncaught Java failure before that shutdown. This does not
establish the cause of the app-host exit or qualify the map screen.

Immutable full snapshot `maps-modem-host-final-uart-20261112-r1` has SHA256
`067193544b6b3c142cd4e45ef6d9c46578a00d2fbec98bdae2fe763feb8c9bf7`.
Its full app log is between MODEM-JOB-MAPS-LOG-BEGIN/END, followed by the
literal final controller receipt between MODEM-HOST-RECEIPT-BEGIN/END.
The earlier append-proof snapshot `maps-modem-host-uart-20261112-r1` retains
the complete controller export too. The existing no-removal planner rejected
noncanonical frame fields; no reconstructed controller archive is claimed and
no checker was weakened. Its minimum observed disk was7953838080 bytes and
MemFree37088KiB. Guest r36 repeats the same SDK/native/core/fixture binaries
with a fresh data image; the already-passed API regression need not be rerun.
The synced, stopped r35 image has final SHA256
`18c8bb612590219639ba07a337dab0bb6c3f6f63bfe436cb37a35fc47b2965c1`.
Guest r36 staging passed guard/child0/0 with complete cleanup,8818ms,
RSS36814848 and shared growth137330688 bytes; read-only filesystem/UUID
inspection and ARM volume write/readback passed before broker preparation.

Guest r36 repeated the same SDK/native/core/fixture set with fresh disk-backed
data. It passed onboarding rendering and exited after Skip on a main-looper
NoClassDefFoundError for android.app.usage.StorageStatsManager, used as a
class literal by Play Store `amne.<init>` source74. That constructor calls
typed getSystemService, casts its possibly null result and wraps it with
Optional.ofNullable; an unavailable service is explicitly supported. Caller
readback is `vending-storage-stats-caller-20261112-r1/classes.dex/amne.smali`.
The r35 native app-host pipe failure did not reproduce; this does not establish
its cause or repair. The previous IMEI and job-deadline linkage failures are
absent from this complete Maps log.

Snapshot `maps-modem-repeat-final-uart-20261112-r1` has SHA256
`58154b8cfc46a8231c054c9dc69cd3d3e4fd8a8f13fadbc97be67bc78af3f273`;
log markers are MODEM-REPEAT-MAPS-LOG-BEGIN/END. The observer sampled minimum
disk7952162816 bytes and MemFree34480KiB before verified shutdown at about344
seconds. No600-second stability observation is claimed.
The stopped r36 image SHA256 is
`6b48beba6e30a39df1378ceb92491da2de9aea1c0a6debf3c15732b24d0d7282`.

`framework_storage_stats_type.v` makes the public API class resolvable and
adds Context.STORAGE_STATS_SERVICE with its
[documented name](https://developer.android.com/reference/android/content/Context#STORAGE_STATS_SERVICE).
This is type availability for the caller's optional path, not a storage
accounting implementation. The runtime registers no instance or statistics
backend, exposes no per-package data and invents no byte counts. The signed
fixture checks the class literal, cast of null, Optional.empty result,
service-name constant and both typed/string lookup absence.

SDK `framework-storage-stats-20261112-r1` passed guarded full assembly and
DEX readback: guard/child0/0, complete cleanup,3188ms, RSS480919552 and shared
growth36077568 bytes. Signed fixture r30 build/link/sign/verify passed0/0,
complete cleanup,1053ms, RSS126418944 and growth26378240 bytes. Guest r37
stages that pair with unchanged native/core, volume probe and VM resources.

The r37 API regression correctly failed: the generic typed-service fallback
tries the first public constructor of unknown classes. StorageStatsManager
has no public SDK constructor, so lookup threw ArrayIndexOutOfBoundsException
instead of returning absent. Snapshot `storage-stats-api-failure-uart-20261112-r1`
has SHA256 `7044a5eddfcc91076c07ef444ebb6c63ff9e3fa3b2ac6f4d3c5c985aa50fe42c`.
No broker or Maps retry used this unqualified intermediate SDK.

The final adapter explicitly returns null for just this type/name before the
generic fallback, preserving other services. SDK
`framework-storage-stats-20261112-r2` passed guarded full assembly/readback,
guard/child0/0, complete cleanup,3732ms, RSS474398720 and shared growth47915008
bytes. Guest r38 retains the same signed fixture r30 to qualify the repair.
The stopped intermediate r37 image has SHA256
`43ba94021354af0ef553ac92f8b4a58f1768ec3bc42b06743a3261008d2b4215`.

The complete signed r30 fixture passed on ARM in r38 as UID/GID10160 with
disk-backed data, ready/pass once, drained EOF and exit0. Both service lookup
forms returned null and the caller's optional pattern completed. Snapshot
`storage-stats-api-uart-20261112-r1`, plan
`storage-stats-api-plan-20261112-r1.json` and strict independent readback
`storage-stats-api-readback-20261112-r1` retain its two-entry export, archive
SHA256 `6eb8fe4ee4308327e34a5c0c8c25b11870341d6988177d6024a29385f398c13e`.
The fixture bind was released before broker preparation and the Maps retry.

Guest r38 rendered onboarding and exited10 after Skip on missing
Build.getSerial in GMS `bjaa.a` source17. That caller explicitly catches
SecurityException and falls back to an absent serial; it does not catch a
linkage error. Readback is `gms-build-serial-caller-20261112-r1/classes.dex/bjaa.smali`.
It also logged an asynchronous missing SSLSessionCache(Context) constructor
in Play Store `bosv.<init>` source88, retained at
`vending-ssl-cache-caller-20261112-r1/classes.dex/bosv.smali`. The previous
StorageStatsManager failure is absent from the complete log.

Snapshot `maps-storage-stats-final-uart-20261112-r1` has SHA256
`a30eec2d07363c9f1910b3e8f016288894e940d895136a5b88fa35a3c2d4c5b8`;
log markers are STORAGE-STATS-MAPS-LOG-BEGIN/END. Minimum disk was7947096064
bytes and MemFree34000KiB before verified shutdown at about482 seconds.
No600-second or functional map/search result is claimed.
The synced, stopped r38 image has SHA256
`621ab22013d9ec4839706473c4b99824c94276cfb3d78d8e03c848d2956c52c6`.

`framework_serial_tls_cache.v` adds getSerial with explicit SecurityException:
this deployment has no authorized hardware-serial service. No host identifier
or fabricated serial is returned. The caller's denial handling follows the
[Build API contract](https://developer.android.com/reference/android/os/Build#getSerial()).
The SSLSessionCache context overload requests getDir("sslcache", MODE_PRIVATE)
and delegates to the existing File overload, following the directory selection
in [AOSP](https://android.googlesource.com/platform/frameworks/base/+/27f592d/core/java/android/net/SSLSessionCache.java).
That existing overload has no persistence backend. This change supplies the
constructor and directory selection, not session resumption or caching; socket
factories, trust stores, hostname and certificate verification are unchanged.

SDK `framework-serial-cache-20261112-r1` passed guarded full assembly and DEX
readback, guard/child0/0, complete cleanup,9636ms, RSS482000896 and shared
growth180051968 bytes. Signed fixture r31 checks direct serial denial,
getDir name/mode/count through a recording ContextWrapper, the actual private
directory and null-context rejection. Build/link/sign/verify passed0/0,
complete cleanup,2355ms, RSS130007040 and growth62132224 bytes. Guest r39
stages that pair with unchanged native/core, volume probe and VM resources.

The complete signed r31 fixture passed on ARM in r39 as UID/GID10160 with
disk-backed data, readiness/pass once, drained EOF and exit0. Snapshot
`serial-cache-api-uart-20261112-r1`, plan `serial-cache-api-plan-20261112-r1.json`
and strict independent readback `serial-cache-api-readback-20261112-r1` retain
its two-entry export, archive SHA256
`5a57c75a4dc800e8de01e3dc18fb1a0417ec1adf6171e1f0651e91d635ba1715`.
The fixture bind was released before broker preparation.

Guest r39 passed the full signed API fixture and rendered onboarding in the
actual Maps retry (`maps-onboarding.png`). Before Skip could be qualified,
host free space fell to2.1GiB amid ongoing shared filesystem writes. Only the
verified owned QEMU was stopped. No subsequent map/search/routing/login or
clean Maps exit is claimed. Its private RAM-backed Maps log was not exported
before shutdown, so this attempt cannot identify another runtime failure.
Immutable snapshot `maps-serial-cache-blocked-uart-20261112-r1` has SHA256
`302d8d2cecd4f80ffea15788bb9c5bd92ca959dae80038c016e37dfa0ceb142b`;
the stopped raw data image has SHA256
`d8fcf0a64f112330d841f5eb1847ac5519ec09bf40cc9847fcc04e982dcddf28`.
Read-only inspection retained a native-crashloop marker but no stack trace;
the marker alone does not establish a native crash or its cause.

Host-space samples `host-space-after-r39-stop-1.log` through `-6.log` retain
the subsequent recovery. The last three were21556308,22781740 and25040008KiB
free, above20GiB and increasing. Guest r40 therefore repeats the same already
qualified SDK/native/core/fixture set with a fresh disk. Its diagnostic bundle
will be placed on that disk before broker preparation, preserving private
logs if another host-pressure stop is needed. No identity check is relaxed.

Guest r40 staging passed guard/child 0/0 with complete cleanup: 14587ms,
RSS 37224448 bytes and shared growth 13930496 bytes. Broker preparation
accepted the disk-backed diagnostic bundle and printed ACCOUNT-READY.
After onboarding and Skip, Explore/search controls rendered, then the main
looper failed with StackOverflowError. View.forceLayout called virtual
requestLayout, which forwarded to TableLayout.requestLayout, which forces
each child again. Snapshot `maps-force-layout-final-uart-20261112-r1` has
SHA256 `a1a8ddda91d88911469d014531b1173003e0d809bdc872aff367479c34f59bf3`.

After syncing and stopping only verified owned QEMU PID44587, read-only
debugfs exported `maps-current-20261112-r40/maps.retained.log` from
`/.maps-account/results/maps.log`, SHA256
`d5642ed5343c6b639118c7f7b17264efa9a2a9dccd2a35f41d8d3ebc6a624fdf`.
The stopped image has SHA256
`ec1aa8e47aebb01f5313a46efd6533899c904ffff4fa5923a83b285fa91b2ab0`.
This complete log also retains the asynchronous missing
SSLCertificateSocketFactory.getDefault(int, SSLSessionCache) call in Play
Store bosr.a. No TLS security behavior was changed to bypass that failure.

`framework_force_layout.v` marks the view's existing measurement request
flag directly, without scheduling traversal or calling virtual requestLayout
on either the view or parent. This follows the
[Android contract](https://developer.android.com/reference/android/view/View#forceLayout()).
The signed fixture adds a counting TableLayout child, unchanged-spec
remeasurement checks and a joined worker-thread forceLayout check. It
requires zero child/parent request callbacks for forceLayout and checks
that a subsequent table request forces its child without recursion.

SDK `framework-force-layout-20261112-r1` passed full assembly/selected DEX
readback under the original caps: guard/child 0/0, complete cleanup, 3527ms,
RSS 469680128 and shared growth 350302208 bytes. Signed fixture r32 passed
build/link/sign/verification: 0/0, complete cleanup, 1255ms, RSS 137052160 and
shared growth 24563712 bytes. Guest r41 stages these for ARM validation.

The complete signed r32 fixture passed on ARM in r41 as UID/GID10160,
readiness/pass once, drained EOF and exit0. The table regression completed
with no recursion, both forceLayout callers avoided request callbacks, and
unchanged-spec measurement ran again only when forced. Snapshot
`force-layout-api-uart-20261112-r1`, plan
`force-layout-api-plan-20261112-r1.json` and independent strict readback
`force-layout-api-readback-20261112-r1` retain its two-entry export, archive
SHA256 `a77d51aa3934e06ef5d6802556c2597fa96bbcca9079fa88215dc7271c7ecbac`.
The fixture bind was released before broker preparation and the Maps retry.

Guest r41's Maps retry rendered onboarding but went blank after Skip.
The complete disk-retained log records an uncaught GMS check-in call to
UserManager.isGuestUser at bpiq.m source11, with no repeated layout overflow.
Read-only exported `maps-current-20261112-r41/maps.retained.log` has SHA256
`924e32a2530863d3bd7e28061115ec4d99be708fd570bbd8a5ba119395523d8d`.
Its stopped data image has SHA256
`61f3e04f0000ddb9fada9d481414681a01a2c02cc49a1a83d293dfc65bdceb85`.
Snapshot `maps-guest-user-final-uart-20261112-r1` has SHA256
`1b6358dc97c25e5f348c7ed69a5663ebeb43d835bac4d4d18ac3f2c98f96fcc7`.
Only the verified owned QEMU PID67288 was stopped after syncing. Minimum
observed disk was7253815296 bytes and MemFree48752KiB. Functional Maps
qualification remains pending.

`framework_guest_user.v` returns false for this backend's one persistent
Android system user; no guest-user backend exists. Exact GMS caller readback
is `gms-guest-user-caller-20261112-r2/bpiq.smali` at isGuestUser source11.
An initial diagnostic invocation omitted the descriptor delimiters and did
not produce a class; the corrected readback reuses its extracted DEX.

`framework_certificate_factory.v` supplies the observed secure
SSLCertificateSocketFactory.getDefault(int, SSLSessionCache) entry and its
timeout constructor/default overload. It delegates to the existing default
JSSE context, retaining its trust policy. Host-name overloads complete the
handshake and check the default HTTPS hostname verifier before returning.
Address-only and unconnected overloads retain Android's caller-owned hostname
verification requirement. The socket wrapper applies the handshake timeout
to explicit and first-I/O handshakes, restores the application's read timeout
on success and closes failed transports. No insecure factory or trust-manager
override is added. The optional cache retains its existing inert backend.
Contract: [Android secure socket factory](https://developer.android.com/reference/android/net/SSLCertificateSocketFactory).

The deterministic signed probe covers first read/write handshake dispatch,
explicit handshake, read-timeout restoration, failure cleanup, socket options
and the unconnected factory. The optional `--certificate-network` fixture
adds trusted Google HTTP, wrong-host rejection and self-signed-chain rejection.
Only certificate-specific failures can satisfy rejection: a certificate
exception cause, the exact wolfSSL self-signed error -275 or no-signer error
-188. DNS failures, timeouts, generic SSL errors and successful connections
cannot pass. The native no-signer meaning is documented by
[wolfSSL](https://www.wolfssl.com/documentation/manuals/wolfssl/appendix06.html).

Guest r42 used SDK `framework-certificate-20261112-r2`. Its first fixture r34
rejected self-signed TLS but the new test required a nested CertificateException;
wolfSSL supplied the specific native SSLHandshakeException without that cause.
The corrected r35 fixture passed the complete API suite and live TLS checks
as UID/GID10160, ready/pass once, drained EOF and exit0. Snapshot
`certificate-network-api-uart-20261112-r1` and strict readback
`certificate-network-api-readback-20261112-r1` retain archive SHA256
`2271670243fdc1a24f269f13062d5e6d5766ad14f95b188c3a1de33d884c4660`.

The next combined test passed the stalled-peer timeout but failed a later
negative-case assertion without retaining its underlying certificate detail.
The revised diagnostics retain the native error and endpoint, and the final
fixture repeats both rejection cases three times. No historical checker was
changed. The r37 fixture passed timeout, trusted HTTP and both rejection cases
in r42. `certificate-stall-server.v` recorded the ClientHello and withheld the
handshake for ten seconds; the client required SocketTimeoutException within
five seconds and a closed transport with its 250ms factory timeout.
Snapshot `certificate-stall-api-uart-20261112-r1` retains the exact append
interval after the earlier receipt; strict readback
`certificate-stall-api-readback-20261112-r1` retains archive SHA256
`8536544f9bc5445823a07e7146d4524b8a3aed49af25e1908a6cee14db7f2c2e`.
The read-only exported final child log has SHA256
`a57d9ce06a162d90f8a7aa6a2bc86c5a2dcc110e880c22a5ebf8ef1b9127b593`.
The synced, stopped r42 disk has SHA256
`b8a463789404d70c8a3a1ec639c5bd05af9b8f857570c7ac5eb99111e4f581f3`.
No Maps retry used r42. The single-use loopback `current-fixture-serve.v`
delivered replacement signed APKs; host and guest SHA256 matched before each
run, and the runner retained their actual identities independently.

Final SDK `framework-certificate-20261112-r3` also rejects non-SSL arguments
to verifyHostname with IllegalArgumentException without closing the caller's
plain socket. Full SDK assembly/readback passed under the original caps:
0/0, complete cleanup, 3734ms, RSS469172224, shared growth31453184 bytes.
Final signed fixture r39 adds that regression and three rejection pairs;
build/link/sign/verification passed0/0, complete cleanup,1070ms,
RSS142000128 and shared growth17125376 bytes. ARM qualification is pending.

Staging r43 stopped at the original shared-growth cap: 547020800 bytes
observed, guard125, child-1, cleanup initially incomplete. A subsequent
process check found no surviving selected group6250 or staging process;
`certificate-stage-cleanup-followup-2.log` preserves that check. No r43 VM was
started and no failed image was reused. The caps remain unchanged.

Fresh staging r44 passed0/0 with complete cleanup under those same caps:
5792ms, RSS36929536 and shared growth206790656 bytes. Host UUID inspection,
read-only e2fsck and initial-image hash verification passed before boot.
The first r44 test passed timeout, trusted HTTP and two rejection pairs, but
the third self-signed connection ended with native socket error -308 instead
of a certificate verdict. It correctly failed qualification. The fixture
now retries only that exact transport error, on a new connection, at most
three attempts per case. It still requires three successful rejection pairs;
no socket error is counted as a certificate rejection.

Final signed fixture r40 passed build/link/sign/verification under the
original caps:0/0, complete cleanup,1394ms, RSS106315776 and shared growth
18780160 bytes. The complete fixture passed on ARM in r44 as UID/GID10160,
ready/pass once, drained EOF and exit0, including the plain-socket contract
and all three rejection pairs. Snapshot `certificate-final-api-uart-20261112-r1`,
plan `certificate-final-api-plan-20261112-r1.json` and strict independent
readback `certificate-final-api-readback-20261112-r1` retain archive SHA256
`ceb98bfd45e1c3419720442b5d13d4053c7b016d2e0be0c088c294abdb052603`.
The runtime SDK SHA256 matches the host artifact
`5ea39caa3fa81f62aaddad082f8fb4494aaf3f0c822f0dbaa7850c4baba05cfa`.
The fixture bind was released before broker preparation. Actual map tiles,
search, routing and login remain unqualified.

With source `f7add1d38`, guest r44 rendered onboarding and exited after Skip
on ClassCastException in MultiUserCoordinatorService.onCreate: its graph rsz
does not implement the expected akab entry point. The installed manifest
declares that service in `:background` with singleUser=true. Caller readback
is `vending-multiuser-caller-20261112-r2`; the preserved manifest dump is
`vending-manifest-20261112-r1.txt`. Named services currently share ART, so this
secondary-service creation exception escaped into the primary Maps looper.
No missing serial, cache, guest-user or socket-factory linkage error recurred.

The log also records Bundle rejecting a GMS
OnSyncCompletedListener$Receiver because the ResultReceiver placeholder did
not implement Parcelable. Fresh caller readback
`gms-result-receiver-caller-20261112-r2/classes7.dex` confirms that subclass's
ResultReceiver superclass. Complete r44 Maps log
`maps-current-20261112-r44/maps.retained.log` has SHA256
`2dc1f29822fcdbb89e8a0da68dc2452c2677bb0f37c35bc1db0eff248105e0be`.
Stopped disk SHA256 is
`639dfd1ddff21073cd758cc03bc86d2f2eb5f1de31fba9c0746e24580ee58728`;
snapshot `maps-multiuser-final-uart-20261112-r1` has SHA256
`d9fb3b31d96144e2cab553c640a4bcb566598bffd18ecbae195fb8a887f84f2e`.
Only verified owned QEMU PID9172 was stopped after syncing.

`framework_service_create_failure.v` contains RuntimeException from onCreate
only for a registered component owned by another package or declared in a
different process from the primary app. Unknown/mismatched components and
primary-process service failures propagate the original exception. Failed
creations do not enter the service cache or receive bind/start callbacks.
Accepted binding registrations remain available for the caller's normal
unbind, with delivery canceled. Client callback exceptions stay outside this
boundary. The original failure is logged. This contains a secondary failure;
it does not repair Play Store's DI graph or implement separate process hosting.
[Android's process declaration](https://developer.android.com/guide/topics/manifest/service-element#proc)
defines the intended process boundary.

`framework_result_receiver.v` replaces the constructor-only placeholder with
Parcelable/CREATOR, local delivery, asynchronous Handler delivery and Binder
parcel transport using the standard IResultReceiver descriptor. Callback
parcels are recycled on success and failure; RemoteException follows the API's
best-effort delivery behavior. This uses the existing Binder backend and adds
no process lifecycle or authority grant. Contract:
[ResultReceiver](https://developer.android.com/reference/android/os/ResultReceiver).

SDK `framework-service-create-20261112-r3` passed guarded full assembly and
selected DEX readback:0/0, complete cleanup,3799ms, RSS483835904 and shared
growth29421568 bytes. Signed fixture r43 passed build/link/sign/verification:
0/0, complete cleanup,1287ms, RSS150044672 and shared growth24637440 bytes.
Guest r45 staging passed0/0, complete cleanup,10190ms, RSS36634624 and shared
growth267366400 bytes. Host UUID inspection, read-only e2fsck and initial disk
hash verification passed. VM resources remain12GiB/4 CPUs.

The complete fixture passed on ARM in r45 as UID/GID10160, ready/pass once,
drained EOF and exit0. It checks primary/mismatched failure identity, repeated
failed secondary creation without caching, no start/bind/destroy callbacks on
failed instances, normal unbind, and an unrelated healthy service's complete
lifecycle. ResultReceiver checks include the Intent Parcelable pattern,
direct and parcel callbacks with null/non-null bundles, stable Binder identity,
callback lifetime after parcel recycling, descriptor rejection and a worker
delivering asynchronously to the main Handler. Snapshot
`service-receiver-api-uart-20261112-r1`, plan
`service-receiver-api-plan-20261112-r1.json` and strict readback
`service-receiver-api-readback-20261112-r1` retain archive SHA256
`f762b96df595d5a031ba01446e35229d3bf215948724d4fdd3a2f46f41f951c9`.
The fixture bind was released before broker preparation. Maps functionality
remains unqualified.

With source `f1d1528e2`, r45 reached Explore/Local vibe after Skip. The full
private log retained the Play Store class cast under the new scoped creation
failure message, without a primary-looper failure. The previous ResultReceiver
Parcelable cast did not recur. The app exited during a Louvre search attempt;
the complete log identifies uncaught GMS background failures, not a proven
search-handler fault: BluetoothAdapter.getBondedDevices in cjui.l source12,
and ContactsContract.Directory resolution in enfw.e source12. Exact caller
readback is `gms-bond-directory-caller-20261112-r1`: cjui is in classes.dex,
enfw in classes2.dex, and the synthetic outline in classes12.dex reads
Directory.ENTERPRISE_CONTENT_URI.

Complete r45 log `maps-current-20261112-r45/maps.retained.log` has SHA256
`33ba3f1ae520f5b1c15d01aa17396e4dc0bff0d4b9e27b50fbd08eb010620d37`.
The synced, stopped data image has SHA256
`59c03f7e0464f9faea35e3643bad1671cc5112b8f5f9e3805815fc9e698e0719`.
Snapshot `maps-bond-directory-final-uart-20261112-r1` has SHA256
`0d50c33ba68fb931c64a36506f6a246c2af100ae1c802c046ad42ff6dc52a660`.
Only verified owned QEMU PID64396 was stopped. Minimum observed disk was
7245332480 bytes and MemFree177504KiB; no600-second stability claim is made.

`framework_bluetooth_unavailable.v` makes manager lookup delegate to the
existing null default-adapter lookup, removing the inconsistent fabricated
adapter. Legacy directly constructed objects expose off-state queries, absent
name/address and fresh empty bonded-device snapshots. It adds no radio backend.
The [BluetoothAdapter contract](https://developer.android.com/reference/android/bluetooth/BluetoothAdapter)
requires empty bonds outside STATE_ON. `framework_contacts_directory.v`
supplies URI/MIME and directory-ID metadata, including the observed enterprise
URI. [AOSP's directory definitions](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/provider/ContactsContract.java)
define these values and numeric classifications. They do not create a provider
or managed profile; ContentResolver retains its absent-provider null result,
which the exact enfw caller handles.

SDK `framework-availability-20261112-r1` passed guarded full assembly/readback:
0/0, complete cleanup,2273ms, RSS471416832, shared growth29290496 bytes.
Signed fixture r44 passed build/link/sign/verification:0/0, complete cleanup,
941ms, RSS90750976, shared growth24702976 bytes. Guest r46 staging passed0/0,
complete cleanup,9048ms, RSS36864000, shared growth138141696 bytes. UUID,
read-only e2fsck and initial-image hash verification passed before boot.
ARM qualification is pending for the new availability checks.

The complete signed r44 fixture passed on ARM in r46 as UID/GID10160,
readiness/pass once, drained EOF and exit0. It checks both manager lookup
forms against the null default adapter, direct legacy off-state queries,
bonded-set mutation isolation, directory URI values and ID boundaries, and
the exact caller's enterprise-directory projection with an absent provider.
Snapshot `availability-api-uart-20261112-r1`, plan
`availability-api-plan-20261112-r1.json` and strict readback
`availability-api-readback-20261112-r1` retain archive SHA256
`7a6ec270977263a5f2a1c3729400c8594d25aaf4600365973affa60e5ef6b2da`.
The fixture bind was released before broker preparation and the Maps retry.

With source `e40e2bb7e`, r46 exited before onboarding when GMS application
startup sampled its StrictMode VM-policy interceptor path. The primary looper
reports the missing `VmPolicy.Builder(VmPolicy)` constructor at
GmsApplication.onCreate source206. The fresh exact caller readback is
`gms-vmpolicy-caller-20261112-r1`; `gms-vmpolicy-outline-20261112-r1` retains
the synthetic outlines for the subsequent policy detection/listener calls.
Complete private log `maps-current-20261112-r46/maps.retained.log` has SHA256
`254fe31465cb743be418a0fe6a1c570e0b445b5006f4685449dc0a813a7415b9`.
Only verified owned QEMU PID6553 was synced and stopped. Its data image has
SHA256 `84f3a38ef154a6851202843a5529660aa162d60cb06dac2eb9bcdcdbd467135e`.
Snapshot `maps-vmpolicy-final-uart-20261112-r1` has full SHA256
`6fe6df4ea80c48ccd6c93cf413328bfababb612e67e2f646c15a1b9e58bb4ea8`.
Minimum observed disk was7260200960 bytes and MemFree1069584KiB; this is
not a full600-second stability result.

`framework_vm_policy.v` supplies copyable VM-policy configuration: detection
and penalty flags, independent class-limit snapshots, retained listener and
executor references, null rejection, and synchronized process-wide get/set.
It follows [AOSP's builder/copy contract](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/os/StrictMode.java).
This replaces the prior stateless VM-policy facade. It does not add missing
runtime leak instrumentation or claim VM violation detection/callback coverage.
Existing BlockGuard-backed ThreadPolicy behavior is preserved.

SDK `framework-vmpolicy-20261112-r1` passed guarded full assembly/readback:
0/0, complete cleanup,3500ms, RSS489947136, shared growth140025856 bytes.
Signed fixture r45 passed build/link/sign/verification:0/0, complete cleanup,
1240ms, RSS170344448, shared growth442368 bytes. Guest r47 staging passed0/0,
complete cleanup,13159ms, RSS36978688, shared growth198488064 bytes. UUID,
read-only e2fsck and initial-image hash verification passed before boot.
ARM qualification and the actual Maps retry remain pending.

The complete signed r45 fixture passed on ARM in r47 as UID/GID10160,
ready/pass once, drained EOF and exit0. It checks builder chaining, copied
detection flags, independent class-limit snapshots after both builder mutations,
listener/executor preservation, get/set identity, null rejection without
clobbering the installed policy, and restoration of the original policy.
Snapshot `vmpolicy-api-uart-20261112-r1`, plan
`vmpolicy-api-plan-20261112-r1.json` and strict readback
`vmpolicy-api-readback-20261112-r1` retain archive SHA256
`2b16fa7c67e353c30f79d28b511023a9dccfd523d91694776e4ccaf5d8f9a99a`.
The fixture bind was released before broker preparation. Actual Maps
functionality remains unqualified.

With source `c7be0e744`, r47 rendered onboarding, then exited after Skip on a
native SIGSEGV in wolfSSL_read+28, called by WolfSSLSession.read on an
OkHttpClientTra thread. The complete log records a concurrent socket close
immediately beforehand. Exact boot inputs extracted from the retained base
media are under `wolf-boot-inputs-20261112-r1`; the wolfssljni JAR SHA256 is
`fed6b0a6f7553bc34f91607b8c86337178bd7afb8aaf5d109aa343f75d20a0c7`.
Readback shows stream-private read/write locks and unconditional native free
in close, with no shared active-operation lifetime. This supports a close/I/O
use-after-free diagnosis; the crash alone does not establish every TLS failure.
Complete log `maps-current-20261112-r47/maps.retained.log` has SHA256
`8a4f2da3e03c047394dd314e283833f617f74b466c0e681187aab3bc31ee9b53`.
Only verified owned QEMU PID35518 was synced and stopped. Its data image has
SHA256 `54828833d8bd65c510c60c1b7244b43eae44f9f1fba27d2b4ac81c9256050b71`.
Snapshot `maps-wolf-final-uart-20261112-r1` has SHA256
`d667fcdd3545e6bca3d88a5d8711f79bb8c3ad5512cfa584573e8bb8a7759f7d`.
Minimum observed disk was7257812992 bytes and MemFree291472KiB.

`boot_tls_lifetime.v` leases the entire wolfJSSE stream read/write operation,
including its subsequent native error query and exception paths. Closing
rejects new leases; idle close retains the original TLS shutdown/cache path,
while busy close closes only an owned transport and defers native free until
the last lease exits. Borrowed transports remain caller-owned; an outstanding
operation retains its session until it completes. A native operation with no
timeout on such a borrowed transport may remain pending: this older JNI has
no upstream interruptBlockedIO entry point. The change does not claim to add
that missing interruption capability. [Upstream wolfJSSE](https://github.com/wolfSSL/wolfssljni/blob/master/src/java/com/wolfssl/provider/jsse/WolfSSLSocket.java)
also tracks active I/O before native free, using its newer JNI interrupt API.

Boot output `wolf-lifetime-boot-20261112-r1` passed guarded assemble, readback
and unchanged-control comparison for every unrelated class:0/0, complete
cleanup,1748ms, RSS196870144, shared growth73752576 bytes. ARM concurrent-I/O
qualification and the next actual Maps retry remain pending.

The first ARM attempt in r48 correctly failed the pre-existing unconnected
certificate-socket close check: publishing the closing state before idle
shutdown made Socket.getSoTimeout reject that shutdown. Boot r3 corrects the
ordering under the socket monitor, publishing closed after transport cleanup
and before releasing the monitor. It passed guarded assembly/control/readback:
0/0, complete cleanup,2113ms, RSS207142912, shared growth786432 bytes. All73
boot classes remain present; only the three intended socket/stream classes
differ from the unchanged assembly control. Output SHA256 is
`e7cff7f1da757082f28593a4b01e3b569a07d8a59eb4b3443eff429d0f38cbee`.

Signed TLS fixture r47 passed build/link/sign/verification:0/0, complete
cleanup,910ms, RSS168820736, shared growth17297408 bytes. In r48, its complete
API suite passed with boot r3 as UID/GID10160, ready/pass once, drained EOF
and exit0. The authenticated loopback fixture checks real concurrent read
and write closure, bounded close and worker completion, native-session release,
idle close and double close. A held lease checks that a borrowed transport
stays open, the native session remains active until the lease exits, and the
last exit frees it without closing that transport. The server uses a fresh
test certificate trusted only by the fixture's private SSLContext. Its state
is `tls-lifetime-server-state-20261112-r1`; the server accepted all four
connections. The generated certificate/key and signed APK remain outside Git.
Snapshot `tls-lifetime-api-uart-20261112-r1`, plan
`tls-lifetime-api-plan-20261112-r1.json` and strict readback
`tls-lifetime-api-readback-20261112-r1` retain archive SHA256
`27349326863d4d8f1a246498e5ffa32081b03c17e48f6e05b184c8cac65ccbdf`.

The unchanged signed r40-network fixture also passed with boot r3: trusted
Google HTTP, three wrong-host/untrusted-chain rejection pairs, and a stalled
handshake bounded by the configured timeout with transport closure. It ran in
fresh guest directory current-api-r3 and passed ready/once, EOF and exit0.
Snapshot `tls-lifetime-network-uart-20261112-r1` preserves the exact append
interval after the previous snapshot; plan and strict readback of that interval
retain archive SHA256
`3c4fcf145b09bc14491e4db2d1cdc0ca6994b186cefd1e094815b6a1c4b4b480`.
Only verified owned QEMU PID77908 was synced and stopped. Its data-image SHA256
is `84f62917d7d4d85507b4ead303a1d528eabf9efa62b86e10b2cfe88c596b0c03`.
Complete child logs are retained in `maps-current-20261112-r48` and the strict
readbacks. No actual Maps attempt was made in that test-only guest.

Fresh r49 stages the same tested SDK/native/core and boot r3 from the outset.
Its stage passed0/0, complete cleanup,8206ms, RSS37060608, shared growth
136142848 bytes. UUID, read-only e2fsck and initial-image hash checks passed.
The actual Maps retry remains pending.

With source `cc1e07257`, r49 reached Explore/Local vibe after Skip and stayed
alive past the prior wolfSSL crash. A Louvre search was entered, but no search
result or map imagery was qualified. Complete disk-retained logs identify
uncaught GMS NearbyDiscovery Display.getState linkage failure in dvyc.a
source11, followed by a primary-looper missing Telephony.Sms.CONTENT_URI in
fgiz.a source7, called by EmergencyPersistentChimeraService.onStartCommand.
The previous native TLS crash did not recur in this log. Exact caller readback
is `gms-display-sms-caller-20261112-r1`, classes2.dex/dvyc and classes11.dex/fgiz.

On resumption, QEMU PID83685 was absent and its QMP socket refused connections;
the stop reason is not established. Read-only extraction retained complete log
`maps-current-20261112-r49/maps.retained.log`, SHA256
`8245699dc7ff3cf887262fa65be7bd35de7357f9e03d6ca24dd83c048fdf19a2`.
The stopped data image has SHA256
`ad90004564afb66c7db2f9a57907f136126c394d96f096141cd7fb11d0f81a36`.
Snapshot `maps-display-sms-final-uart-20261112-r1` has full SHA256
`64c51e7c00cf7142afa190ad9e5b240af76f12bcee55a8ef7c5c4c6acfb9866c`.
The last watcher sample is364502ms; minimum available disk7246450688 bytes,
MemFree83056KiB. No600-second stability or controlled clean stop is claimed.

`framework_display_sms.v` exposes the current desktop adapter's one continuously
driven display as STATE_ON, consistent with its default-display object. The
catalog now enumerates that display, returns null for unsupported IDs and
returns independent arrays. This adapter has no suspend/hotplug/display-power
control. [Display's Android contract](https://developer.android.com/reference/android/view/Display#getState())
defines STATE_ON=2. The SMS addition supplies the standard [content://sms URI](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/provider/Telephony.java);
it does not add a provider, messages or change notifications. Existing
ContentResolver absent-provider behavior remains unchanged.

SDK `framework-display-sms-20261112-r1` passed guarded assembly/readback:0/0,
complete cleanup,2579ms, RSS458522624, shared growth288309248 bytes. Signed
fixture r48 passed build/link/sign/verification:0/0, complete cleanup,1019ms,
RSS167018496, shared growth15273984 bytes. Guest r50 staging passed0/0,
complete cleanup,9672ms, RSS36847616, shared growth134238208 bytes. UUID,
read-only e2fsck and initial-image hash verification passed before boot.
ARM qualification and the actual Maps retry remain pending.

The complete signed r48 fixture passed on ARM in r50 as UID/GID10160,
readiness/pass once, drained EOF and exit0. It checks default display state
through DisplayManager and WindowManager, unsupported IDs, independent display
arrays, SMS URI identity, absent-provider query and no fabricated observer
callback. Snapshot `display-sms-api-uart-20261112-r1`, plan
`display-sms-api-plan-20261112-r1.json` and strict readback
`display-sms-api-readback-20261112-r1` retain archive SHA256
`8095562e00f78547cfa0fbc893ba9560c58dec4bb3c38fc44ab2db417329ffd0`.
The fixture bind was released before broker preparation and the Maps retry.

With source `00cafadd8`, r50 reached Explore after Skip, then exited during a
Louvre search attempt. Complete logs identify an uncaught GMS update-control
worker calling missing DevicePolicyManager.getSystemUpdatePolicy in fhpe.a
source37. The exact caller checks for null before any policy-specific work.
Fresh readbacks are `gms-update-policy-caller-20261112-r1` and
`gms-update-control-caller-20261112-r1`; they retain the surrounding control
path as well as the immediate caller. No search, map or route result was
qualified, and the previous Display/SMS linkage failures did not recur.

Complete log `maps-current-20261112-r50/maps.retained.log` has SHA256
`2db7f8d34122d28871d4ea0910a09c9515c3cd570961bcfa163d8deb60f5974d`.
Only verified owned QEMU PID4382 was synced and stopped. The data-image SHA256
is `fc2c7e15556d6eb977950ed36775222eaac38b7cd9a84559beb4e566bf7749f8`.
Snapshot `maps-update-policy-final-uart-20261112-r1` has full SHA256
`f1e48c67127d1c84f1823a153b635f00580fc2c889fdaac1e05823699742c21d`.
Last watcher sample295748ms, minimum disk7244890112 bytes, MemFree106960KiB.
This is not a full600-second stability result.

`framework_update_policy.v` returns null for the absent managed update policy
and supplies its resolvable return type with a private constructor. It creates
no policy object and adds no device-owner, management or update authority.
[Android's query contract](https://developer.android.com/reference/android/app/admin/DevicePolicyManager#getSystemUpdatePolicy())
defines null when no policy is set. Value factories and policy installation
remain unsupported; the observed caller takes the null branch.

SDK `framework-update-policy-20261112-r1` passed guarded assembly/readback:0/0,
complete cleanup,3042ms, RSS471056384, shared growth155389952 bytes. Signed
fixture r49 passed build/link/sign/verification:0/0, complete cleanup,1262ms,
RSS165019648, shared growth30089216 bytes. ARM qualification remains pending.

Guest r51 staging passed0/0, complete cleanup,52287ms, RSS37535744, shared
growth456011776 bytes. An early inspection/launch attempt before staging
completion refused missing metadata/launch arguments and started no VM.
Post-completion UUID, read-only e2fsck and initial-image hash checks passed
before the actual launch. The original limits were retained.

The complete signed r49 fixture passed on ARM in r51 as UID/GID10160,
ready/pass once, drained EOF and exit0. It resolves the policy return type,
checks null-policy queries repeatedly through both service lookup forms, and
checks consistency with the unmanaged/no-device-owner state. Snapshot
`update-policy-api-uart-20261112-r1`, plan
`update-policy-api-plan-20261112-r1.json` and strict readback
`update-policy-api-readback-20261112-r1` retain archive SHA256
`6150e91ec4de9224959efc2defce80a4e93e976ba8e6ca290c2d3a02a7dcef06`.
The fixture bind was released before broker preparation and the Maps retry.

Guest r51 did not reach broker readiness, so no Maps launch was attempted.
After input/companion preparation it reported `real GMS authenticator did not
attach before deadline`; the original45-second attachment limit was retained.
Its private broker log contains only the listening-socket announcement, without
a Java crash. During preparation, read-only probes showed the controller
advancing from browser assets to GMS/Play Store APKs. The complete receipt
records started14:04:18 and finished14:13:02 UTC. No host-memory shortage was
observed in the later probe; the startup failure's cause is not established.

Only verified owned QEMU PID32397 was synced and stopped. The complete raw data
image remains at `maps-current-20261112-r51/app-data.ext2`, SHA256
`070597c3a11424cccd2eb2db8b8b7daa03090df341a4c6fbf75d989d01898c4a`.
Read-only debugfs extraction retained result contents under
`maps-current-20261112-r51/retained-results/results`. Host chown attempts were
denied; original ownership metadata remains in the raw image and receipts.
Receipt SHA256 is `91bac066f3c728786746117934c04dbbc4d50f974b9b5f7b60ec2c932cb5b560`;
broker.log SHA256 is `9c47814b4e6aeb647bbb450b895c88ed4bc28ac2ecf3a374cdaa7c4617d6995a`.
Snapshot `maps-auth-attach-final-uart-20261112-r1` has full SHA256
`4d7ec259f400330ce4c12d347a9963a26a64ed3765f14036882af320ff4c85f9`.
A diagnostic receipt print interleaved with the broker's UART export. No strict
reconstruction or removal is claimed for that export; its original complete
disk bundle is preserved. The earlier successful API export remains separate
and strictly verified. A fresh unchanged-artifact retry is being prepared.

Fresh r52 staging passed0/0, complete cleanup,32756ms, RSS37601280, shared
growth218722304 bytes. Its UUID, read-only e2fsck and initial-image hash checks
passed before boot. SDK, JNI, core and wolfJSSE inputs are unchanged from the
successful r51 API run. Broker preparation has begun; no Maps result is claimed.

The unchanged-artifact r52 retry reached broker readiness, so the r51 attach
timeout did not recur. Maps rendered onboarding and then Explore, including
Restaurants/Hotels/Coffee/Shopping chips and Local vibe. The map remained
blank. Clicking search and waiting, without typing a query, preceded process
exit. The complete log identifies an uncaught GMS location worker calling
missing TextUtils.isGraphic(CharSequence) at gfyp.p source17. Fresh exact
caller readback is `gms-graphic-caller-20261112-r1`. This run does not qualify
tiles, search, routes or login.

Complete r52 log SHA256 is
`f234baada8add1a69adca4077f8f10510c55aea19e34294c1b00d584c78e5a45`.
Only verified owned QEMU PID77652 was synced and stopped. Data-image SHA256 is
`8761f5b6cae680c421ea9e59a2b317e5f53cb809f67910693652f1f394c4c53f`.
Snapshot `maps-graphic-final-uart-20261112-r1` has full SHA256
`4e6424388f610414425f53515d91cd93af8351c6eca2c99241de89805e2a56e2`.
The observed watcher interval was shorter than600 seconds; no full-duration
stability pass is claimed.

`framework_graphic_text.v` adds both TextUtils.isGraphic overloads using
Character Unicode categories. The CharSequence overload iterates code points,
including supplementary characters; the char overload classifies one UTF-16
unit. Unassigned, separator, control, format and surrogate categories are
excluded. Empty input is false and null CharSequence throws NullPointerException,
matching [the Android implementation](https://github.com/aosp-mirror/platform_frameworks_base/blob/master/core/java/android/text/TextUtils.java).

Available V `0.5.2 8415951` compiled the builder and fixture generator without
a compiler-revision prerequisite. SDK `framework-graphic-text-20261112-r1`
passed guarded full assembly and selected DEX readback:0/0, complete cleanup,
2623ms, RSS475136000, shared growth30842880 bytes. Signed fixture r50 passed
build/link/sign/verification:0/0, complete cleanup,918ms, RSS170180608, shared
growth2015232 bytes. Guest r53 staging passed0/0, complete cleanup,8533ms,
RSS37535744, shared growth237395968 bytes. UUID, read-only e2fsck and initial
image hash checks passed before boot. ARM qualification remains pending.

The complete signed r50 fixture passed on ARM in r53 as UID/GID10160,
ready/pass once, drained EOF and exit0. New cases cover empty input, Unicode
separators/controls/format/unassigned characters, combining marks/private use,
supplementary emoji and format code points, isolated surrogates, StringBuilder
input, both overloads and null rejection. Snapshot
`graphic-text-api-uart-20261112-r1`, plan
`graphic-text-api-plan-20261112-r1.json` and strict readback
`graphic-text-api-readback-20261112-r1` retain archive SHA256
`a1273fe6ad7144a6ddb635c5c5dbb57b0e09a7f04e87a0f3216894f8faae7c0b`.
The fixture bind was released before broker preparation. The actual Maps
retry remains pending; this API pass does not qualify Maps functionality.

With source `c339f52e0`, r53 reached broker readiness, rendered onboarding and
Explore, and accepted a typed Louvre query after the search field was visibly
focused. It returned Louvre Museum/Musée du Louvre,4.7 stars(382,525), opening
hours and real place photos. Directions accepted Eiffel Tower as origin and
returned10-minute driving,29-minute transit and46-minute walking estimates.
Screenshots `search-louvre2.png` and `route-origin.png` are retained privately
under `maps-current-20261112-r53`. This validates search/details/photos and
route estimates for that run, not map tiles, route geometry or navigation.

The map background remained blank. Its log reports missing native
GLES20.glVertexAttribPointerBounds, separately from the eventual exit. After
selecting Preview, the app exited; complete retained logs identify uncaught
DeviceConfig class resolution in the GMS platform-configuration update worker
at eqea.k source10. The exact caller uses getProperty and setProperty, including
null values and both makeDefault modes; fresh readback is
`gms-device-config-caller-20261112-r1`. Cronet module linkage errors explicitly
fall back to Java networking and are not the uncaught exit identified here.

Only verified owned QEMU PID26170 was synced and stopped. Complete log SHA256
is `419c30f767cb3591193c94bc6b69e9d5793fb112efd6914585c56e3bb833457f`;
data-image SHA256 is
`ec42f496cc77f7fd4089f845dc8defc9c9de338fb07a06a1a3f4d170c2c28cad`.
Snapshot `maps-gles-final-uart-20261112-r1` has full SHA256
`3dcfaba9354f7cfe3dd5a9141a0cf1fec9b356d5b9e8b8bad385f84628bd0468`.
The watcher did not complete600 seconds, so this is not a stability pass.

The GLES client-pointer binding now forwards the caller-owned direct address
plus the typed buffer's byte position to the existing Mesa renderer. Like
[Android's JNI implementation](https://github.com/aosp-mirror/platform_frameworks_base/blob/master/core/jni/android_opengl_GLES20.cpp),
it does not retain, pin, copy or free client storage; the application must keep
it alive through draws. Heap storage is rejected, and Java position/limit stay
unchanged. The pixel regression retains its buffer through glFinish, mutates
vertices after pointer registration and checks direct/read-only rendering and
failed heap-pointer replacement. Existing offset/VBO paths remain exercised.

The first native-builder compilation with available V `0.5.2 8415951` emitted
an unresolved trim_space_eq helper and failed; its automatic historical fallback
also failed. No output from that attempt was used. The binding parser now tests
blank lines with is_blank directly. The current compiler then built the helper
successfully. Guarded JNI build `current-native-build-20261112-latest-r5` passed
0/0, complete cleanup,9520ms, RSS412909568, shared growth152965120 bytes. It used
the graphic-text SDK declarations. ARM execution remains pending.

`framework_device_config.v` exposes the observed property query and write
signatures for the absent platform configuration datastore: reads return null,
writes/deletions return false and null namespace/name are rejected. It stores
no global overrides and claims no successful write. This is the unsupported
storage outcome described by [Android's DeviceConfig contract](https://android.googlesource.com/platform/packages/modules/ConfigInfrastructure/+/refs/heads/main/framework/java/android/provider/DeviceConfig.java).

SDK `framework-device-config-20261112-r1` passed guarded full assembly and
selected DEX readback:0/0, complete cleanup,2523ms, RSS459587584, shared growth
29384704 bytes. Signed fixture r52 passed build/link/sign/verification:0/0,
complete cleanup,975ms, RSS159252480, shared growth1753088 bytes.

Guest r54 staging failed the unchanged shared disk-growth guard:exit125,
543596544 bytes growth in8278ms, cleanup timeout reported. A later process
inspection found no surviving supervised process; the failed root and receipt
remain retained and were never launched. After read-only free-space checks
stabilized, fresh r55 staging passed0/0, complete cleanup,4689ms, RSS37535744,
shared growth143552512 bytes. UUID, read-only e2fsck and initial-image hash
checks passed before launch. Neither guard limits nor guest resources changed.

The complete signed r52 fixture passed on ARM in r55 as UID/GID10160,
ready/pass once, drained EOF and exit0. It runs the existing EGL/GLES shader,
uniform, VBO/EBO, texture and readback checks plus the new client-pointer pixel
regression and DeviceConfig cases. Snapshot
`gles-device-config-api-uart-20261112-r1`, plan
`gles-device-config-api-plan-20261112-r1.json` and strict byte readback with
zero removals `gles-device-config-api-readback-20261112-r1` retain archive
SHA256 `164d1fceb234e0bd640dbeed5f9a5b099a829cec95c70ba5dded3c08424a03c6`.
The fixture bind was released before GMS broker preparation. Actual Maps tile,
route-preview and login qualification remains pending.

With source `d521b3e66`, r55 again returned Louvre Museum details and photos,
then Eiffel Tower→Louvre estimates of11-minute driving,30-minute transit and
46-minute walking. Route Preview opened and displayed the first instruction,
"Head toward Pont d'Iéna". The map and route geometry remained blank. The
complete log contains no repeated missing GLES client-pointer or DeviceConfig
linkage. It records two EGL frames of uniform opaque beige, matching later
compositor samples; sampled GL-Map stacks wait in blfc.run source537. These
observations locate the blank content before composition without establishing
the renderer's readiness failure. Captures and complete log remain private.

The600-second watcher completed at600248ms with minimum app-data space
7237775360 bytes and minimum MemFree183232KiB. This proves completion of the
storage observation, not full functionality or indefinite memory stability.
Maps subsequently exited with an uncaught missing android.util.StatsLog in
csev.g source122, called by a GMS credential-registry worker. Fresh caller
readback `gms-stats-log-caller-20261112-r1` identifies writeRaw([BI)V on this
selected runtime path. The caller's newer StatsEvent path was not entered.

Only verified owned QEMU PID61542 was synced and stopped. Complete log SHA256
is `37a4981ddf1d13d8d430ddfe05dc985eba49eadfdde47833f63fc772b40241d9`;
data-image SHA256 is
`5c33c1e41b936df16fddef967710413b2091f6410b47bc5b885d1bc1a8107a4a`.
Snapshot `maps-stats-final-uart-20261112-r1` has full SHA256
`b679da61011c4ff7e6f138cdd134add92c99dc27f297f43ab801f42f8699f044`.

`framework_stats_log.v` supplies the observed legacy best-effort writeRaw entry
point. The runtime has no statsd transport and drops optional events; it
returns no delivery status and never modifies the supplied array. Null and
oversized payloads remain harmless, as in [Android's legacy implementation](https://github.com/aosp-mirror/platform_frameworks_base/blob/android-10.0.0_r1/core/jni/android_util_StatsLog.cpp).
The newer StatsEvent serialization API remains unsupported. SDK
`framework-stats-log-20261112-r1` passed guarded assembly/readback:0/0,
complete cleanup,10243ms, RSS465747968, shared growth133763072 bytes. Signed
fixture r53 passed build/link/sign/verification:0/0, complete cleanup,3074ms,
RSS190201856, shared growth64225280 bytes. Current V at the usual path was
used; its version was observed advancing from8415951 to8ccd6ad while these
tools were prepared. No historical compiler requirement was introduced.

Guest r56 staging passed0/0, complete cleanup,22003ms, RSS37601280, shared
growth217210880 bytes. UUID, read-only e2fsck and initial-image hash checks
passed before boot. Host free space had fallen to roughly6GiB; original
reserve/growth guards remained enforced. ARM qualification remains pending.

`maps-dex-interfaces.v` locates direct DEX interface implementations with
bounded inputs and checked table/string offsets. Its scan of the retained Maps
DEX files identified bkue and axmw as direct blfb implementations, enabling
fresh selected-class readback without whole-APK disassembly. Related retained
readbacks are `maps-gl-wait-caller-20261112-r2`,
`maps-gl-state-caller-20261112-r1`, `maps-gl-view-caller-20261112-r1` and
`maps-gl-ready-caller-20261112-r1`. The earlier r1 wait-caller attempt used a
nonexistent APK path, failed extraction and supplied no evidence.

The complete signed r53 fixture passed on ARM in r56 as UID/GID10160,
ready/pass once, drained EOF and exit0. It includes the existing EGL/client
pixel and DeviceConfig checks, plus legacy raw-stats input preservation and
harmless null/oversized/zero-length payloads. Snapshot
`stats-log-api-uart-20261112-r1`, plan
`stats-log-api-plan-20261112-r1.json` and strict byte readback with zero removals
`stats-log-api-readback-20261112-r1` retain archive SHA256
`59bf802879ea379eb3bba44682b456b0c7cc8a10449be034022af843871155f2`.
The fixture bind was released before broker preparation. Full Maps functionality
and its actual retry remain pending.

### Protected surface diagnostics, current V continuation

On continuation, r56's QEMU PID was absent and its QMP socket refused
connections. No orderly-stop or sign-in result was retained; its final serial
observation is at watcher163181ms. Treat this attempt as interrupted, not a
completed stability or login check. Offline extraction retained maps.log
SHA256 `4cd3e8aced4bea0117de26d23fe618f3a33e0779761773121deba654ad5c1a8c`
and app-data image SHA256
`fec1e614caed1315bc6f99e0726958d20ec77cce1be1bbd8638e4205acdf7860`.
No uncaught exception appears in that incomplete log.

The broker now carries an explicit `--trace-surface-dump=METHOD` through its
protected session, private launch and diagnostic receipts. It validates the
method name, clears ambient selections when disabled and enables the existing
sampled tree callback. Host self-tests cover defaults, malformed/duplicate
options, legacy sessions, independent selections, round trips and private-log
exclusion. Production defaults remain disabled. Current staging can replace
both controller paths together and record the deployed hashes.

`build-current-maps-controller.v` retains the available compiler identity, V
source inputs and hashes, command arguments, exit statuses and output.
Bundle `surface-controller-build-20261112-r6` used V0.5.2 5909f83 and passed
host self-tests plus a static AArch64 ELF build under the unchanged guard:
0/0, complete cleanup,14606ms, RSS602767360, shared growth30130176 bytes.
Earlier r3 and r5 attempts exceeded aggregate RSS and were not deployed; r2
rejected an unsupported compiler option. Explicit serial compilation passed
without changing caps. This is retained V/build evidence, not an exhaustive
native dependency audit or application qualification.

Fresh r58 staging passed0/0, complete cleanup,16385ms, RSS37601280,
shared growth152510464 bytes. Volume identity and read-only e2fsck passed.
It selects the already ARM-qualified r53 fixture, StatsLog SDK, current r5
JNI, mandatory delegate-last core and TLS lifetime boot jars, plus the new
controller. r57 failed before staging because the requested stage executable
was absent; it supplied no VM or runtime evidence. The surface diagnostic and
actual Maps retry on r58 remain pending.

r58 reached companion installation and failed closed with `companion shared
catalog is not owned by this batch`, before GMS readiness or Maps launch.
The new compiler exposes a ledger lifetime bug: prune_removed copied an Owned
struct containing a string, then freed that same path storage. Surviving
entries now explicitly clone their paths before releasing the old ledger.
Inode, owner, mode and admission checks remain enforced. All11 companion-stage
tests pass with current V and GC disabled, including paired publication,
rollback and a new storage-ownership/catalog-identity regression. Results are
`companion-lifetime-results-20261112-r2`; the old shallow-copy mutation in
`companion-ledger-negative-20261112-r1` aborts with exit134. The first new-test
attempt rejected inherited macOS /tmp group metadata; the fixture now sets
its intended group explicitly before exercising the ledger.

Only verified r58 QEMU PID9549 was synced and stopped. Offline receipt SHA256
is `130808adefa1afebcd4aebe59fcf430654216b0ab8cd41e9317fbf7044344801`,
serial SHA256 `d31e49d767eb4a46b1fa0b3933bc2ad967958ac4d76d14eac3de95a384384bb8`,
and image SHA256
`eeca07404d1d6629ad44f30720001460c8fad976d0a7192995a7d72ff59cd59a`.

Controller r7(-O2) and r8(-O1) exceeded aggregate RSS and were not deployed.
The builder retains its qualified serial default compilation; no cap changed.
Controller r9 with the ledger fix passed0/0, complete cleanup,11759ms,
RSS603062272, shared growth30302208 bytes, with host self-tests. Fresh r59
staging passed0/0, complete cleanup,9487ms, RSS37683200, shared growth
137273344 bytes; volume identity and read-only e2fsck passed. Actual broker
and Maps qualification of the ledger fix remains pending.

The unoptimized controller's large-input verification took several minutes on
r58. Current-V controller r10 restores -O2 and reduces GCC's internal
collection thresholds (`ggc-min-expand=5`, `ggc-min-heapsize=8192`). Its guarded
build and host self-tests passed0/0, complete cleanup,22742ms, RSS519323648,
shared growth38219776 bytes, with the original limits unchanged. The output
is `surface-controller-build-20261112-r10/maps-account-guest`; optimized ARM
runtime timing remains pending. r59 continues with r9 unchanged.

### Key-generation request metadata

r59 passed companion publication with the ledger fix, then GMS exited before
readiness. Its complete private log reports an uncaught NoSuchMethodError on
thread DG for KeyGenParameterSpec.Builder.setAlgorithmParameterSpec, in bvpd.a
source57. Selected caller readback `gms-keygen-caller-20261112-r1` shows
ECGenParameterSpec(secp256r1), SHA-512 digests, an attestation challenge and
optional reflective unique-ID configuration. KeyPairGenerator operations are
inside its Exception boundary, which cannot catch the missing-method Error.
Only verified r59 QEMU PID21308 was synced and stopped. Broker log SHA256 is
`e2fbb0adabab412fb7b58fa1ba289157c2b619f1edc96048883903e654462b8a`,
receipt `5ebb2374ef2b997fbbc1dd56634989cb89284fed8cc28052ed1525222ab74b75`,
serial `e1b88b7c69f553a8e8a215dc0e79d4b7dceb48ed6cbdc6476003def6a1cf6edb`,
and image `b11075ebc346bf38df680ca6e4cb91041e2fba4b6277240bb6c2d515e1d44555`.

`framework_keygen_parameters.v` stores those request parameters, rejects a null
algorithm spec, distinguishes unspecified/null digests from an empty array,
and returns independent built snapshots with copied mutable arrays. Existing
alias, purposes, key size and authentication configuration survive the copy.
Private block-mode/padding fields retain their enclosing-class accessor
boundary. This follows the request/value semantics in
[Android's KeyGenParameterSpec](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/keystore/java/android/security/keystore/KeyGenParameterSpec.java).
No key-pair provider, attestation certificate or device identity is added.

The signed normal fixture includes null/default/empty/unspecified behavior,
builder reuse, curve and existing-field preservation, distinct snapshots and
array isolation at setters, build and getters. First ARM attempt r60 rejected
integer field instructions for boolean metadata; r61 then rejected direct
access to an existing private array field. Both were fixed, rather than
relaxing verification. Only owned QEMU PIDs34198 and57948 were synced/stopped.
Their retained child logs have SHA256
`e07eacfa8916f573874713929081c288d6e06ed399043b4c03e48a0e203945db` and
`71b925e773d4f7bb0e6f55b32ef58772e714f4595eb969dc881bbeae30f8cc66`;
image hashes are
`9efc0bb319ba0e27b40477e37442eb9a4dbd2ec7c974790eba05bde65bfadfdb` and
`235b626ba67b7e0e25a8b0845b334feff39e903a73e396dfe4b2c9f798456c1a`.

The shared current V advanced to0.5.2 6422d39. It failed compiling an existing
direct split-iteration with an unresolved string__split_next helper; its
compatibility frontend also rejected existing syntax. Materializing that
method-block array before iteration let the current new backend compile.
The replacement behavior, missing/duplicate checks and access controls remain
unchanged. SDK builder `keygen-builder-20261112-r5` and SDK
`framework-keygen-parameters-20261112-r4` passed guarded full assembly/readback:
0/0, complete cleanup,1874ms, RSS472645632, shared growth28061696 bytes.
Signed fixture r55/toolr58 passed0/0, complete cleanup,1052ms, RSS153387008,
shared growth25165824 bytes. r62 staging passed0/0, complete cleanup,4380ms,
RSS37699584, shared growth251441152 bytes, followed by volume identity and
read-only e2fsck. The new ARM fixture and actual broker retry remain pending.

The complete signed r55 fixture passed on ARM in r62 as UID/GID10160,
ready/pass once, drained through EOF and exit0. KeyGenProbe and the existing
EGL/GLES client-pixel and framework regressions all passed. Snapshot
`keygen-api-uart-20261112-r1` full SHA256 is
`43199d0c7d8ce06140250bd0428da6212dcf097a9b50835a3c451a64f0b308f8`;
the matching plan and strict byte readback `keygen-api-readback-20261112-r1`
use zero removals and retain archive SHA256
`fed1719bae2f7029f5c6adddda7e790077788df340139bd5c4955aa4febc1b3f`.
The fixture bind was released before preparing the GMS broker. Full Maps
functionality, current tiles/route geometry and sign-in remain unqualified.

r62 reached GMS readiness with the optimized current-V controller. Maps
rendered onboarding; Sign in opened the chooser and Add account began the
actual GMS WrapperControlledActivity/GlifAuthAccountLayout flow. The broker
then exited with `authenticator returned an unknown session`. Maps subsequently
reported a failed/timed-out native account query. No Google login page,
credentials or authentication success was observed. This run did not exercise
anonymous search/routes or establish current tile rendering.

The selected SurfaceView dump ran three times. Its later samples show a
480x640 surface, EGL context/surface present, unpaused rendering, no bad
surface, renderComplete=true, renderSignaled=false, an empty event queue and
the GL-Map thread waiting. This rules out those sampled lifecycle failures;
it does not identify the missing map scene/request. Captures remain in r62.

Only verified owned QEMU PID62886 was synced and stopped. Complete Maps log
SHA256 is `226fa45e6dbcb61fbd04f1c4875c68548db454a9e3cf38e62d6d4a3d08e61810`,
broker log `0a834239b294053913f57fa903c1e825af9b1c461aa391e6af731c6488f45bfa`,
receipt `42e55480eadefa4119d2d5fc6bd12749d264fdde6e7e7e288cc7d901df16cda3`,
serial `aca1c8d1ce8dfe27d5ce829a13beecfcd0d89c98b21b49aa44674b2fdb134433`,
and data image
`ddd93b7e37d233d4cd05976b53056612471b9ff8f5b96e99c71409fff41909e5`.
The storage watch stopped before600 seconds; its minimum app-data space was
7246454784 bytes and minimum MemFree164896KiB. It is not a stability pass.

Current-V protocol checks exposed the same implicit-string-copy assumption
in accountmanifest.string_pool. It appended a decoded string and freed its
storage; fixture diagnostics showed zeroed/corrupted manifest names. The pool
now clones each retained string explicitly. Class-name splitting is also
materialized before iteration to avoid the current compiler's unresolved
split helper. All existing package, namespace, component, complete-document,
CRC, compression and malformed UTF-8/UTF-16 rejection checks remain enforced.
The focused activity test passed. Full18-file protocol/manifest suites in
`account-protocol-plain-20261112-r2` and `account-protocol-asan-20261112-r1`
passed with the pending cancellation-race changes:0/0, complete cleanup,
34293/40332ms, RSS378896384/486998016, shared growth107245568/110616576 bytes.
ASan checks address lifetimes, with leak detection disabled for the existing
manual-allocation fixtures. Paired ARM protocol deployment remains pending.

### Account cancellation crossings

Real stream regressions reproduce the broker's fatal unknown-session outcome
when a selected service reply arrives after the requesting client disconnects.
They also exercise the reverse crossing: a cancellation arriving after the
service has sent its terminal reply. This is a candidate explanation for r62;
that run did not retain per-session correlation data, so the host reproduction
does not prove the exact runtime interleaving.

The broker now closes the cancelled client's output/UI immediately and retains
only its existing capability/deadline in a draining entry. A matching in-flight
reply is discarded. A cancellation acknowledgement releases the entry; it
otherwise expires at the original deadline plus ten seconds of transport grace.
These entries count against the existing32-session admission bound and cannot
deliver results or redeem interactions. The original request/authority deadline
is unchanged. The service acknowledges a live cancellation and retains a fixed
32-entry completion window solely to consume a crossing cancellation once.
No completed session can create another response. Unknown IDs, wrong
capabilities, unsupported reply kinds and consumed/replayed authority still
fail closed. Public diagnostic schemas remain unchanged.

Broker and service-side library must be deployed together. Current staging's
single `VINIX_CURRENT_ACCOUNT_PROTOCOL` directory selects both and records the
actual deployed bytes. The maintained current-V producer retains source inputs,
commands, output hashes and symbol readback. It rebuilds static PIC zlib from
the available repository source; no historical compiler or dependency receipt
is required. Source/input capture is not an exhaustive native dependency audit.

Full31-file suites in `account-protocol-plain-20261112-r3` and
`account-protocol-asan-20261112-r2` passed0/0, complete cleanup,62152/68640ms,
RSS379273216/481525760, shared growth128536576/129454080 bytes. They include
both wire crossings, continued unrelated clients, cancellation ACKs, queued
client failure preservation, replay/forgery rejection, admission bounds/expiry
and existing broker/client/manifest/native-auth checks. ASan leak detection is
disabled for existing manual-allocation test fixtures; address checks remain on.

Paired AArch64 build `account-protocol-build-20261112-r3` passed0/0, complete
cleanup,19016ms, RSS389595136, shared growth180232192 bytes. The broker is a
static ELF executable; the shared library has75 defined account ABI exports
and needs only the existing SQLite and libc DSOs. Broker SHA256 is
`e6a925818761b2e4e8c775160381b0e199220969b5a7d5d16ab54cca52264ab7`;
library SHA256 is
`abe1747ea9616526f0d94253665eaf455a7a3678428f1d35241ed85152093879`.
Earlier r1 lacked target zlib headers/archive; r2 then exposed the current
compiler's split helper in service_identifier. The source now materializes
those segments, preserving all identifier validation. Neither failed build was
deployed. Original build limits remain unchanged. ARM execution and the actual
Google account-flow retry remain pending.

Fresh r63 stages both protocol artifacts from r3 together with the qualified
keygen SDK r4, native r5, mandatory core/TLS boot jars and signed fixture r55.
Staging passed0/0, complete cleanup,10001ms, RSS36634624, shared growth
158474240 bytes. Both deployed protocol file hashes match the build outputs;
volume identity, read-only e2fsck and the initial image hash passed before boot.
The complete signed SDK/API regression repeated successfully on ARM as
UID/GID10160, ready/pass once, drained EOF and exit0. Snapshot
`account-protocol-api-uart-20261112-r1` full SHA256 is
`1705778c63990584fba44f9c846612147130b6a368a8ea4f1c72fb44fd5f0e35`;
matching plan/readback use zero removals and archive SHA256
`2e047bd0fb3bbfb5e85468bab2e95992fb42f4b7c274e0e57f3f060aaa714c35`.
The bind was released before broker preparation. This API pass does not itself
exercise the paired protocol's real account interaction; that retry remains
pending.

### EGL error formatter and r63 account retry

The actual r63 Sign in / Add account retry reached the GMS activity handoff
and redemption acknowledgement. Its complete broker log did not repeat the
unknown-session failure. A background GMS MlBenchmark installer then threw
NoSuchMethodError for GLUtils.getEGLErrorString(int); GMS exited10 and the
broker reported account input disconnected. This is neither authentication
success nor proof that the cancellation race can never recur. No credentials
were entered. The watch ended before600 seconds (minimum app-data space
7255179264 bytes, MemFree32832KiB), so it supplies no stability pass.

Verified owned QEMU91502 was synced and stopped before offline extraction.
Under `maps-current-20261112-r63`, complete Maps log SHA256 is
`e77b722cf29b0c04e55e3a8251e38cf72b4ad4545f80891d0cdf3fdc194708ef`,
broker `c312c0fce19617730701eb12460524e3a328d2626af9699c0b4edf32b27ebccc`,
receipt `f9e841f8996dd71184ba2fd8a6e9837d7e40215015e2fdf72abdab5f8d06aab8`,
serial `980292208a8c6d1b0d02397e6f169bb51536f5b33106cfd95f9fa96dc840a416`,
and data image
`0f9c580b94c172fcf36da13d3cdb29c318645ea1257eb3b2fc7c55068c26fba6`.

The SDK now implements the Android GLUtils error formatter: the15 standard
EGL names and an unsigned hexadecimal fallback. It only formats the supplied
integer; it does not call EGL, consume an error, or advertise GPU capability.
The ordinary SDK producer and full signed regression both include it.
Source contract: Android framework GLUtils.java at
https://android.googlesource.com/platform/frameworks/base/+/06c01a2f962a/opengl/java/android/opengl/GLUtils.java.

Using current V0.5.2 6422d39, SDK `framework-egl-error-names-20261112-r1`
passed the unchanged build guard:0/0, complete cleanup,2391ms,
RSS476774400 and shared growth28848128 bytes. The fixture tool initially
failed on the compiler cache's unresolved split helper; compiling with
`-nocache` succeeded without changing the fixture source. Signed fixture r57
passed0/0, complete cleanup,819ms, RSS197279744, growth786432 bytes.

Fresh VM r64 passed staging0/0, complete cleanup,7670ms, RSS36700160,
growth150298624 bytes, then volume identity, read-only e2fsck and initial hash
checks. It uses the new SDK/fixture with the same paired protocol r3,
optimized controller r10, native r5 and mandatory core/TLS boot jars. The full
signed regression passed on ARM as UID/GID10160, including15 standard codes,
seven unknown/signed boundary values and a real EGL_BAD_DISPLAY error that
remains available after formatting and is consumed exactly once. Ready/pass
occur once, child output drains to EOF and exit0.

Snapshot `egl-error-api-uart-20261112-r1` has full SHA256
`84697bc49e765f024390ecbe033236562d2baf1f9b79554cb9747ace0f497693`.
Matching plan/readback r1 reconstruct the unchanged export with zero removals,
archive SHA256
`c8f7c8f981be854cea567c993773d9ab375dc2e1a58383c4f79ba36f98a2d895`.
This API pass does not establish Maps tile rendering or account completion;
the real Maps retry follows after releasing the API bind.

r64 reached onboarding and anonymous Explore after Skip. The map remained
beige, with no tiles or geometry; both retained EGL frame samples are uniformly
opaque f0ede5ff. A Louvre query opened an empty details panel and did not
produce a qualified result before it was dismissed. No current search/route
pass is claimed. Avatar / Sign in opened the account window, but at watch
353589ms the kernel reported `oom: out of memory: killed main, which held
3456 MiB`. Maps exited and the broker later reported account input disconnected.
There is no new missing-method/uncaught marker in the complete Maps log.
The killed process identity beyond the kernel's name is not established by
that message; a subsequent process listing was too late, after broker cleanup.
This run requires per-process memory measurements before attributing the OOM
to Java heap, native mappings, stacks, another process or the kernel.

The12GiB/4CPU VM limit is unchanged. The watch reached only418764ms before
stopping, minimum app-data space7235670016 bytes and MemFree32784KiB;
this is a failure, not a600-second stability pass. Only verified owned QEMU
92229 was synced and stopped, then the complete offline artifacts retained
under `maps-current-20261112-r64`. Maps SHA256 is
`1fc0897e686cdf360353f3456479fea6e2239509b9405d1e7c30678ceff409c1`,
broker `fa894999296a21df1312ee92d4d74e1e497d0f2164f0dcb2aaf789f78a8ffc3a`,
receipt `de94091b0cd09d4dc416b1a5e01efe9b54e9249fc72fe8db98fdc49410f2e0b9`,
serial `def577a2ee264f8da7ced2cece5665492743b67c7cd23a1750192250ecf21e42`,
and data image
`65eb7852574a7c960dbc33bbe0b6d30e7aa71477cf43d747746d71aa8db54151`.

The storage observer now has an explicit one-shot
`--memory-snapshot FRESH_OUTPUT` diagnostic. It retains process stat/status/maps/
smaps files in a private fresh directory, with128-process,4096-directory-entry,
per-file and64MiB total capture bounds. Start times bracket each process to
detect PID reuse; the files remain non-atomic samples. Missing proc features
and disappearing processes are reported, not silently asserted complete.
Normal600-second storage observation is unchanged. It does not read process
environments, credentials or request authority.

Current V6422d39 built the ARM observer r3 under the original guard:0/0,
complete cleanup,2112ms, RSS207028224, growth1945600 bytes. SHA256 is
`555128baf2d57c44f93359d0799fa3212ddaf7812ffbff68d337ad780c93d1df`.
Host ASan GC-none selftests passed (address checks enabled, leak detection
disabled) after catching and fixing an initial double-free: current V's typed
string-array free already releases its elements. Tests cover decimal overflow,
malformed/duplicate RSS, stat comm parentheses, truncated stat, exact/oversized/
empty input, byte-preserving capture and refusal to overwrite evidence.
Sources/checksums and logs remain under `maps-memory-watch-*20261112-r3`.

Fresh r65 staged the same qualified runtime with this observer, passing0/0,
complete cleanup,4670ms, RSS36700160, growth149897216 bytes. Volume inspection,
read-only e2fsck and initial image hash passed. The observer selftests passed
on ARM, then its first real pre-broker snapshot retained all four files for
six processes (354327 bytes), with stable start times. This kernel's status
files do not yield VmRSS in the observer's Android/Linux format; the raw maps/
smaps are retained for inspection. Maps runtime memory sampling follows.

### Retained process mappings and r65 outcome

r65 captures before preparation, during preparation (the directory named
`ready` predates actual broker readiness), with GMS ready, during Maps startup,
and after account cleanup remain under `maps-current-20261112-r65`.
The raw data image is authoritative. Offline debugfs extraction retained file
contents; changing ownership to the guest's root failed on the host, so the
extracted directories do not reproduce guest ownership. Their content checksum
list `memory-retained.sha256` has SHA256
`28acef585ca8c1a3af288b6ee81a0e0338e7c63763797788a86412e44e01d2f7`.

The new V `maps-memory-report.v` checks complete per-mapping Size/Rss fields
and stable bracket identities, and reports unavailable captures explicitly.
Malformed, duplicate, missing and inconsistent fields fail its selftests.
Its derived GMS/Maps reports have SHA256
`035581d69895e1d21306a479ac7b0a91d9c807f020ec5254646fe4aae590da7a` and
`0210dd027d72da331e6e3d572f9faa4ce1278946b4a2f11d681b2bc52e062667`.
These are non-atomic RSS samples, not physical-memory totals: shared pages may
appear in multiple processes, and mappings can change between reads.

The GMS-phase sample shows controller PID55854 at2094288KiB RSS,
root broker48389 at655840KiB, service launcher46055 at1022288KiB and GMS38656
at688816KiB. The later Maps launcher11867 has1083968KiB RSS. Many large
anonymous regions match APK and decoded-entry sizes. Maps6835's smaps exceeded
the2MiB per-file capture bound; its stat/maps/status remain retained, but no
complete Maps smaps result is claimed. These measurements implicate substantial
launch/preparation retention rather than establishing a Java-heap explanation.

Direct onboarding Sign in / Add account reached GMS PreAddAccountActivity and
check-in/FRP state processing. GMS then reported native SIGSEGV at address0x898,
PC0x80111921b94 on thread51281, followed by account input disconnected. No OOM
kill was logged in r65; low memory may be relevant but does not establish the
native fault's cause. No login page or credentials were observed. The600-second
watch was interrupted; minimum space7221202944 bytes at the retained late
sample and minimum MemFree34480KiB supply no stability pass.

Only verified owned QEMU93163 was synced and stopped before offline access.
Maps log SHA256 is
`b629c9da1b1f3149c50f858602b4bf29e291866122ff0470ccf82f6c42d43b08`,
broker `6f4bb8b695d39ad175bc565c7bffdd4296e2a6469bdad314d42bbf39256301b3`,
receipt `25dcaec111655e71716475e58ca2cd650e35c15cfe376ddc3584994a5932d2ee`,
serial `522e7633a1e19d982b59dac809c4c3fa451029cf271407dc1eb6166d42abead1`,
and data image
`0440b3388e3d003d336a1029e93391a1c83d3873db4ff607e010ac5c24937728`.

### Release APK preparation storage with current V

Current V's szip.open eagerly caches all decoded entry payloads, while read-only
close does not free its storage. Native APK installation now uses the lazy
reader, validates every payload one at a time (including unused assets and
directory entries), then releases it. It streams file hashes and explicitly
releases the archive's owned names, payloads, backing bytes and reader object;
the borrowed path remains owned by the caller. Entry allocation is capped at
512MiB before decoding. ZIP/member validation, native path/ABI checks, atomic
publication and verification of an existing installation remain enforced.
Corrupt unused payload and nonempty-directory regressions fail before publication.
Generated C confirmed that typed ZipEntry-array free is shallow in this compiler;
entry fields therefore need explicit release, unlike its string-array free.

Activity verification reuses the existing bounded, unique-member streaming APK
reader for AndroidManifest.xml and frees its result. It scans the complete
central directory and checks the selected member's local metadata, compression,
CRC and complete binary XML; it does not decompress unrelated resources. The
caller still authenticates the whole APK. Controller hashing now releases its
buffer and digest. Two controller split loops are materialized for the current
compiler's unresolved split helper, without changing their validation.

The current protocol producer also builds/captures the native launcher and
checks its ARM ELF identity. Staging's VINIX_CURRENT_NATIVE_LAUNCHER selects
those actual bytes and updates deployment hashes. The test suite now includes
nativeapk and companionstage as well as the original31 files. Its first ASan
attempt failed because companionstage's required external fixture root was not
set; the producer now creates a fresh private root, preserving the test rule.

All33 files then passed ASan in `apk-memory-asan-20261112-r2`:0/0, complete
cleanup,64556ms, RSS475676672, shared growth82886656 bytes. Leak detection is
disabled for existing manual-allocation fixtures; address checks remain on.
After the final directory-entry validation case, focused nativeapk ASan tests
passed again and the complete33-file plain suite passed in
`apk-memory-plain-20261112-r1`:0/0, complete cleanup,58993ms, RSS370868224,
growth105615360 bytes. No historical checker was relaxed.

Using available V0.5.2 6422d39 under the unchanged guard, controller build
`apk-memory-controller-build-20261112-r4` passed0/0, complete cleanup,19684ms,
RSS514195456, growth42373120 bytes. Protocol/launcher build
`apk-memory-protocol-build-20261112-r2` passed0/0, complete cleanup,24264ms,
RSS369917952, growth50483200 bytes. Controller SHA256 is
`935e9d8df10fd91371b50418090311a7a2c92de8c8f8f6f28763411b5937fb3e`,
broker `375210203078ea52751e4b327eef0e4d4cf73f6ebc42c368adf65d3caf5c7799`,
launcher `10be0d265dcc4322fb26723108b60f89761c0ab39a614ebdc2de69778e768cb4`,
and account DSO
`626a0ff645e0a058755c01866f1a67340a6e79cf6b7968b51c21f2b20e5aa69e`.

Fresh r66 stages all these artifacts with the qualified EGL SDK r1/fixture r57,
native r5 and mandatory core/TLS jars. Staging passed0/0, complete cleanup,
4899ms, RSS36585472, growth182820864 bytes. Deployed launcher, broker and
controller hashes match their build outputs; volume identity, read-only e2fsck
and initial hash passed. ARM/API and memory comparison are pending; host tests
and builds alone do not establish the memory reduction or fix the native fault.

r66's completed ARM/API check, preparation-memory reduction,600-second
observation, working Louvre search and remaining account native fault are
recorded in [the current memory runtime report](maps-current-memory-runtime-20261112.md).
