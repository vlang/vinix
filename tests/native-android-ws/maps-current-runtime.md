# Current Maps runtime work — 2026-11-12

Current V is `/Users/alex/code/v/v` (`0.5.2 f2edf66`). The new
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
