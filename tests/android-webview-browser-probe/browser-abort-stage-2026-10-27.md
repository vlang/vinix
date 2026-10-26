The credential-free abort diagnostic is prepared at
`/Users/alex/.local/state/vinix/android/browser-probe-vm-2026-10-27-r17-abort`.
No VM was launched during preparation. Preserve this immutable prepared root;
use separate mutable launch media for a guest run. This preparation establishes
no Google sign-in result.

The complete historical r13 seal was independently rechecked against
`e441db6a38048b330918e8935f3ee2abde7acd3dc643d1228ea257a297556de2`:
all 29 roots passed. The complete prepared r17 bundle passed its existing
mode/content/literal-symlink inventory, SHA-256
`83c22e2ab3d81a169ca47399f9895bb336bc7bd129f4772c47738b35cb0c99f9`.
The original Maps372 base image and firmware passed their historical pins
before staging. Original full bundles and historical auditors remain required.

The retained old stager uses Boehm, but captures live dependency sources.
Its embedded dependencies predate the current tarstream and modulestream
changes. Reusing it now would misidentify the sources consumed by that tool.
Instead, the unchanged stager entry was rebuilt once with the pinned current
V compiler and `-new-compiler -prod -gc boehm`, after the compiler slot was
released. All three existing stage self-tests passed. The audit bundle keeps
the executable, local dependency sources, compiler identity, exact commands,
timing logs, full prior seal check and r17 inventory check:
`/Users/alex/.local/state/vinix/android/browser-stage-rebuild-2026-10-27-r17-abort`.
It is not a complete historical compiler or macOS SDK source closure.

Staging clones the original 4 GiB media with APFS, adds only the browser
diagnostic overlay and reuses the frozen quiet PID1, authority and recvmsg
fixtures. Overlay contents and original modules are independently read back;
all input hashes and complete bundle entries are compared again afterward.
The same frozen PIDFD kernel as r13 was then installed with the unchanged
default browser patch profile. Kernel readback, all five baseline modules,
the new overlay, Limine and firmware preservation passed. Existing SDK and
kernel builds were reused; production sandbox policy was unchanged.

| Check | Elapsed | Peak RSS | Swaps |
| --- | ---: | ---: | ---: |
| Host stager build | 14.10 s | 388,153,344 B | 0 |
| Stage self-tests | 2.74 s | 30,900,224 B | 0 |
| Full historical r13 seal check | 9.28 s | 26,886,144 B | 0 |
| New media staging | 73.71 s | 31,080,448 B | 0 |
| Frozen kernel replacement | 71.35 s | 22,233,088 B | 0 |

The stager records source revision `15fd6d2eb27cb478e744bd3ed7969050535972bf`;
its entry source is unchanged at SHA-256
`83d47a504414777e4dee2297c39e4e5851ec4ef126640a437ad8e91fb7747227`.

| Artifact | SHA-256 |
| --- | --- |
| Rebuilt host stager | `c9e23faf7c172249847ae3d65f7f37a0346bd8d281a0e4f842c22130a83f817d` |
| Prepared r17 `build.json` | `240b192570ccfe951031979db0cbc4523e5042fbebbfb6175880581949c1108d` |
| Patched `stage.json` | `ad8765db26ccbbd905676d442b292508b5f8eaa2dfdc2061a091f0ef1ec1764b` |
| `kernel-patch.json` | `8eba451e5c47922897ac69833c7d0c318eed153720e10659227bbeb1a84fae24` |
| Patched `boot.img` | `e4d4a644df7b64a2bf93d0692c243b23ec75ba485c7a7d2cfe86d1dd45030759` |
| Browser overlay | `576b97bcd9fe433c85e548a76033c365d66365a436f4410921d23b9c51b10445` |

The immutable prelaunch seal is
`/Users/alex/.local/state/vinix/android/browser-r17-abort-prelaunch-seal-2026-10-27-r1`.
Its 16 complete roots bind 5,195 typed entries, including original and new
media, the prepared browser bundle and manifest, full shared fixture/kernel
roots, tools, source snapshots and prior evidence receipts. Manifest SHA-256:
`3650a056eaa791b22b8ec4ffe919e739e886263841bffc5365f6508e527868a8`.
Creation and its full internal check passed in 33.05 s, peak RSS
27,557,888 B, zero swaps. The independent recheck uses the pinned streaming
sealer from `maps-account-r5-stream-plan-2026-10-27-r1/seal`; its stdout and
timing log are retained beside the new seal, outside its immutable roots.
The independent full check passed all 16 roots and 5,195 entries in 17.87 s,
peak RSS 22,970,368 B, zero swaps.

The separate mutable launch root is
`/Users/alex/.local/state/vinix/android/browser-r17-abort-launch-r1`.
It was restaged from the same audited inputs using the existing host stager,
followed by the same frozen kernel patch. This avoids adding a manifest to
the immutable source or broadening the Maps-only clone helper. Its sibling
`browser-r17-abort-launch-r1-audit` retains commands and timing logs.
Fresh staging passed in 102.47 s, peak RSS 31,358,976 B; kernel installation
and complete module readback passed in 224.41 s, peak RSS 22,364,160 B.
Both recorded zero swaps. The original 16-root prelaunch seal then passed
another full independent check, preserving all 5,195 entries.

| Mutable launch artifact before boot | SHA-256 |
| --- | --- |
| `stage.json` | `49c4063314f0d2f3543765fc1a7f86f30698b6e33b5b02fbf70c48a0294db0a3` |
| `kernel-patch.json` | `622cd8f5b2b230858adf3e09270a4dacf4d520be0fe246360072a00b2858396b` |
| Patched `boot.img` | `4e01cff85bb325fe497c9a8967895c90e10103f261da1c16930e4a9f56b2a04f` |

The overlay and firmware retain their immutable prepared hashes above.

The existing daemon-log runner was checked against its retained source
`c13a45576372481b911e0623dda7b0080438c7c5ba54b668c681459d57b67e12`;
its generic format-1 media contract accepts the browser stage. All 20 files
of its retained closure independently passed manifest
`711c05cc23e68cf81039e37ea0d3d5a92fb52bed8ab083cedaef79cf6153de2f`.
The executable is pinned at
`2419d0760fa92a3e9caa3e60c5596836400616cad8205ca8e6118ade14979908`.
It captures daemon stderr through a private `qemu.log`, retains single-VM
and process ownership guards, and fixes guest memory at 12 GiB with four
vCPUs. Only the parent agent launches the prepared guest.
