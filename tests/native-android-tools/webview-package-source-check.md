# WebView's current Android provider package

GMS reached the missing static `WebView.getCurrentWebViewPackage()` query.
The getter now returns null without initializing WebView or calling the native
browser transport. This follows the nullable
[API-28 contract](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r3/core/java/android/webkit/WebView.java):
the API returns the loaded or selected Android provider package, and null when
none exists. The target has no Android WebView provider package or update
service. Its real, separately launched WebKit browser helper does not supply
an Android provider's PackageInfo.

The provider appends one public static no-argument PackageInfo method. All 42
existing methods, two private fields, constructors, callbacks and six native
declarations remain unchanged. WebView is consumed by the native70 generator;
the changed canonical input requires a fresh coupled DSO and its provenance,
even though this getter adds no native declaration or JNI call.

Host qualification passed 14 malformed/schema/duplicate-query refusals before
writes and nine mutation controls, followed by API-28 baseline and patched
assembly and two stable DEX roundtrips. Controls reject fabricated package
objects, instance/private/wrong-return methods, provider initialization, added
state and changes to constructors, native declarations or native callbacks.
Independent full provider/checker/driver reviews approved. ART fixture and
complete SDK/native deployment audits remain separate checks.

Evidence is retained at
`/Users/alex/.local/state/vinix/android/webview-package-source-check-2026-11-03-r1`,
including frozen source closure, generated C, input pins, controls and DEX
results. Receipt SHA-256:
`5cec87de478a07833d535d8961afe4a5c1b6b7cdae8521f4eebf4f64dcad3371`.
Recorded source parent: `467a8e4c7230275672dcae8617e0fb58e68e1933`.
Parent Build ABI SDK manifest/JAR SHA-256:
`23c75e5be1445f177d7a6a801f907235d166b7a0f541c41bf0895f861bbed3e9` /
`251753fdee85367880a9b0c48d1cb0058fd17a819e4651a8dc29f232673f531f`.

One guard invocation was rejected before execution because its generated-root
path contained the control-output paths. Its exact rejection text is retained
in `controls/run-rejected.txt`; no receipt or proof output was overwritten.
The corrected first actual proof execution and every compiler/Java phase
exited zero with complete cleanup. Proof took 7.203 seconds with sampled
232,472,576 bytes aggregate RSS, detailed 182,829,056 bytes RSS and zero swaps.
Split compiler sampled/detailed maxima were 269,762,560/278,511,616 bytes.
Original limits remain 600 MiB RSS, 300 seconds, 512 MiB shared-volume growth,
1 GiB reserve, 4 MiB output and file cap 16777216.
