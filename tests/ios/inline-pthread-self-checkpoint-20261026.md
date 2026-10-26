# Inline pthread-self checkpoint — 2026-10-26

Tested implementation and evidence tools revision:
`8db5ee47f861dde911d8d5fd3989a56c24c960ec`. Advertising work remains skipped.

The ARM64 loader translates the application's two inline Darwin pthread-self
idioms to native pthread calls. Trampolines preserve general/vector registers,
floating-point state, flags, SP/LR and the Darwin red zone. Image mappings reserve
nearby trampoline space before loading, including for the large application;
cleanup releases this space with the image. Host ASan/UBSan checks pass with both
normal and deterministic Swift hashing. They recognize all 13 reads in the
unchanged application, check invalid instruction patterns and branch bounds,
and exercise worker threads, native TLS/errno and repeated unloads. The ARM64
guest passes the same execution and large-image-placement fixtures, alongside
dictionary snapshots, Blocks captures, VM/tag and signal-context checks.

All six guest build targets pass. The unchanged Fortnite 42.30.1 executable has
SHA-256 `6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The explicit `--probe-no-ads` diagnostic binds SKAdNetwork to nil and changes
application behavior. All three images bind/register, all nine Objective-C
`+load` methods finish, and three initializer-stage markers appear. The loader
reports translating all 13 inline pthread-self operations. The former null
thread-data SIGSEGV is gone; the only fault is the deliberate signal fixture,
which records all 31 ARM64 registers and restores execution successfully.

Startup now stops at `V panic: iOS: unsupported Foundation search path/domain`.
The application exits 1 (wait status 256); the complete diagnostic harness exits
0. Its exact 24 GiB tagged virtual reservation succeeds at `0x8009b884000`;
errno 22 is stale after success. This reservation does not commit 24 GiB of
physical memory. Seven headroom queries return 663,217,062 or 662,684,198 bytes.
The final application cgroup has zero `oom` and `oom_kill` events with
`memory.max=2147483648`.

Progress remains **2 of 8 observable gates (25% of this checklist)**: image
loading/binding and all `+load` calls pass. Initializer completion, application
entry, a rendered frame, an interactive menu, login and a playable match remain
unverified. This fraction does not estimate remaining engineering effort or time.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/inline-pthread-self-20261026`.
It contains 1,164 source records, 692 selected input records and 1,490 manifest
records, including application/frameworks, generated C, sanitizer objects and TLS
archives, runners/tools, command/status logs and complete guest media.
`probe-no-ads-state.txt` selects `probe-no-ads-1353166`. An earlier failed
trampoline-placement probe is retained separately in the same bundle.
SHA-256 of `manifest.sha256`:

```text
8543df20d93ca9a06ea8d93f53461f523d51299a4fcd5dc51c75576025a4c38a
```

The inline-pthread-self evidence tool's seal, independent check and selftest
pass. It rejects missing media, changed reservation size/tag/results/traces,
missing inline/large-image validation, changed translation counts, changed
panic/exit boundaries, extra faults/panics, altered logs and unmanifested files.
Historical checkers remain unchanged. The prebuilt ARM64 kernel is inventoried;
concurrent kernel edits were not rebuilt. Selected input hashes do not seal the
complete compiler, header or host-library closures.

Reproduce using the frozen toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, setting `V_RESOURCE_PATH`
there and `V_MACOS_V3_NO_FALLBACK=1`. Compile `notification-checks.v`,
`notification-vm.v`, `inline-pthread-self-run.v`,
`image-initializers-input-inventory.v` and `inline-pthread-self-evidence.v` with
`-nocache -prod -gc none -cc clang`; the notification tools need the `tests/ios`
module path. Run the notification wrapper's `inline-pthread-self-host` mode with
`VINIX_IOS_INLINE_SELF_IMAGE` pointing to the unchanged executable, then the
checkpoint runner's `build` and `probe` modes. The latter selects the 2 GiB
cgroup budget and gzip level 9. Preserve the application, capture source/input
inventories, then run the evidence tool's `seal`, `check`, `selftest` and `hash`
modes against the external bundle.
