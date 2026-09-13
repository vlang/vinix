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

`gpu,t8103` selects the native Apple DeviceTree path instead. That path is
**not** supported: it carries no OPP-v2 table and no ABI tuple, and both
`report_native_t8103_opp_gap()` and `validate_g13_firmware_compat()` refuse it
before any power domain or ASC register is touched. Anyone completing it has to
supply the ABI tuple as well as the performance data — the firmware check is not
optional just because a later gate happens to also stop the boot.

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
* The 12.3.0 gate checks the device tree's claim, not the firmware image.
* Userspace is a separate acceptance criterion. The submission interface is
  pinned to a particular Mesa-era UAPI (`drm_ioctl.validate_asahi_25_layouts()`),
  and whether userspace selects the native driver and emits commands and shaders
  this kernel accepts is not covered here.
