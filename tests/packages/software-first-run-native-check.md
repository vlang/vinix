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

## First-run review with an empty catalog

Add `--first-run-refresh=true` to the installed first-run Review recipe. Use a
fresh root and matching fixture publisher from
`native-catalog-check --software-bundled-https`. The image enrolls its HTTPS
publisher with an online-capable policy and a signed local bundle. The desktop
builder accepts `--musl-cc=x86_64-linux-musl-gcc` when using a standalone
musl cross compiler. It stages the selected V compiler's runtime for each link.

The guest checks for an empty catalog and approval history after first login.
The controller clicks **Refresh offline**, captures its administrator prompt
and password mask, and waits for the signed catalog and read-only proposal.
It approves installation in a second prompt and reopens the saved Counter
after a cold boot. Retention requires the refresh screenshots, separate
approvals in order, and a cold boot without a repeated prompt or refresh.

### Empty-catalog results

At `937dc04c4331cf784f1f2160539d5a6d1e467cec`, the installed aarch64
and x86-64 guests passed with freshly built compositors at 1024×768
and guest networking disabled. Each began with an empty catalog, approved
offline refresh and installation in separate prompts, and reopened the
saved Counter after a cold boot. The second boot preserved the HTTPS
configuration, package state and private data. Both boots ended with
guest-initiated QMP shutdown.

The independent retainer verified 59 artifact digests on aarch64 and 66 on
x86-64. Both retained 21 screenshots and rejected 48 altered-evidence cases.
Kernel serial output interrupted the proposal JSON in an earlier ARM run.
Its logs are retained with the accepted runs.
The fixtures start an ordinary seat with `vinix-session` and retained
kernels. Production login and public catalog rollout remain separate gates.

The evidence is archived at
`~/.local/state/vinix/r14-first-run-graphical-3DNZqu/qualification.tar.gz`.
Its SHA-256 is `4da2477914bc030ec87dc532148eee6c0a76ca14b8849c5383d0bb80980cbede`.
Independent extraction matched all 9,547 inventory entries and both decoded
VJFS disks matched their original receipt digests.

## First-run offline refresh through production login

Add `--production-root=STAGED_DESKTOP_IMAGE` to the empty-catalog command
above. Use the matching architecture's release staging root. The controller
copies its PID 1, BusyBox, musl loader, volume and system tools, and power
action into the signed package fixture root. Production init starts the
test observer through its optional version-check hook. The observer
records installed files, process identities, package state and the Counter
checkpoint. QMP sends all registration, login, package approval and
shutdown input through the real desktop.

At `f9b2aee46a4a1ee4d6c7424b50ea0df110508e8b`, freshly built aarch64 and
x86-64 compositors passed on retained kernels with 1024×768 framebuffers
and guest networking disabled. Both runs registered the first administrator
through the root registration screen and logged in through the UID 101 greeter. The
ordinary UID 1000 seat reviewed the release, refreshed the empty catalog
from the signed offline bundle, and approved the Counter installation
separately. On the second boot, the greeter logged into the retained
account, the first-run prompt stayed dismissed, and Counter reopened at
3 and saved 4. All four boots ended through the desktop shutdown menu
and produced guest-initiated QMP shutdown events.

The retainer checked 79 artifact digests on aarch64 and 86 on x86-64,
including 26 screenshots per run. Each rejected 55 altered proofs,
including missing or reordered login evidence, repeated registration,
fixture-driven poweroff, an altered init digest and enabled networking.
The aarch64 direct-seat mode also passed with the shared observer.
The first production assembly attempt exposed a missing root home in
the minimal fixture. Its logs are retained with the successful run.

The evidence archive is
`~/.local/state/vinix/r14-production-first-run-3bVLw6/qualification.tar.gz`.
Its SHA-256 is `1417bfe053165c7114c18597ae246e3e847ec5b93ad71594ca21a5bfa1c5330a`.
Independent extraction matched all 18,332 inventory entries. Both
decoded VJFS disks matched their original digests.

## First-run production login with the staged native catalog

Add `--staged-catalog=true` to the production-login command. Supply a fresh
`--rootfs` from `native-catalog-check --software-bundled-https` and omit
`--publisher`. This mode uses the format-2 lock produced by image staging
for Counter, Memo and Package Hello. The controller checks each pin against
the bundled signed index and preserves the lock bytes and signed bundle.

The login workflow reviews all three apps before installation. On each boot
the observer runs a read-only deployment audit after Counter has closed.
The evidence check requires all three installed entries to match the
staged lock digest and the same active generation across both boots.

At `333d8b702f7671035b989b3ee89057f976b54e6d`, the aarch64 and x86-64
QEMU runs each installed all three locked 1.0.0 packages through Software.
Each recorded separate refresh and installation approvals, reopened Counter
at 3 and saved 4. The complete deployment audit matched generation 1 before
both shutdowns per target. The runs reused the previous production
compositor and kernel builds and booted with networking disabled.

Independent retention checked 81 artifact digests on aarch64 and 88 on
x86-64, including 26 screenshots on each. Both rejected 61 alterations,
including a different staged lock, a missing audit or package, a changed
generation and a proposal from the wrong publisher. The aarch64 direct-seat
regression also passed. Earlier runs exposed an interleaved startup marker
and an observer that could start verification before the deployment writer
exited. The corrected runner uses the verified manager marker and waits for
the successful installation approval. The archive includes the early logs.

The evidence archive is
`~/.local/state/vinix/r14-staged-production-catalog-gGFsJq/qualification.tar.gz`.
Its SHA-256 is `994a864004158d64d627d7263bc73533f35f5d6ae94038443640442204f664ae`.
Independent extraction matched all 19,456 inventory entries, both staged
locks and both decoded VJFS disk digests.

## Selected repository refresh through production login

Add `--targeted-refresh=true` to the staged production login command above.
Supply the unbooted root from `native-catalog-check --software-targeted-refresh`
and a compositor that includes **Refresh selected**. The staged root contains
the HTTPS publisher's offline bundle and two signed sequences of the enrolled
local `field` repository.

Boot 1 installs the three native apps through the graphical first-run review.
The installed observer moves the HTTPS bundle aside and switches the local
fixture to sequence 2. QMP opens **Repositories**, selects **field**, changes
access to **Use policy** mode and back to offline, then activates **Refresh
selected**. It captures the administrator prompt, masked password, completion
and the return to the catalog.

The observer compares the cached publisher identities and signed indexes,
configuration, application lock, trust history and active state around the
operation. Authentication must record exactly one extra approval from the
ordinary administrator. The observer waits for the signed pair to reach the
cache after the authentication service starts the worker. Both guests then
save Counter data and shut down through the desktop. Boot 2 checks the retained
catalog, trust history and file ownership before login. It also checks the
refresh record after reopening and saving Counter's data.

The retainer checks both signed field sequences, the exact cached HTTPS input,
the ordered serial records and framebuffer transitions. Earlier scenarios keep
their existing input and evidence checks.
