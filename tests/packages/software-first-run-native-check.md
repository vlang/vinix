# Native first-run release review in an installed ordinary session

`software-graphical-check.v --ordinary=true --installed=true --first-run=true`
extends the [installed Software scenario](software-graphical-check.md) with the
real first-run release card. It starts the ordinary compositor through
`vinix-session run --seat alex /usr/bin/vinix-desktop`, without an application
argument. The fixture stages an ordinary root-owned declaration at
`/usr/share/vinix-packages/applications.json`:

```json
{"format":1,"architecture":"aarch64","packages":["org.vinix.counter"]}
```

The x86 fixture uses `x86_64`. The exact package ID comes from the fixture's signed
native catalog; this declaration adds no publisher trust or default catalog.
Neither `/usr/bin/pkg` nor the legacy first-run pending marker is present.

Before sending card input, the guest checks all four compositor UIDs are 1000,
the real account home artifacts and its private mode-0700 runtime directory.
The host waits for the rendered card, retains its PNG, and clicks **Review release
applications**. Desktop readiness is required only after that choice. Software's
actual full deployment proposal is captured before the separate **Confirm** and
administrator password steps. An independent read-only `deployment-review`
request records the complete architecture-matched Counter proposal and signed
publisher/permission metadata. The guest checks that package activation,
generation files and approval audit records are absent before and after that
read-only request.

The choice must create the ordinary account's regular mode-0600
`.vinix-first-run-release` file containing exactly `review\n`. Acquisition then
uses the existing real Software confirmation and password flow, with exact signed
Counter state and administrator attribution. Pointer input saves Count 2,
close/reopen compares its exact rendered label, and a second save records Count 3.
The second cold boot selects the same installed root and compares retained
account/package/private-data bytes and metadata, including the declaration and
decision. It requires a fresh readiness inode and no repeated card, opens Software
through Start, reopens the exact rendered Count 3 label, and increments to Count 4.

Both boots require the real Counter child to finish closing, compositor/session
and authentication-service cleanup, a boot-bound QMP `SHUTDOWN` event with
`guest=true` and `reason=guest-shutdown`, and a reaped QEMU exit status zero. RESET,
panic, fallback-initramfs and image-update diagnostics refuse acceptance. The
earlier direct-catalog mode remains available; its historical qualification is
separate.

The run receipt binds the fixed declaration, eighteen required PNGs, installed
tool declaration, signed repository/configuration, generated guest, compiler and
boot tools, final disk and both serial/QMP transcripts. The production-built
retainer checks all artifact digests, its embedded fixture sources, exact ordered
first-run markers and proposal contents, and thirteen frozen/current desktop
sources before copying evidence. Source changes after controller or retainer
compilation refuse admission.

## Retained qualification, 2026-10-22

Both architectures passed with identical frozen controller and guest sources.
Each completed two cold boots, exact Counter label comparisons and guest QMP
shutdown followed by QEMU exit status zero. Independent retention verified 54
artifact digests on ARM and 61 on x86, plus all thirteen current desktop sources.
Manual inspection confirmed the real Review/Skip card, complete deployment
proposal, separate masked password prompt, no repeated card on boot 2 and visible
Counter values 0, 2, 3 and 4 on both targets.

| Target | Receipt and build | First-run UI | Guest and power evidence | Saved application |
| --- | --- | --- | --- | --- |
| aarch64 | [Receipt](results/2026-10-22/software-first-run-native-aarch64.json), [desktop build](results/2026-10-22/software-first-run-native-aarch64.desktop-build.json) | [Card](results/2026-10-22/software-first-run-native-aarch64.first-run-01-card.png), [proposal](results/2026-10-22/software-first-run-native-aarch64.first-run-02-proposal.png), [reboot](results/2026-10-22/software-first-run-native-aarch64.first-run-03-reboot-desktop.png) | [Boot 1](results/2026-10-22/software-first-run-native-aarch64.serial.txt), [boot 2](results/2026-10-22/software-first-run-native-aarch64.serial-2.txt), [shutdown 1](results/2026-10-22/software-first-run-native-aarch64.shutdown-1.jsonl), [shutdown 2](results/2026-10-22/software-first-run-native-aarch64.shutdown-2.jsonl) | [Retained 3](results/2026-10-22/software-first-run-native-aarch64.10-reboot-counter-retained.png), [incremented 4](results/2026-10-22/software-first-run-native-aarch64.11-reboot-counter-four.png) |
| x86_64 | [Receipt](results/2026-10-22/software-first-run-native-x86_64.json), [desktop build](results/2026-10-22/software-first-run-native-x86_64.desktop-build.json) | [Card](results/2026-10-22/software-first-run-native-x86_64.first-run-01-card.png), [proposal](results/2026-10-22/software-first-run-native-x86_64.first-run-02-proposal.png), [reboot](results/2026-10-22/software-first-run-native-x86_64.first-run-03-reboot-desktop.png) | [Boot 1](results/2026-10-22/software-first-run-native-x86_64.serial.txt), [boot 2](results/2026-10-22/software-first-run-native-x86_64.serial-2.txt), [shutdown 1](results/2026-10-22/software-first-run-native-x86_64.shutdown-1.jsonl), [shutdown 2](results/2026-10-22/software-first-run-native-x86_64.shutdown-2.jsonl) | [Retained 3](results/2026-10-22/software-first-run-native-x86_64.10-reboot-counter-retained.png), [incremented 4](results/2026-10-22/software-first-run-native-x86_64.11-reboot-counter-four.png) |

Independent [ARM](results/2026-10-22/software-first-run-native-aarch64.controls.json)
and [x86](results/2026-10-22/software-first-run-native-x86_64.controls.json) controls
accepted each baseline and rejected all 43 corrupted cases before copying output.
The 21 first-run-specific refusals cover missing card/proposal/reboot PNGs,
resealed declaration changes, pre-ready identity, missing or incomplete proposals,
publisher/permissions, unchanged state, private decision, ordering and repeated
prompt/proposal on boot 2. The existing 22 source, artifact, serial and QMP power
controls remain in the same run.

## Reproduction

Use the prerequisites and fresh staged image/publisher inputs in the
[installed Software instructions](software-graphical-check.md#reproduction).
Build a matching compositor snapshot and production controller/retainer, then add
the new mode:

```sh
/build/software-graphical-check --ordinary=true --installed=true --first-run=true \
  --arch=aarch64 --rootfs=/build/native-arm/guest/root \
  --publisher=/build/native-arm/publisher \
  --desktop=/build/frozen-desktop-arm/vinix-desktop --kernel=/build/arm-kernel \
  --out=/build/new-first-run-arm
/build/software-graphical-retain /build/new-first-run-arm /build/frozen-desktop-arm \
  /build/arm-kernel /build/software-graphical-check /build/retained aarch64
```

Repeat with the matching x86 inputs. Each boot has a 1,200-second deadline. Use
new output directories; the fixture owns the blank installed disk and never
copies package or account state between cold boots.

This scenario qualifies the Review path for a controlled ordinary session and a
single declared native application. [Host qualification](software-first-run-release-check.md)
separately covers durable Skip, failed-save retry and handoff cancellation.
Native Skip, graphical login, foreign/default application catalogs, physical
hardware and the whole roadmap 14 release gate remain separate work.
