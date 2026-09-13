# Base M1 (t8103 / G13G) AGX bring-up contract

This pins the one boot handoff the native AGX driver supports on a base M1, so
that a failed bring-up is a driver bug rather than an unpinned input. Everything
below is what `kernel/modules/gpu/agx/driver/driver.v` actually reads; it is not
a wish list.

Scope is base M1 only. `hw.get_config()` recognises exactly two chip IDs,
`0x8103` and `0x6050`, and only `0x8103` has a complete firmware path.

## The supported handoff

| Input | Requirement |
| --- | --- |
| Bootloader | m1n1 in its Linux/FDT hand-off mode. Vinix consumes a flattened device tree, not the Apple DeviceTree. |
| GPU node `compatible` | `apple,agx-g13g` (preferred) or the older `apple,agx-t8103`. |
| Firmware ABI | 12.3.0, published as `apple,firmware-abi = <12 3 0>`. |
| Firmware image | The macOS 12.3-era G13 firmware. The ABI tuple is checked, the image is not: a newer image behind a 12.3 tuple will be accepted and will then disagree with every structure in `gpu/agx/fw`. |

`gpu,t8103` selects the native Apple DeviceTree path instead. That path is not
supported yet, but the gap is now a short named list rather than an open
question. See [native Apple DeviceTree](#native-apple-devicetree) below.
`validate_g13_firmware_compat()` also refuses it, because an ADT carries no ABI
tuple: whoever finishes the native path has to supply one, and the firmware
check is not optional just because a later gate happens to also stop the boot.

## Device-tree properties the driver consumes

### GPU node — addresses

* `reg` with `reg-names` `asc` and `sgx`, or an unnamed `reg` whose first range
  is the ASC and whose second is the SGX aperture. The ASC window must cover
  `0x48` bytes (`ASC_CTL` at `0x44`) and the SGX window `0xD04014` bytes
  (`GPU_ID_CLUSTERCFG` at `0xD04010`).
* `mboxes`, phandle index 0, resolving to a node whose first `reg` range is the
  ASC mailbox.
* `memory-region` / `memory-region-names` naming three reserved regions:
  * `ttbs` — at least 1 KiB (64 UAT contexts × 16 bytes).
  * `handoff` — at least `sizeof(mmu.UatHandoff)`.
  * `pagetables` — at least one 16 KiB UAT page.
* `power-domains`, a list of zero-cell PMGR domain phandles. The driver walks
  the hierarchy up to eight levels deep and enables each domain through
  `aarch64.pmgr` before it reads the GPU identity registers.

### GPU node — performance data

* `operating-points-v2`, phandle to a table with at least two enabled children.
* `apple,min-sram-microvolt` — the SRAM floor, at least 1000 µV.
* `apple,power-sample-period` — nonzero, in milliseconds.
* `apple,perf-base-pstate` — optional, defaults to 1.
* `apple,firmware-version` — optional, up to four cells.

Each enabled OPP child must carry `opp-hz` (64-bit), `opp-microvolt` (one cell
per cluster, so one cell on t8103) and `opp-microwatt`. A child with
`status = "disabled"` is skipped.

**The first entry is the off state.** m1n1 emits `opp00` enabled with
`opp-hz = 0` and `opp-microwatt = 0`, because `calc_power_t8103()` computes zero
power for state 0. It is loaded and published to firmware as a zero-frequency,
zero-power state rather than filtered out: `perf_state_base`, `num_pstates` and
`max_pstate` are all indices into this table, so dropping the entry would
renumber every state above it. `hw.apply_opp_table()` accepts an off state only
at index 0 and only with zero power, and holds every active state to strict
validation — increasing frequency, at least 1000 µW, one voltage per cluster.
`tests/agx-t8103-opp/run.sh` pins this against the stock seven-entry table.

### GPU node — power controller

`load_t8103_power_controller_config()` requires all of:

`apple,core-leak-coef`, `apple,sram-leak-coef` (one cell per cluster),
`apple,avg-power-filter-tc-ms`, `apple,avg-power-ki-only`, `apple,avg-power-kp`,
`apple,avg-power-min-duty-cycle`, `apple,avg-power-target-filter-tc`,
`apple,fast-die0-integral-gain`, `apple,fast-die0-proportional-gain`,
`apple,perf-filter-drop-threshold`, `apple,perf-filter-time-constant`,
`apple,perf-filter-time-constant2`, `apple,perf-integral-gain2`,
`apple,perf-integral-min-clamp`, `apple,perf-proportional-gain2`,
`apple,perf-tgt-utilization`, `apple,ppm-filter-time-constant-ms`,
`apple,ppm-ki`, `apple,ppm-kp`, `apple,pwr-min-duty-cycle`.

`apple,power-zones` is optional but must be a multiple of three cells when
present. The remaining `apple,*` gains, delays and thresholds fall back to the
defaults in `load_t8103_power_controller_config()`.

Every coefficient is carried through as a raw IEEE-754 word and is rejected if
it is not finite. The kernel never executes a floating-point instruction to
build InitData.

## Native Apple DeviceTree

`tools/agx-re/recover_t8103_adt.py` reads a base-M1 Apple DeviceTree and Apple's
own `AGXG13G` and reports what the native path is actually short of. Both are
staged under `/System/Volumes/Preboot/*/restore-staged` on **any** Apple Silicon
Mac — a macOS install keeps one kernel collection and one DeviceTree per
supported board for restore — so none of this needs an M1 to reproduce:

```sh
make -C tools/agx-re recover-t8103-adt
```

Apple publishes the GPU control loop as little-endian `gpu-*` DeviceTree
scalars. m1n1 republishes the identical set as big-endian `apple,*` FDT cells,
and the names differ by that prefix and nothing else. So
`load_t8103_power_controller_config()` reads either spelling through one
implementation, and **22 of the 26 inputs it requires are already in a native
tree**, including the whole PID/filter coefficient set and the power zone.

Four are not there, at any spelling:

| Missing input | Where Apple gets it |
| --- | --- |
| per-state power | Nowhere. `perf-states` is `{frequency_hz, voltage_mV}` pairs with no power column, and `AGXFirmware::setupConfig` reads a *published* maximum — `gpu-device-max-power`, else `gpu-max-power` — with no computed fallback behind it. Neither name is in a base-M1 tree, staged **or live**. G13 firmware refuses a zero `max_power_mw`, so this one blocks the performance table. |
| minimum SRAM voltage | An m1n1 invention. It clamps the ADT core voltages to a floor Apple's boot data never states. |
| core and SRAM leakage coefficients | Fused, not published. `AGXAcceleratorG13G_B0::calculateGPULeakage` reads one 64-bit word from the fuse aperture, shifts it, masks it, adds one and scales it by a driver-held `f32`. HwDataA wants the two resulting coefficients at `0x3cf4` and `0x3d14`. |

### Confirmed against a live M1

A staged DeviceTree is only a template: its `perf-states` is zero-filled and
`perf-state-count` is 0, because iBoot writes the fused table in at boot. So the
above was re-run against a real MacBookAir10,1 (j313ap, t8103) on macOS 26.3.1:

```sh
# on the M1
ioreg -rw0 -p IODeviceTree -n sgx -d1 -a > sgx.plist
# here
./recover_t8103_adt.py --live-sgx sgx.plist
```

A live tree has 68 sgx properties against the template's 53, and it supplies
**values, not new inputs** — the same four are still missing. In particular
neither `gpu-max-power` nor `gpu-device-max-power` appears on real hardware, so
the missing per-state power is not an artefact of reading a template.

The fused table it does supply, seven states with the off state first and one
voltage column, `gpu-perf-base-pstate` 1:

| state | MHz | mV |
| ---: | ---: | ---: |
| 0 | 0 (off) | 400 |
| 1 | 396 | 618 |
| 2 | 528 | 650 |
| 3 | 720 | 687 |
| 4 | 924 | 778 |
| 5 | 1128 | 868 |
| 6 | 1278 | 928 |

`tests/agx-t8103-opp/` uses this ladder. Its power column still cannot come from
hardware, and is m1n1-shaped.

The same machine also confirms the static configuration in `hw/t8103.v` and the
runtime identity path. Its `AGXAccelerator` publishes `gpu_gen` 13, `gpu_var`
`G`, `num_cores` 8, `num_frags` 8, `num_gps` 4, `num_mgpus` 1 — matching
`t8103_config()` field for field — with `gpu-core-count` 7 and
`core_mask_list` `[0xfe]`. That is the fused-off seven-core Air the identity
decoder exists to handle, so `apply_g13_identity()` should see
`total_active_cores` 7 against a `core_masks[0]` of `0xfe` there.

### What the M1 Air actually boots

The native path above is not the one this machine takes, which a boot with
`vinix.apple_gpu=1` settled. The M1 Air starts through its existing m1n1/U-Boot
chain and Limine is handed **m1n1's FDT**, so `find_gpu_node()` matches
`apple,agx-g13g` and the m1n1 branch runs. Observed:

```
kmain_thread: init GPU driver...
agx: Probing Apple GPU
agx: loaded 7 t8103 operating points (1 off, 396..1278 MHz, 19488 mW max)
agx: loaded t8103 power controller (1 zone, 8 ms period)
agx: detected chip 0x8103, up to 8 cores
agx: t8103 apple,firmware-compat 13.5.0
agx: only the G13 12.3.0 firmware ABI is being implemented
kmain_thread: GPU driver done
```

Everything before the last two lines is bring-up working on hardware:

* **The operating-point table loads, off state and all.** Seven states with one
  off over 396..1278 MHz is the fused ladder above, arriving through m1n1's
  OPP-v2 translation. Before the off-state fix this table was rejected outright.
* **The power controller loads** — one zone, 8 ms sample period — so m1n1
  supplies all four inputs the native Apple DeviceTree lacks. The 19488 mW
  maximum is `opp-microwatt`, which m1n1 computes itself. **The native-ADT gap
  is not on this machine's critical path**; it matters for booting an M1 without
  m1n1, not for the bring-up in progress.
* **All thirteen G13 ABI self-checks pass.** They print only on failure, and the
  fragment command layout that failed the previous boot was the last one wrong.

### The firmware ABI is the live blocker

`apple,firmware-compat 13.5.0`. This machine's installed GPU firmware speaks the
**13.5** ABI; `gpu/agx/fw` implements **12.3** and nothing else — its HwDataB is
explicitly the pre-13.0b4 layout. The probe refuses and touches no power domain
or ASC register, which is correct: the structures it would publish describe a
different firmware.

Note the spelling. An M1 Air carries `apple,firmware-compat` and no
`apple,firmware-abi` at all, so the fallback name is the one that turns up on
hardware.

The tuple is not m1n1 guessing. That machine's Asahi install pinned its firmware
bundle at install time, and it records which:

```
$ cat "/Volumes/EFI - FEDOR/asahi/SystemVersion.plist"
        ProductVersion          13.5
        ProductBuildVersion     22G74
```

So the GPU firmware is macOS 13.5's, which is also the ABI Asahi's own driver
targets for G13. Reaching a first accepted command on this machine means meeting
13.5 somewhere.

There are two honest ways past this, and only two:

1. **Boot firmware that speaks 12.3.** The tuple is not a setting — it reports
   what m1n1 found installed — so this means installing a 12.3-era AGX firmware
   bundle on the machine. It matches what this tree already implements and is
   the shortest route to a first accepted command.
2. **Implement the 13.5 ABI.** The 12.3 structures here are complete and
   byte-validated; 13.0b4 moved HwDataB and the InitData graph, so this is a
   real port, not a version bump.

Editing the accepted tuple is not a third option. It would publish 12.3
structures to firmware expecting 13.5 — the exact failure the check exists to
prevent, moved from a refusal at boot to undefined behaviour after power-up.

One more thing worth knowing before trying to finish it:

* `AGXAccelerator::applyLeakageEquation` is a double-precision, `pow()`-based
  *thermal* model. It is not the per-pstate table, and it could not be used in
  this kernel anyway — the AArch64 build is `-mgeneral-regs-only`, which is why
  every coefficient here is carried as a raw IEEE-754 word.

So the remaining work is reproducing a fuse read and finding a source for a
maximum power, not reconstructing a power model.

## Acceptance sequence

A `/dev/dri` node and an "initialized" log line are not evidence that the GPU
executed anything. In order:

1. **Boot evidence.** Record chip identity, the ABI tuple the driver printed,
   the loaded operating points (`agx: loaded 7 t8103 operating points (1 off,
   396..1278 MHz, ... mW max)`) and the fused topology line. Confirm the render
   node appears.
2. **Compute.** Submit one small compute job that writes a known pattern, wait
   on a firmware-backed fence, and read the result back from the CPU.
3. **Render.** Render an offscreen clear and a triangle, then compare pixels.
   Do not make display-controller takeover a prerequisite: `kernel/main_arm64.v`
   has independent GPU and DCP switches, so keep the inherited framebuffer and
   read back offscreen.
4. **Lifecycle.** Repeat across allocate/free, mapping reuse, process exit and
   several contexts. Check for leaked objects, stale mappings and stuck fences.

## Known unproven

* No step of the sequence above has been run on hardware from this tree.
* The native Apple DeviceTree path is still gated; see above for the four
  inputs it is short of.
* The 12.3.0 gate checks the device tree's claim, not the firmware image.
* Userspace is a separate acceptance criterion. The submission interface is
  pinned to a particular Mesa-era UAPI (`drm_ioctl.validate_asahi_25_layouts()`),
  and whether userspace selects the native driver and emits commands and shaders
  this kernel accepts is not covered here.
