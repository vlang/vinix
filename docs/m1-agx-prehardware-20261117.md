# M1 AGX pre-hardware parity recheck

**Whole-driver parity remains open.** All twelve modern ioctl words match the
packaged C header. The host probe reproduces a cross-queue dependency regression
introduced by `f183daa00`. All validation ran on the host.

## Source revisions

| Input | Revision |
| --- | --- |
| Vinix | `f183daa00bb61420ec7039f31e8baabe22dc497f` |
| [Omarchy default branch](https://github.com/omacom/omarchy/tree/a6193cab1b99cc9f8f8de218f84e1c91b0fc7adc) | `a6193cab1b99cc9f8f8de218f84e1c91b0fc7adc` |
| [Omarchy packages](https://github.com/omacom/omarchy-pkgs/tree/a6b27dbb118186a7a30cdae1fad70c612e5ea00e) | `a6b27dbb118186a7a30cdae1fad70c612e5ea00e` |
| [Packaged Linux-Aurora](https://github.com/omacom/linux-aurora/tree/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi) | `bed544bdf93a496ebf70ba180923bab12b6e01cf` |
| [Packaged Mesa](https://github.com/omacom/mesa/tree/b7b03c5b3b8abe1e040d6056dc62c01b02d3639c) | `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` |
| m1n1 | `b4654b32941d51afdb77579d63e7cb1aa6c03ecc` |

The fresh default-branch checkouts keep the preceding kernel and Mesa pins.
The host tests used committed kernel sources from an isolated checkout. The
shared checkout's concurrent event edit was outside this run.
The [previous dependency evidence bundle](m1-agx-job-dependencies.md) passed its
complete integrity check again.

## Confirmed differences

- **Dependency ordering.** An older compute job and a newer render job on the
  same producer queue share a fence context. A consumer on a second queue
  explicitly waits on both fences. When the fixture retires render first,
  Vinix dispatches the consumer while the compute fence is pending. The same
  probe with the parent revision's submit path waits for both fences. The
  production ioctl and worker run in both probes. The fixture injects GPU
  completion order, so the corresponding hardware ordering remains open.
- **Fence sequence model.** The prior 4,096 selections still match the
  packaged scheduler with its 64-bit comparison branch selected. Packaged
  Asahi actually exports scheduler finished fences with a per-entity 32-bit
  counter and signed low-32-bit delta ordering. Vinix stamps its output fences
  with a 64-bit clock value. The reverse-retirement failure occurs without
  sequence wrap. [Packaged fence initialization](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/scheduler/sched_fence.c)
- **DRM timeline discovery.** Vinix returns 0 for
  `DRM_CAP_SYNCOBJ_TIMELINE`. Packaged Asahi enables this driver feature and
  Linux returns 1. [Vinix capability handler](../kernel/drm/drm.v) ·
  [Packaged Asahi features](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/driver.rs)
- **Userspace stack.** Vinix builds and checks its image against Mesa 25.0.5.
  Omarchy packages Mesa 26.3.0 development source at the pin above. The
  packaged Mesa build and end-to-end submission against Vinix remain
  unqualified. [Vinix build](../scripts/build-asahi-aarch64.sh) ·
  [Omarchy Mesa package](https://github.com/omacom/omarchy-pkgs/blob/a6b27dbb118186a7a30cdae1fad70c612e5ea00e/pkgbuilds/mesa-aurora/PKGBUILD)

The [remaining differences](m1-agx-parity.md#remaining-differences) also cover
VM reservations and backing, purge/repopulation, full firmware defaults and
recovery, and M1 Pro/Max/Ultra topology. The scope of this recheck is base M1.

## Checks and reproduction

Passed 82 V test files, five firmware/protocol source gate groups, all 28 C UAPI
record layouts and field offsets, and the 12 complete ioctl encodings from the
registered Vinix table. ASan/UBSan passed the packet, file-close, async,
DRM synchronization, TLB and G13 failure suites. A wrong encoding list was
rejected by the compiled file-close fixture. The unchanged source audit exits
1 based on its selected legacy compatibility facts. Modern wire results above
come from the separate compiled checks.

```sh
ASAN_OPTIONS=detect_stack_use_after_return=1 \
  v run tests/agx-async/run.v --audit-dependency-order

git show f183daa00^:kernel/gpu/agx/file/file.v > /external/pre-dedup-file.v
ASAN_OPTIONS=detect_stack_use_after_return=1 \
  v run tests/agx-async/run.v --audit-dependency-order --file-source /external/pre-dedup-file.v

v -path "$PWD/tools/agx-re|@vlib|@vmodules" run tests/agx-packet/run.v \
  --asahi-linux /reference/linux --state-dir /external/fresh-packet
ASAN_OPTIONS=detect_stack_use_after_return=1 \
  AGX_ASAHI_WIRE_ORACLE=/external/fresh-packet/oracle.log v run tests/agx-file-close/run.v
```

The first invocation exits 1 at the consumer dispatch assertion on the audited
kernel. The parent submit path passes. This change adds the opt-in test and
wire comparison. Kernel sources were unchanged, so build evidence remains in
the preceding report. Native firmware execution, deployment and reboot counts
for this audit are zero.

Complete retained inputs, logs, executables and archive restoration are under
`/Users/alex/.local/state/vinix/omarchy-m1-fence-sequence-20261117/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `53d17b0a1b644c954cf3f6ba33573775bb0c331a81ef13eba2edec8b10df00c9` |
| `bundle.tar.gz.inventory.txt` | `53d3ba4a4fd63aed1f93ae33d7124202bc180ea8348c8902cc5ad03172423054` |
