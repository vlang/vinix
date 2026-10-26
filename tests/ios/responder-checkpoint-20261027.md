# UIKit responder-chain checkpoint — 2026-10-27

Runtime and audit tools: `a33c9bc336bca4498413932407d42a146831b97c`.
Advertising remains skipped.

`UIResponder nextResponder` now follows the UIKit view/controller/window/
application chain. Controller root views have a zeroing weak backlink to their
owner; replacing or clearing the root detaches its old hierarchy link. Lazy
views and storyboard-created views use the same ownership path. Inherited
selector introspection, type encodings, method signatures and direct
implementation calls are supported.

Validation:

- Shared native Catalyst UIKit and emulated-runtime cases cover bare
  responders, nil receivers, reparenting, controller roots, replacement,
  clearing roots, detached lifetimes, metadata and direct implementation
  calls. Runtime cases also cover subclasses, storyboard roots, active-window
  replacement and destruction; two drained runtimes return object counts to
  zero. Native window/application cases use isolated allocations without
  `UIApplicationMain`; they do not compare full native application startup.
- Host cases pass with normal and deterministic hashing, assertions enabled
  and ASan/UBSan errors fatal. Leak detection is disabled. The ARM64 responder
  fixture, supervisor and application runner build freshly. All 16 guest
  regression fixtures return wait status zero.
- Complete evidence passes seal, independent check and mutation selftest.
  Changed or missing fixture/host results, alert, startup, desktop, exit,
  memory, registers, media, validation statuses and provenance are rejected,
  as are unmanifested files. Historical evidence checkers remain unchanged.

Fortnite advances past the previous `UIView nextResponder` panic and reports
the full application alert:

```text
Showing Alert:
  Title:Message
  Message:Failed to open descriptor file ../../../FortniteGame/FortniteGame.uproject
For troubleshooting, please go to https://docs.unrealengine.com/SharingAndReleasing/Mobile/iOS
```

The application then remains in its event loop until the desktop peer ends
its bounded session (the peer's default is 10 seconds):

```text
IOS-PROBE-DESKTOP: stop=session complete handshake=true builds=86 polls=85 closed=true supervisor_kill=false wait=0
IOS-PROBE-BUDGET: final current=27178 events=low 0;high 0;max 0;oom 0;oom_kill 0;oom_group_kill 0;
FORTNITE PROBE: process exit status 0
FORTNITE PROBE COMPLETE
```

There is no application panic, supervisor kill or cgroup OOM. Application exit
zero follows the bounded peer closure and does not establish a successful game
launch. The peer confirms 86 tree builds and 85 polls; observed trees contain
one root, zero images and 336 bytes. Tree 2's printed record is interleaved with
VM tracing; the final peer record confirms the build count. The peer has no
compositor or input device, and no rendered game frame is verified.

The probe retains three loaded/bound images, nine completed Objective-C
`+load` calls, three completed initializer groups, application entry and 13
inline pthread-self translations. A tagged 24 GiB virtual reservation succeeds;
92 process-headroom queries remain positive inside the 2 GiB cgroup. The only
signal fault is deliberate fixture input, with all 31 ARM64 registers captured
and execution restored.

Progress remains **4/8 observable gates (50% of this checklist)**: load/binding,
Objective-C `+load`, image initialization and application entry are verified.
A rendered frame, interactive menu, login and playable match remain unverified.
This fraction does not estimate remaining work or time. The next blocker is
the project-descriptor lookup. The current overlay copies five launch
resources into the guest; searches of the preserved partial application
directories found no `.uproject`, `.pak`, `.utoc` or `.ucas` files. This does
not establish the contents of the original IPA or whether the lookup failure
is caused by absent resources or path translation. No substitute descriptor
was introduced. `--probe-no-ads` binds SKAdNetwork to nil and changes
application behavior.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/responder-20261027`, VM state
`probe-no-ads-1033125`. It contains 1222 runtime-source records, 699 selected
build-input records and 1576 manifest records, plus separately recorded audit
sources. SHA-256 of `manifest.sha256`:

```text
7bed527b10a7ab3c5ead0569ac8cf3afd5e03986522c93725348c3af99d0ee26
```

The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The entire application directory preserved by the prior checkpoint is an APFS
clone verified against its manifest; it is a partial extraction, not a complete
IPA inventory. Fifteen fixture binaries and their generated C (30 files) are
reused; the responder fixture, supervisor and runner are rebuilt. Preserve the
complete prior bundle at
`/Users/alex/Library/Caches/vinix-ios/view-tag-20261027`, manifest SHA-256
`ff8b6295e7260f0323cb49dcdb9a1d1f80c6dc4c6d9848249e8d2b153ea1bd49`.
Its unchanged independent checker passed before preparation. The prebuilt
kernel is inventoried, not rebuilt. Selected input hashes do not seal complete
compiler, header or host-library closures.

Reproduce from an isolated checkout of the revision above with the frozen
compiler at `build/ios/fortnite/ns-calendar-checks/toolchain/v` and a fresh
external output directory. Set `V_RESOURCE_PATH` to that toolchain directory,
`V_MACOS_V3_NO_FALLBACK=1` and `V_C_ERROR_BUG_REPORT_DISABLED=1`. Compile
`tests/ios/responder-run.v` with `-nocache -gc none -cc clang -cflags -O2`,
without `-prod`, preserving assertions. Run `prepare OUT PRIOR`, `fixture OUT`,
`build OUT`, `host OUT`, `probe OUT` and `audit OUT FULL_REVISION`. The audit
exports committed runtime/audit sources and rebuilds its tools. Run
`OUT/responder-evidence seal OUT`, `check OUT`, `selftest OUT` and
`hash OUT/manifest.sha256`; keep subsequent logs outside the sealed bundle.
Exact commands, statuses, generated artifacts, boot media and serial logs are
retained in the complete bundle.
