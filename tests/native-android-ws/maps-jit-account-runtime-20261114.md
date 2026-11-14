# Account preflight after JIT and route validation

Fresh r85 uses the exact SDK/native/controller/protocol/core/TLS artifacts
qualified by [r84](maps-jit-route-runtime-20261114.md), source 77dfe88ec. The
unchanged signed API fixture was not rerun. The native build used available
latest V; no compiler pin was introduced. Staging passed the original explicit
caps (RSS 629145600, wall 300000 ms, reserve 1073741824, growth 536870912,
output 4194304): 11085 ms, RSS 38338560, growth 165249024 bytes, exit 0/0 and
complete cleanup. maps-r85-stage.json/.log remain outside the generated root.
UUID f97143ea237a423eb0f6d558854ced9d, read-only e2fsck and initial hash passed.
The guest retained 12 GiB/four CPUs and its separate 8-GiB data image.

The root operator explicitly selected VINIX_ANDROID_TRACE_THREADS=1 for the
existing bounded Play Services sampler. Maps diagnostics remained disabled.
After readiness, onboarding Sign in opened Add account, then the Google account
window's "Checking info..." page. At 09:46:13 UTC the window showed the server
communication error; no credential form or authentication was reached.

The private log identifies CheckinHelper's 10000-ms timeout at line 25928,
setCheckinResult=false at 25965 and RESULT_ERROR immediately afterward. At
24913, its callback was registered for a check-in starting after monotonic
380706 ms. The initial task had started at 192425; its later SUCCESS at 467109
delivered zero callbacks. The next task started at 482511 and its SUCCESS at
591384 delivered one callback. Thus real Google check-ins succeeded, but the
eligible result arrived after the preflight timeout. This establishes neither
authentication nor the cause of the delay.

The sampled blocks at 23322–23886 precede callback registration; blocks at
31710–32824 and 33981–34753 follow the timeout. None brackets the critical
registration-to-timeout interval, so their stacks do not identify its worker
stall. The log also retains 20 failed dynamic-module dex2oat invocations and
20 corresponding completion timings, including the 23.671-second AdsDynamite
attempt. These are a concrete source of extra work, not a measured attribution
of the entire account timeout. Scheduler constraint gaps remain separately
known; this run does not assign them as the cause.

The [referenced ART fork's OatFileAssistant](https://gitlab.com/android_translation_layer/art_standalone/-/blob/e78bf68917bcaaf58fef3960cd88793b3b7f39cc/art/runtime/oat_file_assistant.cc)
attempts dex2oat directly when a non-resource module is out of date. Its
[option parser](https://gitlab.com/android_translation_layer/art_standalone/-/blob/e78bf68917bcaaf58fef3960cd88793b3b7f39cc/art/runtime/parsed_options.cc)
defines the image compilation option and JIT independently, but lacks the older
-Xnodex2oat definition despite retaining that spelling in usage text. No
unsupported option, false-success compiler wrapper, verifier bypass or trust
change was added. Qualifying a fix needs the deployed ART build inputs and a
new guarded runtime build, not a nominal flag change in the native bootstrap.

The broker remained live beyond five minutes after Add account, until the
checked --stop request at 09:52:14. The final receipt is
user-stopped-no-authentication-claim with no error or auth-pump failures; neither
private log contains a missing-method, fatal native signal, ANDROID-WS-FAIL or
service-exit marker. This is stability evidence after the request lifetime,
not proof that the exact local-expiry/root-cancellation crossing was exercised.
The receipt records two cleanup survivors; both were contained by stopping
the owned VM. The 600284-ms watch retained at least 7241887744 guest disk bytes
and 3565392 KiB available memory.

Complete UART BEGIN/END agree on
f0edbb861db92c0f765ea3d09ca3718c1b54bfd6e2585786b9e6c90192606300,
1428725 bytes and 2791 chunks. Sync returned to the actual prompt before owned
QEMU PID 38438 was stopped and confirmed absent. Offline extraction followed.
Both r84/r85 are stopped. Complete bundles remain outside Git under
`/Users/alex/.local/state/vinix/android/maps-current-20261114-r85/`:

| Artifact | SHA256 |
| --- | --- |
| maps.retained.log | a509f72d5bc5c38beab1ef141b0b9ca48a08330ed64dfcd9763f7d893f848850 |
| broker.retained.log | 38846a3b9b47971cc46e6105fbedfd667efff9709eda70b7136a13018d8eb8d9 |
| receipt.retained.json | 7b1137578b3043d5b93fa8d8f4f361578187a4037d714b885c41645e3eeddcb5 |
| maps-launch.retained.json | 17ad56789d71c9e9051f84b3bec4511acde6412cc80993660fd2cf4dd0019870 |
| final serial.log | 4c2ede03490acf510196dbca71ed2aca4473307392014dad6cc4507231637b90 |
| final app-data.ext2 | 08794d714035eda79cca4fe4cec2d2ac276c859e83c9c45490d7754a0000d65e |
| account-preflight.png | 51b6da87aa81fa2cb9cb3929078f18be2bffd0ee4c8d2ba0b35782f942403168 |
