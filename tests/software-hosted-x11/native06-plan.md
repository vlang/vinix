Native06 launch-options execution plan, 2026-10-26. This records a proposed
execution admission; it contains no new target build or guest qualification.
The bounded host supervisor has passed its focused host controls, recorded in
`supervision.md`. Guest execution still requires a separate lane cue.

The fixture worktree is
`/Users/alex/code/vinix/build/package-hosted-launch-options-guest-worktree`, at
`6e6cf3bb68ed1dbdc08ccf5dda5194bfefd244f9` plus the frozen fixture and five
production prerequisite files below. Main was
`a44c38e3c17657e897e72776f7bc4e6033321ee7` when inspected. The compositor
snapshot was built from `3770607e67052a3e179d8c27a19b1668993a440e` plus its
eleven explicitly pinned production files; neither Git revision alone identifies
the tested bytes.

The production prerequisites add canonical authenticated `--package ... run-args`
admission, preserve the signed-application lease path, and pass Software's frozen
literal operands, granted paths and cwd selection to that bridge. The native
fixture changes add the explicit `launch-options` scenario, child observations,
permission refusal, format-2 retention and 29 supplemental refusal controls.
The latest correction is confined to `guest/main.v`: an adopted zombie's
`waitpid(..., WNOHANG) == 0` remains pending under the existing bounded 50 ms
poll; only the exact child PID followed by `/proc` disappearance accepts.
Negative/other-PID results fail with the saved errno. Native05 did not log its
immediate wait result, so its cause remains unproven. There is no new kernel or
production fix in native06.

Frozen source SHA-256 values, relative to the fixture worktree:

| Path | SHA-256 |
| --- | --- |
| `desktop/software_app.v` | `fbe37cc132d224b00d44c183ff76958ca0fb8100ce7cb63f8b12bd50162b4695` |
| `desktop/software_hosted.v` | `8e366c7f1a1706e736b3982e8bb842d5cde02edec77f49959f9ffbf0ace6938d` |
| `desktop/software_launch.v` | `11db058fe944789a19df91f2c8a3cb0b31a84d6bd5955913922a524d064e5719` |
| `build-support/xorg-server/winehost/core.v` | `bc31ff0dcb2746bf81e54c9e44e900cb0e33dbaa7037392b72277fa44d3ccedf` |
| `build-support/xorg-server/winehost/package.v` | `7ce47e4cacad1fc1acbcd7a91dc2bd25b5fd127407307785f5996a923bdcccb3` |
| `tests/software-hosted-x11/check.v` | `7690dd77af1f8e9abd051d1cb79823a2a880bb2940f44dc1c1a3cea708d2b37d` |
| `tests/software-hosted-x11/retain.v` | `9a8d5aa7eb271a0818a9fe0c75bf3ace0a00caad3e5fc4d27fcce0732195a3ca` |
| `tests/software-hosted-x11/evidence-check.v` | `d2d95972e9ea71c0421769a32a6d277f3baa83e9312dbb4ff91872e8c52dd274` |
| `tests/software-hosted-x11/guest/main.v` | `00fc5487e03bcc0067c07d6e370f3fa66be15d4ee0ce67308de613cbb2aadaf7` |
| `tests/software-hosted-x11/guest/options.v` | `42922aa9a2a998a07545feed7357622559e0147deed8490e919a6fd6ee10c614` |
| `tests/software-hosted-x11/optionsfixture/fixture.v` | `c5d895e978fb42959de5824ea5945683edd3acab05f0fd126cf963d59b369b56` |
| `tests/software-hosted-x11/launchproof/admit.v` | `e8ba120b8b4ac08207bd53be979c5d6ea8085eb11df4689025b107ab0f1aeb94` |

Use existing inputs, without rebuilding or copying their complete bundles:

```
STATE=/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a
SUPP=/Users/alex/Library/Caches/vinix-codex/section14/package-hosted-launch-options-native-20261026
V=/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v
```

These names are notation for paths, not an environment setup script. The runner
sets `VINIX_ROOT`, `V`, the LLVM-prefixed `PATH` and the exact Limine path itself.
Rehash its complete source/tool pins before reuse. Normal and production host
compilation already passed; normal tools are compile checks only because the
retainer and control runner require `-prod` at execution. Their pin manifests are
`STATE/host-build-normal-06/pins.json` SHA-256
`94cae0303b520c2994795a8cde8721cc6162103c8326e0352d3287887f59d06d`
and `STATE/host-build-06/pins.json` SHA-256
`14f9e6296142c0fb636938049d1d46cd73d977295be98ea6b6cd1a7765635a38`.
No host sanitizer, allocation tracking or host manual-free qualification is
claimed. The controller builds the account, session, auth, package and guest
programs with `-prod -gc none -manualfree`. The bridge uses its separately
recorded flags without `-prod`; all are cross-linked with the pinned toolchain.

| Input | SHA-256 |
| --- | --- |
| retained V compiler | `ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5` |
| `STATE/tools-06/check` | `204c34fcd734af70e818fd578f19222859a671de00dddece4da154231b38fb77` |
| `STATE/tools-06/retain` | `8c33a98130f2d8eb7799de3641760690cfe03f3b41badf556f90bf91c42a7be7` |
| `STATE/tools-06/evidence-check` | `b04fafb039b5818869b970cdc1c9f03a4b4ccf04e7baa4006cac0b12792d7c33` |
| `STATE/run-native06.v` / executable | `2161a5cfc3c936f30372cb65557a1c4cd1542317be338abbafe05c902fb8fa7d` / `924ee617447341825754ca01b9f7580c7e5e5c50f85eb1569aa70e633820ee68` |
| `STATE/run-evidence06.v` / executable | `e6a4b84faccddf673a79a89905b80ca0c837af9cf6058bb23f1a775bd6d8c5d9` / `b419dea8ac587dd974728b781e09f9147f484b80d276024eb6077835fe4a00f1` |
| x86-64 imported compositor | `60a2a6619403dd551f969445f3548d6fadd6f785303315377fb2043ca0d2b4a0` |
| AArch64 imported compositor | `cb23ee2f37ecdde3703dfb6c0d4a2e02526499d0942685bacc0cf4c256d75d68` |
| x86-64 frozen kernel | `06a9936a923892a01fb291d8a9ec21a69b3ad1a1a1658c47cf7d5e85ee10d039` |
| AArch64 frozen kernel | `246ce2e5c33f0941870cb76d47d5c095575503df405a3de9243bdc1d935e4771` |
| LLVM Clang / llvm-readelf | `4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8` / `9ff1c0f23cd0809ff80e33cdf2ccbf11868027977f3b574d0388c3e2e8618a3c` |
| QEMU x86-64 / AArch64 | `25afcb2986e4a0f2c567de17273f55de3c99792b78a07c99e923bb62024c088f` / `45d74da57beb9be259ca3d6996e5c70d4ab14326ea59c3db3e80308859d91a3e` |

The reviewed eleven-source target bundle is
`/Users/alex/Library/Caches/vinix-codex/section14/package-section14-hosted-options-target-20261026/full-compositor-hosted-options-v2`;
its manifest seal is
`c5b72beb336e451695c58094d8f77ed850014ee180fe609bf5d05582b267834d`.
`launchproof` verifies the complete bundle, original tools, source/generated
inventories, both architectures and ELF types before admitting the two imports.
Their `desktop-build.json` hashes are x86-64
`62d2181a49654386ca31f7495c9b1941da804309f78c2bd1a712dc5670086ee1`
and AArch64
`894148dd9b8f978d9de7ecb6ea83671e7c6ef7f588ae7ac096ca3c4359df8ead`.
Use the existing complete restored stages under `SUPP/restored-stage-ARCH/root`;
their exact original generated-C restoration receipts and historical checker
anchors remain required. The controller records and rechecks complete original
input trees, copied inputs, compiler/tool bytes, generated C and build argv
before boot and after guest exit.

Run only x86-64 first, after a separate lane cue:

```
STATE/native-supervision-host-01/supervise-07 --native-x86_64
STATE/native-supervision-host-01/supervise-07 --controls-x86_64
```

Here `STATE` must be expanded to the literal path above. The fixed supervisor
binds the exact wrappers, controller, foreground tools and inherited-group
source profile before releasing a child. The second
command runs only after a complete accepted native qualification. Its controller
invocation is `tools-06/evidence-check tools-06/retain NATIVE CONTROLS
--scenario=launch-options`. Do not run ARM or refusal controls to bypass a failed
x86-64 baseline. After x86-64 acceptance, storage accounting and a separate ARM
cue, use `--native-aarch64` and then `--controls-aarch64`. The frozen wrappers
expand the exact restored stage and new output paths above themselves.

Storage admission is fresh `/bin/df -k STATE` available space at least
2.1 GiB (2,202,010 KiB), a 1 GiB incremental allocation cap per architecture
including its sequential controls, and a 1 GiB shared available-space floor.
Reserve another 256 MiB before later preservation/archive writes; those writes
need their own lane and budget. Prior complete failed expansions occupied about
477 MiB x86-64 and 451 MiB ARM. The controller makes a 4 GiB logical sparse disk,
uses `cp -cRp` for rootfs/stage, and writes an initramfs and x86 ISO. Logical disk
length is not physical allocation. Controls use one APFS private native/desktop
clone, mutate and restore small files sequentially, then remove only that private
clone after all refusals. Retained baseline outputs copy five frames and small
receipts, not another raw disk. APFS sharing is an estimate until measured; stop
if the cap/floor is reached. Two retained guest lanes have a proposed total cap
of 2 GiB incremental, but ARM must pass a new admission with x86 evidence still
present. Run one VM and one large writer at a time. The initial planning
observation was700,344KiB available and did not satisfy admission; no old
observation substitutes for the supervisor's fresh admission.

The maintained `supervise.v`/`nativeguard` supervisor drains output, samples
separately owned direct `df -k` helpers and new namespace allocation every
second, and enforces a30-minute outer build/guest deadline. Each helper and the
main leader use a checked group barrier before executable release. Success
requires actual leader wait/reap, a further ECHILD, and group ESRCH; raw signal
errors remain in the receipt and never establish cleanup. The1GiB allocation
cap includes an8MiB reserve for bounded final receipts, followed by another
guarded df observation and allocation check. It uses the reviewed inherited-
group lifetime model and has13 actual host controls. Numeric PGIDs are trusted-
host observations; this does not protect against hostile PID/PGID reuse.
A sampled guard is not a continuous-space guarantee. No frozen foreground path
detaches its descendants; source/tool binding rejects a changed profile.
The controller separately bounds QEMU to20minutes;
x86-64 uses 1 GiB guest RAM with TCG, ARM 2 GiB with HVF, both two CPUs, one boot,
1024x768 and `-nic none`. Plan a separate 20-minute wall cap for host retention
and refusal controls. The host supervisor build and controls are complete;
this document does not authorize target staging or guest execution.

For the allocation cap, sum `st_blocks` without following links only within the
new native/control outputs and their wrapper/supervisor siblings. This is a
conservative namespace bound because APFS shared blocks can be counted twice;
do not equate it with exclusive physical usage or infer it from unrelated
filesystem free-space changes. Use direct `df -k` independently for the shared
floor. A new same-filesystem output and sole large-writer lane are prerequisites.

Success requires each architecture's fresh format-2 `launch-options`
qualification, unchanged complete input inventories, and all five screenshots.
The signed child must observe exact empty/Unicode/space/metacharacter/literal-flag
arguments, private cwd, granted-file read and write, unchanged inaccessible
neighbor, and relative private output; the independent observer must verify the
private receipt and actual file effects. Its authenticated bridge must carry the
exact NUL-delimited `run-args` vector. The separate signed no-files package must
fail with the expected permission error, nonzero exit and no executed child,
lease or launch context. The signed application must paint, repaint on an actual
pointer event, close with actual bridge/Xvfb reap and authority/socket removal,
retain its lease while the child lives, then release it after actual child reap.
Require real guest QMP shutdown and reaped QEMU exit zero. Inspect the catalog
and options frames manually; painted, pointer and closed frames also have
checker-enforced color phases. Retention must accept the immutable original and
the private cloned baseline, then refuse exactly 69 corruptions (historical 40
plus new 29) for their expected reasons before creating output. Claim the new
zero-wait branch was observed only if native serial actually records zero.

On any failure, stop the group, retain the complete failed output plus its
`.argv.json`, `.environment.json`, `.runner.json`, `.controller.log` and
`.controller-exit.json` siblings and supervisor/source/build receipts. Keep all
external inputs and literal symlink referents needed by existing checkers. No
failed baseline supplies acceptance. No deletion follows automatically: a later
approved fixed-scope preservation must verify original completeness, independent
streamed archive contents, original again and source/tool/root identity before
reclamation. Preserve the existing native02/03/05 archives, manifests, independent
reader receipts, controller siblings and separate diagnostic referents; ARM03's
Software SIGSEGV remains unresolved. See `diagnostics/recovery-guard.md` and
`launch-options.md`. This plan qualifies neither broad native X11 behavior nor
arbitrary applications, production publishers, HTTPS clipboard access,
cross-account authentication or desktop-menu shutdown.

If the outer guard has to kill the wrapper before it writes final controller
siblings, preserve their observed absence and the supervisor's actual wait/
group/output records. Do not synthesize an exit-zero or complete wrapper record.
