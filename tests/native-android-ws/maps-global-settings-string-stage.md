# Global String-write image tools

The successor overlays the closed `maps-process-packages-r1` parent with the
[qualified Global String-write SDK](global-settings-string-sdk-2026-11-05.md).
Only Global changes among 2,117 canonical classes: one added public static
writer, with every old method and field preserved. The
[retained-native audit](global-settings-string-native-host.md) is required;
the process-package DSO keeps its original producer/SDK coupling, all 70 raw
and canonical consumed classes remain exact, and its sources, JNI, exports,
generated C, headers and helper closures have no current changes.

The payload changes exactly six regular files: JAR, DEX, framework build and
manifest receipts, headless guest inputs and Maps deployment metadata.
Headless inputs change only the JAR; deployment changes five input pins and
its framework-manifest field. Native bytes and their build/manifest receipts
remain inherited. Current receipts describe retained production; historical
production deltas remain in the sealed parent chain.

The stage requires two complete audits of 145 flat dependency inventories in
64+64+17 batches, with separate typed kernel provenance and 56 parent stages.
It retains 147 flat and one typed input inventories. Preparation reads all 62
inherited modules and the frozen kernel, clones the closed parent directly,
then reads all 63 successor modules and the kernel. The original kernel
checkpoint keeps its distinct 59-module lineage. Preparation retains the
5 GiB initial-space requirement, 512 MiB charged-write budget, 1 GiB reserve
and 127 one-MiB digest-receipt charges. No kernel patcher or VM is used by
these host tool checks.

Using `S=/Users/alex/.local/state/vinix/android`, complete tools and controls
are `S/maps-global-settings-string-tools-2026-11-05-r1` and
`S/maps-global-settings-string-controls-2026-11-05-r1`. Production uses
predecessor revision `62b5825d8` plus the exact image-profile and collector
changes committed with this report. Retained source/executable SHA-256:

| Member | SHA-256 |
| --- | --- |
| Stage source | `e7448cb50d5b6e3046a241e984f13ef92d78e693464f43a128dce0e11b42a4eb` |
| Stage executable | `5a4b037c5f8d998ba7aa57bc0f70e6d717ba64ea14497f5ca7ce81c132d04617` |
| Ancestry source | `9ff255e110afae44e733e1df88adf494605a802de686b7fcf7b478f78c35d7a7` |
| Project-input collector source | `65ea43bf34614bce6dc69af0fc99a7a0211cc5f9ed9944cbbf348180f00405ac` |
| Project-input collector executable | `ab86ceb18dc0b743a6feda57032367fd2ffa5ce3bf3ac97acf1335c75541c03a` |

All 17 qualification phases passed with guard/child 0/0, empty reason and
complete cleanup. This includes 72 stage refusal controls, the complete
three-bundle SDK/native audit, unchanged 340/660-input native generator/builder
closures, the complete batch suite through 145 inventories, 56-stage ancestry,
and discovery of 284 V/408 C inputs. Independent metadata review confirmed
each saved guard's result and original limits.

The new V collector enumerates all regular files under the four actual
generated project roots, rejecting links, special files and noncanonical
paths with bounded depth/count/list sizes. It preserves six explicit source
pairs from the repository and frozen tree, the capture source, and its own
source/executable. It parses the four emitted compiler commands and retains
the actual linked archive; the batches command consumes
`/Users/alex/code/v-tccbin-bootstrap-20261026/thirdparty/tcc/lib/libgc.a`,
SHA-256 `82871c4e2ca0054ac0cb558fd982e3fb8f19a8000763835ff4795f96396c50ca`.
Its positive run recorded 24 project files, 15 explicit inputs and one archive.
Lists are sorted absolute names created exclusively, after all three payloads
validate. The complete capture passed with 852 selected inputs, preserving
actual generated projects, V/C closures and the linked archive.

Every phase retained 600 MiB RSS, 512 MiB observed growth, 1 GiB reserve and
4 MiB output. Self-test, full audit, helpers and batch execution used
900 seconds; the other thirteen phases used 300 seconds. Peak sampled RSS
was 333,414,400 bytes during stage generation; largest observed shared growth
was 185,511,936 bytes during capture. Collector compile/run took 2,802/321 ms;
capture took 6,330 ms. The first fourteen phases and both collector phases
used zsh `limit filesize 16m`; capture used `limit filesize 8g` to retain the
compiler and clang inputs. No RSS, growth, reserve or deadline was raised.

The two-root, 18,809-entry aggregate seal is
`S/maps-global-settings-string-tools-sealed-2026-11-05-r1/sealed/manifest.json`,
SHA-256 `b03b88ad2e745105db8639f577b6c00bd59299be38096d63882765449d2e40ab`.
Seal and separate fresh readback passed 0/0, empty reasons and complete cleanup.
Readback took 1,542 ms, sampled RSS 21,741,568 bytes and shared growth
10,850,304 bytes. Both retained 600 MiB RSS, 900 seconds, 64 MiB growth,
1 GiB reserve, 4 MiB output and an 8 GiB shell file cap. Preserve the complete
tools/controls, inventories and original evidence bundles with historical
auditors. These results qualify host tools; preparation and ARM/GMS/Maps
execution remain separate.
