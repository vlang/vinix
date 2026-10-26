# Foundation file and memory checkpoint — 2026-10-26

Runtime, fixtures and evidence tools revision:
`7d8db8a3587506288708f17330c021a132c076ae`.
Advertising work remains skipped.

`NSProcessInfo physicalMemory` now returns an unsigned 64-bit scalar using the
existing hardware-memory query. The native Foundation oracle confirms the
`Q16@0:8` encoding and physical-pages-times-page-size value. Runtime fixtures
check singleton and allocated instances, reflection, preservation of errno and
the indirect-result buffer, and 8,000 concurrent queries per runtime cycle
without new Objective-C objects.

`NSData +dataWithContentsOfURL:` now loads file URLs through the same owned
regular-file reader as NSURLConnection. It preserves the requested data class,
including NSMutableData, and returns nil for missing files, directories and
files over the existing 16 MiB bound. The native oracle and runtime fixtures
cover the factory ABI, empty and binary contents, the 8,192-byte chunk boundary,
Unicode paths with spaces, mutable results, and retained snapshots after pool
drain and file replacement. Runtime checks cover inherited reflection,
200 concurrent loads per cycle, explicit nil/wrong-class/HTTP rejection, and two
zero-live-object shutdowns. NSURLConnection's existing ownership, error,
descriptor, callback, cancellation and pending-work tests also pass after the
shared-reader extraction.

All three assertion-enabled ARM64 host fixtures pass ASan+UBSan at `-O0 -g`,
normally and with `SWIFT_DETERMINISTIC_HASHING=1`; leak detection was disabled.
The startup host and both guest programs build successfully. Host and Vinix
ARM64 QEMU probes pass all nine ordered Objective-C `+load` methods and print
initializer-stage markers for EOSSDK, MarketplaceKitWrapper and the main
executable. Neither preceding unsupported Foundation selector appears.

Both probes now report `iOS: HTTP and HTTPS data loading is not implemented`
from the worker. The host exits with status 1 without a sanitizer report; the
guest records wait status 256, process status 1 and the diagnostic completion
marker. Harness status 0 means the guest probe completed. The host prints
`Using MallocBinned3 allocator.`; the guest does not, so that milestone is not
claimed for both runs. Initializer completion, application entry, rendering,
login and gameplay remain unverified. `--probe-no-ads` binds SKAdNetwork to nil
and changes application behavior; ordinary launch still requires SKAdNetwork.
Executable SHA-256:
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/foundation-file-memory-20261026`.
Manifest SHA-256:
`959c5d5d306be445d52eaf9e3fc3e065e59b52c1c70d29641be10480f20ac904`.
The manifest covers 1,271 files, including 1,138 source snapshot files; the
inventory records 76 selected build-input hashes.

Evidence `seal`, `check` and `selftest` pass. The self-test rejects missing
guest media, a changed file-loading fixture log and an unmanifested extra
file, then restores and revalidates the complete bundle.

The bundle preserves the source snapshot, fixture apps, generated C and host
objects, compiled runners and helpers, command/status logs, unchanged
application and frameworks, and complete guest boot media, initramfs, firmware
variables, Limine configuration and serial log. Selected input hashes do not
seal compiler, header or host-library closures. The prebuilt kernel is
inventoried; concurrent kernel edits were not rebuilt. The preceding failure
and its complete sealed bundle remain in the
[scene notification checkpoint](scene-notifications-checkpoint-20261026.md).

Reproduce with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, `V_RESOURCE_PATH` set there
and `V_MACOS_V3_NO_FALLBACK=1`. Compile the V helpers with
`-gc none -nocache -cc clang`. Run notification-checks modes `processinfo-host`,
`data-url-host` and `connection-host`, each into its own external directory.
Use startup-host `build OUT` then `probe-no-ads OUT APP_EXECUTABLE` for host
diagnostics. Use notification-checks `build-init`, `build-run-ios-gles` and
`probe-no-ads` for the guest, with `VINIX_IOS_VM_GZIP_LEVEL=9` for this run.
Exact invocations are in command logs. Run image-initializers-input-inventory
with repository root, bundle directory and tested revision, then
foundation-file-memory-evidence modes `seal DIR`, `check DIR`, `selftest DIR`
and `hash FILE`. Historical checkers are unchanged.
