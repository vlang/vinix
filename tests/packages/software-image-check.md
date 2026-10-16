# Software on a preconfigured native image

`native-catalog-check.v --software` boots the production-staged package tools,
a signed native catalog and a reviewed image configuration, then runs the actual
Software controller as ordinary administrator and standard accounts. This joins
the previously separate image, administrator-client and native-window checks.
The controller copies the current `desktop/software_*.v` implementation and
builds a static target fixture with headless ui2. Its controls must exist in the
actual element tree before the fixture dispatches their actions.

The host verifies the native builder's input pins and publishes complete 1.0.0
and 1.1.0 Hello, Counter and Memo releases. Its fixture signing seed stays outside
the image. The production staging tool installs configuration, package/session
tools, actions and notices. The guest starts with empty package state; it neither
enrolls a publisher nor edits the package configuration. The authentication daemon
and account manager are freshly compiled for the target too.

The ordinary administrator's Software window performs:

- Read-only initial catalog, cancelled approval, bad-password diagnostics, and
  successful authenticated refresh from the staged repository.
- Visible catalog/search selection, complete signed package review, confirmed
  install of all three applications, password masking/retirement, structured
  progress and asynchronous reload.
- Counter protocol-1 rendering/click/close and Memo protocol-2 text entry,
  explicit save and close through the real isolated-launch action. A Start-style
  request opens Memo; Hello receives a literal document path with spaces and
  shell punctuation through an explicit document grant.
- Updates filtering and reviewed update-all, rollback with saved Memo data,
  reviewed uninstall with launcher removal, then reinstall after the host-staged
  repository's object directory is hidden in the guest. Cached authenticated
  payloads suffice and Memo retains its saved text.

The standard account can read the catalog/review but its own password cannot
authorize removal. It then launches Counter through the same Software code with
its account memberships intact at the caller boundary. The launch transport
removes groups for the confined application. Both users' counters independently
start at zero and persist one click under their respective UIDs; the standard
account cannot inspect the administrator's private counter file.

The guest verifies the final package closure and root-owned state, restored
launcher registration, per-user private-data ownership, unchanged staged
configuration, authorization audit attribution, absence of passwords in captured
output/audit, and cleanup of both users' package sockets. The root image's
`launch_user=alex` does not change the standard caller's launch identity.

## Qualification

Final fresh-image runs passed on both architectures:

| Architecture | Software image workflow |
| --- | --- |
| AArch64 | PASS, 22.9 s |
| x86-64 | PASS, 27.5 s |

Seven native compile/run checks passed: the default, CLI-image and Software-image
scenario listings, plus the existing boot and suite assertion runners. Both architectures
require every workflow marker and guest-initiated QMP shutdown. The unchanged
isolated socket-qualification kernels are inputs; this check changes no kernel
code. Receipts and the ledger pin the service/fixture binaries, native payloads,
signed exports, configuration, generated C, current Software sources, headless UI
module and toolchain. The V invocation and retention helpers are retained too.

This is a real guest controller/service integration check. Small presentation
helpers and the unused Terminal adapter are fixtures. It does not run a compositor,
paint pixels, authenticate a graphical login, exercise a real PTY, or qualify a
foreign display/audio runtime. The root filesystem is an initramfs; persistent
storage and physical-device crash durability remain separate acceptance work.
Public release publisher selection and migration of the advertised Alpine/vendor
catalog remain open. No roadmap 14 checkbox is closed by this check.

Build the controller with a reviewed V compiler, then use the native builder's
inputs and matching sandbox/kernel:

```sh
v -path '@vlib|@vmodules|.|tests/hardware-platform|tools/accounts' \
  -o /tmp/native-catalog-check tests/packages/native-catalog-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  VINIX_PACKAGE_TEST_UI2=/path/to/headless/modules \
  VINIX_NATIVE_CATALOG_INPUTS=/build/native-inputs \
  VINIX_NATIVE_CATALOG_SANDBOX=/build/aarch64-root/usr/bin/vinix-sandbox \
  /tmp/native-catalog-check --software --arch aarch64 \
  --kernel /build/aarch64-kernel --state-dir /build/new-software-state
```

Repeat for x86_64 with matching inputs and a new state path. `--image` retains the
CLI image scenario; the default retains the explicit-enrollment native scenario.

- [AArch64 receipt](results/2026-10-16/software-image-aarch64.json), [serial](results/2026-10-16/software-image-aarch64.serial.txt), [QMP](results/2026-10-16/software-image-aarch64.qmp.txt)
- [x86-64 receipt](results/2026-10-16/software-image-x86_64.json), [serial](results/2026-10-16/software-image-x86_64.serial.txt), [QMP](results/2026-10-16/software-image-x86_64.qmp.txt)
- [Host checks](results/2026-10-16/software-image-host.txt), [source/toolchain/artifact ledger](results/2026-10-16/software-image-toolchain.json), [guest invocation](results/2026-10-16/software-image-guest.v)
