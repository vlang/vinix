# UIApplication minus-one badge clearing checkpoint — 2026-10-26

Implementation and inventoried source revision:
`bd4b654884d479710f3b02d234361693ce4ff658`. Advertising remains skipped.

`setApplicationIconBadgeNumber:` now accepts signed 64-bit values zero and
minus one to clear the absent badge; the getter remains zero. Other counts
still fail explicitly because there is no launcher badge backend. The minus-one
sentinel follows the iOS client practice described in
[Tencent's badge FAQ](https://www.tencentcloud.com/document/product/1024/40457).
This does not establish delivered-notification behavior in this runtime.

The shared Catalyst/runtime fixture checks defaults, repeated zero/minus-one
clears, reflection, signatures and direct IMP calls. Runtime checks also cover
subclasses, idle timer independence and two completely drained lifetimes.
Isolated children verify rejection across positive, negative and signed 64-bit
boundaries. All eight host execution statuses pass across normal and
deterministic-hashing ASan/UBSan runs; leak detection is disabled. Native
inspection confirms method signatures and the minus-one call, but its getter
stays zero for every tested count. Badge authorization and display remain
unverified.

All 14 ARM64 guest builds and all 12 guest regression fixtures pass. Build
commands, logs and exit statuses are retained. Complete window, storyboard and
alert host artifacts are inherited without rerunning from source revision
`6d2639b7a0486823456cecd33ef74519a70d8787`, bundle
`/Users/alex/Library/Caches/vinix-ios/window-20261026`, manifest SHA-256
`55a48d4d9db015cf83e393022e88585270559db8e84e3ac092df685cbac95d9f`.
Badge host tests, native inspection and guest fixtures are fresh.

The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The minus-one badge stop is gone. Three images load/bind, nine `+load` calls
and three initializer groups return, and application entry is reached.
The next observed stop is:

```text
V panic: iOS: storyboard source is missing; compiled storyboardc resources are unsupported
```

Application exit is 1 (wait status 256); the diagnostic harness exits zero.
Progress remains **4/8 observable gates (50% of this checklist)**. A rendered
frame, interactive menu, login and playable match remain unverified. This
fraction does not estimate remaining work or time. `--probe-no-ads` binds
SKAdNetwork to nil and changes application behavior; this is a diagnostic run.

All 13 inline pthread-self reads are translated. The tagged 24 GiB virtual
reservation succeeds without committing that much physical memory. Seven
headroom queries stay within the 2 GiB cgroup limit; final application OOM
counters are zero. The sole signal fault is the deliberate regression fixture,
which captures all 31 ARM64 registers and restores execution.

Complete evidence is outside Git at
`/Users/alex/Library/Caches/vinix-ios/application-badge-clear-20261026`.
It contains 1196 source records, 696 selected build-input records and 1971
manifest records. The selected guest state is `probe-no-ads-419250`.
SHA-256 of `manifest.sha256`:

```text
a3abbb60855bf8871a1462fd2866296ed2e20cda126e882fee8a14f8ba21b454
```

`application-badge-clear-evidence` seal, independent check and mutation
selftest pass. Missing minus-one fixture/native inspection cases are rejected,
along with missing media, changed startup/VM/memory/fault/exit evidence, failed
validation statuses, changed logs and extra files. Historical checkers remain
unchanged. The prebuilt kernel is inventoried, not rebuilt from concurrent
edits. Selected hashes do not seal complete compiler, header or host-library
closures.

Follow-up resource inspection found no storyboard or NIB files in either
`build/ios/fortnite/local/Payload/FortniteClient-IOS-Shipping.app` or the base
`build/ios/fortnite/probe-initramfs.tar.gz`. The local Info.plist names
`LaunchScreen` in `UILaunchStoryboardName` and has no `UIMainStoryboardFile`.
The probe currently copies frameworks but does not add those local application
resources. These observations are separate from the sealed runtime results.
The next investigation must establish the actual resource set and requested
storyboard before choosing compiled storyboard support; the panic alone does
not show that a compiled storyboard was present.

Reproduce with the frozen V compiler and flags documented in the
[window checkpoint](window-checkpoint-20261026.md). Build
`application-badge-clear-prepare.v`, then run it with a fresh external output
directory and `/Users/alex/Library/Caches/vinix-ios/application-badge-20261026`.
Use the prepared `notification-checks` for `application-badge-host`,
`application-badge-inspector-build` and `application-badge-inspect`; use
`application-badge-run` for `build` and `probe`. Run the preparation tool with
`--finish-tools OUTPUT` to build the inventory and boundary checker. Run
`inventory-inputs ROOT OUTPUT SOURCE_REVISION`, then
`application-badge-clear-evidence seal|check|selftest OUTPUT` and hash the
resulting manifest. Preserve the complete inherited artifacts and provenance.
