# WebView defining loader, 2026-11-15

The [content-parent and AlertDialog repairs](maps-window-content-runtime-20261115.md)
passed the full signed ARM suite in r101. Real Maps opened the chooser and
Add account progressed past the previous layout callback. GMS then failed on
the missing WebView.getWebViewClassLoader()Ljava/lang/ClassLoader; API.
The complete r101 public export and private disk copy are retained and checked;
the owned guest is stopped. No credentials were entered.

The new V adapter returns the actual defining loader of Vinix's framework
WebView implementation. It does not consult the application or thread context
loader, initialize the native transport, select a provider package or claim
Chromium support. A missing defining loader raises IllegalStateException.
The existing getCurrentWebViewPackage query still returns null. Android's
[API contract](https://developer.android.com/reference/android/webkit/WebView#getWebViewClassLoader())
requires a non-null loader for internal WebView classes, for use by the support
library. Vinix's Java WebView internals live in the framework boot class path.

The signed fixture compares loader identity, repeated query identity and the
actual loaded WebView, WebSettings and CookieManager classes. It installs a
hostile context loader and verifies that it receives no calls, restoring the
original loader on both success and exception. It repeats the checks on a
worker without a Looper, and checks that no provider package is advertised.

External evidence root: /Users/alex/.local/state/vinix/android.
Source parent: c70b52dbc; adapter, SDK builder and fixture are in this change.
Builds use current /Users/alex/code/v/v, V 0.5.2 cbfc1be. Successful guards keep
RSS 629145600, wall 300000 ms, reserve 1073741824, growth 536870912 and output
4194304 bytes, exit/child 0/0, empty reason and complete cleanup. Raw inputs,
generated C, inventories, binaries and receipts remain outside Git.

| Check | Evidence stem | Time ms | Peak sampled RSS | Observed growth |
| --- | --- | ---: | ---: | ---: |
| SDK assembly, DEX readback, nine input refusals | framework-webview-loader-20261115-r1 | 1910 | 482246656 | 27869184 |
| Full native producer and AArch64 GCC -Werror link | webview-loader-native-20261115-r1 | 8856 | 579190784 | 9519104 |
| Signed shared-display fixture assembly and signature check | current-api-webview-loader-20261115-r1 | 835 | 175702016 | 921600 |

| Candidate artifact | SHA256 |
| --- | --- |
| framework-webview-loader-20261115-r1/classes.dex | 92b68eb2786b011c380f9bc75d98b46edf74d6caab6a72a1378c3b143f108adc |
| webview-loader-native-20261115-r1/native/libvinix-android-native.so | f22029254d0829f6271294c8fb7da24c5665f1204efc6329db2daf81c6f6bace |
| current-api-webview-loader-20261115-r1/probe.apk | e7e87abc9a6ce5604d5a3a2f240acf9e09bdbb59d08722f505fb67d08bc3062c |

The full signed ARM API suite passed in fresh r102, child exit 0. The retained
child log contains WEBVIEW-LOADER-PASS and CURRENT-API-PASS, including defining
loader identity, framework class loading, hostile context loader, worker and
unchanged absent provider package. The complete API export reconstructed
without removals: 23607 bytes / 47 chunks.

| r102 ARM API evidence | SHA256 |
| --- | --- |
| maps-webloader-api-uart-20261115-r1/full.log | a7e16109c37b9e50f50f56b338d8de7aea32d84fe0b7faf4ea750e74609b2a12 |
| maps-webloader-api-readback-20261115-r1/archive.json | 40cf82a089acadf5efb3f873b4f2ab560c36f979326febea27820b6faa92b121 |
| maps-webloader-api-child-20261115-r1/child.log | b919d20a546d4a95303ce5c659dc1f06c6b5b6fe9585f547458f1a9ced04a909 |

In r102, GMS PID29873 reached readiness. Its descriptor snapshot captured
245 entries, unavailable=0, non_atomic=true. Maps PID15250 launched once,
opened the chooser and attempted Add account once. The loader failure is gone;
account fragment creation then failed with IncompatibleClassChangeError:
GMS class attt implements android.webkit.ValueCallback, but the retained SDK
declares that type as a class. No credentials were entered and no restart was
attempted. The [callback interface repair](maps-value-callback-20261115.md) is
prepared separately; its qualification is blocked by host disk pressure.

The checked data volume UUID was 7ec5976cb3af4fd48f8e9dd7bba2851d. The full
private API/account results were copied to r102-private and synced, with the
copied receipt and prompt observed before stopping owned QEMU66337. PID absence
and no image handles preceded read-only extraction. e2fsck passed. The storage
watch is partial. Complete private evidence is under
maps-current-20261115-r102-account/private-readback. Logs match their private
manifest. The complete public Maps export reconstructed without removals:
1429550 bytes / 2793 chunks, receipt identical to the private copy.

| r102 account evidence | SHA256 |
| --- | --- |
| maps-r102-uart-20261115-r1/interval.log | b60d92adb9102fc747e3b9fa386fff72f00b4710c20fead63c6c6d572f8ef8b0 |
| maps-r102-readback-20261115-r1/archive.json | 6effe83e16495aebef701f73163bdb33fdcd33014707958cc63df32a745d6097 |
| Same readback/exported-receipt.json | 23800a184f7ae2ace053bca79d63bea728725c8d596da5a691ab7f2c47642d7c |
| Private r102-private/results/broker.log | e5bfe131b5c28f8d5ef92ab1f4076302835326d7b7166c3c36781dde9cb70853 |
| Private r102-private/results/maps.log | 15df2664b9beb312a7eed4d5eececa81635d73f8cfcef4b427c99be72ebac557 |

Google Maps remains incomplete; no Google authentication success is claimed.
