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

The next real account attempt is pending. Google Maps is not fully qualified
and no Google authentication success is claimed.
