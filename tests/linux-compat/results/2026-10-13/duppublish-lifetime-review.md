Independent duppublish lifetime review: PASS

Reviewed the sole production kernel change in `kernel/file/file.v`, the maintained private instrumenter, final probe/reference wrapper sources, all eight before/after production/QA kernel builds, emitted C, and completed native/QA/Linux captures. This independent review changed only this report and found no remaining lifetime or lock-order concern in the fix. Artifacts are in `/Users/alex/.cache/vinix-linux-compat/duppublish-20261013`; the recorded baseline is `d1cf55595f1d395344a9cb5099984b95cb5f8daf`.

`fdnum_dup` finishes both the descriptor flag mask and optional CLOEXEC assignment while it owns `new_fd`, before `fdnum_create_from_fd` inserts that object under the table lock. Successful publication is followed only by scalar result handling and release of the separately retained source FD/Handle; there is no successful post-publication dereference of `new_fd`. Reservation/publication failure retains the existing paired cleanup: source lookup releases through defer, failed insertion releases the untransferred duplicate and its Handle reference. The source hold remains alive across insertion and the private scheduling window. No allocation, free, reference-count operation or lock was added or removed.

Complete production before/after C diffs contain only the four moved flag lines in `fdnum_dup`. The corresponding QA diffs contain that move and unused-loop symbol offsets. Private QA copies alone add 32 reschedules after insertion when the returned scalar descriptor number is 63; that window borrows no new descriptor pointer. Production/QA C comparison on x86-64 additionally relocates one contiguous, byte-identical block of 48 `mmap__` literal macro definitions. Their definitions and surrounding constants are unchanged, with no conditional/executable change or intervening use of those macros. The block hash is `3fc719ce492013f61dbb05e84c9d12757860806d3e76ab1e14f24105f59d376a`. Removing that exact block from both sides and restoring only `fdnum_dup` preserves the remaining whole-C comparison. AArch64 has no macro relocation.

Each producer borrows an explicit alloca `State` until pthread join. Release/acquire go/done/ack operations order the closing producer's ordinary `ret` write and the consumer's read; the next go value is not published until sentinel checks finish. Producer-only counters are read after joining. Every successful worker creation reaches a join before returning or freeing stack storage; join error exits the whole child instead of returning with a live worker. Fork children use synchronous flag checks and `_exit`; parent controls wait for them, and any fork/wait/status failure prevents PASS. Each C stat buffer is explicit stack storage borrowed by synchronous fstat, whose existing paired descriptor lookup copies metadata before releasing the resource hold. Temporary aliases, sentinel descriptors and the observer close on their successful paths; returning setup failures release acquired descriptors. Successful parent processes intentionally pause with stable source/seed descriptors until guest termination.

The completed-producer branch now takes a fresh fstat after acquire(done), while the producer waits for the next go value, so an earlier seed sample cannot produce a false failure. Only definitive 16-fork/600-second probe captures are approved here: `qualified-after-*`, `qualified-yield-before-*`, `qualified-yield-after-*` and `verified-reference-*`. Earlier stale-sample and timeout runs remain diagnostic artifacts. Both reconstructed pinned previews match the tested generated C and native ELF exactly; all six explicit allocas remain stack allocations, with no memdup, heap promotion or dynamic-array allocation sites. The reference wrapper borrows a three-pointer stack argv through synchronous execv. Both actual Linux 6.12.51 boots use the byte-identical native probe ELF with `--reference` and skip Vinix allocator accounting; their final receipts bind the tightened maintained reference parser.

Each production, QA and Linux-reference run passes six 128-call visibility phases and 16 successful fork checks per phase for both root and UID/GID 1000 with supplementary groups cleared: 1536 publication calls and 192 fork checks per architecture/run. Source descriptor flags oppose the requested result. All candidate/reference visibility, post-return, producer and fork controls pass. Both QA baselines reproduce wrong flag observations in all 12 phases and fork-control failures in both credential groups; post-return/producer controls pass, and the baseline deliberately skips close/reuse after visibility failure.

Close/reuse runs 200 rounds per credential, checking the duplicate return plus sentinel inode/mode/size, cursor and CLOEXEC flag after closing 63 and creating 64. The table records acquire-load observations of an unfinished producer immediately before close; these are observed timing counts, not a synchronized proof that close itself preceded syscall return. All close/sentinel checks pass. Source/seed bytes, cursors and parent descriptor flags remain exact.

| Architecture/profile | UID 1000 unfinished observations | Root unfinished observations | Sequential retention per credential |
| --- | ---: | ---: | --- |
| AArch64 production | 0/200 | 0/200 | 18 flat slab classes; 63/63 large pages |
| AArch64 QA | 200/200 | 200/200 | 18 flat slab classes; 63/63 large pages |
| x86-64 production | 8/200 | 5/200 | 14 flat slab classes; 160/160 large pages |
| x86-64 QA | 175/200 | 148/200 | 14 flat slab classes; 160/160 large pages |
| Linux AArch64 reference | 8/200 | 4/200 | Not measured |
| Linux x86-64 reference | 0/200 | 2/200 | Not measured |

The retention snapshots bracket 200 sequential duplication cycles after 32 warmup cycles and settling, using the same observer descriptor 80. They qualify this measured operation set after the concurrent phases, not whole-concurrency retention. Both production four-case aggregate logs and complete receipts pass `duppublish`, `dupabi`, `open` and `runtime`; both candidate QA aggregates pass, and both complete QA baselines fail as expected. Actual exec inheritance, concurrent F_SETFD/source-close behavior, atomic whole-table fork snapshots, descriptor-limit pressure, GNU wrappers and translated/ELF32 paths remain separate qualifications.

SHA-256 pins use repository-relative source paths and artifact-directory-relative build/capture paths. Shared rows were independently compared as identical. Probe reconstruction used `/Users/alex/code/v/v`, V 0.5.2 c020355, with compiler hash `0640ac69f682e4132215ff08f286f391150b070fe35ef7f14ad1251959755926`; its manifest pins the compiler, generator and build inputs.

| File | SHA-256 |
| --- | --- |
| `kernel/file/file.v` | `e05b64e8f3e5f1a6145baa27900f5796491544c0152ebc8c72768e126dbf23c2` |
| `tests/linux-compat/duppublishfixture/core.v` | `6fe0fcdeff9ae86605da0fda0738bf588ee9b32a17a27bf2bcdd579b12b4f13e` |
| `tests/linux-compat/duppublish-instrument.v` | `92fa5b34456f713026e0a8d5c844557d0ecee41e3fea4a6e7e94f229a50c5704` |
| `tests/linux-compat/duppublishreferenceinit/core.v` | `5e611560618a92b9851515ae10c29ce3cd0132e8d7d1ce0173662e56da2b396b` |
| `tests/linux-compat/duppublish-reference.v` | `97e967e9103ce33a3c95826f7ff5407e39f326d6b52f94037139dd669da962d7` |
| `baseline-file.v` | `2f617b59bd296d4d5e47a2e5959cf370c2c5866e8409b6135d0a2322af647bb7` |
| `yield-before-file.v` | `d12acacb40534a113cf5a19bc59f71e7b6766c52aef4fbed54d3f64a5f87e2df` |
| `yield-after-file.v` | `3e5b5f86616d53bdf712a24af459f1c7511e8ad3c1ec54db70fff6022ae7ac4b` |
| `before-kernel-arm.c` | `822a0efc824dc537d55a4cf15be8ffa7a0d33716a1efdd6483601588aab3d821` |
| `before-kernel-x86.c` | `a767de3cd734f847d0473dd2db76358f4d499678367bba171b94a78d53558b3f` |
| `before-yield-arm.c` | `34f3ed1641c8dee3acd6ee9cd98e5f329dfeea69acac399d5c901aecc5fda413` |
| `before-yield-x86.c` | `55f09cbd40c8a455098e1c653c662ea57b7e3bc0de0eb260f831bc8ec78090be` |
| `kernel-arm/kernel/obj/blob.c` | `7d6bf90617ae3b955c1e16a8a73f8709df9b52a9772f95013e8f20909ac2bcd3` |
| `kernel-x86/kernel/obj/blob.c` | `a9ea5aa549b835d1a0feba747f8cc9104103dfe073708d5b7dbaf151c4f8cb49` |
| `yield-arm/kernel/obj/blob.c` | `2525c2769c3f7b46af7e8d05195ed22f82bfa7577d34ed7ecd3828528a69ef67` |
| `yield-x86/kernel/obj/blob.c` | `26b9e43f44fffabb74236c52fc1ba3dcd0c3e260a2f8c05e0dddb66eea7e7ec4` |
| `before-kernel-arm.kernel` | `1e31d99ca35ba563fc78f6fa2df3f4a7d3cdf572598da66d1ba9049fb38d2015` |
| `before-kernel-x86.kernel` | `9f4cad5435bc8a970d39603ce0b54ca9d6b8b0102ea5f1d475d9ddbda8286f96` |
| `before-yield-arm.kernel` | `197f050d52ffb83a1b5144ee5c895825c1452d5e63a2e26a59c82a6cb17a56c2` |
| `before-yield-x86.kernel` | `5dd8982d79da6479bc8ebde507ab6c98f5399af137154e2bac4bc9ec05642efa` |
| `kernel-arm/kernel/bin/vinix` | `1f1f25287f7306187445a391b2a4deed1155a5a52de59792a03cae148696e63f` |
| `kernel-x86/kernel/bin/vinix` | `82dd05c98a004bc143e532ec850f716cd87e60f3a1da8d7eef8f567de98e1334` |
| `yield-arm/kernel/bin/vinix` | `9dc0c4074eb99ad309f78c1a2bdeb1f7cb98fae3741818ea0c6f360d6adef292` |
| `yield-x86/kernel/bin/vinix` | `5978f7965fa006ae616f38a3b1789e270fa802e29522379512b492364413a760` |
| `pinned-preview-arm.c`, `pinned-preview-x86.c`, all qualified native/QA `duppublish/fixture.c` files | `2c8652632ca046d2ba488141497dd2e3dfb8f42336fadda40f4fdb4ffe4c3815` |
| `verified-reference-arm/fixture.c`, `verified-reference-x86/fixture.c` | `78da9a83b39a86e28ed371f97ff05604d53a0b0371f64913ee3a86fc2544d856` |
| Qualified ARM native/QA `duppublish/init`, `verified-reference-arm/probe` | `464dc71b48a4de8abaa0acdd607db05c05e5e9836e1917deb0e7239bddaf780a` |
| Qualified x86 native/QA `duppublish/init`, `verified-reference-x86/probe` | `a72e4bc1673354d7979b9c6da5a7e13aac19874b1fc99b7dcc6d83edb96f251a` |
| `verified-reference-arm/init` | `6e84da85a0a845349344cdee03e499cee0a9c5a57ac04d5e7c2e57b74c877a51` |
| `verified-reference-x86/init` | `a899807f93d96e5e9a5c8f44ae371515649d8d8352fc47367a6ae5e01f627d8a` |
| `qualified-after-arm/duppublish/serial.log` | `2379c26db87fab1531102a74093c1ade3a0c6239150ed95da72b543290077dbd` |
| `qualified-after-x86/duppublish/serial.log` | `33e4bff8f5f50febf5ec8acbdda0e866c9aa030ea4dfac30c6af1721c65e002a` |
| `qualified-yield-after-arm/duppublish/serial.log` | `9fb476f919cad7226d23a1e2c8c6a5147248081275bc045604445207519ea050` |
| `qualified-yield-after-x86/duppublish/serial.log` | `9c3327b8a854c5996081c681f1816575442a59931a4c08273505bde07043b2e1` |
| `qualified-yield-before-arm/duppublish/serial.log` | `86adcfda5bc81f8b3ea51cd7a68b1ba82724f5f01b74124ca52480c0c0b069d5` |
| `qualified-yield-before-x86/duppublish/serial.log` | `258822a3d022ba25ee7327652d091f1144d60f2aa124f04a7db8cc476ce7b769` |
| `verified-reference-arm/serial.log` | `7fea82903fb863b0b10477bde3d035112b4224b7420e382e6dc9e317e02c9c11` |
| `verified-reference-x86/serial.log` | `542c6e28444bae3a3e8691d0c30bdb4bf9f22e5049653c391a13e10bdc09a035` |
| `qualified-after-arm.log` | `cb69134f7d9e70da21de19116e656b57dc0573a724c05f3d1e71f76192117be0` |
| `qualified-after-x86.log` | `fcd0060c5ce3169a15a801fb11a78954db85bcd159bef865ecfd684580292ab5` |
| `qualified-yield-after-arm.log` | `2a765230197b5e11bda4e52a207301a1ba60d1d98eee00546eed74e7e8c7b364` |
| `qualified-yield-after-x86.log` | `e95f270b8c5a383889c06ebe6a08021ecaebc5426d5bd45a50c86c8758d23567` |
| `qualified-yield-before-arm.log` | `47f917cea26695cb6d2f8a66c262d4658604e9430c3263eb3d2439ca536309ff` |
| `qualified-yield-before-x86.log` | `7f7ece55ee22d567e4f7b1015ef773424664643c9ed5b9ff3cbf62b2b752b4a6` |
| `verified-reference-arm.log` | `8fa95d61ada2ed6411bba81c8b4ea04f63a0d60eabcb501c37b76f189ecbe4f1` |
| `verified-reference-x86.log` | `c694bdd2e5422b34351631078c7cd9fb9d44c1bf299dd4a38d4885a190065572` |
| `qualified-after-arm/receipt.json` | `2bedacd1ed545812d7542ab97f9a088cbe73cc96c3704aa64ff33aae06d83b20` |
| `qualified-after-x86/receipt.json` | `713e6f756fd745cdfc874d1f0fa83fada8de9b8011657ae024d2ce8dd2ecc8ab` |
| `qualified-yield-after-arm/receipt.json` | `715084ccd16deb3b37301999ba56b2460be4e255664f31bbbaabddba1663db74` |
| `qualified-yield-after-x86/receipt.json` | `77ca4f9fa004f68c7a3b001bcb04296e9bcf29482da1213e83d8df94fd3357f2` |
| `qualified-yield-before-arm/receipt.json` | `1887854f18dc255aa6d1cb42a8458fb7670d2ad873eb1f41567ddc4517acea71` |
| `qualified-yield-before-x86/receipt.json` | `98d27e2d4ad3465039b2691ac42c5bf2a29ce0a26b00ebea2e3d4fb8a59ed297` |
| `verified-reference-arm/receipt.json` | `db63d689e349652fdc44da80a2e490af8c39cc730e006e6f17c1df8a162f1dd3` |
| `verified-reference-x86/receipt.json` | `f257034f64772e1f32042e44c39bfdeb1a4d27b19d29a9cc20cf1342611e8469` |
| `probe-compiler.json` | `65716ffdbee59b2cc564e03afb5036a34322f7f6eb90b3a33078d852e1611ff5` |
| `qualified-probe-rebuild.log` | `d849d5d6dd0a9ab43bb28cef6da4f228c3c6a57a3143e6ee8913b2f778bb681c` |
| `rebuild-probe.v` | `2542cd1b3fa91fab8f0ca9c9e4864b75dda39c29b79ed2c1a90085773978851d` |
