# Foundation HTTP checkpoint — 2026-10-26

Runtime, fixtures and evidence tools revision:
`92f2c96d66bcbea20167714ec016c0b038a2a443`.
Advertising work remains skipped.

`NSData +dataWithContentsOfURL:` now loads HTTP and HTTPS URLs, preserving the
requested class, including NSMutableData, and existing file-URL behavior.
Responses have a 16 MiB body bound, a 64 KiB aggregate header/framing bound and
a limit of six requests including redirects. Socket operations, TLS handshakes,
redirects and response reads share a ten-second monotonic deadline; DNS retains
the platform resolver's timeout. TLS uses V's bundled mbedTLS with required
certificate and hostname verification, SNI and `/etc/ssl/cert.pem`. HTTPS
redirects cannot downgrade to HTTP. Failed transport, non-success status, malformed or truncated
framing, unsupported content encoding and oversized responses return nil.
Sockets, TLS state and response storage are released on success and failure.
NSURLConnection's network transport remains unsupported.

Supported URLs use ASCII host names or addresses, optional ports and encoded
request paths/queries. IPv6 literals, userinfo and internationalized host names
are rejected. Redirects support absolute, scheme-relative, root-relative,
path-relative, query and fragment references; dot segments are not normalized.
EOF-delimited HTTPS responses require TLS close-notify.

The assertion-enabled ARM64 HTTP fixture passes ASan+UBSan normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. It checks binary, empty, EOF, informational,
content-length and chunked responses; malformed, truncated and oversized
responses; redirect limits, deadlines and URL validation; trusted TLS,
hostname/CA rejection, close-notify, downgrade rejection and closed-peer sends.
The native Foundation oracle checks the factory ABI and binary result.
Mutable results, retained data, concurrent loads and two zero-live-object
runtime shutdowns pass. File-URL and NSURLConnection regression fixtures also
pass in both modes. Runner C uses `-O0 -g`; bundled TLS uses `-O1` with the
same sanitizers. Leak detection was disabled. Guest and host TLS archives are
built separately, with their expected object membership checked before linking.

The startup host and both guest programs build successfully. Host and Vinix
ARM64 QEMU diagnostic probes pass all nine ordered Objective-C `+load` methods
and print initializer-stage markers for EOSSDK, MarketplaceKitWrapper and the
main executable. Neither the previous unsupported Foundation selectors nor the
HTTP/HTTPS unsupported panic appears. Both probes print
`Using MallocBinned3 allocator.` before a later crash.

The host reports an ASan write fault at address `0x000000000003` and exits with
status 134. The guest reports signal 11, wait status 35584 and process status
139, followed by the diagnostic completion marker. Harness status 0 means that
the guest probe completed. The crash's cause is undetermined. Initializer
completion, application entry, rendering, login and gameplay remain unverified;
successful HTTP/HTTPS loading inside Fortnite is not established by these
probes. `--probe-no-ads` binds SKAdNetwork to nil and changes application
behavior; ordinary launch still requires SKAdNetwork.
Executable SHA-256:
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/foundation-http-20261026`.
Manifest SHA-256:
`e445cb2ca779d49d70ebe8f3226e799b08863c0abda37190cc4754f5ffc0d524`.
The manifest covers 1,871 files, including 1,144 source snapshot files; the
inventory records 691 selected build-input hashes.

Evidence sealing, validation and self-test pass. The self-test rejects missing
guest boot media, a changed HTTP fixture log and an unmanifested file, then
restores and revalidates the bundle.

The bundle preserves the source snapshot, fixture apps, generated C and host
objects, compiled runners and helpers, TLS archives and objects, ephemeral
fixture certificate/key, command/status logs, unchanged application and
frameworks, and complete guest boot media, initramfs, firmware variables,
Limine configuration and serial log. Selected input hashes include bundled
TLS sources, CA certificates, compilers and selected headers; they do not seal
compiler, header or host-library closures. The prebuilt kernel is inventoried;
concurrent kernel edits were not rebuilt. The preceding failure and its
complete sealed bundle remain in the
[file and memory checkpoint](foundation-file-memory-checkpoint-20261026.md).

Reproduce with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, `V_RESOURCE_PATH` set there
and `V_MACOS_V3_NO_FALLBACK=1`. Compile the V helpers with
`-gc none -nocache -cc clang`, adding `-prod` for the evidence checker.
Run notification-checks modes `data-http-host`,
`data-url-host` and `connection-host`, each into its own external directory.
Use startup-host `build OUT` then `probe-no-ads OUT APP_EXECUTABLE` for host
diagnostics. Use notification-checks `build-init`, `build-run-ios-gles` and
`probe-no-ads` for the guest, with `VINIX_IOS_VM_GZIP_LEVEL=9` for this run.
Exact invocations are in command logs. Run image-initializers-input-inventory
with repository root, bundle directory and tested revision, then
foundation-http-evidence modes `seal DIR`, `check DIR`, `selftest DIR` and
`hash FILE`. Historical evidence checkers are unchanged.
