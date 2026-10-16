# Apple iOS ARM64 publisher qualification

`apple-profile-check.v` tests the `apple-catalog` CLI and public V API. The
[SDK contract](../../tools/packages/SDK.md#apple-ios-arm64-publisher-profile)
defines its templates, file/format limits, explicit runtime and license rules.
These checks use V-generated Mach-O/ELF bytes and XML/binary property lists;
host fixtures do not execute either synthetic executable.

The fifteen host build/run checks cover:

- Reproducible AArch64-only locks, copied file pins, preserved literal arguments,
  permissions, proprietary flags, licenses, associations and bounded runtime
  versions. The output contains only a canonical `catalog.json` in a private
  directory. A separately updated runtime preserves application metadata.
- Normal packing/signing and offline install, license refusal before activation,
  association registration, removal and rollback. An x86-64 consumer cannot
  install this AArch64-only application.
- Thin plain ARM64/iOS admission, real framework-image headers, truncated and
  oversized files/commands, CPU/platform/type/PAC/encryption/entry/segment errors.
  XML and binary plists must agree on bundle ID, executable and `APPL` type;
  malformed, duplicate, missing, wrongly typed and oversized properties refuse.
- Changed source image/plist/runner/notices, directory substitution, insufficient
  space, altered staged locks and concurrent output ownership. Failure cleans
  private staging and permits retry; recipe replacement after capture cannot
  change the declarations being published.
- CLI/API equivalence, argument counts and occupied destinations, plus existing
  ELF, catalog and composition regressions. Both new admission suites also run
  under clang ASan/UBSan, with leak detection disabled.

```sh
v -no-skip-unused -o /tmp/apple-profile-check tests/packages/apple-profile-check.v
V=/path/to/reviewed/v /tmp/apple-profile-check /build/new-apple-profile-check
```

The work directory must be new. Logs and `qualification.json` are written there;
the receipt records the compiler hash and each completed check. The tests supply
the built CLI through `VINIX_PACKAGE_APPLE_CLI`.

The [Apple runtime guest](apple-runtime-check.md) now creates both versioned
app/runtime recipes, generates the profile lock and packs its pinned catalog
inside the guest. It then signs, enrolls and maintains that catalog under the
production sandbox. Its native boundary launcher delegates to the actual static
iOS runtime in the same signed closure. Five Mach-O successes check Foundation
files and private keychain counters across two users, upgrade, rollback and
cached reinstall, followed by damaged-store refusal. The host supplies kernel,
sandbox and runtime build artifacts; it does not repair guest package state.

## Qualification, 2026-10-16

All fifteen host checks passed with the retained V 0.5.2 compiler. The AArch64
guest passed in **18.1 seconds** using freshly built package/account/session
tools and launcher, the prior qualified static iOS runtime, and the same
isolated kernel/production sandbox. The serial log retains both versioned
profile lock digests and five framework/keychain successes. The controller
required all profile/maintenance/refusal markers and guest-initiated poweroff.

Four controller list/input/unsupported-host checks passed. Production staging
also built the updated CLI, session runner and Linux runner for x86-64; all three
outputs have the expected ELF target. This is a tooling build, not x86-64 Apple
runtime execution. No kernel, sandbox or compatibility-runtime code changed.

- [Host receipt](results/2026-10-16/apple-profile-host.json), [host lifecycle](results/2026-10-16/apple-profile-lifecycle.txt), [header/plist checks](results/2026-10-16/apple-profile-headers.txt)
- [AArch64 receipt](results/2026-10-16/apple-profile-aarch64.json), [serial log](results/2026-10-16/apple-profile-aarch64.serial.txt), [QMP log](results/2026-10-16/apple-profile-aarch64.qmp.txt)
- [x86-64 tooling build](results/2026-10-16/apple-profile-x86_64.json), [source/artifact ledger](results/2026-10-16/apple-profile-toolchain.json)

Header admission does not qualify all imports, fixups, bundled resources or
Apple signing/entitlements. The current profile excludes universal, ARM64e,
macOS, simulator and x86-64 applications. Proprietary distribution rights and
consumer consent stay explicit. Real upstream application catalogs, graphical
services and installed-device crash/reboot qualification remain open.
