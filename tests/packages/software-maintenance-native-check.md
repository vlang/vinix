# Native Software maintenance in an installed ordinary session

`software-maintenance-check.v` runs the real Software framebuffer UI through
Refresh, Update all, Rollback, Uninstall and a cached reinstall. It uses the
ordinary account's actual compositor and native Counter application on a blank
installed system disk, with two cold boots of that same disk. Every change uses
the visible Software confirmation or Refresh control and a separate real
administrator password approval; package mutation is never driven through a
fixture CLI command.

The fixture starts with signed version 1.0.0 and no installed generations or
previous package approval. After GUI installation, pointer input saves Count 2.
It replaces the controlled local repository directory with a newer signed
1.1.0 medium. Refresh must authenticate the exact index while leaving active
1.0.0 and private data unchanged. Update all activates 1.1.0 and its launcher;
Counter must reopen with exactly the saved Count 2 label, then save Count 3.

Boot 2 checks the retained tools, accounts, configuration, trust history,
package state, signed catalog and private file bytes and metadata before
starting Software. Rollback restores 1.0.0; Uninstall removes requested roots,
active packages and the launcher while preserving the private Count 3 file.
The fixture then removes both local repository payload directories. GUI
reinstallation must recover signed 1.1.0 from verified caches without restoring
those payload directories or altering the private file. Counter must render the
exact previous Count 3 label and save Count 4 through pointer input.

Independent read-only `review` requests capture all five complete proposals:
install, upgrade, rollback, remove and reinstall. Before and after each request,
the guest compares activation state, exact approval count and any private file
contents and metadata. The retained proposals must match the target architecture,
Counter-only requested closure, version transition, operation/action, generation,
MIT license, display permission and configured publisher key. The final approval
count is exactly six: install, refresh, update, rollback, uninstall and reinstall.

Each boot requires all four compositor UIDs to be 1000, real home artifacts,
a private runtime directory and fresh owned readiness inode. The actual Counter
launch child must retire before compositor/authentication cleanup. Acceptance
also requires a dedicated boot-bound QMP `SHUTDOWN` event with `guest=true` and
`reason=guest-shutdown`, followed by QEMU exit status zero and reaping. RESET,
panic, fallback-memory root and installed-image update refuse admission.

This qualification uses the exact frozen production compositor snapshots from
[c035 first-run qualification](software-first-run-native-check.md), and separately
pins every desktop build input. It does not claim a later assembled greeter/X11
build. Versions 1.0.0 and 1.1.0 use the same SDK Counter executable with different
signed release metadata; the scenario proves package/version maintenance and
private data behavior, rather than an application code migration. It uses a
controlled signed local repository, with no network service or default catalog.

## Retained qualification, 2026-10-22

Both targets passed the full framebuffer workflow, including the second cold
boot, all six real administrator approvals, exact saved Counter label comparisons
and both guest-originated shutdown events. The canonical screenshots were
visually checked for Count 0, 2, reopened 2 after Update, 3, reopened 3 after
cached reinstall and 4. The visible proposals, active versions, removed launcher
and masked password fields were also checked on both architectures.

| Target | Native receipt | Refusal controls | Verified artifacts | Desktop input hashes | Screenshots |
| --- | --- | --- | ---: | ---: | ---: |
| aarch64 | [PASS](results/2026-10-22/software-maintenance-native-aarch64.json) | [Baseline + 50 refusals](results/2026-10-22/software-maintenance-native-aarch64.controls.json) | 78 | 2,519 | 32 |
| x86_64 | [PASS](results/2026-10-22/software-maintenance-native-x86_64.json) | [Baseline + 50 refusals](results/2026-10-22/software-maintenance-native-x86_64.controls.json) | 85 | 2,519 | 32 |

The controls reseal private copies to test missing screenshots and artifact pins,
changed frozen sources, missing or duplicated success/identity markers, panic,
invalid shutdown events, incorrect maintenance order or approvals, and incomplete
or altered proposals. Each refusal occurs before retained output is created.
The retainer removes only the known EFI cursor-home escape before checking exact
serial markers; the original serial bytes and their digests remain retained.

Examples from the actual UI are the
[x86 Update proposal](results/2026-10-22/software-maintenance-native-x86_64.update-review.png),
[aarch64 rolled-back version](results/2026-10-22/software-maintenance-native-aarch64.12-rolled-back.png),
[x86 uninstall result](results/2026-10-22/software-maintenance-native-x86_64.13-uninstalled.png)
and [aarch64 cached reopen at Count 3](results/2026-10-22/software-maintenance-native-aarch64.15-reinstalled-counter-three.png).
The complete ordered assertions are in the
[aarch64 first boot](results/2026-10-22/software-maintenance-native-aarch64.serial.txt),
[aarch64 second boot](results/2026-10-22/software-maintenance-native-aarch64.serial-2.txt),
[x86 first boot](results/2026-10-22/software-maintenance-native-x86_64.serial.txt)
and [x86 second boot](results/2026-10-22/software-maintenance-native-x86_64.serial-2.txt)
transcripts. Each receipt binds both raw QMP shutdown transcripts and the frozen
desktop build manifest as well as every screenshot.

## Reproduction

Use the fresh staged native image roots and publisher workspaces described in
[installed Software qualification](software-graphical-check.md#reproduction).
The publisher must contain `workspace-1.0.0`, `workspace-1.1.0` and its original
private signing seed. The controller publishes fresh bounded-validity sequences
into its own work directory; it never places the seed in the guest or retained
proof. The selected compositor directory must include the complete frozen
source snapshot and `desktop-build.json` matching the accepted c035 manifest.

```sh
V -new-compiler -w -nocache -prod \
  -path '@vlib|@vmodules|.|tools|tests/hardware-platform|build-support|tools/accounts' \
  -o /build/software-maintenance-check tests/packages/software-maintenance-check.v
V -new-compiler -w -nocache -prod \
  -o /build/software-maintenance-retain tests/packages/software-maintenance-retain.v
V -new-compiler -w -nocache -prod \
  -o /build/software-maintenance-controls tests/packages/software-maintenance-evidence-check.v
/build/software-maintenance-check --arch=aarch64 \
  --rootfs=/build/native-arm/guest/root --publisher=/build/native-arm/publisher \
  --desktop=/build/frozen-desktop-arm/vinix-desktop --kernel=/build/arm-kernel \
  --out=/build/new-maintenance-arm
/build/software-maintenance-retain /build/new-maintenance-arm /build/frozen-desktop-arm \
  /build/arm-kernel /build/software-maintenance-check /build/retained aarch64
/build/software-maintenance-controls /build/software-maintenance-retain \
  /build/new-maintenance-arm /build/frozen-desktop-arm /build/arm-kernel \
  /build/software-maintenance-check /build/new-controls-arm aarch64
```

Use the pinned compiler as `V`, and the architecture toolchain environment in the
installed Software instructions. Repeat with matching x86 inputs. Each boot has
a 1,200-second deadline. Outputs must be new directories. The host controller and
retainer must be production-built and refuse changed source bytes after build.
The retainer verifies every receipt artifact digest, exact screenshot set,
embedded fixture source, frozen compositor manifest and all its input hashes
before copying proof. Negative controls mutate private copies and must refuse
before creating any retained output.
