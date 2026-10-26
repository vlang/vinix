# NSString floatValue checkpoint — 2026-10-26

Implementation, evidence tools and inventoried source revision:
`e56dfc445ef4f24675e55c26cc187beaf46b3244`. Advertising work remains skipped.

`NSString` and `NSMutableString floatValue` now parse the measured decimal
grammar, BMP decimal digits, leading whitespace and optional exponent. Invalid
exponents leave the preceding number intact. Results use the observed
double-to-float rounding, including halfway cases, signed zero, overflow and
underflow. Instance metadata (`f16@0:8`), signatures and direct IMP calls return
the float through the ARM64 floating-point ABI. Mutable-string ownership reads
in the adjacent dispatch path are protected against concurrent map mutation.

The host Foundation inspector records 675 input vectors for each class,
giving 1,350 bit-exact observations plus two metadata records and a summary.
The vectors include repeated inputs; this is not a count of unique cases.
Normal and deterministic-hashing host fixtures pass under ASan/UBSan. Eight
workers exercise both message dispatch and direct IMP calls; runtime checks
also cover mutable updates, UTF-8/UTF-16 constant strings and two lifetimes
ending with zero tracked live objects. Sanitizer leak detection is disabled.
All twelve ARM64 guest builds pass, and all ten guest regression fixtures
finish with wait status zero, including the new float fixture.

The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The `NSString floatValue` panic is gone. All three images bind/register,
nine `+load` calls and three initializer groups return, and application entry
is reached. The next observed stop is:

```text
V panic: iOS: object has no live runtime metadata
```

The responsible object and call site remain unidentified. The application
exits 1 (wait status 256); the complete diagnostic harness exits zero.
Progress remains **4 of 8 observable gates (50% of this checklist)**: image
loading/binding, `+load`, initializers and application entry pass. A rendered
frame, interactive menu, login and playable match remain unverified. This
fraction does not estimate remaining engineering effort or time. The explicit
`--probe-no-ads` diagnostic binds SKAdNetwork to nil and changes application
behavior; these results do not establish a normal launch.

All 13 inline pthread-self reads are translated. The exact 24 GiB tagged
virtual reservation succeeds at `0x800996f0000`; this does not commit 24 GiB
of physical memory. Seven headroom queries return 663,192,486 or 662,659,622
bytes. The final application cgroup has zero `oom`/`oom_kill` events under a
2 GiB limit. The only signal fault is the deliberate fixture, which captures
all 31 ARM64 registers and restores execution.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/string-float-20261026`.
It contains 1,187 source records, 696 selected input records and 1,563 manifest
records, including application/frameworks, generated C, sanitizer objects,
TLS archives, tools, command/status logs and complete guest media.
`probe-no-ads-state.txt` selects `probe-no-ads-329375`.
SHA-256 of `manifest.sha256`:

```text
dadc13df86ba47afa9dfb0964b4a846ba42e8131c1c36011893aaabafde462fe
```

The float evidence tool's seal, independent check and selftest pass. It rejects
changed native float metadata/bits, missing or repeated observations, missing
fixture validation, failed waits and changed startup boundaries, together with
the inherited CString/receipt/CFString/VM/search-path mutations, missing media,
altered logs and unmanifested files. Historical checkers remain unchanged.
Inherited CString evidence was independently checked before copying its
observations from source `b25fba5a4c42f2655d1a814b340abeba3173fa90` and complete
bundle `/Users/alex/Library/Caches/vinix-ios/string-cstring-20261026`, whose
manifest SHA-256 is
`911924675d2015f133ebc6a8384ec824dfbd45cf9170adc7b97ba1f8b55db885`.
The earlier CFString and receipt provenance is retained in
`inherited-evidence.txt` and the [CString checkpoint](string-cstring-checkpoint-20261026.md).
The prebuilt ARM64 kernel is inventoried; concurrent kernel edits were not
rebuilt. Selected input hashes do not seal complete compiler, header or
host-library closures.

Reproduce from the inventoried revision using the frozen compiler at
`build/ios/fortnite/ns-calendar-checks/toolchain/v`, with `V_RESOURCE_PATH`
pointing to that toolchain and `V_MACOS_V3_NO_FALLBACK=1`. Compile
`notification-checks.v`, `notification-vm.v`, `string-float-run.v`,
`image-initializers-input-inventory.v` and `string-float-evidence.v` with
`-nocache -prod -gc none -cc clang` and module path
`@vlib|<repository>/compat/ios|<repository>/tests/ios|@vmodules`. Preserve the
application/frameworks and inherited observations with their provenance.
In a fresh external bundle, run the notification wrapper's `string-float-host`,
`string-float-inspector-build` and `string-float-inspect` modes, then the
checkpoint runner's `build` and `probe` modes. The runner sets the 2 GiB cgroup
budget and gzip level 9. Capture source/input inventories using the full
revision above, then run the evidence tool's `seal`, `check`, `selftest` and
`hash` modes.
