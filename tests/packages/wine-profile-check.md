# Wine Win64 publisher qualification

The `wine-catalog` publisher profile turns four reviewed application/runtime
templates and two prepared roots into a canonical pinned catalog. Its
[SDK contract](../../tools/packages/SDK.md#wine-win64-publisher-profile) describes
the layout, required notices, separate host and PE architectures, runtime bounds,
publishing and execution limits.

The maintained V driver compiles the actual package CLI and four assertion
runners. It supplies that CLI to the Wine-profile runner, so the public API and
command must produce identical catalog digests. Run with a reviewed V compiler
and a new work directory:

```sh
v -no-skip-unused -o /tmp/wine-profile-check tests/packages/wine-profile-check.v
V=/path/to/reviewed/v /tmp/wine-profile-check /build/new-wine-profile-check
```

The driver retains each build/run log and a `qualification.json` containing its
scope, compiler digest and nine check results. The existing full distribution
driver also discovers the new `pkgcore/wine_profile_test.v` runner.

Assertions cover:

- Repeated catalog construction yielding identical canonical bytes and a private
  output containing only the lock; `pack-catalog` and signed offline publication.
- Both host targets selecting their own application/runtime pair, retaining
  explicit proprietary licensing, grants, MIME types and runtime dependency bounds.
- Consumer installation refusing an unaccepted proprietary license; explicit
  policy acceptance permitting installation, launcher/MIME registration, removal
  of the complete unused runtime closure and rollback.
- A compatible explicit runtime update preserving the application manifest.
- DOS/PE/header/section bounds, x86-64 PE32+ identity, executable file-backed
  entrypoints, and rejection of DLL, PE32, ARM64 PE and EFI inputs.
- Missing notices, inconsistent host declarations, unbounded runtime requirements,
  source-root aliases, occupied output, and CLI argument-count errors.
- Imported PE/launcher/notice changes after preflight, modified lock bytes,
  insufficient space and a destination created concurrently. Handled failures
  preserve concurrent content, remove staging and allow exact retry after
  restoring trusted inputs.
- Regression runners for ELF profile admission, canonical catalog construction
  and composition of complete catalog closures.

## Qualification, 2026-10-16

Nine host build/test checks passed with V 0.5.2 `826e96f` (compiler SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`). The
Wine-profile assertions also passed clang AddressSanitizer/UndefinedBehaviorSanitizer
with `ASAN_OPTIONS=detect_leaks=0` and `UBSAN_OPTIONS=halt_on_error=1`; this checks
invalid memory/undefined behavior on exercised paths, not retained allocations.

The production V staging tool was used to cross-compile the package CLI, account
session tool and Linux runner for both hosts. The receipts check each output's
ELF64 target and retain sizes and hashes. No runtime fixture is executed by these
checks. Retained results:

- [Host checks](results/2026-10-16/wine-profile-host.json)
- [Wine lifecycle/CLI log](results/2026-10-16/wine-profile-host.txt)
- [AArch64 staging receipt](results/2026-10-16/wine-profile-aarch64.json)
- [x86-64 staging receipt](results/2026-10-16/wine-profile-x86_64.json)
- [Source and artifact ledger](results/2026-10-16/wine-profile-toolchain.json)

These fixtures use synthetic PE/ELF bytes for structural and package maintenance
assertions. They do not ship a Wine closure, authenticate upstream binaries,
establish redistribution rights, validate Authenticode, or qualify Wine APIs,
translation, IPC, display/audio, process lifetimes or ordinary-user graphical
execution. The existing host-wide Wine launcher needs a separately packaged and
qualified runtime before it can satisfy this profile's execution contract.
The roadmap's Windows/Apple runtime acceptance gate remains open.
