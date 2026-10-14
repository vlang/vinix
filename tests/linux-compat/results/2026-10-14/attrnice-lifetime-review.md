Independent attrnice lifetime review: PASS

Reviewed the native sched_attr nice and scheduler-capability change against frozen baseline `4fd5c605d87b05208b73cf725ba93b59699b4f1c`, original/corrected production C, final V fixture/reference/controller/auditor sources, preflight1 C/ELFs and actual native/Linux p1 captures on both architectures. No new lifetime blocker remains. Qualification covers stable single-thread process leaders, nice normalization/admission and observed state; worker-thread nice and identity races remain separate.

Kernel source scope is limited to sched_setattr, may_set_sched_params, new sched_nice_permission and default_rlimits. The default initializer adds only RLIMIT_NICE={0,0} and updates its privilege comment. The existing scheduler permission helper changes only its UID-zero bypass to effective CAP_SYS_NICE. Nice import is clamped to [-20,19], authorization precedes policy mutation, and only OTHER/BATCH subsequently write nice.

Independent whole-C comparisons remove the three changed definitions and new helper/prototype. Source insertion also changes exactly three uses of one local loop identifier inside proc__find_free_id: ARM __discard_174_21692_21693 becomes __discard_174_21821_21822; x86 uses matching __discard_179_... stems. Neither original contains the new name nor corrected contains the old one. The complete find_free_id body matches after that exact rename, and every remaining byte of each whole C file then matches. No allocator, usercopy, task lookup or scheduler mutation implementation changes.

The caller process belongs to the running task. sched_nice_permission validates the numeric TID and keeps target/owner borrows under the PID-table lock, returning only an errno scalar. Generated C has one lock acquisition, four error releases, one success release and V's unreachable final defer release. MAC/owner checks precede scalar target-limit admission; effective CAP_SYS_NICE grants priority increases. After clamping, 20-wanted is bounded to 1..40. No pointer/interface box escapes and no new allocation/free occurs. default_rlimits continues returning a copied fixed 16-element stack array. Permission, policy mutation and nice assignment acquire the lock separately; identity/credential/limit races remain unqualified.

Each final probe has 25 explicit alloca sites, fixed count/snapshot arrays and a real 4096-byte stack slab buffer. Independent C checks find no heap, dynamic-array or fixed-index helpers in the fixture. Attr, Limit, Message and sched_param storage stays live through synchronous syscalls/pipe operations. Unaligned attributes use memcpy/memcmp; input comparisons fit the accessible 56-byte prefix and eight-byte guards. Each Query immediately copies errno. State observations check raw and real musl getpriority, policy/priority and exact sched_getattr output/guards.

Peers close inherited broker endpoints, report readiness and block until released. The privileged parent keeps its stack Message/Counts/sched_param values live while servicing requests, accepts only its child/registered peer PIDs, restores policy/nice and acknowledges completion. Restoration works even on original defective kernels and ordinary credentials. Final Counts are sent/read before buffers expire and the parent waits before reporting. Both peers are released/reaped and mappings unmapped before Fixture storage ends. The reaped control child only closes endpoints and calls _exit after fork.

Capability toggles preserve other bits, check capget after capset and verify the complete caller snapshot on exit. Caller soft nice limits cycle through 0/20/40 with hard 40; same-owner/cross-owner peers use soft 20/40. Default limits 0/0, caller/peer policy/nice restoration and final caller nice/realtime limits 0/0 are checked. Peer limits remain valid until their processes exit. The root broker retains its credentials and limits. Native nice is process-wide while Linux nice is per-thread; all tested targets are actual single-thread leaders.

Counts independently recompute to [3456,6912,3456,831] per cohort, 14655 each and 29310 per architecture. The fair matrix combines six target classes, three caller limits, capability off/on, twelve signed nice values, OTHER/BATCH, four input forms and four PID/flag-word variants. Kind 3 adds 360 IDLE/FIFO/RR controls, 48 legacy permissions, 320 short/read-only layouts, 96 error controls and seven default/final checks. CASES/FINAL rows require exact counts and no duplicates. Original root failures are [1056,2112,1056,435], ordinary failures [1080,2160,1080,387], totaling 9366 per architecture. Corrected kernels and identical-ELF Linux 6.12.51 references have zero failures.

Both native cohorts run 32 warmups and 200 nice/permission/broker cycles with 13-second settling periods. All 18 ARM/14 x86 slab classes stay flat, as do large pages 85/85 and 216/216. The observer remains open through snapshots and closes on nonfatal return paths. Parsing bounds pread/termination to 4096 bytes and caps rows at 32. The allocation scans identify the same 398/290 sites with existing allowance refusals: four proc/proc.v positions shift down two lines. Only those positions are normalized; every other byte matches. Measurements cover retained leaders/broker paths rather than complete creation/exit or scheduler execution.

Independent checks rehash all 15146 compiler inputs, both private 64-input inventories and final native source/ELF/ISO/kernel receipts. Four fresh production builds, eight host files and four inventory passes are bound. Eight distinct cases pass per architecture across separate receipts: ARM combines five completed p1 cases and three p3 cases; x86 combines five p1 cases, two p3 cases and a fresh p4 fcntlabi case. All use identical corrected-kernel/source pins. Preflight1 ELFs equal the original/corrected native and actual Linux probes. Reference receipts bind kernel, probe, wrapper source/C/ELF, initramfs, serial adapter/log, QEMU and controller and require passed/finished/forced=true and status=0. Wrapper argv is one stack allocation valid through execv. Hash files/buffers and host process handles are closed/freed after synchronous use. Cleanup pins reverify retained captures and retire only unbound staging/NVRAM.

Host disk exhaustion stops each p1 profile after five completed cases and prevents its aggregate log from being written; an interrupted watcher has 11 completed entries. All 117 retained partial p1 artifacts/checkpoints are independently rehashed. The p2 retry stops during build preparation without receipts or aggregates; all 30 regular staging/checkpoint files are retained and rehashed, while the nonregular qmp.sock has no file-content pin. P3's x86 fcntlabi ISO build then fails with explicit xorriso "No space left on device" after its source/C/ELF are generated. Its genuine exit-1 receipt and aggregate, empty ISO hash, absent ISO/serial and all 67 retained p3 artifacts/checkpoints remain preparation evidence; its interrupted watcher records 16 completed entries. The final p4 case passes with the same source/C/ELF and corrected kernel. This preparation failure has no descriptor semantic verdict. The completed watcher records 18 native captures, and every retained content hash is rechecked. No nonexistent aggregate or single complete-profile receipt is claimed.

Independent helpers are compiled without -prod. The false assertion and passing ARM Linux capture supplied as an original-failure capture both actually exit 1. Initial strict C-scope refusal of the compiler loop-name change and its bounded difference logs remain private preparation evidence. After proving the exact rename, source/C/lifetime checks pass. The maintained auditor's semantic, scope, diagnostic-line, receipt, compiler, retained-input and publication bindings were inspected separately. Implementation, publishing and committing remain with the parent.

Complete realtime/deadline admission/transitions, reset/utilization clamps, exiting IDLE, UID transitions, worker-thread nice, identity/credential/resource races, namespaces, pledge/MAC combinations, GNU libc, translated/ELF32 and broader roadmap section 15 gates remain separate. This review changes only its owned report.

SHA-256 pins were independently recomputed after producers completed. Paths are relative to `/Users/alex/.cache/vinix-linux-compat/attrnice-20261014`, except repository paths starting with `kernel/` or `tests/` and absolute compiler paths.

| Artifact | SHA-256 |
| --- | --- |
| `/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler-inputs.json` | `fbcba16306f70092c3b0df0cad3776ab7c3e8be13ef1a4797a07b21f3dd71074` |
| `/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v` | `9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b` |
| `after-arm.c` | `7669123b58cff1746ac07d1e5a4168190d1f0558f2a48663b88dc540878f5707` |
| `after-gaps.v` | `a8b4735d5226e9b9d551b18963486b90edc34fd5ebf946e620f48de7badfe1d0` |
| `after-proc.v` | `81154124ce64e42994efe289fa371262a953eaa9cf01a37074b123a2e54a8a58` |
| `after-x86.c` | `c51971fd43f252850ba37328e029410a8e3d2b636db8bebfec60f08840430f0c` |
| `allocs-after.log` | `b2b9a4202b7ae0a9f9a3785ec54e09f7854cd5f313b23f0b89a1091b42ffd403` |
| `allocs-before.log` | `e2d3446bcb3933294a0e4c52da5b595050113de01f001f1b737e78e803c3d84b` |
| `base.txt` | `dd87d7432f21aeb0c14988631a9d5e5bcf8f4814ed8372d897aaa61a4f7945d6` |
| `before-arm.c` | `6d2b4d5677736e73289b2d87de3330110377cbe1a9c20035bc3e6cd455b1267d` |
| `before-gaps.v` | `e6862eeec7003d68048c651895bf68e437a5403e96c369c0266903204265e3ac` |
| `before-proc.v` | `29bfa676d2c071ccab7b9dbae29536a15d146058c82a492c2b2a9ccf5937c40c` |
| `before-x86.c` | `d259e073b30afc2dad656511412bde0df74934ea88ebca49988271d41d0ade1c` |
| `build-after-arm.log` | `729d386b42994c2ac1951a9c2c7feea339a589a5d2dd7642a2989c78d356116f` |
| `build-after-x86.log` | `41ef26ed39da3d8452d8ed34907a000e76c2f3d78c29f588d84ce0f441ba88f7` |
| `build-before-arm.log` | `79dc25d0edce8385080605903662ceda81270381447455a8fc0546e01d751b0c` |
| `build-before-x86.log` | `0b159bc908b92179839f0b31962cd087f5305da749449673e1584d68ed5ab4cb` |
| `compile-reference.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `compile-run.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `coverage-check.log` | `f14b0219fd4094c269a82b893f4a2424ffc8461e1745db3f9971f06dd81031fb` |
| `host-tests.log` | `905975ef8a564b94c309e68e4fd6bc13f089a6ad985db37dd6f78455471dfd93` |
| `independent-artifacts` | `73c3f1d4f87b9f64496050fab7da900ee7f62ab83be6130539fa9dbe84c9e083` |
| `independent-artifacts-compile.log` | `a6ae6f9e1847143fb1db67cf67c951124ba52e321a6b6bbee1548167539fbee0` |
| `independent-artifacts.log` | `75b3a91e77b8304ff74d245ffaf418e7716df1612a64dc168cda3a70a1995017` |
| `independent-artifacts.v` | `1138419a8ab6df6f8a1a09734ad5cd0b593dfae83c7739af86e5d865cff308f2` |
| `independent-baseline-control.log` | `88c566b528b7444dc33d048a0ccd1ab530a29beb353e2d3b117e40ac7c55276d` |
| `independent-code` | `027136b4b2b84ff57901751d45270cd642f26d5a7ee13398330520337d286a6e` |
| `independent-code-body.v.txt` | `5ad5543cfa700e0aa149c66981f35b04461a100b4710c590755160b46c4f705b` |
| `independent-code-compile.log` | `158d476d2907b43af1e042dc754cddc15e51b396c446f740c07d173ddbc61ccf` |
| `independent-code.log` | `eb11fbc2303e3ba9167de1b2ecc9178a04fc7d77a3dc00301bae520bfb947978` |
| `independent-code.v` | `e692f670b60edc9ef6fb1b28db84c16ceaf86b4d6223d0f0408359c401eb0f2c` |
| `independent-compiler` | `51be7f767b1a4cca499f8e1be9971c30f968c39defa74e11171cd7ae885f9be9` |
| `independent-compiler-compile.log` | `570a1d7e0dabcaaa8272bbaf7fc22fbefe102640e7a4bdc28ccb0baee5c9637e` |
| `independent-compiler.log` | `804f25f1d86c1ca93ab1e5e8ad7feb8d533e505a64657087771fa842cf76db7b` |
| `independent-compiler.v` | `efaf52ef755c684ae2a81c918941a5615ce694d18ae0f4f3176c8fe0e9bfd631` |
| `independent-completion-update.v` | `22e2bf2c24547f876d0cf96db9c4670cf38163e2d6b6750d706bde960c94cd07` |
| `independent-controls` | `43e6cedb6f588f4f354b96fe6efd2d9e27360cc0d0508be82e3548c215e463f6` |
| `independent-controls-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-controls.v` | `d3972087b1aeb3aecb85507ab543f471670cc6d088efa5f275a1bb6f6258458d` |
| `independent-count-finalize.v` | `dfd4065c6a761725911c265a1c9a52ba09b6e0d3ecfec0125df83dbf99b5310a` |
| `independent-counts` | `4d08ff13549c6dcea5890b7168c5bfc17174a141ef7da7c2f4c4b80eedde9cb3` |
| `independent-counts-after-arm.log` | `ef1cd015b566b925e832e16bb21038810e6406855f1b5c3589991429fd783e4b` |
| `independent-counts-after-x86.log` | `aecfc1708949bdc9d8b99b252a66f230914eb7c15589eaf88817f4cfea30013c` |
| `independent-counts-before-arm.log` | `d37e216a874519f79b450d79e3deafdf713c0f8d3ace6cedbd25b2042f831242` |
| `independent-counts-before-x86.log` | `31a5a1e39fb6429c95dfeb2499e4aac4bc851c476e3fb1ba4e498a3fc67644fb` |
| `independent-counts-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-counts-reference-arm.log` | `a57fc8b2dac7f4ec0df37724430c39d590ad2c6421e4f665f9d59068bdb075ef` |
| `independent-counts-reference-x86.log` | `7c8f942913bc87194222c816e0efcd82ca503d0c32cb8d0cf3fd5cf24a27c6ea` |
| `independent-counts.v` | `f259884254216cda16ad3c010edb30f3870bf868858513dbcf3bd0450362ee35` |
| `independent-execute` | `0d50364f7e3309d9aea9b926cda2708d15818ccd76245ba1e3e21cd2c848ae54` |
| `independent-execute.v` | `2e66665f259e258601629d022319a21e320eb79fb0127a6a7aaec9924b706251` |
| `independent-false` | `f38535ba672a41ea109be830c658ea93039abf5483881b54b3e6063b19c60d06` |
| `independent-false-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-false.log` | `94f35742a86167868f916c1fa3d7524a4b4bc50beb76e1f17cf233344befbc57` |
| `independent-false.v` | `c2af5d63b16375d6365417921adee72efe89a1ec500431371173c49cb73a6e1a` |
| `independent-final-manifests.v` | `4bc51ae6a46c8746b23578efa7f477fd0b657b672dc310e715384db35045d52a` |
| `independent-fixture` | `974873779d49fa6ab2ad4e3a58522a3f91bc6f531bd4914886f051e788727cad` |
| `independent-fixture-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-fixture.log` | `68789979822aadec994673a4ebf7762990289549d60bb5b838e8535e33287a9c` |
| `independent-fixture.v` | `e93172694692e04fb733de9348945bd997fad3b9b6bd5ee9e2a3a6907f657734` |
| `independent-p2-pin-update.v` | `4da3c5b32984d6241094f9e1915a3ba519dc7ae619b665927f997f0c202854d3` |
| `independent-p3-update.v` | `25a384b148fece86f9f637dcb28e16f9e88e56ae16ef4500827291d732b11c7f` |
| `independent-preparation-loop-temp.log` | `d9215e7a1368d98dbdb348bf5a227f96af350ab7c6d269c4632133f897b588fa` |
| `independent-preparation-loop-temp.v` | `cfd63da8fa0b56c1de109c25538a32d8e61c3758ead9a103963a91d522180f8b` |
| `independent-provenance` | `2c766cc8dfcce84db141e7ce7729d60d465979085d6fd2f2cd7d393113c5431a` |
| `independent-provenance-body.v.txt` | `b6db462cfc9a3e94e87cee75a76e03dd438e2129600a82bd94c6577836da9c6d` |
| `independent-provenance-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-provenance-setup.v` | `542a5245406b8438dca33164676d9927d62a462feb5ba0f7d64e6e1927f62f92` |
| `independent-provenance.log` | `bba1b02a2ad22e5271043eeff4f8c1ee8c894350369faad76aaee8c6e48a2631` |
| `independent-provenance.v` | `227c2416a5d72375c65a1521a1dc84b580f38d94d4fa937017c2b3856eaf4cb4` |
| `independent-rename-update.v` | `20b7adc94d5fba42a143213410992c37f72287c4959e00fe3b5582854a4acf13` |
| `independent-report` | `7622a74717ca1621d12960fed7d8606654b6ec8075f6c1e0f287b4e54f7aaa82` |
| `independent-report-body.v.txt` | `07d6e4e5abe7500d0cfa0faff3a5d635a0bdad8a0d37a417f2d0a6a0d197ea40` |
| `independent-report-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-report-prose.md` | `a1b74811cde82cdfbc0168c2cdc3f8e8386a64bdd08a1c14a2b3029dde47791f` |
| `independent-report-setup.v` | `4d01469ee08aaef86896f94f359583d0d594122f9ea8ad5a219f7a7248960ef2` |
| `independent-report.v` | `d917c3ba3df00a1726c371917bda5da9050c2495e2f8d35678ac14013f4333a3` |
| `independent-scope-difference-arm.log` | `8dbf7b88fbab7b3ab5af3705d782c572eb47df4beb82df8d9cc04e69b148bfff` |
| `independent-scope-difference-x86.log` | `1df17955d4f9fd2954f312b3cd319bed627a4e14281b8a47ed02b45451722592` |
| `independent-scope-difference.v` | `2712996f3bd41db17a4cdf80e3d5379738b6cc4a10360320918c1096601e7ba0` |
| `independent-setup.v` | `fa7c0430a72376e6450e3aefc6cb4101c57777f5ae5aa7158d5269e3c15f4c61` |
| `independent-suite-setup.v` | `f739af58fb5ec1780c5f6c166428c914acd5b75f92f66e75d207daa92e5bccf2` |
| `kernel/proc/proc.v` | `81154124ce64e42994efe289fa371262a953eaa9cf01a37074b123a2e54a8a58` |
| `kernel/syscall/table/gaps.v` | `a8b4735d5226e9b9d551b18963486b90edc34fd5ebf946e620f48de7badfe1d0` |
| `linux-sched-v6.12.c` | `a9c89bc6e1eca2587f39518718aa0a53fd8ef646f16927a0252e5fa7f25b5804` |
| `linux-source.sha256` | `828a563c1b01f45bf492129e1d6194103b5172fc520c49f1e8f224a449410d96` |
| `p2-interrupted-watch-final-retained-inputs.json` | `86bcae9924fecc2041db864db004162ce60496b666fd723edea617c7cce2c356` |
| `p2-interrupted-watch-final.log` | `28bb4952ac17826f9137bfa4c109eed292031b97ee4287d2387440f57cadea36` |
| `p2-interruption.log` | `b4510b1eeaf8ed14fe7ba3998898e131dddeafb5dd0f15be1e01c5e4ca22c122` |
| `p2-retained-inputs.json` | `4b1a0db28a81da24461fe12c6027359435660ee17332cc9c858c224306a5e8d1` |
| `p3-driver-arm.log` | `69f6ac51280ac952f8d8c116668511d5244429983e2e22d072536e2f751132e0` |
| `p3-driver-x86.log` | `f8bce69a17cad301856325dea8d25da86bc84d77d7fffaa3aa57aa94b04c1e6e` |
| `p3-interrupted-watch-final-retained-inputs.json` | `8ed275fa42de22438f68179bedeef2d2aa2ab2e85be7d749e0a303f9b014937a` |
| `p3-interrupted-watch-final.log` | `4ad5d285d63632056bb572975bf0f5c6b9ac30d7973bd68bff0502d85f1b3b2e` |
| `p3-interrupted-watch-p3-driver.log` | `4f493cffebc3a7005ed909eabfee13d2de393ab1e6b4153cc78cb33b74928357` |
| `p3-retained-inputs.json` | `55f66c6e14638cdc8e1be18f017ca3c008ffde6c18cd3215b956dcfdeb915257` |
| `p3-retire.log` | `ebf098f73c05d47432ba69076cec4532e88e245859dd74799f14446d9019a682` |
| `p4-driver-x86.log` | `7292062b9a1f81e558c085c54d6c22ccf8b673405649dc034d18099ad123f33e` |
| `preparation-retained-inputs.json` | `346e33d2c1d7bcc8ad58b2ef85a53ab583aa0541ed2e78854461f2b8630a8c78` |
| `preparation-retire.log` | `ec5e585ca9414b234c1b547d7dbb6da3c002850297c36472917ea53d0cbe4d90` |
| `preview-arm.c` | `16c678caf8594875e8a3cb4b663125e7d627aa73ec339e83d20c4850d812ce54` |
| `preview-x86.c` | `16c678caf8594875e8a3cb4b663125e7d627aa73ec339e83d20c4850d812ce54` |
| `reference` | `35572d0f114a63152ef511250c9cb443bcdfbecf218e99eabb1fa1537ca18a42` |
| `run` | `acb418d6e9b514e58a24107215b3a263bc445aaf51f9184c7d02d35601d0b8e5` |
| `states/p1-after-arm/attrnice/fixture.c` | `16c678caf8594875e8a3cb4b663125e7d627aa73ec339e83d20c4850d812ce54` |
| `states/p1-after-arm/attrnice/init` | `cc88302a486072416ef3c9b193a008ed10d1b074f23d0ed032e586200e20afeb` |
| `states/p1-after-arm/attrnice/serial.log` | `c5e9593b4b39a637290d60f4e544736d561abcc096957b8502dc537e0baa1f27` |
| `states/p1-after-arm/attrnice/test.iso` | `8ed0fe39cf39588417634e6a295444e668bd1d4b0049e386784d6c479320bb34` |
| `states/p1-after-arm/kernel/bin/vinix` | `69977adb542fd4dc42f4796b3b11684684a57f0dd7f2b4208dad681ac1674d11` |
| `states/p1-after-arm/receipt.json` | `02684d644675df456792910e870ad90bd8ab41f51db30373c21b3aca56784e8e` |
| `states/p1-after-arm/sources/attrnicefixture/core.v` | `42f45edd6322c95037aa848404275527503570ab70929f9678c60db82701fb59` |
| `states/p1-after-x86/attrnice/fixture.c` | `16c678caf8594875e8a3cb4b663125e7d627aa73ec339e83d20c4850d812ce54` |
| `states/p1-after-x86/attrnice/init` | `d69ffafc9b23ce6ac63a458cf1de887959c250adad6131441ee236e56a86a6ff` |
| `states/p1-after-x86/attrnice/serial.log` | `00249ca4e4c06795ffaf663fe8e380c3e8a3ca6580c6301c1f2b53fdd35889a8` |
| `states/p1-after-x86/attrnice/test.iso` | `723da0e14c7b27b436f1efece518dd3e1d7dc3410fb184a0e9f95422763a5236` |
| `states/p1-after-x86/kernel/bin/vinix` | `79368a324980ef011bb8276f5f3a8e6e16f44a12f7421f3d816e950f635a1ef8` |
| `states/p1-after-x86/receipt.json` | `1ae0f382126ed1be44f61b0f3f0b7201772f815b7ca03d9bcdc5bf93654f0633` |
| `states/p1-after-x86/sources/attrnicefixture/core.v` | `42f45edd6322c95037aa848404275527503570ab70929f9678c60db82701fb59` |
| `states/p1-before-arm.log` | `d0fa87b181f4c1141c5164871b71b615018d8398a506a244ce741cc1371a0987` |
| `states/p1-before-arm/attrnice/fixture.c` | `16c678caf8594875e8a3cb4b663125e7d627aa73ec339e83d20c4850d812ce54` |
| `states/p1-before-arm/attrnice/init` | `cc88302a486072416ef3c9b193a008ed10d1b074f23d0ed032e586200e20afeb` |
| `states/p1-before-arm/attrnice/serial.log` | `86c2fba46957e8d443b7d3dd83bed184a129ccf36050aa039afe70e828f54208` |
| `states/p1-before-arm/attrnice/test.iso` | `81a04ea810d9a76db6442b740498acc028635e62cfe4cf36b981f4860c14ab22` |
| `states/p1-before-arm/kernel/bin/vinix` | `2930f9dff3f55357d3bc047db6cb1fcc4b9704e1276eb8dc08da5b2f2dda8636` |
| `states/p1-before-arm/receipt.json` | `b3a61fc788f199e602cbd769b0cee263406b92dfa3faf16c5f74a7450574e7a0` |
| `states/p1-before-arm/sources/attrnicefixture/core.v` | `42f45edd6322c95037aa848404275527503570ab70929f9678c60db82701fb59` |
| `states/p1-before-x86.log` | `b30eb60902dfc74146ea2930b9e237ebec6277bde1545d783147d18013b6abd0` |
| `states/p1-before-x86/attrnice/fixture.c` | `16c678caf8594875e8a3cb4b663125e7d627aa73ec339e83d20c4850d812ce54` |
| `states/p1-before-x86/attrnice/init` | `d69ffafc9b23ce6ac63a458cf1de887959c250adad6131441ee236e56a86a6ff` |
| `states/p1-before-x86/attrnice/serial.log` | `3d12a04434cd6f41e21d9c26f20759ec8c8d0e00d29eb6ecb290222c9b296ead` |
| `states/p1-before-x86/attrnice/test.iso` | `edba29d2e82043a0a3553e40ba54732fb5488b81a90f14e300d1e2a1a2d65ce3` |
| `states/p1-before-x86/kernel/bin/vinix` | `2adda6e222287a834b9e3081bf87e87a9a74620aa1211aa74792c890886cf27b` |
| `states/p1-before-x86/receipt.json` | `99b29321ff1bdcdc1664e79ee5adb36050d594e4bebf1c3b072437e2a21ee6ca` |
| `states/p1-before-x86/sources/attrnicefixture/core.v` | `42f45edd6322c95037aa848404275527503570ab70929f9678c60db82701fb59` |
| `states/p1-reference-arm.log` | `827b53721e88d09bb1e8fb00a2992c0c70a354567b191c28ca1876df449b2e1e` |
| `states/p1-reference-arm/fixture.c` | `8983871d995606e685a03a2c3ea8bc38adf5cf39ef518539b43fb4cfabc67773` |
| `states/p1-reference-arm/init` | `98b6609e6af78cb114e7f349fbe1bc23ebbee267ff69210ea05cb9a861f6f80b` |
| `states/p1-reference-arm/initramfs.cpio` | `0e06bb23fd8951578f6627063b1b6316a7c39483e0d0dfd233595027b4a1cc3f` |
| `states/p1-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p1-reference-arm/probe` | `cc88302a486072416ef3c9b193a008ed10d1b074f23d0ed032e586200e20afeb` |
| `states/p1-reference-arm/receipt.json` | `e1ea9dcbc4cfce412830a4354a2320378081e833e79255842063ba30cd0f8516` |
| `states/p1-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p1-reference-arm/serial.log` | `d0e366523aeaa6f00cd2d1da29dc26316a09cc915da766a43c02f3fa1df107f3` |
| `states/p1-reference-arm/source/attrnicereferenceinit/core.v` | `bee9c2099e97cf1f6d50eed04208ab68b4e7afc63c92f6733629a0c103a6987b` |
| `states/p1-reference-x86.log` | `dac9fc9c61a92335a0cf4cc74fc85e8dd64d9cc2f82b1d258a9a192e442ea6d3` |
| `states/p1-reference-x86/fixture.c` | `8983871d995606e685a03a2c3ea8bc38adf5cf39ef518539b43fb4cfabc67773` |
| `states/p1-reference-x86/init` | `b36b723a79b29f1dec51eccc8cdab478f2e0567bd94e3980177b9473ebfc0427` |
| `states/p1-reference-x86/initramfs.cpio` | `e64496486f7e501589bee0dfcb15530822cc39ff4db6848f5b086064806520bb` |
| `states/p1-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p1-reference-x86/probe` | `d69ffafc9b23ce6ac63a458cf1de887959c250adad6131441ee236e56a86a6ff` |
| `states/p1-reference-x86/receipt.json` | `9d49ad8e880f738f8698cfe87bd990194bee6dec67aa2b5641089a313719f371` |
| `states/p1-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p1-reference-x86/serial.log` | `231d47cb7a98ed2711cf67711e2be4d737a5697cb55e3071bc01b0752471e665` |
| `states/p1-reference-x86/source/attrnicereferenceinit/core.v` | `bee9c2099e97cf1f6d50eed04208ab68b4e7afc63c92f6733629a0c103a6987b` |
| `states/p3-after-arm.log` | `1458374ea35c1fce8d7d36e8b053dee270857809311e0fc655df29f1953cf5c9` |
| `states/p3-after-arm/affabi/fixture.c` | `5f078939b42a25668def6b7fd8bb25c20329df87d0aa27f33aa5b55da14cbd3e` |
| `states/p3-after-arm/affabi/init` | `170454ca46fa486d0c1fce09e7105e702710e1f42d9e90816bbb28cd0ba5fb14` |
| `states/p3-after-arm/affabi/serial.log` | `a539a751e554b9a09f2ddfbe97ae6eb73cd2f76a6b45781cc1b786bc17d8d760` |
| `states/p3-after-arm/affabi/test.iso` | `043caf8a4b30f316ca99d65ac6345c48feddae04f32651ebbec867c81773069c` |
| `states/p3-after-arm/attrimport/fixture.c` | `962a0933bd5988449c889075854dda060a5b4ff362847bb3f50b050d92a5889d` |
| `states/p3-after-arm/attrimport/init` | `4805664d48a3609e91df4d388b3d2caed44459b9496d450b0f93e96c5d819d1a` |
| `states/p3-after-arm/attrimport/serial.log` | `96c855fdbf2b5fba4a93b98f54b852cf85b9e6972c6be13c19092f7ee286d436` |
| `states/p3-after-arm/attrimport/test.iso` | `08d64ea5d030a979669b8396f3a3b9ef7c46c18ddec8e8b878e0217409af8aff` |
| `states/p3-after-arm/fcntlabi/fixture.c` | `214391504c640d251498205116f3dd9473925931e8a068e6a15ffb349965fb09` |
| `states/p3-after-arm/fcntlabi/init` | `b92892f1860ff4aae349f27924922645aed79becbcff2dd00a0a18fc797fd3fd` |
| `states/p3-after-arm/fcntlabi/serial.log` | `03e2b8eb059517a37f83c8a764c94b1091a1579ca9991838efb1f1b5053ad408` |
| `states/p3-after-arm/fcntlabi/test.iso` | `0360f148da778d111a70248d7ab062b067b71a427e85a84a1c3ccdcaf5aec719` |
| `states/p3-after-arm/kernel/bin/vinix` | `69977adb542fd4dc42f4796b3b11684684a57f0dd7f2b4208dad681ac1674d11` |
| `states/p3-after-arm/receipt.json` | `579969f050e05e57b1f8f0a705edd8614085f0424b7f71805136e7b8f2afd034` |
| `states/p3-after-arm/sources/affabifixture/core.v` | `d3f1524a56978720649930294770174cbf8803682882b1e10af880139643a00f` |
| `states/p3-after-arm/sources/attrimportfixture/core.v` | `ea50d5decd874adb05f39d61b06e650f4163647c3fb7df84795333d55d1d62aa` |
| `states/p3-after-arm/sources/fcntlabifixture/core.v` | `6f70bc290dff8671cbde66025806b7b5d99d82468dc6e7098ec86a27cc43c3ac` |
| `states/p3-after-x86.log` | `905334f61e1b91a2ed9063e1e1045b28c19eebc633570da0408cb451c96b711c` |
| `states/p3-after-x86/affabi/fixture.c` | `5f078939b42a25668def6b7fd8bb25c20329df87d0aa27f33aa5b55da14cbd3e` |
| `states/p3-after-x86/affabi/init` | `c4a5e5a6ba17781b026c420c6caae299a5b4ec9d8c682d19a3ecb059d07077a7` |
| `states/p3-after-x86/affabi/serial.log` | `5f57a1b2eac8a732f3125d8286d1b6b753d61bc063fbfcd02cbf19dcaa428f47` |
| `states/p3-after-x86/affabi/test.iso` | `2590a37226c914237fc63c29fd1ba6fd89a002863cfa54683f401a0c81d94c83` |
| `states/p3-after-x86/attrimport/fixture.c` | `962a0933bd5988449c889075854dda060a5b4ff362847bb3f50b050d92a5889d` |
| `states/p3-after-x86/attrimport/init` | `44c4e4bbbde3ebf4f527ae712af747cd53e066bfd73e9a00825afe070ae21917` |
| `states/p3-after-x86/attrimport/serial.log` | `c6dea594a1831c456686257fbdeddc24cff8b21f66e592773122a9f1855da075` |
| `states/p3-after-x86/attrimport/test.iso` | `d773935f4065c15c4489c2da9115a5b39dac2bea8af68a3ee2c718cdf0e742b5` |
| `states/p3-after-x86/fcntlabi/fixture.c` | `214391504c640d251498205116f3dd9473925931e8a068e6a15ffb349965fb09` |
| `states/p3-after-x86/fcntlabi/init` | `d627872a0a61cbe541ae88541b21efe49f0ae214e13801f1828a0cd19cb8dc16` |
| `states/p3-after-x86/kernel/bin/vinix` | `79368a324980ef011bb8276f5f3a8e6e16f44a12f7421f3d816e950f635a1ef8` |
| `states/p3-after-x86/receipt.json` | `2fa1004ed1be273dbf3c7ac203bd3209fe053ac014ab8d344470fdc300759656` |
| `states/p3-after-x86/sources/affabifixture/core.v` | `d3f1524a56978720649930294770174cbf8803682882b1e10af880139643a00f` |
| `states/p3-after-x86/sources/attrimportfixture/core.v` | `ea50d5decd874adb05f39d61b06e650f4163647c3fb7df84795333d55d1d62aa` |
| `states/p3-after-x86/sources/fcntlabifixture/core.v` | `6f70bc290dff8671cbde66025806b7b5d99d82468dc6e7098ec86a27cc43c3ac` |
| `states/p4-after-x86.log` | `07525ed434d3d022702755004515907823e57185bcf7dd8826cd20de84a6504d` |
| `states/p4-after-x86/fcntlabi/fixture.c` | `214391504c640d251498205116f3dd9473925931e8a068e6a15ffb349965fb09` |
| `states/p4-after-x86/fcntlabi/init` | `d627872a0a61cbe541ae88541b21efe49f0ae214e13801f1828a0cd19cb8dc16` |
| `states/p4-after-x86/fcntlabi/serial.log` | `fb0f6b4a53a70a2345a2577acfadf9023db79e6ee9c55e65c169903af212d54f` |
| `states/p4-after-x86/fcntlabi/test.iso` | `a03789fe5d705345826735823748690565b5d4f1966e4a704352756208b8e371` |
| `states/p4-after-x86/kernel/bin/vinix` | `79368a324980ef011bb8276f5f3a8e6e16f44a12f7421f3d816e950f635a1ef8` |
| `states/p4-after-x86/receipt.json` | `0abc55989360cbccc85e9e26277e6617649ac274066ac837b98599e617a66a38` |
| `states/p4-after-x86/sources/fcntlabifixture/core.v` | `6f70bc290dff8671cbde66025806b7b5d99d82468dc6e7098ec86a27cc43c3ac` |
| `states/preflight1-attrnice-arm/fixture.c` | `16c678caf8594875e8a3cb4b663125e7d627aa73ec339e83d20c4850d812ce54` |
| `states/preflight1-attrnice-arm/init` | `cc88302a486072416ef3c9b193a008ed10d1b074f23d0ed032e586200e20afeb` |
| `states/preflight1-attrnice-x86/fixture.c` | `16c678caf8594875e8a3cb4b663125e7d627aa73ec339e83d20c4850d812ce54` |
| `states/preflight1-attrnice-x86/init` | `d69ffafc9b23ce6ac63a458cf1de887959c250adad6131441ee236e56a86a6ff` |
| `tests/linux-compat/attrnice-check.v` | `751b04c70e9c1ca6f89e26f882bf9e57e91673cd011b6f32c812db506c114a1c` |
| `tests/linux-compat/attrnice-reference.v` | `18c691a5b017a23d4997aedcbbeb41815e1ae9dab5824700eecb9cc3f5fd2e20` |
| `tests/linux-compat/attrnicefixture/core.v` | `42f45edd6322c95037aa848404275527503570ab70929f9678c60db82701fb59` |
| `tests/linux-compat/attrnicereferenceinit/core.v` | `bee9c2099e97cf1f6d50eed04208ab68b4e7afc63c92f6733629a0c103a6987b` |
| `tests/linux-compat/run.v` | `d9c142c9b95e7d77966214809d3e31366744924ee1dbbcee2a404f569967da41` |
| `watch-final-retained-inputs.json` | `a9f76cdd5470c8829eac34ac504aca8793d3143f3efb286829265a89fc48c333` |
| `watch-final.log` | `caa757434b9d68858f969880f13c92a67ffa76f2c1f595ebcdb6ab75ae84176f` |
| `watch-p4-driver.log` | `4e59d2f161ccea24e1f3ff385546f6f1b6706525d35d62e9bee6e4bb96d0c982` |
| `watch-retained-inputs.json` | `391644765f37a613374562d6dc4e3be8087b0d43ddcf085fd2938e83a05d3662` |
| `watch.log` | `8146b592696408978c2c7ba2123a793d0a3977ca34b3cd82424aba74817b2105` |
