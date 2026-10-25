# View tooltip state and constructor attributes

The API-26 regression fixture passed against framework282 and the unchanged
qualified276 native library. Baseline278 failed with the expected
`View.getTooltipText()` `NoSuchMethodError`. Both sides used the same signed
APK; the framework JAR was the only staged runtime difference.

Framework282 printed `BOOTSTRAP-TOOLTIP-STATE-PASS`,
`BOOTSTRAP-TOOLTIP-INFLATION-PASS` and `BOOTSTRAP-READY` once, in order. The
assertions cover mutable `CharSequence` identity, independent view state,
replacement and null/empty clearing, whitespace, content-description
separation and inherited access during virtual button text dispatch. Compiled
XML/style/theme constructor tests cover literal/resource text, absent and
explicit empty attributes, default styles and exactly one virtual setter call
for each present XML case. Tooltip popup rendering is outside this change.

The fixture corrects the [failed280 setup](tooltip280.md): its minimum SDK is
26, and both `SDK_INT >= 26` and `RESOURCES_SDK_INT >= 26` assertions precede
the unchanged XML/style checks. The production tooltip implementation is
unchanged from attempt280.

Both suite wrappers completed naturally with exit zero. At the end of the fixed
fixture's 30-second observation, backend readiness was true, process exit was
false and QEMU was alive before capture. The raw outcome remains
`startup_failed` with `functional_passed: null`, retaining the two existing
`Lnge`/`nge` diagnostics. These targeted assertion results do not relabel the
suite outcome or establish a subsequent Maps run.

| Artifact | SHA-256 |
| --- | --- |
| Baseline278 framework JAR | `a1b839c77a575a40ddab8d6e264e92c9abcc9de54ae6c3dcefcc0e725c938eba` |
| Fixed282 framework JAR | `92b069b1dbb31b08960d00d4f33f84b068a3adf53af9339f2ef3c1a6478f0618` |
| Shared signed API-26 fixture APK | `bad3243070013ecf31f1d13e01fac24ebbd358537a1b1927e7fc761765151833` |
| Shared qualified276 native library | `5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca` |
| Fixture source | `6e0c042e40e68d0594ecfc2a6c6edf5d9868323e3d4eb79722283568c1b4a4dd` |
| Completed282 external prelaunch inventory | `2d9a307a57f3ffd5f07170a61cb6fb42361cc65ab260e78c158be2c9b05edefc` |
| Baseline raw results | `07ae260850b607dd74027a52421c7590646ed7aa24ee8ba7f7bc3e2ae9214673` |
| Fixed raw results | `59df0a6e98a057df8b0cde50c48a7edfef99d8364eea1a41e9c5bd2c57bb016b` |
| Complete retained inventory | `d966016994e234c6f4d8b2bf4a39fc041be60023fc7f61a1cf653fedeaf857d4` |

Production and fixture source is committed in `1ed005eb5`; build tooling is
committed in `bb8e18b13`. Six actual compiler, assembly and
self-test receipt triplets have exit zero. The retained closure has 127
framework and 83 native source files; the framework delta from completed278 is
only the tooltip helper and its registration. Completed278 provenance and the
qualified276 native reference are retained separately from this pair's runtime
qualification.

The complete audit bundle is retained at
`/Users/alex/.local/state/vinix/android/compound282-2026-10-25`.
The positive semantic seal and independent complete check passed with exit
zero; a wrong inventory pin was rejected with exit one. The sibling
`compound282-check.log` has SHA-256
`5575f092b6896899e2b944eaa703c199218e7fa3286c616e9cd74e68e2b2c4ce`;
`compound282-wrong-pin.log` has SHA-256
`aebb5a55d7e2324cc95c210df0ca6c41e8585a64183b22bc06e0c8135328d0af`.

From the repository checkout, reproduce the complete check with the retained
assertion-enabled checker:

```sh
/Users/alex/.local/state/vinix/android/compound282-2026-10-25/checker/tooltip-evidence check \
  /Users/alex/.local/state/vinix/android/compound282-2026-10-25 \
  d966016994e234c6f4d8b2bf4a39fc041be60023fc7f61a1cf653fedeaf857d4
```
