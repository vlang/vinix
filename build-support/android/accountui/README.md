# Authenticator window bridge

This helper displays the existing authenticator process's VSF1 framebuffer in
a normal desktop window. It forwards desktop events through the existing VNI1
`WsEvent` input ABI. It never starts ART, recreates an Intent, or owns the account
session. The authenticator retains its Application, Activity and response Binder.

The root broker launches `/usr/libexec/vinix-android-account-ui` under the verified
desktop UID/GID, with only these inherited descriptors:

```text
--surface-fd N --input-fd N --lifetime-fd N [--window-socket PATH]
```

All descriptors must be distinct and at least 3. The lifetime descriptor is a
connected Unix stream whose kernel peer UID is root; incoming bytes are forbidden.
The helper sends exactly one byte, `0x01`, after receiving CREATED and mapping
the destination surface. This is the readiness gate before the broker attaches
the source and input reader to the retained service. There are no further bytes.
The broker keeps its peer open for this one account interaction. The helper
rejects setuid/setgid execution. This is an inherited capability interface, not
a public socket service. The launcher must close unrelated descriptors,
especially the opposite lifetime endpoint and input reader, before exec, and
select the desktop principal and endpoint from verified session policy.

The surface descriptor must be an already initialized, writable regular VSF1
file: version 1, header 48 bytes, format 1, active index 0 or 1, reader UINT_MAX,
two complete buffers, and valid bounded dimensions and stride. The broker owns
its size and lifetime and must prevent truncation while either process maps it
(Linux memfd seals SHRINK and GROW). The helper claims/releases the existing
shared reader slot and caches validated geometry. The source must have exactly
one reader. It does not open APK paths.

Input is a pipe writer; the service receives the matching reader. Headers are
single atomic 24-byte writes. Key payloads are at most 4096 bytes and may be
written in pieces, matching nativews's payload read loop. A bounded queue
preserves order across backpressure and clears delivered key bytes. Queue
exhaustion ends the bridge instead of silently losing a button release.

The desktop connection requests feature bits 0: its framebuffer stays fixed,
the compositor scales pointer coordinates, and keys use the existing raw byte
encoding. It uses normal `windowfb` authorization; the desktop peer UID check
remains intact. The helper also verifies the desktop socket's kernel peer UID.
The optional endpoint is selected by the broker. Without it, the ordinary
`windowfb.socket_path()` session/environment rules apply. Production launchers
should provide an explicit verified endpoint and sanitized environment.

Connecting and window creation share a five-second deadline. Exit 0 means
desktop Close or lifetime EOF. Exit 1 means invalid capability, surface,
transport or protocol failure. Every exit closes the input writer and desktop
window; it never sends a signal to ART. The native service must treat input EOF
as UI dismissal and keep its service VM alive. Broker policy decides whether
dismissal cancels the account request.

Build and test with V, keeping outputs outside the checkout:

```sh
v -new-compiler -cc clang -path '@vlib|@vmodules|/path/to/vinix|/path/to/vinix/build-support/android' test build-support/android/accountui
v run build-support/android/accountui/tools/build.v --arch=arm64 --out=/external/state/account-ui
```

The builder also supports `--arch=host`. It records source, compiler, selected
link input, generated C and binary hashes in external `build.json`. Host tests
exercise real Unix streams, nonblocking pipe backpressure, shared mappings,
CREATE/PRESENT/FRAME_DONE, binary keys, malformed surfaces and lifetime EOF.
They do not claim Google authentication or guest UI validation.
