# Window content parent, 2026-11-15

In r98 Add account ended the native service UI pump without describing its
pending exception. Commit b8a310c0a reports failed active-cycle exceptions before
releasing the JNI frame, retaining the numeric first-cause record and failure
status. The production lifecycle checker passed 33 cases and 20 rejected
mutations, including removing the report and moving it after frame release.
The terminal observer passed its five mutations and reporting-exits scenario.

Fresh r99 passed the complete signed ARM API suite, then reproduced the account
failure. Its new diagnostic identified a NullPointerException in
frmk.onLayoutChange:77, calling ViewGroup.addOnLayoutChangeListener on null.
Read-only inspection of the actual GMS classes3.dex shows the callback obtains
the content view's parent before that call. Vinix used the same FrameLayout
for its window decor and android.R.id.content; its root has no ViewGroup parent.

The V SDK adapter now creates a distinct MATCH_PARENT content FrameLayout
inside the retained decor. Window.setContentView replaces only that container's
children. Decor identity, background and native root selection stay intact.
This follows the parented content FrameLayout in AOSP's
[screen_simple layout](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/core/res/res/layout/screen_simple.xml)
and [PhoneWindow content replacement](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/core/java/com/android/internal/policy/PhoneWindow.java).
The signed probe checks decor identity, distinct content parentage, replacement
without replacing the container, and real native layout callbacks seeing that
parent. No exception is suppressed and account authority is unchanged.

External evidence root: /Users/alex/.local/state/vinix/android.
Builds use current /Users/alex/code/v/v, V 0.5.2 cbfc1be. Build caps remain
RSS 629145600, wall 300000 ms, reserve 1073741824, growth 536870912 and
output 4194304 bytes. Read-only derivations use growth 67108864.

## Diagnostic qualification and r99 retention

The diagnostic native producer service-ui-cycle-native-20261115-r1 passed in
9861 ms, peak sampled RSS 571670528, observed growth 9945088 bytes. Lifecycle
and terminal evidence stems are service-ui-cycle-check-20261115-r5 and
service-ui-cycle-terminal-20261115-r1. The full signed ARM suite passed in
maps-cycle-api-child-20261115-r1; complete API export: 22755 bytes / 45 chunks,
reconstructed without removals.

GMS PID54240 reached readiness; descriptor snapshot gms-ready-r99 captured
227 entries, unavailable=0, non_atomic=true. Maps PID64876 launched once,
reached the account chooser and attempted Add account once. No credentials
were entered, and neither app nor UI attachment was restarted.

The mounted data volume UUID was 5fd3b32754c54cd394a72824e798b9cf. The full API
and account results were copied to r99-private and synced; the checked mount,
copied receipt and prompt were observed before stopping owned QEMU18705.
PID absence and no open image handles preceded read-only debugfs extraction.
Read-only e2fsck passed. Complete private evidence is retained under
maps-current-20261115-r99-account/private-readback/r99-private; broker.log
matches its private-log-sha256.json manifest.

The Maps UART exporter emitted BEGIN/END for 1429546 bytes / 2793 chunks, but
the unchanged no-removal planner rejected noncanonical frame fields. Its
failed plan/readback and original interval are retained; no repaired public
archive is claimed. The private disk copy supplies the exception evidence.

| Evidence | SHA256 |
| --- | --- |
| service-ui-cycle-native-20261115-r1/native/libvinix-android-native.so | ccb70baab51dfb5261dc0262eae3b52f7f40056ed57b945e6045f8cb3d45c2e0 |
| maps-cycle-api-uart-20261115-r1/full.log | 028dcc7ffaae1062339499498ad4baf85af80d57492a7ee00694376fbe1b8c77 |
| maps-cycle-api-readback-20261115-r1/archive.json | c28a381f81d1f3626a6c5cb09f4a6ef7cf93464f4e50692fcfa74d189cea0c76 |
| maps-cycle-api-child-20261115-r1/child.log | 4aac8b106b34de0717d58537a0fdc1bf1d30210f301399486e9b38996cbd9bd7 |
| maps-r99-uart-20261115-r1/interval.log | b9c89e030ae50e712fab5f1ee2f869cfc463591fb876b631b4c74b78465dcabb |
| Private results/broker.log | 5feeded18c2c1ad4cfd3805b813c4de1ff82da710246e08151d7d82415d6491b |
| Private results/receipt.json | 4770e552a68332b58d5dacb2b0b62526f81333ff461d282682a72ec2eb8a2adf |

## Content-container candidate

SDK assembly, Window DEX readback and four input refusals passed in
framework-window-content-20261115-r1, 2383 ms / RSS 467812352 / growth
47575040 bytes. The signed fixture assembled and verified in
current-api-window-content-20261115-r1, 951 ms / RSS 176439296 / growth
839680 bytes. The first full native build was stopped by the retained disk
growth guard after 7047 ms: 539914240 observed bytes, with RSS 582926336;
exit/child 125/137, cleanup complete. A subsequent 15-second read-only quiet
probe passed with 368640 bytes growth before retrying the original build caps.
The retry window-content-native-20261115-r2 passed in 8907 ms, peak sampled
RSS 571179008 and observed growth 20344832 bytes, exit/child 0/0 and complete
cleanup. Fresh r100 staging also passed under the original caps.

| Candidate artifact | SHA256 |
| --- | --- |
| framework-window-content-20261115-r1/classes.dex | 1a4d405be214b9d1bc4575e9bc3a6f6e70d95417a96e2ee85c44657868e6d254 |
| current-api-window-content-20261115-r1/probe.apk | dace772c667869a49a32286a3ffcff1501d9ab5923149e008fbb5d5f1ba0a7fe |
| window-content-native-20261115-r2/native/libvinix-android-native.so | 7065d0f0acee0f615e874db0fe92a55f7c35e88a9ca3fbad3fd46de6a9803210 |

The complete signed ARM suite passed in fresh r100, child exit 0. Its
WINDOW-DECOR-PASS record includes content-parent, replacement and layout-callback,
followed by CURRENT-API-PASS. The API export reconstructed without removals:
22795 bytes / 45 chunks.

| r100 ARM API evidence | SHA256 |
| --- | --- |
| maps-content-api-uart-20261115-r1/full.log | 276efa7991bdf1c33b08b7a7e345f3402231bc6d4a8c3c27970272d45f1a7577 |
| maps-content-api-readback-20261115-r1/archive.json | feb9787335ec99b0682e9ca14fff19c098866ff3458286fad4d4f1f55c29fbc7 |
| maps-content-api-child-20261115-r1/child.log | d4ff972bc173380359554e075891b5af164125ce88fe0c108433e2e513181903 |

## r100 chooser regression and dialog follow-up

The r100 real attempt exposed a second tree assumption: Maps PID49596 exited
when Sign in opened the account chooser, before Add account. ART rejected JNI
ViewGroup.removeAllViews on null from AlertDialog.setView. The native
ws_dialog_node helper assumed decor child zero was the dialog body; it is now
the content container. GMS PID15381 remained ready. Its descriptor snapshot
captured 221 entries / unavailable=0 / non_atomic=true. This run does not prove
the original GMS layout failure resolved, because it never reached Add account.

The follow-up native helper finds android.R.id.content first, then the body
and selected node. Missing trees leave a managed IllegalStateException instead
of invoking JNI on null. Callers return with that exception pending. The signed
probe now exercises AlertDialog custom view replacement and removal, title and
message text, findViewById, and the missing-container exception path.

After checked --stop, the complete export ended. The checked data volume UUID
was 0d3fbe74cc224c3bafffab192070ff09. Full API/account evidence was copied to
r100-private and synced, with copied receipt and prompt observed before
stopping owned QEMU49155. PID absence and no image handles preceded read-only
extraction; e2fsck passed. The storage watch is partial. Private logs match
their manifest. The complete public export reconstructed without removals:
1429293 bytes / 2792 chunks, receipt identical to the private copy.

| r100 account evidence | SHA256 |
| --- | --- |
| maps-r100-uart-20261115-r1/interval.log | f4d58702352f89067e2875c2c30bf3fc69de3f733741befe948b04e2cc5bf30f |
| maps-r100-readback-20261115-r1/archive.json | 2efe6042923f673b53742c5a2803c447509d38cd4539f379c8543cb89e754cb6 |
| Same readback/exported-receipt.json | 9cc9cacd56154693c3ed1458019edc2fbf612f7917ac318ae4af96817b397bec |
| Private r100-private/results/maps.log | d11e5faec6d7a87747951dd7d743097f7624acd59993896215feba6b89ab8502 |
| Private r100-private/results/broker.log | ad68a3a10b0b162299c1df6249d8eab9a318a66841ea7178c7b221a5fc811e99 |

Private root: maps-current-20261115-r100-account/private-readback.
The dialog native producer dialog-content-native-20261115-r1 passed in
9553 ms / RSS 577060864 / observed growth 11042816 bytes under the original
caps. The updated signed fixture is current-api-dialog-content-20261115-r1.

| Dialog candidate artifact | SHA256 |
| --- | --- |
| dialog-content-native-20261115-r1/native/libvinix-android-native.so | 11500fa1ed2b0ceacdfb1c1cbb0555441008cf81379d19575765c504e620dd2d |
| current-api-dialog-content-20261115-r1/probe.apk | 65f144f368ff66588a342d6eff8f1e9a066dec6c3292334d3b2fe2a682a7e5b6 |

The complete signed ARM API suite passed in fresh r101, child exit 0, including
the alert-dialog marker and missing-container exception check. Its complete
API export reconstructed without removals: 23475 bytes / 46 chunks.

| r101 ARM API evidence | SHA256 |
| --- | --- |
| maps-dialog-api-uart-20261115-r1/full.log | 775bf9bfe5a499acd3c652f0bbcffea5a8e609562ba7cdb714bfde47fcb999e9 |
| maps-dialog-api-readback-20261115-r1/archive.json | 77f9b7e5725cff7ccbbe1d400d8615d4eb6420fc3625f144c041b1f069bbd146 |
| maps-dialog-api-child-20261115-r1/child.log | d0bda82b5dc93fa483c34bf9d05b1e18c38216bf63613ae6a5bdd6e6eb5ee08f |

In the r101 real attempt, Maps PID26853 opened the account chooser normally
and Add account progressed past the previous frmk layout failure. GMS PID23785
then failed with NoSuchMethodError for the static
WebView.getWebViewClassLoader()Ljava/lang/ClassLoader; method, during an account
activity onCreate through the main Looper. The new failure is the next SDK task.
The descriptor snapshot captured 231 entries / unavailable=0 / non_atomic=true.
No credentials were entered and the protected session was not restarted.

The checked data volume UUID was 90bf6dbcc6d7474a86c21935188bbe99. Full private
API/account results were copied to r101-private and synced, with copied receipt
and prompt observed before stopping owned QEMU54224. PID absence and no open
image handles preceded read-only extraction. e2fsck passed; the storage watch
is partial. Private logs match their manifest. The complete Maps export
reconstructed without removals: 1429559 bytes / 2793 chunks; exported receipt
compares identical to the private copy. The retained root is
maps-current-20261115-r101-account/private-readback.

| r101 account evidence | SHA256 |
| --- | --- |
| maps-r101-uart-20261115-r1/interval.log | 04a3644eede230a75dc24b49ab7769df60b26afd1dfccfed848b366ca8960994 |
| maps-r101-readback-20261115-r1/archive.json | 27f8b4a97c7ebc698e7452f817c62414bd79feec85b9f4684591ff6af5441a09 |
| Same readback/exported-receipt.json | 3247576105a616e5f2d20fdaa8f8b2921b2b9c81b491d5885a3b3570f3bfe7ac |
| Private r101-private/results/broker.log | 737a891823d63057221a219a3e797fe03e6fd92aafa5cd1a95136eaa63f15460 |
| Private r101-private/results/maps.log | 7800b7d0dd192911e1d9a01550a70ba628edbc53e938fc75e4ec883ec7402261 |

Google Maps is not fully qualified and no Google authentication success is claimed.
