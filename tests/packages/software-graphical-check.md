# Software acquisition in an ordinary graphical installed session

`software-graphical-check.v --ordinary=true --installed=true` drives the real
framebuffer compositor with QMP pointer and keyboard input (virtio on ARM, USB
HID through xHCI on x86). PID 1 starts
`vinix-session run --seat alex ... --open=Software`; the compositor must have all
four reported UIDs equal to 1000 before the host sends input. The fixture removes
two empty account-created folders before launch and requires the compositor to
recreate them, with the account-owned XDG folder configuration, in `/home/alex`.
The ordinary account bypasses legacy root registration.
Readiness must come from the account-owned marker inside its private runtime
directory. On the second boot the fixture holds the old marker open and observes
a new inode, so a retained marker cannot admit pointer input before startup.

The first boot uses the normal `vinix.disk=auto` installer with a blank 4 GiB
VJFS disk. The guest requires the installed root device, image identity, ordinary
root-owned tool files and exact staged tool/configuration digests. The host does
not format, repair or copy consumer state between boots. The kernel and fallback
initramfs remain on the FAT/ISO boot medium; autonomous firmware installation is
a separate gate.

The fresh guest rejects active package state, existing package generations and
previous package-approval audit records. Only catalog refresh uses the package
CLI before Software opens. Acquisition uses visible Install, the frozen review's
Confirm button and real key events for administrator approval. The guest then
runs read-only payload verification, requires exactly the signed Counter package
as the requested/installed set, and checks ordinary administrator attribution
without password disclosure in the audit log.

| Boot | Required graphical and retained behavior |
| --- | --- |
| 1 | Install Counter through Software; launch it; send two pointer increments; save private UID-1000 data; return to the catalog and reopen the exact rendered `Count: 2` label. Increment to three, save and shut down. |
| 2 | Select the same installed root; compare exact account, trust, catalog, replay-history, activation and private-data bytes/UID/GID/mode before desktop launch. Reopen Counter with the exact rendered `Count: 3` label, increment to four, save and shut down. |

The comparison covers the same 300 by 80 pixel label region after moving the
pointer away. Screenshots preserve review, approval, acquisition, application,
catalog-return and cold-boot states. Guest file values and private directory
ownership/mode independently check that input reached the real native app.
Each boot observes the native Counter launch helper and child finish closing
before it stops and reaps the real compositor, its session supervisor and the
authentication service before reporting its complete workflow marker. Acceptance
also requires a boot-bound QMP `SHUTDOWN` event with `guest=true` and reason
`guest-shutdown`, followed by a reaped QEMU process with exit status zero. A
dedicated event socket preserves the raw greeting, capabilities and power event
transcript. RESET or guest-panic events fail acceptance. ARM also requires its
serial kernel poweroff diagnostic; the frozen production x86 kernel sends that
diagnostic only to the graphical console. On both architectures,
initramfs fallback or an image-update diagnostic fails acceptance.

`software-graphical-build.v` freezes compositor/module/assets sources before
building either architecture. Ordinary mode requires a build manifest bound to
the actual compositor ELF and verifies every frozen input. The run receipt pins
the controller, compiler, QEMU, firmware, selected cross compiler, copied fixture
sources, generated guest C/ELF, kernel, compositor/build manifest, actual staged
configuration, signed repository files, initramfs, both serial logs and raw QMP
power transcripts, all fifteen
PNGs, installed-tool declaration and final disk. Final artifacts are hashed after
QEMU has exited and been reaped; disk hashing uses a bounded 1 MiB buffer.
`software-graphical-retain.v` verifies the complete required screenshot set and
artifact hashes, exact single success markers and guest-shutdown events on both boots and absence of guest
failure/panic/fallback diagnostics. It checks the controller, builder and guest
against its compiled embedded sources, and all nine current home/console/runtime/readiness
sources against the frozen desktop build before copying review evidence.
The production-built controller and retainer reject source changes made after
their own compilation; the controller records its embedded source copy.
The x86 fixture uses the bounded V `plainiso` helper to assemble a UEFI ISO with
the uncompressed USTAR archive accepted by the pinned kernel. Its embedded
source, loader files, xorriso, actual configuration, command and ISO are pinned.
Production image compression policy remains separate from this frozen-kernel test.

## Retained qualification, 2026-10-22

Both targets passed the installed ordinary-account scenario with the same frozen
controller and guest sources. Each completed two cold boots, exact saved-label
comparisons, the native child-close check and guest-initiated QMP shutdown,
followed by QEMU exit status zero. Independent retention verified 49 artifact
digests on ARM and 56 on x86, plus all nine current desktop source files.
The canonical screenshots were also inspected: Counter visibly renders 0, 2, 3
and 4 on both targets.

| Target | Receipt and build | Guest output | Power evidence | Visible application |
| --- | --- | --- | --- | --- |
| aarch64 | [Receipt](results/2026-10-22/software-graphical-aarch64.json), [desktop build](results/2026-10-22/software-graphical-aarch64.desktop-build.json) | [Boot 1](results/2026-10-22/software-graphical-aarch64.serial.txt), [boot 2](results/2026-10-22/software-graphical-aarch64.serial-2.txt) | [Boot 1](results/2026-10-22/software-graphical-aarch64.shutdown-1.jsonl), [boot 2](results/2026-10-22/software-graphical-aarch64.shutdown-2.jsonl) | [Initial 0](results/2026-10-22/software-graphical-aarch64.03-counter-zero.png), [saved 2](results/2026-10-22/software-graphical-aarch64.07-counter-reopened.png), [retained 3](results/2026-10-22/software-graphical-aarch64.10-reboot-counter-retained.png), [incremented 4](results/2026-10-22/software-graphical-aarch64.11-reboot-counter-four.png) |
| x86_64 | [Receipt](results/2026-10-22/software-graphical-x86_64.json), [desktop build](results/2026-10-22/software-graphical-x86_64.desktop-build.json) | [Boot 1](results/2026-10-22/software-graphical-x86_64.serial.txt), [boot 2](results/2026-10-22/software-graphical-x86_64.serial-2.txt) | [Boot 1](results/2026-10-22/software-graphical-x86_64.shutdown-1.jsonl), [boot 2](results/2026-10-22/software-graphical-x86_64.shutdown-2.jsonl) | [Initial 0](results/2026-10-22/software-graphical-x86_64.03-counter-zero.png), [saved 2](results/2026-10-22/software-graphical-x86_64.07-counter-reopened.png), [retained 3](results/2026-10-22/software-graphical-x86_64.10-reboot-counter-retained.png), [incremented 4](results/2026-10-22/software-graphical-x86_64.11-reboot-counter-four.png) |

Independent [ARM](results/2026-10-22/software-graphical-aarch64.controls.json) and
[x86](results/2026-10-22/software-graphical-x86_64.controls.json) validation accepted
each baseline and rejected all 22 corrupted evidence cases. These cover missing
screenshots or digests, mismatched paths or hashes, resealed source changes,
missing/duplicated success markers, kernel panic and altered QMP shutdown events,
including independent guest/reason checks on each boot.

## Reproduction

Use the [hardware controller requirements](../hardware-platform/README.md),
reviewed V and LLVM tools, static musl desktop sysroots, the ui2 source tree and
an unbooted production-staged native image/publisher workspace from
`native-catalog-check.v --software --image`. The staged configuration must name
the selected architecture and `launch_user` `alex`.

```sh
v -path '@vlib|@vmodules|.|desktop/tools' \
  -o /build/software-graphical-build tests/packages/software-graphical-build.v
/build/software-graphical-build --arch=aarch64 --out=/build/frozen-desktop-arm
v -prod -path '@vlib|@vmodules|.|tools|tests/hardware-platform|build-support|tools/accounts' \
  -o /build/software-graphical-check tests/packages/software-graphical-check.v
/build/software-graphical-check --ordinary=true --installed=true --arch=aarch64 \
  --rootfs=/build/native-arm/guest/root --publisher=/build/native-arm/publisher \
  --desktop=/build/frozen-desktop-arm/vinix-desktop --kernel=/build/arm-kernel \
  --out=/build/new-graphical-arm
v -prod -o /build/software-graphical-retain tests/packages/software-graphical-retain.v
/build/software-graphical-retain /build/new-graphical-arm /build/frozen-desktop-arm \
  /build/arm-kernel /build/software-graphical-check /build/retained aarch64
```

Repeat with `x86_64` and its matching image, kernel and desktop build. Both output
directories must be new. Each boot has a bounded 1,200-second deadline, including
full-strength account creation and administrator password verification. This host
uses ARM HVF and x86 TCG, 1024 by 768 display,
2 GiB ARM / 1 GiB x86 RAM and no guest network. Set `CC_AARCH64`/`CC_AMD64` and the hardware
controller's sysroot/boot-media variables when the host needs a cross wrapper.
The image contains throwaway fixture credentials; the signing seed stays outside
the guest. The optional noninstalled/root modes are diagnostics and do not meet
this installed ordinary-session gate.

The [twelve host home/identity/readiness checks](results/2026-10-22/software-session-ready.txt)
separately execute a real PTY child and check identity, HOME/XDG variables and
working directory, account-specific readiness paths and legacy registration regressions. Guest `/proc` environ
is intentionally empty and is not used as environment evidence.

The [host process-observer qualification](results/2026-10-22/software-graphical-poll-host.txt)
uses `software-graphical-poll-check.v` to extract the actual guest process-observer
function and changes only the procfs location for a host fixture. Its ASan/UBSan
run with `-gc none -manualfree` performs 4,000 scans covering the package launch
helper, Counter child, unrelated executable and a process that disappears before
its command line is read.

This scenario covers native Counter acquisition and integrated Software display.
It does not cover a graphical login chooser, the whole advertised catalog,
foreign runtimes, graphical upgrade/rollback/removal, audio/device acceptance,
unorderly power loss or autonomous firmware boot. Release publisher selection,
catalog migration and the broader roadmap 14 gate remain open.
