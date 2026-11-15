# ValueCallback interface candidate, 2026-11-15

Status: SDK assembly, native build and signed fixture passed the original host
caps after space recovered. The complete signed ARM suite passed in the r103
API-only profile. Protected account staging was refused when free space fell
below the retained reserve; the real account retry is still pending.

The [WebView loader adapter](maps-webview-loader-20261115.md) in 38730c57d passed
the full signed ARM suite in r102 and the real flow progressed beyond the
loader call. GMS then failed during account fragment creation: class attt
implements non-interface class android.webkit.ValueCallback. The actual retained
ValueCallback.smali contains only a concrete class and empty constructor.
The SDK cookie callback already uses invoke-interface for onReceiveValue.

Android defines [ValueCallback<T>](https://developer.android.com/reference/android/webkit/ValueCallback)
as an interface with onReceiveValue(T). The existing ATL Java patch already
states the correct interface, but the retained SDK input predates that patch.
This V adapter accepts either that exact legacy empty class or the correct
interface input, then writes the generic interface with erased
onReceiveValue(Object)V. The new SDK builder checks legacy/correct input,
idempotence, twelve refused mutations, full assembly and DEX readback. These
host checks passed in the latest continuation below.

The signed fixture implements the interface from an application DEX. It checks
reflection shape, generic type parameter and erased return type, real interface
dispatch, the existing VinixCookieCallback wrapper's true/false forwarding and
worker-thread invocation. It does not perform a cookie operation or synthesize
an authentication result. Fixture compilation and ARM execution passed.

External evidence root: /Users/alex/.local/state/vinix/android.
Source parent: 38730c57d. Current compiler remains /Users/alex/code/v/v,
V 0.5.2 cbfc1be; no historical compiler requirement is added.

With all owned guests stopped, the read-only 15-second quiet probe
value-callback-host-quiet-20261115-r1 was stopped after 13525 ms with
121544704 bytes observed shared disk growth. Its read-only growth cap was
67108864 bytes; exit/child 125/137, cleanup complete. This is a pressure probe,
not a failed run under the larger build growth allowance.

The original build profile remains RSS 629145600, wall 300000 ms, reserve
1073741824, growth 536870912, output 4194304. Attempt
value-callback-tools-20261115-r1 was refused before launch: initial free
1177317376 bytes, reason "disk growth budget", exit 125, child -1, pid 0 and
no supervised groups. Its cleanup_complete=false does not describe a live
child: no command started. The empty output directory and guard receipt are
retained. No command ran in that refused attempt.

The resumed qualification below supersedes the initial build blocker. Retain
the failed attempt and original caps; do not treat it as a compiler failure.

## Resumed host qualification

Source: candidate 6a301fe1c. Current V remains 0.5.2 cbfc1be. Fresh tooling in
value-callback-tools-20261115-r2 compiled and linked under the original caps.
All three build guards below returned exit/child 0/0, empty reason and complete
cleanup. Raw inputs, inventories, generated C and signed APK remain outside Git.

| Check | Evidence stem | Time ms | Peak sampled RSS | Observed growth |
| --- | --- | ---: | ---: | ---: |
| Full SDK assembly, DEX readback, idempotence and twelve refusals | framework-value-callback-20261115-r1 | 2689 | 487358464 | 41930752 |
| Full native producer and AArch64 GCC -Werror link | value-callback-native-20261115-r1 | 11917 | 582762496 | 61181952 |
| Signed shared-display fixture assembly and signature check | current-api-value-callback-20261115-r1 | 1009 | 177373184 | 29392896 |

| Candidate artifact | SHA256 |
| --- | --- |
| framework-value-callback-20261115-r1/classes.dex | a137d46008fc6bcee29dbfdeb628540ed2614c2a4f1ce32199e4c10cca37b8f5 |
| value-callback-native-20261115-r1/native/libvinix-android-native.so | 03891fb9dbca80b389de3ec28921cfdcb2423fb92cfb2880f556e353d3b90666 |
| current-api-value-callback-20261115-r1/probe.apk | caab0c81cce70667011923c75b0aac910a25540912c0aab62a0b9645a6f5fdf2 |

Fresh r103 staging passed under the original caps in 8909 ms with 101797888
bytes observed growth. This run explicitly sets VINIX_CURRENT_APP_DATA_DISK=0;
it omits the protected account volume to qualify the signed API suite with less
host disk use. It must not run a protected broker/account attempt. A full retry
still needs a fresh account-profile guest with its checked persistent volume.

## r103 signed ARM qualification

The complete signed API suite passed, child exit 0. Its retained log includes
VALUE-CALLBACK-PASS and CURRENT-API-PASS. This exercised interface reflection,
the generic type parameter, erased method, application interface dispatch,
true/false forwarding through VinixCookieCallback and worker-thread dispatch.
The complete API export reconstructed without removals: 23727 bytes / 47 chunks.

| ARM API evidence | SHA256 |
| --- | --- |
| maps-value-api-uart-20261115-r1/full.log | 6584682a5a4ce7d6871f597b346c5253007722499b11cf37952a9679992bc0b9 |
| maps-value-api-readback-20261115-r1/archive.json | 514ae6ecf959f94f9823f2561c6f46d92bb41a40800b41029fa6ed69db1adb34 |
| maps-value-api-child-20261115-r1/child.log | c93d9815360736b4e17979f9d9d06ec67c54896cef7117114cbcf46abf5864b2 |

The runner's readiness-pass, exit status 0 and shell prompt were observed.
After verifying its executable and exact guest paths, owned QEMU14029 was
stopped and PID absence confirmed. No account broker or protected UI ran in
this API-only guest. The full signed API evidence is retained outside Git.

The next full profile was selected with VINIX_CURRENT_APP_DATA_DISK=1 and the
qualified SDK/native/fixture above. Guard maps-r104-stage-20261115-r1 refused
before launching staging: initial free 812937216 bytes, reason "disk reserve",
exit 125, child -1, pid 0, no supervised groups. Its cleanup_complete=false
accompanies a prelaunch refusal, not a live child. No r104 guest was created.

After space and a quiet window are restored, stage the qualified artifacts in
a fresh full account profile and run the protected account retry, preserving
the checked persistent-volume and single-use rules. Do not infer a successful
Google account transition from the API-only result. All owned guests are
stopped; Google Maps and authentication remain incomplete.

In the subsequent full r104 profile the same signed suite passed again. That
guest was interrupted before services became ready. Fresh r105 then reached
the actual account chooser and Add account progressed past the callback-type
failure, ending instead on the missing View.setRevealOnFocusHint API. Complete
r105 private/public evidence and the next repair are recorded in the
[reveal-hint continuation](maps-reveal-hint-20261115.md). No Google authentication
success is inferred from that progression.
