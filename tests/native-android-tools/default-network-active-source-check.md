# Default network activity hint focused qualification

`ConnectivityManager.isDefaultNetworkActive()Z` is a public instance query that
returns true under Vinix's current unmonitored network-activity policy.
[Android's API contract](https://developer.android.com/reference/android/net/ConnectivityManager#isDefaultNetworkActive())
describes a traffic-batching/power hint. The
[Android 9 service](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-9.0.0_r1/services/core/java/com/android/server/NetworkManagementService.java)
considers activity active when no idle timers monitor it. Vinix has no such
monitor; this method does not query or claim link availability, a default route,
current traffic, Internet validation or a measured radio power state.

The adapter appends one method while retaining every predecessor byte, all 28
old methods, four fields and both native declarations. Ordinary SDK generation
calls it immediately after `framework_connectivity`; removing that one new
call restores the exact predecessor `framework_classes.v` SHA-256
`41058a6edb1dbf080b5839e6a10db9353b47e4fa9d55774af2d7bba9fb7f9a83`.
The final source base is `156c7497640dbf2015fae375ae12dccf64683956` plus this
change. The provider accepts the ordinary writer's exact decimal field values
and the equivalent canonical DEX hex spellings without rewriting either input.

On November 5 the focused checker passed against the exact Global string SDK,
manifest `cadfaa0105eb24580f1cdcef590f707e52aab334e9d7bf164524a403f1b43cbc`,
JAR `9207dab7a6a37e09fb049bb636ba6ebad3e63e43bfe7fd95821f67fc2aebeeb7`.
The final r4 pass covers 40 input refusals, 40 directory-adapter atomic refusals,
28 independent semantic/preservation controls and 11 formatting positives. The actual
private directory adapter is called through an isolated test bridge; rejected
input remains unchanged. Native-query calls, altered API flags/results and
old method/field/native-declaration mutations are rejected by the oracle.

The checker also runs the pinned real `framework_connectivity` writer and its
real method-replacement helper, then applies the directory adapter to that
writer's decimal-field output. Only ConnectivityManager from this generation
enters its DEX checks; the retained NetworkInfo seed supplies the unrelated
writer input. This focused control does not execute a complete ordinary SDK
pipeline.

Baseline and patched API-28 DEX assembly/disassembly passed for both the exact
SDK predecessor and the actual writer's output. Both patched reassemblies have
stable second disassemblies. The predecessor SDK class is
`1fd6af85766920db5576fec29ced1331db5b20d914a8909819299116e9c30ec3`,
and the patched canonical class is
`a6a2b21fa2bfae7788d0690d47a746eea3f33a51c109b5c544d5eeead930236a`.
ConnectivityManager is one of the 70 native-consumed classes. This focused pass
does not qualify a full SDK/native pair or establish an ARM, GMS or Maps result.

Final source SHA-256 values:

| Source | SHA-256 |
| --- | --- |
| `framework_default_network_active.v` | `fc459a6cba2efacf8183de5945e9d12ea741d2deccc745da97d72a2cfd9bf51e` |
| `framework_classes.v` | `23b8cd3a0f0f1b45909be0000c532691bd9ce8243d06495691dd66ee1b1fcbf7` |
| `default-network-active-source-check.v` | `f866dbc87f87a7274a98c3335dbb2157cb1703c21a27889198bbb2bc619a02fd` |
| `defaultnetworkactivecheck/main.v` | `87cdb1482c8ad29ea071b5d33e74657af739a6d83ce3e212a3da3597da999905` |

Complete originals are outside Git under
`S=/Users/alex/.local/state/vinix/android`:

- Frozen sources and driver: `default-network-active-source-tools-2026-11-05-r4`.
- Compiler/qualification logs, guards and explicit 16 MiB file-cap records:
  `default-network-active-source-controls-2026-11-05-r4`.
- Compiler inputs, source controls and DEX roundtrips:
  `default-network-active-source-check-2026-11-05-r4`.

`receipt.json` SHA-256 is
`b6643fa9516220f84f8e2c0c54f21526807eca1b493ece960b2d48cb80ff32d2`.
The compile/qualification guard SHA-256 values are
`a0efa538f4012a86ba4d577d2b17fc3894937d2ea0521768a1996a917c1880cb` /
`d9d7baca7a8210a5b54b44751270fed44ef5c598dd020f16ffa3ba0e6eca635f`.
Compiler and qualification both passed guard/child 0/0, empty reasons and
complete cleanup in 11,508/52,343 ms. Sampled RSS was 323,567,616/241,090,560
bytes; observed shared growth was 36,962,304/200,413,184 bytes. Both retained
600 MiB RSS, 300 seconds, 512 MiB growth, 1 GiB reserve, 4 MiB output and the
stricter 16 MiB shell file cap. Preserve all complete bundles and original
SDK/tool inputs. Aggregate sealing/readback is separate.

All earlier attempts remain under the corresponding r1–r3 roots. The r1
canonical-only pass (receipt
`d3e707fdf4aa60ff04550f8d222ceaf24d3cdf0f9ad88ffc66fe560f9922e64d`)
did not expose the initial provider's rejection of decimal field spellings;
the corrected provider and actual-writer control supersede that qualification.
The r2 driver compilation failed on Option propagation in the extraction helper
before any checker execution. The r3 driver compiled, then its new generation
fixture failed because `android/atl` had not been created. R4 corrects that
fixture setup. Every failed guard reports complete cleanup. Retained guard pins:

| Attempt | Guard SHA-256 |
| --- | --- |
| r1 compile | `418c6f1a4eecee8cc4aa965d8a63054d4b08158d1e18985305a4386e666da07d` |
| r1 qualification | `661f0b000f615853cc831da23452fa3700c8d62ba76df15cb42401379f90bb1d` |
| r2 compile | `6af00b329867284b7b57564231b9c8d19a0a9299779f485b86dd8c9bd08a41f1` |
| r3 compile | `927a8e829d73f2a6ae2892410e670befd369feb2bae98a8520576d842e5e20dd` |
| r3 qualification | `c5e07a7b4a5096ea8f19b6874ed4162f4db3426b8933358d3400d3874fb38651` |
