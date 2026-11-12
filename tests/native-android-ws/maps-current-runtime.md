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
