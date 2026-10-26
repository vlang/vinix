# Foundation search-path checkpoint — 2026-10-26

Tested implementation and evidence tools revision:
`c88d29929d9761951191429c5104a1e812c4573c`. Advertising work remains skipped.

`NSSearchPathForDirectoriesInDomains` now supports the user Library (5),
Documents (9), Caches (13) and Application Support (14) directories, including
tilde paths and the existing Documents override/container convention. Queries
copy bounded UTF-8 paths into owned strings, return autoreleased arrays with
balanced element ownership, and perform no filesystem operations. Unsupported
directories/domains and invalid container paths are rejected.

Native macOS and emulated host checks pass under ASan/UBSan with normal and
deterministic Swift hashing. They cover all four directories, Unicode/root/
trailing-slash/borrowed paths, a protected input boundary, the 1,023-byte limit,
invalid inputs, retained arrays/strings, eight concurrent workers and two drained
runtimes. Home-directory checks also pass after removing the old assumption
that a Documents query creates directories. Sanitizer leak detection is disabled;
the emulated ownership checks assert that tracked live objects return to zero.
All eight guest build targets pass. The ARM64 guest passes both path fixtures,
alongside the existing VM/tag, Blocks, dictionary and inline-pthread-self checks.

The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
Static inspection finds 19 direct callers of the Foundation search-path thunk.
The diagnostic launch observes one call with directory 14, domain 1 and tilde
expansion enabled, returning `/opt/Library/Application Support`. The previous
search-path panic is gone. Startup now stops at
`V panic: iOS: CFString output encoding is not implemented`.

The explicit `--probe-no-ads` diagnostic binds SKAdNetwork to nil and changes
application behavior. All three images bind/register, all nine Objective-C
`+load` calls finish, and three initializer-stage markers appear. All 13 inline
pthread-self reads are translated. The only fault is the deliberate signal
fixture, which captures all 31 ARM64 registers and restores execution.
The application exits 1 (wait status 256); the complete diagnostic harness exits
0. Its exact 24 GiB tagged virtual reservation succeeds at `0x80098308000`;
errno 22 is stale after success. This does not commit 24 GiB of physical memory.
Seven headroom queries return 663,184,294 or 662,651,430 bytes. The final
application cgroup records zero `oom` and `oom_kill` events with a 2 GiB limit.

Progress remains **2 of 8 observable gates (25% of this checklist)**: image
loading/binding and all `+load` calls pass. Initializer completion, application
entry, a rendered frame, an interactive menu, login and a playable match remain
unverified. This fraction does not estimate remaining engineering effort or time.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/search-paths-20261026`.
It contains 1,169 source records, 693 selected input records and 1,643 manifest
records, including the application/frameworks, generated C, sanitizer objects,
TLS archives, runners/tools, command/status logs and complete guest media.
`probe-no-ads-state.txt` selects `probe-no-ads-1063708`.
SHA-256 of `manifest.sha256`:

```text
0de745fa26e9ce96937cc51412afe6df1307e2e8c2d0c19a8cd7a5b7e6fdd8ab
```

The search-path evidence tool's seal, independent check and selftest pass.
It rejects missing media, altered reservation diagnostics, missing fixture
validation, failed fixture waits, changed search arguments/path/count,
changed translation/panic/exit boundaries, extra faults/panics, altered logs and
unmanifested files. Historical checkers remain unchanged. The prebuilt ARM64
kernel is inventoried; concurrent kernel edits were not rebuilt. Selected input
hashes do not seal the complete compiler, header or host-library closures.

Reproduce using the frozen toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, setting `V_RESOURCE_PATH`
there and `V_MACOS_V3_NO_FALLBACK=1`. Compile `notification-checks.v`,
`notification-vm.v`, `search-path-run.v`, `inspect-search-path-calls.v`,
`image-initializers-input-inventory.v` and `search-path-evidence.v` with
`-nocache -prod -gc none -cc clang`; notification tools need the `tests/ios`
module path, and the inspector needs `compat/ios`. Run the notification wrapper's
`search-path-host` mode in the external bundle and `home-directory-host` in its
`home-directory` subdirectory, then the checkpoint runner's `build` and `probe`
modes. The runner selects the 2 GiB cgroup budget and gzip level 9. Inspect the
import stub at `0x10c63cf54` and forwarding thunk at `0x107c28230`, retaining
their respective outputs as `search-path-import-thunk.txt` and
`search-path-calls.txt`. Preserve the application, capture source/input inventories,
then run the evidence tool's `seal`, `check`, `selftest` and `hash` modes.
