# Desktop protocol probe checkpoint — 2026-10-26

Desktop probe implementation: `243aa50405f7c55d11a2a70a1a39f94c78786ef9`.
Inventoried source, including optimized audit-tool builds:
`82ae8e11f1464eda834bdeb9dd2896b6b45e70db`. Advertising remains skipped.

The diagnostic supervisor now supplies the VAPP v10 request/response pipes.
Its bounded peer validates the handshake, state, tree payloads and polling,
then requests closure or reaps a failed child. Replies have a single deadline
across header and payload, a 1 MiB limit and bounded tree nesting. The peer has
no compositor or input device and does not qualify desktop rendering.

Fresh validation passes:

- Normal and deterministic-hashing ASan/UBSan peer runs, each covering 14
  cases: fragmented replies, malformed headers/state/trees, oversize payloads,
  EOF, partial/silent/stalled children, invalid hello/poll/close payloads,
  truncated trees and a real UIKit window. Assertions remain enabled. The
  window fixture also passes its eight host build/execution steps, including
  both sanitizer runs. Leak detection is disabled; sanitizer errors are fatal.
  Audit tools use C optimization (`-O2`) while retaining V assertions.
- Fresh ARM64 supervisor and window builds. All 13 guest regression fixtures
  return wait status zero. The UIKit fixture completes a handshake, tree build,
  two polls and protocol closure without forced termination. The cgroup fixture
  verifies enforcement and supervisor isolation before launching Fortnite.
- Evidence seal, independent check and mutation selftest. The checker rejects
  failed fixtures/builds, missing host cases or guest media, changed resources,
  altered desktop/exit/startup/memory observations, missing registers,
  unexpected panics/faults and unmanifested files. It permits exactly the one
  recorded application panic below, while historical checkers remain unchanged.

The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
It completes the desktop handshake and two tree builds. Each observed tree is
336 bytes with one root node and no images. The second tree's serial line is
interleaved with concurrent VM tracing; the peer's final record confirms two
validated builds. The next boundary is:

```text
V panic: iOS: CFString encoding is not implemented
IOS-PROBE-DESKTOP: stop=Broken pipe handshake=true builds=2 polls=1 closed=false supervisor_kill=false wait=256
FORTNITE PROBE: process exit status 1
FORTNITE PROBE COMPLETE
```

The application exits 1 naturally; raw wait status is 256. The supervisor does
not kill it. Final cgroup events are all zero, including `max`, `oom` and
`oom_kill`. Harness status zero means the diagnostic completed, not that the
game succeeded. The failing call's input encoding is not recorded yet; trace
that value before implementing a decoder.

Progress remains **4/8 observable gates (50% of this checklist)**: image
load/binding, Objective-C `+load`, image initialization and application entry
are verified. A rendered game frame, interactive menu, login and playable match
remain unverified. This fraction does not estimate remaining work or time.
`--probe-no-ads` binds SKAdNetwork to nil and changes application behavior.

Three images load/bind, all nine `+load` calls and three initializer groups
return, and all 13 inline pthread-self reads are translated. The tagged 24 GiB
virtual reservation succeeds. Eight headroom queries stay positive within the
2 GiB cgroup limit. Final cgroup memory is 27,178 bytes after process exit.
The sole signal fault belongs to the deliberate fixture, which captures all
31 ARM64 registers and restores execution.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/desktop-probe-20261026`:
1209 source records, 698 selected build-input records and 1552 manifest
records. The selected VM state is `probe-no-ads-1659458`.
SHA-256 of `manifest.sha256`:

```text
d2104f9f7bc841ce3cd3ee369469a1d7378df75eeedf10f248415d87b1700ab1
```

The application copy uses an APFS clone. All application files and 26 reused
build files are hash-checked against the prior manifest. Preserve the complete
prior bundle at `/Users/alex/Library/Caches/vinix-ios/thermal-state-20261026`,
manifest SHA-256
`d815747b8f635da1853425374b47f7f61015de03d941959c8bd6b03ea357d53e`.
Its full independent checker passed again. The prebuilt kernel is inventoried,
not rebuilt; selected hashes do not seal complete compiler, header or
host-library closures.

Reproduce from the repository root with the frozen V compiler/environment from
the [window checkpoint](window-checkpoint-20261026.md), adding `tests/ios` to the
module path. Compile `desktop-probe-run.v` without `-prod`. Run its
`prepare OUT PRIOR_THERMAL_BUNDLE`, `tools OUT PRIOR_THERMAL_BUNDLE`, `build OUT`,
`host OUT` and `probe OUT` modes, using a fresh external output directory.
The driver enables desktop probing, a 2 GiB application limit and gzip level 9.
Run `inventory-inputs ROOT OUT SOURCE_REVISION`, then
`desktop-probe-evidence seal OUT`, `check OUT` and `selftest OUT`; hash the
manifest with `desktop-probe-evidence hash OUT/manifest.sha256`. Exact commands,
statuses, generated artifacts, boot media and serial logs remain in the bundle.
