# UIWindow lifecycle checkpoint — 2026-10-26

Implementation and inventoried source revision:
`6d2639b7a0486823456cecd33ef74519a70d8787`. Advertising remains skipped.

A window can now become visible before receiving a root controller. Layout,
touch dispatch and controller lookup tolerate that state; direct subviews
remain usable. Assigning, replacing or removing a root controller preserves
strong ownership and detaches the previous view. Fixtures cover late and
repeated assignment, resize callbacks, hidden windows and switching windows,
with two fully drained runtime lifetimes.

Normal and deterministic-hashing ASan/UBSan host fixtures pass for windows,
storyboards and alerts. Leak detection is disabled. The initial native macOS
alert attempt failed to load UIKit; its logs are retained. The corrected
Catalyst alert runs pass. All 13 ARM64 guest builds pass and all 11 guest
regression fixtures return wait status zero.

The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The earlier missing-object-metadata panic is gone. Three images bind/register,
nine `+load` calls and three initializer groups return, and application entry
is reached. After reporting landscape mode the next stop is:

```text
V panic: iOS: unimplemented Objective-C method UIApplication setApplicationIconBadgeNumber:
```

Application exit is 1 (wait status 256); the complete diagnostic harness exits
zero. Progress remains **4/8 observable gates (50% of this checklist)**.
A rendered frame, interactive menu, login and playable match remain unverified.
This fraction does not estimate remaining work or time. `--probe-no-ads` binds
SKAdNetwork to nil and changes application behavior; it is a diagnostic run.

All 13 inline pthread-self reads are translated. The tagged 24 GiB virtual
reservation succeeds at `0x8009bcd8000`; it does not commit 24 GiB of physical
memory. Seven headroom queries return 663,225,254 or 662,692,390 bytes.
The final application cgroup records zero OOM events under a 2 GiB limit.
The sole signal fault is the deliberate regression fixture, which captures
all 31 ARM64 registers and restores execution.

The complete audit bundle is outside Git:
`/Users/alex/Library/Caches/vinix-ios/window-20261026`.
It contains 1,190 source records, 696 selected build-input records and 1,946
manifest records, including application/frameworks, generated C, sanitizer
objects, toolchain, logs and complete guest media. `probe-no-ads-state.txt`
selects `probe-no-ads-1178416`. SHA-256 of `manifest.sha256`:

```text
55a48d4d9db015cf83e393022e88585270559db8e84e3ac092df685cbac95d9f
```

`window-evidence` seal, independent check and mutation selftest pass. The
selftest rejects missing guest media, window/host validation and failed
fixture waits, changed VM reservations, startup boundaries, application exit,
OOM, extra faults/panics, modified logs and unmanifested files. Historical
checkers remain unchanged. Inherited native observations and their original
bundle provenance are retained in `inherited-evidence.txt`; see the
[float checkpoint](string-float-checkpoint-20261026.md). The prebuilt kernel
is inventoried, not rebuilt from concurrent edits. Selected hashes do not
seal complete compiler, header or host-library closures.

Reproduce using the frozen V compiler in
`build/ios/fortnite/ns-calendar-checks/toolchain`, `V_RESOURCE_PATH` pointing
there, `V_MACOS_V3_NO_FALLBACK=1`, `-nocache -prod -gc none -cc clang` and
module path `@vlib|<repo>/compat/ios|<repo>/tests/ios|@vmodules`. Build
`notification-checks.v`, `notification-vm.v`, `window-run.v`,
`image-initializers-input-inventory.v` and `window-evidence.v`. In a fresh
external bundle, run the wrapper's `window-host`, `storyboard-host` and
`alert-host` modes, then `window-run build` and `probe`. Preserve inherited
observations, application files and provenance, capture inventories at the
source revision, then run evidence `seal`, `check`, `selftest` and `hash`.
