# Separate WebKit engine foundation

`build-support/android/webviewengine` implements a separate V process using
WebKitGTK 2.48.1 / GTK 4.24.1. It consumes the bounded `browseripc` protocol on a
connected Unix stream supplied by `browserlaunch`. The engine does not connect
to a caller-selected socket pathname or accept a claimed package/UID.

The launcher must supply an exclusive application UID, clear supplementary
groups/capabilities and inherited Android loader settings, authenticate a
private Xvfb server with a private Xauthority file, and verify the complete
immutable browser library/helper closure. The engine rejects elevated
effective IDs, the diagnostic sandbox-disable variable, public/linked profile
files, and a second engine using the same profile. These checks do not qualify
WebKit's sandbox on Vinix: sandbox-enabled WebProcess startup still requires
execution evidence. Production must fail if that startup is unsupported.

One principal-owned `WebKitNetworkSession` supplies both the displayed views
and the native CookieManager operations. `flush()` enumerates that session and
commits a complete, bounded SQLite snapshot under the private locked profile
before acknowledging the request. The snapshot includes session cookies,
nullable expiry, domain, path, Secure, HttpOnly and SameSite. Startup restores
the snapshot through WebKit's asynchronous cookie API before admitting any
commands. WebKit remains the authority for live cookies; the snapshot is used
only for durable flush and restart. SoupCookieJarDB is not used because it
excludes session cookies and does not expose checked durable completion.

All-cookie and session-cookie removal enumerate and delete real WebKit
cookies, then durably replace the snapshot before returning the Boolean result.
An empty successful snapshot replaces old state, so clearing cannot resurrect
the old jar after restart. Enumeration, deletion, restoration, storage and
deadline failures report failure or close the channel. No completion is sent
after the channel closes. Cookie operations serialize command admission and
use the same 30-second deadline as the JNI wait.

Views default to JavaScript disabled until an explicit setting command. Pixels
come from real asynchronous viewport snapshots; stale navigation, destroyed
view and resized-view snapshot completions are discarded. Pointer, physical
key and wheel input uses the private X server's XTest path. Committed UTF-8 text
uses WebKit's asynchronous editable-focus query and native `InsertText` editing
command: the [public API routes to the page's editing command](https://github.com/WebKit/WebKit/blob/webkitgtk-2.48.1/Source/WebKit/UIProcess/API/glib/WebKitWebView.cpp),
and [WebCore runs its typing command](https://github.com/WebKit/WebKit/blob/webkitgtk-2.48.1/Source/WebCore/editing/EditorCommand.cpp).
It does not inject JavaScript or implement preedit composition. Physical
key callers supply modifier press/release events separately. Input ACK means
admission to the engine, not acceptance by the website or successful login.

## Build and checks

Use the repository's V compiler with `-gc vgc`. Its cross-OS driver disables
Boehm, including an explicit `-gc boehm`, so the helper refuses builds without
VGC. Async callback objects remain explicitly rooted in engine-owned maps
until GLib completes them. Keep the generated executable outside Git.

```sh
v -gc vgc -os linux -arch arm64 -cc aarch64-linux-musl-gcc -cflags -O2 \
  -path '/path/to/v/vlib|/path/to/vinix/build-support/android' \
  -o /external/state/webview-engine build-support/android/webviewengine

v -gc none -enable-globals -path '@vlib|/path/to/vinix/build-support/android' \
  test build-support/android/webviewengine

v run tests/android-webview-engine/verify_symbols.v \
  aarch64-linux-musl-nm BASE_RUNTIME:ADDON_RUNTIME \
  build-support/android/webviewengine/api.v /external/state/symbol-audit.json \
  build-support/android/browsercookies/store.c.v

v run tests/android-webview-engine/build.v REPO V_COMPILER \
  BASE_RUNTIME ADDON_RUNTIME FRESH_EXTERNAL_ROOT
```

The build runner freezes the compiler-selected V closure and test/tool sources,
builds the copied modules, checks they remain unchanged, and records command
arguments, tool hashes, complete logs, binary and artifact checksums. It does
not execute the guest.

Cookie coverage executes the production callback bodies against controlled
WebKit completions and real SQLite storage. It checks full attribute/session
round trips, restore barriers, clear/no-match results, empty snapshots,
storage/backend failures, callback lifetimes and deadlines. The protocol tests
check exact request/completion identity. The native checker extracts the real
JNI bodies and verifies 19 success/error cases, reply ownership, and Java
exceptions after releasing the browser mutex; five compiled mutations must fail:

```sh
VINIX_V_COMPILER=/path/to/v_old276 v run \
  tests/native-android-ws/check-webview-cookie-native.v /external/state/native-cookie-check
```

The ABI audit reads AArch64 exports without loading foreign libraries, requires
each library to exist in exactly one supplied runtime root, and records source
and library SHA-256 digests. It checks symbol availability, not C ABI correctness
or runtime behavior. The helper invocation is:

```text
webview-engine --control-fd N --profile ABSOLUTE_PRIVATE_DIRECTORY
```

On 2026-10-26, against protocol revision `e261fafd6`, six host security/input/ABI
validation tests passed, the Linux AArch64 VGC cross-build passed, and all 68
resolved APIs were present in the pinned libraries. The ABI test preserves the
high word of GType across the resolved getter/constructor calls; GType uses
64 bits on AArch64. Evidence is outside Git:

```text
/Users/alex/.local/state/vinix/android/account-contract-webview-engine-build-2026-10-26-r5
```

The bundle contains 284 V source files captured over base revision
`e8024080aa7ad38b8c166d91819cc3981d0f9bbb`. Its complete 305-file retention
manifest SHA-256 is
`59515b41e0fc98c3390df9cce7877147f3a2472ec5a1be1493b2fb862d9aedf6`.
The helper SHA-256 is
`98b31d7b5ce52280600116bd076d6f8f387c6d6c28888135acd8135645d4f088`.
The source inventory pins the working source overlay used by the checks.

Compiler executable SHA-256:
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`.
The cross-built executable contains `vgc_gc_run`, `vgc_mark_roots` and
`v3_vgc_runtime_init`, and its direct dynamic dependency is `libc.so`.

No execution of this production helper is claimed by these checks. Required
follow-up evidence includes sandbox-enabled startup, changing viewport pixels,
native pointer/key/UTF-8 editing in a local form, asynchronous policy handling,
shared cookie visibility, cookie persistence after helper restart, and closure
after peer EOF. Google-account authentication and Maps account adoption remain
unverified until the real end-to-end flow passes.
