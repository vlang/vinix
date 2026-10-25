# Compact organization-policy recovery

Stopping an active policy read, a failed service read, or an invalid policy
response leaves the current policy unavailable until a fresh read succeeds.
Compact Software windows previously asked the user to reload without rendering
a Reload control. Returning to Deployment also discarded the entered policy
filename.

Idle compact windows now offer **Reload policy** whenever the policy is
unavailable and no accepted review is pending. It invokes the existing public
read and retains the literal filename. Loaded settings still offer **Read
policy**; pending reads retain Stop, accepted reviews retain Cancel, and approved
saves keep their existing guard. Confirmation remains on the full policy view.

Reload fits at 180×130 and larger. Smaller windows retain Back and status; users
can enlarge to recover without discarding the draft. Optional diagnostics need
space for their complete row and status, and progress appears only when it
does not overlap controls. At 320×240 a failed read exposes both Reload and
Failure details.

The maintained [fixture](software_policy_recovery_fixture.v) uses explicit error
checks and checked side effects in normal and production builds. Real children
exercise partial JSON, complete JSON before exit, nonzero exit and invalid
successful output. Stop kills and reaps both barrier children. Every recovery
locates and activates the rendered Reload button, admits a fresh document, and
starts a review whose child checks the complete Unicode/metacharacter filename.
Nine compact/minimum/boundary canvases check control geometry, status, readers,
review cancellation, busy guards and progress with and without diagnostics.

The [V driver](software-policy-recovery-check.v) preserves project and UI input
snapshots and hashes, all compile/run arguments, generated C, binaries and logs.
It stages the maintained fail-closed hosted fixture; any attempt to use the
unqualified hosted backend panics. Its staged UI uses the same narrow headless
native-control guards as `launcher-check.v`, with original and staged UI inputs
stored and hashed separately. Neither dependency is silently treated as a real
graphical backend. Build arguments include
`-Wno-error=incompatible-pointer-types` for the existing administrator Unix-socket
call under Clang 23; administrator source remains unchanged.

Run the driver from a checkout containing `software_hosted_fixture.v`:

```sh
v -prod -nocache -cc /opt/homebrew/opt/llvm/bin/clang \
  -o /external/policy-recovery-check tests/packages/software-policy-recovery-check.v
/external/policy-recovery-check /absolute/path/to/v /absolute/path/to/modules \
  /external/new-policy-recovery-evidence
```

Five variants cover normal, production, tracked normal, tracked production and
ASan/UBSan. Tracking includes positive and balanced-allocation controls and
measures 1,000 recovery render cycles over 9,000 trees. Sanitizer leak detection
is disabled. Project/UI inputs and V/Clang executables are pinned; imported V
libraries, system headers, linker and transitive tools are not frozen. These
are host headless policy recovery checks, not guest graphical, hosted runtime,
whole-service allocation or full roadmap 14 acceptance.

## Recorded host qualification

On 2026-10-26 all five variants passed for source revision
`a01132716c3850f13b18fcd1cb30a7e3d83d9a6e` (base `afcec6c59`), with the shared
hosted-fixture prerequisite SHA256
`502d852d447240a982c8bef719415025f6f3a9846020d015fc863886e0904aaa`.
The complete project source inventory SHA256 is
`2bea2f34461b14c424ac5f961e2d24839f7d8cd447b400dbb3f13e702891464c`.
Normal and production checks passed all four real-child recovery paths; both
tracked variants retained zero V bytes and zero allocation records over 9,000
render trees each. ASan/UBSan reported no diagnostics. The scope and toolchain
limits above apply to these results.

The final result directory is
`/Users/alex/Library/Caches/vinix-codex/section14/policy-recovery-afcec6c59-2026-10-26-run4`.
The complete external archive, including the bootstrap executables, original
and staged source snapshots, generated C, binaries, argument records, logs and
manifests, is
`/Users/alex/Library/Caches/vinix-codex/section14/policy-recovery-a01132716-2026-10-26.tar.gz`.
Archive SHA256:
`17b669ba465dbc41670b62c4dbcc124b2a3332cd033cc590f1f5d6e48f9779dc`.
It also preserves the three earlier compile failures: missing hosted types,
unadapted native UI branches, and the existing Clang 23 Unix-socket pointer
diagnostic. Those attempts provide no runtime qualification.
