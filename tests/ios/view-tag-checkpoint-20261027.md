# UIView tag lookup checkpoint — 2026-10-27

Runtime and audit tools: `1b9d14fd0138aff0fba4276cb23cae1f8c466e53`.
Advertising remains skipped.

`UIView viewWithTag:` now searches the receiver and its descendants in subview
order, returning the first matching signed 64-bit tag. The traversal uses
constant space and returns a borrowed view. UIWindow and application subclasses
inherit it. Native type encodings, selector introspection, method signatures
and direct implementation calls are supported for lookup and tag accessors.

Validation:

- Shared native Catalyst UIKit and emulated-runtime cases cover signed tag
  boundaries, receiver priority, duplicate tags, missing tags, subtree scope,
  removal, reparenting, a 192-level hierarchy, repeated lookups, metadata and
  direct implementation calls. Runtime cases also cover UIWindow and subclass
  inheritance; two drained runtimes return object counts to zero.
- Host cases pass under ASan/UBSan with normal and deterministic hashing and
  assertions enabled. Leak detection is disabled; sanitizer errors are fatal.
  The ARM64 tag fixture, supervisor and application runner build freshly.
  All 15 guest regression fixtures return wait status zero.
- Complete evidence passes seal, independent check and mutation selftest.
  The auditor rejects failed fixtures/builds, missing or duplicated host cases,
  changed startup/panic/desktop/exit/memory observations, missing registers or
  boot media, altered provenance and unmanifested files. Historical evidence
  checkers remain unchanged.

Fortnite advances past `UIWindow viewWithTag:` and stops at:

```text
V panic: iOS: unimplemented Objective-C method UIView nextResponder
IOS-PROBE-DESKTOP: stop=desktop pipe closed handshake=true builds=2 polls=1 closed=false supervisor_kill=false wait=256
IOS-PROBE-BUDGET: final current=27178 events=low 0;high 0;max 0;oom 0;oom_kill 0;oom_group_kill 0;
FORTNITE PROBE: process exit status 1
FORTNITE PROBE COMPLETE
```

Harness status zero means the diagnostic completed. The application exits 1
with raw wait status 256, without a supervisor kill or cgroup OOM. The desktop
peer confirms two tree builds, each with one root, no images and 336 bytes.
The second printed tree record is interleaved with VM tracing; the final peer
record confirms both builds. This peer has no compositor or input device and
does not qualify a rendered game frame.

The probe retains three loaded/bound images, nine completed Objective-C
`+load` calls, three completed initializer groups, application entry and 13
inline pthread-self translations. A tagged 24 GiB virtual reservation succeeds;
eight process-headroom queries remain positive inside the 2 GiB cgroup. The
only signal fault is deliberate fixture input, with all 31 ARM64 registers
captured and execution restored.

Progress remains **4/8 observable gates (50% of this checklist)**: load/binding,
Objective-C `+load`, image initialization and application entry are verified.
A rendered frame, interactive menu, login and playable match remain unverified.
This fraction does not estimate remaining work or time. The earlier UTF-16
diagnostic began with `Fail`; its full message and cause remain unverified.
`--probe-no-ads` binds SKAdNetwork to nil and changes application behavior.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/view-tag-20261027`, VM state
`probe-no-ads-2554916`. It contains 1219 runtime-source records, 699 selected
build-input records and 1571 manifest records, plus separately recorded audit
sources. SHA-256 of `manifest.sha256`:

```text
ff8b6295e7260f0323cb49dcdb9a1d1f80c6dc4c6d9848249e8d2b153ea1bd49
```

The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
Its complete application directory is an APFS clone verified against the prior
manifest. Fourteen fixture binaries and their generated C (28 files) are reused;
the tag fixture, supervisor and runner are rebuilt. Preserve the complete
prior bundle at
`/Users/alex/Library/Caches/vinix-ios/main-selector-verified-20261026`, manifest
SHA-256 `8897bae68e6d221efa13011a41d46463115a29849f5385f85a443955c2218b41`.
Its unchanged independent checker passed before preparation. The prebuilt
kernel is inventoried, not rebuilt. Selected input hashes do not seal complete
compiler, header or host-library closures.

Reproduce from an isolated checkout of the revision above with the frozen
compiler at `build/ios/fortnite/ns-calendar-checks/toolchain/v` and a fresh
external output directory. Set `V_RESOURCE_PATH` to that toolchain directory,
`V_MACOS_V3_NO_FALLBACK=1` and `V_C_ERROR_BUG_REPORT_DISABLED=1`. Compile
`tests/ios/view-tag-run.v` with `-nocache -gc none -cc clang -cflags -O2`,
without `-prod`, preserving assertions. Run `prepare OUT PRIOR`, `fixture OUT`,
`build OUT`, `host OUT`, `probe OUT` and `audit OUT FULL_REVISION`. The audit
exports committed runtime/audit sources and rebuilds its tools. Run
`OUT/view-tag-evidence seal OUT`, `check OUT`, `selftest OUT` and
`hash OUT/manifest.sha256`; keep subsequent logs outside the sealed bundle.
Exact commands, statuses, generated artifacts, boot media and serial logs are
retained in the complete bundle.
