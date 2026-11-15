# Contact type labels, 2026-11-15

The complete signed ARM suite passed with the reveal-hint adapter in r107.
The protected account retry then reached three successful Google device
check-ins. This is device registration, not account authentication. Maps
opened the chooser and Add account once; no credentials were entered.
GoogleApiHandler terminated on the missing Email.getTypeLabel API in elvx.a,
called from PeopleChimeraService. Inspection of that same method shows Phone
label calls immediately after Email, so this change implements both APIs.

The V framework adapter resolves the bundled Android string resources by
name, then asks the supplied Resources for its text. It preserves locale,
styled text and custom CharSequence identity rather than embedding English
labels or resource numbers. Email maps four types; Phone maps twenty. Unknown
types select Custom. Nonempty custom labels are returned unchanged for
TYPE_CUSTOM and, for Phone, TYPE_ASSISTANT, matching the
[AOSP ContactsContract implementation](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/core/java/android/provider/ContactsContract.java).
No contact-provider data or permissions are added.

The independent signed fixture covers all mapped types, zero and unknown
integer boundaries, resource IDs, non-String custom labels, assistant labels,
empty labels, supplied Resources dispatch and a worker thread. The SDK builder
rejects 22 missing, duplicate or already-present input declarations, assembles
the full SDK and reads back both classes from DEX.

## r107 complete evidence

External root: /Users/alex/.local/state/vinix/android.
The checked persistent volume UUID was 98a56e10ed9543ee98d953f1f0c49fb5.
GMS PID62967 reached readiness; its descriptor snapshot contained 221 entries,
unavailable=0, non_atomic=true. Maps PID19078 launched once. After the complete
account export ended, results were copied to r107-private/results and synced.
The checked mount, copied receipt and prompt preceded stopping owned QEMU67578.
PID absence and no image handles preceded read-only extraction; e2fsck passed.
Private logs match their manifest. The complete public account export was
1429541 bytes / 2793 chunks and reconstructed without removals; its receipt
compares identical to the private copy.

| Evidence | SHA256 |
| --- | --- |
| maps-r107-uart-20261115-r1/interval.log | cd9646855f0df6d9ad370e40237db910e93be40c969019cb4df09526f89b6c95 |
| maps-r107-readback-20261115-r1/archive.json | 49608b4404af0fc0511aa9b0095c6fb168c3fffe824cdff8254d6434eac1bbec |
| Same readback/exported-receipt.json | 2965a852462fcf017558d0e4cae7057ebc3a4ac2b28643d67dbbfa822237fe0c |
| Private r107-private/results/broker.log | 0276393be86fda5e768c5b6fb57df6b621b491324a7a258846ed4cd4bdba0641 |

## Current compiler build checks

V /Users/alex/code/v/v is V 0.5.2 cbfc1be. SDK, fixture and native builds all
passed under the original RSS 629145600, wall 300000 ms, reserve 1073741824,
growth 536870912 and output 4194304 limits, exit/child 0/0, empty reason and
complete cleanup. The SDK took 2219 ms, peak sampled RSS 499728384 and shared
growth 28205056 bytes. The native GCC -Werror build took 9743 ms, peak sampled
RSS 587268096 and shared growth 213528576 bytes. Signed fixture verification
passed APK v3. Generated sources, inventories and binaries remain outside Git.

| Candidate artifact | SHA256 |
| --- | --- |
| framework-contact-labels-20261115-r1/classes.dex | 822e8d1200496183d75a3b5cf757cd4d8c5d7ec6920d2ade7494c7935f6b3606 |
| contact-labels-native-20261115-r1/native/libvinix-android-native.so | 774a82cd60cc64de55c8524aa40f2cfe34fe8f12ec65a9b306c47e17442c4597 |
| current-api-contact-labels-20261115-r1/probe.apk | e8518ec71b4b4a28af7875c0e1371c54392df0a68d95ba8c2297245aaa81b546 |

## r108 signed ARM qualification

Fresh full-profile staging passed under the original caps. The complete
signed ARM suite passed, child exit 0, readiness pass, CONTACT-LABELS-PASS and
CURRENT-API-PASS. All mapped types, unknown boundaries, custom identity,
assistant behavior, supplied Resources, empty labels and worker checks passed.
The complete public API export reconstructed without removals: 24003 bytes /
47 chunks. The next protected account retry is pending; full Maps operation
and account authentication remain unqualified.

| ARM API evidence | SHA256 |
| --- | --- |
| maps-contact-api-uart-20261115-r1/full.log | 47051ca8edd3b0ca556fd102429cdf2bd3acf408880538d9efe6238e1355cb60 |
| maps-contact-api-readback-20261115-r1/archive.json | aff0795c182733027d09f571577bb3124ba5e0e0f5f1e11a692f2932c94cebaa |
| maps-contact-api-child-20261115-r1/child.log | 52f54f4d1cff9bf7eb0c0f463c6b33606fa94134cd59845ba5bd153d1c38e399 |
