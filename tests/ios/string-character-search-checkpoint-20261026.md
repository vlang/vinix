# NSString character search checkpoint — 2026-10-26

Runtime, fixture and evidence tools revision:
`8dbd982d55018b370a1214189b14f3051a853620`.
Advertising work remains skipped.

Fortnite's `FIRMessaging +load` calls `rangeOfCharacterFromSet:` on a loader
constant string (flags `0x7c8`, byte length 8). The unimplemented selector fell
through to an allocation-header lookup, producing the preceding
`iOS: object has no live runtime metadata` panic. The new checked search borrows
validated string and character-set storage under the runtime lock and returns
the first matching scalar's UTF-16 location and length in the ARM64 NSRange
registers. It supports built-in NSString/NSMutableString objects and validated
loader constants without synthesizing object headers. Other search overloads
and public character-set range factories remain unsupported.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`; leak detection was disabled. The same 176
Unicode searches run against the compatibility runtime and Apple Foundation,
with matching method metadata, plus mutable-set/string operations and nil
receiver behavior. Runtime cases cover UTF-8/UTF-16 loader constants, embedded
NULs, combining characters, supplementary scalar pairs, first-match behavior,
the accepted 16 MiB byte limit and two fully drained runtime cycles. All 23
invalid receiver, constant, encoding, size and character-set cases fail
explicitly. An independent Apple oracle and its 88 search rows are preserved.

The unchanged executable reaches these seven `+load` methods in order on both
the ARM64 macOS host and the Vinix ARM64 QEMU guest: FIRMessaging,
FIRInstallations, GDTCCTUploader, GDTCORFlatFileStorage, GDTCORLifecycle,
GDTCORMetricsController and GDTCORApplication. The guest then reports signal 11,
wait status 35584 and process status 139, followed by the diagnostic completion
marker. Harness status 0 means the probe completed, not that the app launched.

The host probe aborts with status 134 and one ASan null-read report at mapped
PC `0x13d69f674`, mapping base `0x13d604000`, application offset `0x9b674`
(preferred PC `0x10009b674`). The faulting instruction is `ldr x4, [x8]` after
loading a null pointer from the slot at preferred address `0x10dc981e0`. The
stack includes a block invocation and `dispatch_once`. The source of the null
slot remains to be identified. Neither probe reaches application initializers
or entry; rendering, login and gameplay remain unverified. `--probe-no-ads`
binds SKAdNetwork to nil and changes application behavior; the ordinary launch
still requires it.
Executable SHA-256:
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/objc-load-probe-20261026`.
Manifest SHA-256:
`84fe7355c7767ad030329f859714dcd6b54ba73a5a59c4cba4d5475c11c98a60`.
The manifest covers 1,248 files, including 1,132 source snapshot files; the
input inventory records 74 selected build-input hashes.
Evidence `seal`, `check` and `selftest` all pass. The self-test rejects missing
guest media, a changed fixture log and an unmanifested extra file, then restores
and revalidates the complete bundle.

The bundle preserves the committed source snapshot, selected build-input
hashes, baseline LLDB inspection, Apple oracle, bounded application disassembly,
baseline/updated host generated C and objects, fixture app, compiled runners
and helpers, command/status logs, application executable/frameworks, and the
guest's complete boot image, initramfs, firmware variables, Limine configuration
and serial log. Selected hashes do not seal compiler, header or host-library
closures. The prebuilt kernel is inventoried; concurrent kernel edits were not
rebuilt. The preceding guest panic and its original complete bundle remain in
the [initializer checkpoint](image-initializers-checkpoint-20261026.md).

Reproduce with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, `V_RESOURCE_PATH` set there
and `V_MACOS_V3_NO_FALLBACK=1`. Compile the V helpers with
`-gc none -nocache -cc clang`. Run notification-checks mode
`string-character-search-host` into an external directory. Use startup-host
`build OUT` then `probe-no-ads OUT APP_EXECUTABLE` for host diagnostics; use
notification-checks `build-init`, `build-run-ios-gles` and `probe-no-ads` for the
guest. Exact build/probe invocations are in the command logs. Run the inventory
with repository root, bundle directory and tested revision, then the new
string-character-search-evidence modes `seal DIR`, `check DIR`, `selftest DIR`
and `hash FILE`. Historical evidence checkers are unchanged.
