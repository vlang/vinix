# Software maintenance on an installed system disk

The newer [installed-release audit check](release-audit-check.md) also pins the
staged release declaration on disk, installs it through one approved Software
review and checks baseline drift as ordinary users through all four boots.

`native-catalog-check.v --installed` starts with a blank 4 GiB disk and the
production-staged native application image. The kernel's normal `vinix.disk=auto`
path formats that disk as Vinix's journaled primary filesystem (VJFS), installs
the image and starts its userland from the disk. Three subsequent boots must
select that same installed root. The host neither formats nor repairs the
filesystem, copies consumer state between boots, rebuilds the image between
boots nor reinstalls tools into the guest.

The boot kernel and fallback initramfs remain on the test's FAT/ISO boot medium.
This tests the installed root and userland, rather than autonomous firmware
bootloader installation or a complete graphical desktop session.

Each boot requires `/dev/root / ext2` in the mount table (the VJFS driver's mount
name), the expected installed image ID and matching filesystem device identities
for the service, account/session tools, authentication daemon, native sandbox,
Software fixture and PID 1. These ordinary root-owned tool files must retain
the exact sizes and SHA-256 hashes recorded before image creation. A file made
only after installation must survive every later boot. An initramfs fallback
fails the root check; serial image-update/fallback diagnostics also fail the
scenario.

| Boot | Required behavior |
| --- | --- |
| 1 | The real installer formats the blank disk and installs the staged tools, trust and signed offline catalog. Ordinary Software installs Hello, Counter and Memo. Separate administrator/standard accounts retain private counters, a saved memo and an explicitly granted literal document. |
| 2 | Boot the installed root. Compare exact retained account/trust/catalog/history/state/tool/user-file bytes and UID/GID/mode. Reopen native apps; refresh signed 1.1.0 media and review an upgrade through Software. |
| 3 | Boot the retained upgrade. Remove both original and later repository object directories. Review rollback, uninstall every application and check launcher removal, then reinstall all three from the disk's verified cache. |
| 4 | Boot the retained reinstall with repository payloads still absent. Verify the complete installed closure, architecture/publisher provenance, tool hashes and private-data ownership; reopen Counter and Memo. |

All application maintenance uses the same actual Software controller, visible
UI-tree controls, authentication service and isolated native launch actions as
[the Software image check](software-image-check.md). Presentation helpers are
headless. The root image's `launch_user` does not change the standard caller's
identity. Each boot checks audit attribution, password omission and package
socket cleanup. Native 1.1.0 changes signed metadata over the same qualified
binary payloads, as in the existing native catalog fixture.

The root's `/run` persists too. The guest's authentication startup helper now
requires a successful response from a root-authenticated service peer, so an old
socket pathname cannot satisfy readiness. No password is sent by that probe.

Receipt hashing streams files with a reusable 1 MiB buffer, including the blank
input and final 4 GiB disk. SHA-256 values retain their existing meaning and the
receipt records `qemu-vjfs-installed-root`, four boots, all staged inputs and all
four serial logs. The images remain in the state directory for inspection; they
contain throwaway fixture accounts. The signing seed remains outside the guest.

## Qualification, 2026-10-16

All nine host controller/hash checks and sixteen target boots passed. The
existing ext2 subtree mode was rerun on both architectures after the shared
fixture and authentication-readiness changes:

| Architecture | Four installed VJFS root boots | Four ext2 subtree regression boots |
| --- | --- | --- |
| AArch64 | PASS, 75.0 s | PASS, 62.5 s |
| x86-64 | PASS, 76.5 s | PASS, 65.6 s |

Every boot requires the guest's complete workflow marker and guest-initiated
QMP shutdown. The installed guests verify disk-root/tool identity themselves;
the AArch64 serial logs additionally record the initial installation and later
root selections. Both targets show archive unpacking only on the first boot.
The V verifier checks all receipt artifact hashes, full initial/final disk
digests, staged-tool proof documents and the unchanged kernel hashes from
[the ext2 identity qualification](software-persistence-check.md). This increment
changes no kernel code.

- [AArch64 installed receipt](results/2026-10-16/software-installed-aarch64.json), [QMP](results/2026-10-16/software-installed-aarch64.qmp.txt), [fourth boot](results/2026-10-16/software-installed-aarch64.boot-4.serial.txt)
- [x86-64 installed receipt](results/2026-10-16/software-installed-x86_64.json), [QMP](results/2026-10-16/software-installed-x86_64.qmp.txt), [fourth boot](results/2026-10-16/software-installed-x86_64.boot-4.serial.txt)
- [AArch64 subtree regression](results/2026-10-16/software-installed-aarch64.persistent.json), [x86-64 subtree regression](results/2026-10-16/software-installed-x86_64.persistent.json)
- [Host results](results/2026-10-16/software-installed-host.txt), [hash checks](results/2026-10-16/software-installed-hash.txt), [source/toolchain/artifact ledger](results/2026-10-16/software-installed-toolchain.json)
- [V invocation](results/2026-10-16/software-installed-guest.v), [host driver](results/2026-10-16/software-installed-host.v), [evidence verifier](results/2026-10-16/software-installed-retain.v)

## Reproduction

Use the [hardware controller requirements](../hardware-platform/README.md), a
reviewed V compiler, both native catalog architecture inputs, a headless ui2
module and matching kernel/sandbox. Compile the host controller with `-prod` for
large-disk hashing:

```sh
v -prod -path '@vlib|@vmodules|.|tests/hardware-platform|tools/accounts' \
  -o /tmp/native-catalog-check tests/packages/native-catalog-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  VINIX_PACKAGE_TEST_UI2=/path/to/headless/modules \
  VINIX_NATIVE_CATALOG_INPUTS=/build/native-inputs \
  VINIX_NATIVE_CATALOG_SANDBOX=/build/aarch64-root/usr/bin/vinix-sandbox \
  /tmp/native-catalog-check --installed --arch aarch64 \
  --kernel /build/aarch64-kernel --state-dir /build/new-installed-state
```

Repeat for x86_64 with its matching kernel/sandbox and a new short state path.
No host `mke2fs` is used in this mode. The controller requires a new state
directory and an explicit QEMU TCG opt-in; it creates only its own blank test
disk. The existing default, `--image`, `--software` and `--persistent` modes
remain available. `--list` builds no guest and creates no disk.

This does not qualify graphical login/composition, every advertised upstream
application, Windows/Apple runtimes, image-version OS upgrades, interruptions
inside filesystem/device operations or physical write-cache loss. Publisher
selection, catalog migration and broader runtime/device qualification remain
roadmap 14 release work. The [ext2 subtree check](software-persistence-check.md)
and [abrupt transaction recovery check](persistence-check.md) retain their
separate scope.
