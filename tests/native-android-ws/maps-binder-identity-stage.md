# Maps Binder identity stage checkpoint

Validated source checkpoint over base revision `938078b43a6f9514cdcbbf607e87dd8c991bfac7`;
the exact changed source snapshots and executable hashes are retained in
`/Users/alex/.local/state/vinix/android/maps-binder-identity-stage-build-2026-10-29-r1/completed-tool-inputs.sha256`.
The runtime fix is commit `40724ff01`; this checkpoint adds its strict image and kernel-install profiles.

The image contract preserves all 24 inherited modules and adds one overlay with
seven files: framework JAR/DEX, native DSO, three framework/headless receipts, and
the Maps deployment receipt. It requires exactly 50 complete dependency seals.
Only the headless JAR role changes; historical native and launch roles remain pinned.

The audit preserves all 88 native origins and permits only the service source,
two binding lines, two generated JNI exports, one broker provider helper, and one
native-consumed framework class to change. It compares every retained JNI ABI/body
and export order, normalizing only generated binding ordinals. All 2,104 canonical
DEX classes remain present; only Binder and its broker context change.

Both tools compiled and all self-tests passed. The completed native/framework audit
also passed. Original per-check limits were 600 MiB aggregate RSS, 300 seconds,
512 MiB observed shared-volume growth, and 1 GiB reserve. Final stager compile used
517,586,944 B sampled RSS; patcher compile used 587,677,696 B. Both recorded zero swaps.

The initial raw-smali class comparison rejected a source-versus-disassembly
representation difference. Its failed audit and initial sources are preserved.
The corrected check compares the complete canonical post-DEX inventories and trees,
with separately pinned raw Binder/context inputs and native-consumed classes.
Independent review passed before and after this correction.

One preparation attempt retained the original 600 MiB/900-second/4 GiB growth plus
1 GiB reserve guard and 8 GiB shell file-size limit. It refused at preflight with
`disk growth budget`: 2,998,128,640 B free, PID 0, child status -1, exit 125.
No image or VM was created. There was no retry or lower budget.

Evidence is closed at
`/Users/alex/.local/state/vinix/android/maps-binder-identity-stage-sealed-2026-10-29-r1/sealed/manifest.json`:
`bb5e79b97fc06adddc0191fa2c7e6dcf32453e88b29010645333a024a1edccf9`.
Seal and independent fresh-process full readback passed: one root, 561 entries,
under unchanged 600 MiB/900-second/64 MiB growth/1 GiB reserve limits.

Final tools live under the build root above:

- `tools/maps-binder-identity-stage-r2`: `c50fd399f619cbbce4d49a60fa2e3bc3c340c5006168d9a42ecc894767e09950`
- `tools/patch-kernel`: `036b0118f3a5064874560917c0bd816176be48d4fc89dee774533d3eb360eece`

The producer CLI is `maps-binder-identity-stage-r2 --prepare FRESH_EXTERNAL_OUTPUT`.
After a sealed image is prepared and cloned, the installer CLI is
`patch-kernel --maps-binder-identity FRESH_VERIFIED_CLONE FROZEN_KERNEL_BUILD BUILD_JSON_SHA256`.
Image preparation, ARM execution, Maps sign-in, and successful authentication remain unverified.
