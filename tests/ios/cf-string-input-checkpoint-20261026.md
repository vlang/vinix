# UTF-16 CFString input checkpoint — 2026-10-26

Runtime fix: `8c380dbf866f4db847e2314319cdce06a70532d8`.
Failure trace: `a38cc95e1f5b0f73363b4539fa4fdac7abab49b8`.
Audit tools: `3da7efde46560d994da79aa49762be49dcbd8b6d`.
Advertising remains skipped.

The previous startup failure receives native UTF-16 (`0x00000100`), 338 bytes,
with external representation disabled. The bounded diagnostic captures the
first eight bytes, `4600610069006c00`, which decode as `Fail`. The complete
message was not captured, so its underlying cause is still unverified.

`CFStringCreateWithBytes` now accepts native, little-endian and big-endian
UTF-16. Native internal input uses host order; external input defaults to big
endian and consumes an initial endian-switching BOM. Explicit endian input
retains its BOM. The decoder copies source storage, handles unaligned input,
combines surrogate pairs and preserves lone surrogate code units. Odd trailing
bytes and one-byte inputs follow the observed native behavior. UTF-8 output
stops before lone surrogates, including when a loss byte is supplied.

Validation passes:

- A native Core Foundation oracle records 420 input cases and 570 UTF-8 output
  observations. The trace bundle preserves its original 420-case oracle and
  reproduces it exactly using the recorded source revision.
- Native and emulated C ABI tests cover endian/BOM handling, odd input,
  embedded NULs, surrogate preservation, source ownership, unaligned pointers
  and guard pages for lengths 0–17. Runtime object counts return to zero after
  repeated cycles. Existing CFString output cases also pass.
- All eight host build/execution steps pass, including normal and deterministic
  hashing ASan/UBSan runs with assertions enabled. Leak detection is disabled;
  sanitizer errors are fatal. A fresh ARM64 CFString fixture and application
  runner build successfully; all 13 guest regression fixtures return wait
  status zero.
- Both complete bundles pass evidence seal, independent check and mutation
  selftest. Mutations include failed fixtures/builds, missing native/runtime
  cases, changed panic/startup/desktop/exit/memory observations, missing fault
  registers or guest media, altered provenance and unmanifested files. The
  original historical checkers remain unchanged.

Fortnite advances past the encoding failure and reaches this next boundary:

```text
V panic: iOS: unimplemented Objective-C method IOSAppDelegate performSelectorOnMainThread:withObject:waitUntilDone:
IOS-PROBE-DESKTOP: stop=Broken pipe handshake=true builds=2 polls=1 closed=false supervisor_kill=false wait=256
IOS-PROBE-BUDGET: final current=27178 events=low 0;high 0;max 0;oom 0;oom_kill 0;oom_group_kill 0;
FORTNITE PROBE: process exit status 1
FORTNITE PROBE COMPLETE
```

Harness status zero means the diagnostic completed. The application exits 1
naturally, with raw wait status 256 and no supervisor kill or cgroup OOM.
The desktop peer validates two application tree builds, each 336 bytes with
one root and no images. The second tree's serial line is interleaved with VM
tracing; the final peer record confirms both builds. This peer has no compositor
or input device, so these observations do not qualify rendering.

Both probes retain three loaded/bound images, nine completed Objective-C
`+load` calls, three completed initializer groups, application entry and all
13 inline pthread-self translations. A tagged 24 GiB virtual reservation
succeeds; eight process-headroom queries remain positive inside the 2 GiB
cgroup. The sole signal fault is deliberate regression-fixture input, with all
31 ARM64 registers captured and execution restored.

Progress remains **4/8 observable gates (50% of this checklist)**: load/binding,
Objective-C `+load`, image initialization and application entry are verified.
A rendered game frame, interactive menu, login and playable match remain
unverified. This fraction does not estimate remaining work or time.
`--probe-no-ads` binds SKAdNetwork to nil and changes application behavior.

Complete evidence is preserved outside Git:

| Phase | Bundle under `/Users/alex/Library/Caches/vinix-ios/` | VM state | Manifest records |
| --- | --- | --- | --- |
| Failure trace | `cf-string-input-trace-20261026` | `probe-no-ads-682291` | 1419 |
| Fixed decoder | `cf-string-input-20261026` | `probe-no-ads-384916` | 1563 |

Each bundle contains 1211 runtime-source records and 698 selected build-input
records. The three audit-tool sources are recorded separately at the audit
revision above. SHA-256 of the trace `manifest.sha256`:

```text
f9d617fa206f900178a0796f63915ebaac44e8141cb7a21c94a5f84d18918a44
```

SHA-256 of the fixed `manifest.sha256`:

```text
294e15b834d314df3333d5d4924c7cb0fe540355c93a4c9cfdf87e9b88483bed
```

The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
Each application copy is an APFS clone, checked completely against the prior
manifest. The trace reuses 28 binary/generated-C files; the fixed probe reuses
26, rebuilding the CFString pair. Preserve the complete prior bundle at
`/Users/alex/Library/Caches/vinix-ios/desktop-probe-20261026`, manifest SHA-256
`d2104f9f7bc841ce3cd3ee369469a1d7378df75eeedf10f248415d87b1700ab1`.
Its full independent checker passed before preparing both new bundles.
The prebuilt kernel is inventoried, not rebuilt. Selected build-input hashes
do not seal complete compiler, header or host-library closures.

Reproduce using an isolated checkout of the runtime revision above, the frozen
compiler at `build/ios/fortnite/ns-calendar-checks/toolchain/v`, and a fresh
external output directory. Set `V_RESOURCE_PATH` to that toolchain directory,
`V_MACOS_V3_NO_FALLBACK=1` and `V_C_ERROR_BUG_REPORT_DISABLED=1`. Compile
`tests/ios/cf-string-input-run.v` with `-nocache -gc none -cc clang -cflags -O2`
and without `-prod`, preserving assertions. Run its `prepare OUT PRIOR`,
`fixture OUT`, `build OUT`, `host OUT` and `probe OUT` modes. For the failure
trace, use the trace revision and omit `fixture` and `host`.

For auditing, compile the driver from the audit revision with the same flags;
run it from that revision's checkout with `audit OUT RUNTIME_REVISION fixed`
(or `trace`). It exports the recorded runtime source and its own separate audit
source, builds the assertion-enabled checkers and reruns the native oracle.
Then run `OUT/cf-string-input-evidence seal OUT`, `check OUT` and `selftest OUT`.
Use its `hash OUT/manifest.sha256` mode to obtain the manifest digest. Exact
commands, statuses, generated artifacts, boot media and serial logs remain in
each complete bundle.
