Independent attrclass lifetime review: PASS

Reviewed stable process-leader FIFO/RR sched_getattr nice-field shaping against frozen baseline `7fcfd033b727496f6146c4c67ce47936abc265ab`, four fresh original/corrected production builds, final V probe/reference/controller/auditor sources and actual native/Linux captures on both architectures. No new lifetime blocker remains. Query output, retained process state and guarded copy behavior are qualified; physical scheduling and concurrency remain separate.

The kernel change replaces only the getter's sched_nice initializer and adds its exact internal comment. FIFO/RR output carries nice zero; other classes retain the existing queried nice. Existing copied SchedParams and the locked owner.nice read remain unchanged. Generated production C matches byte for byte outside table__syscall_linux_sched_getattr, without identifier normalization or new prototypes. New temporaries hold only u32/i32 scalar values before the existing stack Attr initializer. The helper retains one PID-table lock, two unchanged unlock paths, existing MAC check and synchronous usercopy. No allocation/free, interface box, pointer escape or mutation of task nice is added.

PID lookup, scheduler metadata and owner nice use separate lock intervals, so mixed snapshots and target/credential/policy races remain unqualified. No borrowed target/process pointer leaves its existing locked use. Pinned Linux v6.12 initializes kattr to zero; get_params fills only RT priority for FIFO/RR and fills nice for ordinary classes. Genuine supplied Linux 6.12.51 kernels independently check the same native probe ELFs.

Final probe C contains exactly 25 explicit allocas matching source, no heap/dynamic-array/fixed-index helpers, and byte-identical preview/preflight1 C for both matching little-endian ELF64 machines. The explicit Message is 20 bytes of five i32 fields, including priority. Broker requests validate a registered positive cohort/peer PID, OTHER/BATCH/IDLE or FIFO/RR policy, nice -20..19, RT priority 1..99 or ordinary priority zero. The broker restores OTHER/0/nice 0, sets actual nice using canonical signed64 setpriority words, installs policy/priority, verifies real state and acknowledges. Message, sched_param, Attr, Limit, capability and Counts storage remains live through synchronous syscalls/pipe I/O; pointers are not serialized.

Setup state checks deliberately exclude only the RT sched_attr nice field under test, while raw and genuine musl getpriority always verify actual nice with immediate errno checks. The output oracle requires RT nice exactly zero for every successful matrix query. OTHER/BATCH/IDLE report their actual nice. Policy, priority, size, flags, deadline/period/util_min and known native runtime/clamp defaults are compared byte for byte. Reference fair runtime is configuration-dependent and explicitly copied into the expected fair result; reference util_max accepts only 0 or 1024. RT runtime remains exactly zero in both paths. These reference exceptions do not weaken the RT nice contract.

Both root and UID/GID1000 cohorts issue the matrix with effective CAP_SYS_NICE disabled. Actual single-thread leaders include zero/self, same-owner and UID/GID1001 peers, absent and reaped targets and signed-negative controls. Seven configurations cover OTHER/BATCH/IDLE priority zero and FIFO/RR priorities 1/99, combined with nice -20/-1/0/1/19. Each successful query verifies retained policy/priority/raw and musl nice; nonself operations also preserve the caller's OTHER/0/nice 0. Peers close inherited broker ends, report readiness, block until released and are reaped. The mapping is unmapped before Fixture storage ends; final Counts are transferred before the cohort closes its pipes and is reaped. PR_SET_KEEPCAPS is confined to disposable children. Complete process-state restoration is not claimed.

Six request lengths 48/49/53/55/56/57 require their exact known prefix and advertised output size, with untouched surrounding bytes. Aligned/unaligned scratch and page-ending output are checked through memcpy/memcmp rather than unaligned structure dereferences. The three-page mapping has a read-only second page and inaccessible final page. NULL/negative PID/invalid size/flags EINVAL precedes lookup; absent/reaped ESRCH precedes copy faults. Read-only/inaccessible/partial outputs require EFAULT. Only the first 28 bytes of the page-crossing partial-fault form may change, with all surrounding bytes preserved; exact partial bytes are not qualified. PID/size/flags upper words narrow as Linux expects, while pointer width remains intact. No call is replaced by placeholder success.

Counts derive independently to [2520,5040,2520,1928] per cohort, 12008 each and 24016 per architecture. The main matrix is seven configurations by five nice values by four live targets by six lengths by three forms; the two upper PID variants double group 1, and upper size/flags form group 2. Group 3 has 1920 error controls plus eight initial/final observations. CASES and FINAL require exact unique cohort/kind rows and equal outcomes. Both original kernels actually fail [1152,2304,1152,16] per cohort, 9248 per architecture. Four RT configurations with four nonzero nice values explain the main failures; sixteen successful error-group queries expose the same field defect. Both corrected kernels and identical-ELF Linux references pass all 24016.

Both corrected 24016-check results and their two warmed storage cohorts pass independently. Storage establishes self FIFO/99/nice -20, same-owner RR/1/nice 19 and cross-owner FIFO/1/nice -1 before 32 warmups and 200 repeated query/error cycles. Each cohort retains exactly 18 ARM/14 x86 slab classes with flat live counts and 85/85 ARM or 216/216 x86 large pages. The observer remains open through snapshots and closes on nonfatal paths; a bounded 4096-byte stack buffer holds at most 32 slab rows. Thirteen-second settling intervals surround the snapshots. These measurements concern repeated getters with retained leaders, not process churn or whole-kernel allocation.

Independent provenance checks bind all 15146 pinned compiler inputs, both isolated 64-input inventories, four fresh production builds, eight host test files and four inventory passes. Before/after allocation diagnostics are byte-identical at 398 ARM/290 x86 sites, including existing allowance refusals. Actual source/C/ELF/ISO/kernel/serial/receipt identities are rehashed. Reference receipts bind supplied kernel, probe, wrapper source/C/ELF, initramfs, serial adapter/log, QEMU and controller, requiring passed/finished/forced=true and status 0. The wrapper's single stack argv allocation remains live through execv. Hash scratch buffers/files and host process handles close/free after synchronous use.

Complete eight-case receipts and aggregates pass on both architectures: attrclass, runtime, schedabi, rrabi, attrquery, attrnice, rtadmit and idleexit. The completed watcher binds eighteen distinct native captures and its eighteen actual retirement messages, without timeout. Independent hashing compares the complete retained regular-file inventory with all 162 manifest entries and rehashes every file after only unbound ISO staging/firmware variables are retired. Native semantic results come from the genuine captures, not watchdog timing.

Independent helpers compile without -prod. Both the false assertion and a genuinely passing ARM Linux capture supplied as a failing original actually exit 1. The maintained auditor's counts, strict output boundaries, source/C scope, unchanged lock paths, receipts, pins and publication protocol were reviewed independently. Implementation, final publication audit and commit remain with the parent; this review changes only its owned report.

Worker-level nice, target/credential/policy/limit races, fair-runtime and reference clamp configuration, deadline/reset/utilization transitions, security/namespace configurations, setpriority signed32/admission/group semantics, GNU libc, translated/ELF32 and physical priority/fairness remain unqualified. This result does not close the ARM CPU1 QoS blocker or the broad section 15 gates.

SHA-256 pins are recomputed after producers complete. Paths are relative to `/Users/alex/.cache/vinix-linux-compat/attrclass-20261015`, except repository paths starting with `kernel/` or `tests/` and absolute compiler/QEMU paths.

| Artifact | SHA-256 |
| --- | --- |
| `/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler-inputs.json` | `fbcba16306f70092c3b0df0cad3776ab7c3e8be13ef1a4797a07b21f3dd71074` |
| `/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v` | `9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b` |
| `/opt/homebrew/bin/qemu-system-aarch64` | `45d74da57beb9be259ca3d6996e5c70d4ab14326ea59c3db3e80308859d91a3e` |
| `/opt/homebrew/bin/qemu-system-x86_64` | `25afcb2986e4a0f2c567de17273f55de3c99792b78a07c99e923bb62024c088f` |
| `after-arm.c` | `a30317af8e70f295de6d8cf96aaa3d13c6b5dafedf50436ba8e608a084c4f29b` |
| `after-gaps.v` | `e2ba41e28da260a4c91e30851096b7b9a3fc74376787c6f26f68c321957c7360` |
| `after-x86.c` | `d926e14e907de972038763667a3a789f8fd329c0711f6ea519b6c2100ad84c88` |
| `allocs-after.log` | `b2b9a4202b7ae0a9f9a3785ec54e09f7854cd5f313b23f0b89a1091b42ffd403` |
| `allocs-before.log` | `b2b9a4202b7ae0a9f9a3785ec54e09f7854cd5f313b23f0b89a1091b42ffd403` |
| `base.txt` | `d228d002defef93ba18997414f066f89a2140249458252afc82b8e811c086bab` |
| `before-arm.c` | `7db5561197a4e098c9875caab0c3980cef9f430d97d533d7ac0038c5778fa2cf` |
| `before-gaps.v` | `80d2b2fccd54a4d91286ed74c9103eb2b4ff25173a4239910d96fc8fe434304a` |
| `before-x86.c` | `3d16a4d4f3fca2a9eb503bba4e254823d224b73882ddf88aef8c9b3a2387dc5a` |
| `build-after-arm-detached.log` | `fb9cbedf14fa3eda8cd77c8f0138801aead9aa1ef9d6b655f589f7bfad243f7a` |
| `build-after-arm.log` | `58483be7dd673b7341c7d5424c991f0e6848b938efbc314c17931ec1f8a8cf83` |
| `build-after-x86-detached.log` | `d1800f5a6d8da1b68c25bcdec33732bb19c6c93e9ff0cea4b1faff3937f1dfe0` |
| `build-after-x86.log` | `00757702c33717b04816f7dd6bf4977b5090a888e75636053889676420da3482` |
| `build-before-arm-detached.log` | `f5b458dd13387d63a2b33bc938e97a4fb03cc6f2afd45b885e7c61601cc4d8e4` |
| `build-before-arm.log` | `9760efea925f0a99bfe02ea122236b994be6e2312b86cd763d7adb7226f34cef` |
| `build-before-x86-detached.log` | `05773adc8b00390425e60d188c9069877a6551a90828622c0fb2f5849ae65fd7` |
| `build-before-x86.log` | `aced11f4680660adbdb42fc95e3914db84a50610537a4ffd818ec5f20854ee2a` |
| `compile-reference.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `compile-run.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `coverage-check.log` | `f14b0219fd4094c269a82b893f4a2424ffc8461e1745db3f9971f06dd81031fb` |
| `host-tests.log` | `38982595ce0cab14dc29586f5c995fc9f87e37fa0bc2ac00dc0421dede17ff8b` |
| `independent-artifacts` | `e866ebf8259586958e03ca6a51c5aba99154eb1b3d2bd8f6c2dfa3256caee382` |
| `independent-artifacts-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-artifacts-final.log` | `4e339339fdaa90fe3edf080c34e25e30ef43f01807e2d09075b5d9561ffd65a4` |
| `independent-artifacts-initial.log` | `23528f6a48f9322e471ba839fa511339e20d96d160eb6048ca08280c16c21827` |
| `independent-artifacts.v` | `0d18939216e2068e4e75aa2d092021a0875f303001afba33514a5ca7d46c2d94` |
| `independent-baseline-control.log` | `e93f9616f5e5f9672f18bc83270dfb37a0cbb0b6e9fc87a3ce1601d6ea5223f0` |
| `independent-code` | `7a7b580a3a8bd346f3c249171ba1dafdda996f8daa467adbf8cd10278f484373` |
| `independent-code-body.v.txt` | `1cd744f7f24c4dac291eb7da58da90c9b3e4a578fe95d1412142a7d6d655fd12` |
| `independent-code-c.log` | `f7b26ad5af7d3b840a997805249d4f82173d4d192d88b15b1cc7e23ae5b399ab` |
| `independent-code-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-code-compiler.log` | `a930e88517324163016ead0a221d7cb74f7171860d53093d44b44ec500ef318b` |
| `independent-code-source.log` | `7e5b922f56a2ba97fd3f8976505c35fe88f0ae30fc6dbda2fd66309813f825ea` |
| `independent-code.v` | `8a7d775024d87954b9d784ff0f4b7836ee163c6c2b297cc755eb0b10bcc65065` |
| `independent-controls` | `9aef66f603ab0819926c0b598da5cf2362c1a4c70a6b7b55608bcf8e9b317445` |
| `independent-controls-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-controls-final.log` | `68db9ffff3fa8623e31c12178404b8a2b8883aa1f887fec963743ec7701709d3` |
| `independent-controls-initial.log` | `2bcfe72fbee5025d8e26653e1f26a50b9c7f5f3a495b39b5ef9555648122dd10` |
| `independent-controls-negative.log` | `91f09c98f1c826d2f4fea53d8122e5c3fdb6f5ff7ee61278697701efe3cee1ea` |
| `independent-controls.v` | `64855cba7dcc5ab43daef62de343271f06f306204458c3dd41e8fa51bf57c147` |
| `independent-counts` | `ebf228c83f4def0d1e765ad1d80871860fd1f31e98e49548b835d67b18277558` |
| `independent-counts-after-arm.log` | `1554b0a3b2a3d2ce202c59882e364838275f09a23a15e734cfd9c23ecd126a49` |
| `independent-counts-after-x86.log` | `dd76fcdf9e98b4409c6abc6c33dae1ce5fd488439c918ce959937c46218bcfb6` |
| `independent-counts-before-arm.log` | `97fad6198b4074662a889d34d3f160c5559e66d468fc11a469c2511c6ac59f50` |
| `independent-counts-before-x86.log` | `494281755cc09ef7d8d9574cee68129eae436582cf4bf55bca568e33f97b58ce` |
| `independent-counts-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-counts-reference-arm.log` | `305e76e9e3ba6b52543c85d57cd78bdb9e8d222aadba6d11bc99ded234916d1f` |
| `independent-counts-reference-x86.log` | `1224b17d9abf50d0f11bdb018a3d86aa7f58445abd7cac6f1b302d6ee1759046` |
| `independent-counts.v` | `3fbb06e9dcaeccea8bcd99581a6e279dc9ee18e666b3d995a9f01422ae2477a6` |
| `independent-execute` | `d47b4640e839dea5e0585a30116b2ec40286ebf97e0cef9795bedd4a3f427455` |
| `independent-execute.v` | `3cbd8cb2461491f70b514310693069f53ad534229e3956e5906092ed53314802` |
| `independent-false` | `ab770180d38f71adfa1cac383a5ba9280bafd234c1f58b18b3c0e10b09f906c5` |
| `independent-false-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-false.log` | `e28cc1bb14d60773f01d661e4f45eb1bc709995859fbdf7c46920134d351bfb9` |
| `independent-false.v` | `27297871805fe9036fe2528c12295d7b2e07922f42704d22c792ac524dea0552` |
| `independent-fixture` | `2bd22669f90ffe3d8600ebf18cbac0974f55f45497a8796c500b8a61b011e0a3` |
| `independent-fixture-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-fixture.log` | `3368f24ed4c3e1527c6f4d1faa0281ec154e3d63f0aea2dcb9ed0e8eb97f16d5` |
| `independent-fixture.v` | `c24950daf94b7e052e8ed731afdc8102b55f336e541cb3c530e803a6c6c00b96` |
| `independent-maintained.sha` | `8b4f4f6a387c9cd0293682dc39317b9d9fb7d5b02f6fabaa2dc104b6fc51b214` |
| `independent-prepare` | `f894cfb10926ba373a0e2c95f7be0f605929c6e7145ef4c6e82ee02ce07244cf` |
| `independent-prepare.v` | `ccb05869b6d63f3b71e2c8abeb0185374140123c6b5a61b39113971699ffb79d` |
| `independent-provenance` | `e74e3200ec781b4bb10496c680a23f26d7de0ca4fd7db5438fb5991c54dac974` |
| `independent-provenance-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-provenance.log` | `f50743af5d656cf7b107d6f960aa2aa239706df2b75a51596ab5344cfa75ddf0` |
| `independent-provenance.v` | `1b9b686b45c4f986e8bbb47e341dea7eab1f54c19273157744624abd0ccb0bbc` |
| `independent-report` | `0ad8fd0f2528e4c57a17f663774d0ab1932e18f19e52d2458d533a1ca12a39af` |
| `independent-report-body.v.txt` | `8470ec84ecbddce6f9fd1888c3dfa92383c582d92fa33debfd95749cbeb777a5` |
| `independent-report-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-report-freeze.log` | `d6c87ab8b21f28be673d53ce7e1c81ab102d3bae436073002d809396a556532f` |
| `independent-report-prepare` | `84f8cccb9b94701deac6251572fab07a2cd14df53f92682c6d03f63fdf54ffb5` |
| `independent-report-prepare-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-report-prepare.log` | `3bbab4fd0cc46a5187c5388cedc35f03ce977c1995581aa599d130e444a65f31` |
| `independent-report-prepare.v` | `7180a7f328366c2b67747e998edd321bde74a514911272d71f72948d88d7b03d` |
| `independent-report-prose.md` | `7d85a1ab6ee33c36ae34d946ee8013c28864f2eea163904120568aefdc5c242a` |
| `independent-report.v` | `71051918226733e2845d24230ba18cde5582a38ce701de5e5cf726813b98a51c` |
| `independent-retained` | `607da62d65df4e2a308d3e8805a4126c1957b3440f8a12e2b86913742995ee28` |
| `independent-retained-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-retained-final.log` | `adca42b31bcda23d6b9063f5eb47890679278f7bb92dfd743bd93b5681799af3` |
| `independent-retained.v` | `148ece5a3869e641191dec6f059823f2a57482d659efbe175e67bfa2387fa4ce` |
| `kernel-arm/docs/linux-syscall-coverage.json` | `3a9292f94c2e854bec6fed3d2c06d75db7e90ccb7c210d391b2f26a53f13f091` |
| `kernel-arm/kernel/proc/container.v` | `f66753325982603ea72a325798e309d627c910d76df03d4fbc5744fd94fd4018` |
| `kernel-arm/kernel/proc/proc.v` | `81154124ce64e42994efe289fa371262a953eaa9cf01a37074b123a2e54a8a58` |
| `kernel-arm/kernel/syscall/table/linux_common.v` | `e02ca1595fcc117e237c44cfd5634218184c328592f9e4fcb82af3be15047f68` |
| `kernel-x86/docs/linux-syscall-coverage.json` | `3a9292f94c2e854bec6fed3d2c06d75db7e90ccb7c210d391b2f26a53f13f091` |
| `kernel-x86/kernel/proc/container.v` | `f66753325982603ea72a325798e309d627c910d76df03d4fbc5744fd94fd4018` |
| `kernel-x86/kernel/proc/proc.v` | `81154124ce64e42994efe289fa371262a953eaa9cf01a37074b123a2e54a8a58` |
| `kernel-x86/kernel/syscall/table/linux_common.v` | `e02ca1595fcc117e237c44cfd5634218184c328592f9e4fcb82af3be15047f68` |
| `kernel/syscall/table/gaps.v` | `e2ba41e28da260a4c91e30851096b7b9a3fc74376787c6f26f68c321957c7360` |
| `linux-sched-v6.12.c` | `a9c89bc6e1eca2587f39518718aa0a53fd8ef646f16927a0252e5fa7f25b5804` |
| `linux-source.sha256` | `828a563c1b01f45bf492129e1d6194103b5172fc520c49f1e8f224a449410d96` |
| `preview-arm.c` | `5dcf494da018b6c9315e9c047881510061d3631fa40b27c1a089aa3ecbbb21d0` |
| `preview-arm.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `preview-x86.c` | `5dcf494da018b6c9315e9c047881510061d3631fa40b27c1a089aa3ecbbb21d0` |
| `preview-x86.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `reference` | `2b70d1431db589653a309c98060c890e964fd22ddb3ae98e861847f75f15db5d` |
| `run` | `6dd05cbb40e93fe8da07eea2d762615929d2eedd5047d196f34790faa5247a75` |
| `states/p1-after-arm.log` | `9a6847fcf4aa50c73730238822c0daefefc785a9729a01495a341729e7074243` |
| `states/p1-after-arm/attrclass/fixture.c` | `5dcf494da018b6c9315e9c047881510061d3631fa40b27c1a089aa3ecbbb21d0` |
| `states/p1-after-arm/attrclass/init` | `d71703b6b0c45ee1a9b07e388354747bfc3b0c085d6c4a0e5e7c82b6bf5cd742` |
| `states/p1-after-arm/attrclass/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p1-after-arm/attrclass/serial.log` | `b97edd3a844e872c864773bee159275d41f2a2b977670fae4c261a3287159106` |
| `states/p1-after-arm/attrclass/test.iso` | `17ef5b5fdbc4d4d00f59dd18f50dbad8bafe9236b618c551316aaedfd3c34120` |
| `states/p1-after-arm/attrnice/fixture.c` | `16c678caf8594875e8a3cb4b663125e7d627aa73ec339e83d20c4850d812ce54` |
| `states/p1-after-arm/attrnice/init` | `cc88302a486072416ef3c9b193a008ed10d1b074f23d0ed032e586200e20afeb` |
| `states/p1-after-arm/attrnice/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p1-after-arm/attrnice/serial.log` | `a9b6e6192b30033c895093238512903887c67f46fb7c17e751d61957c5b356e4` |
| `states/p1-after-arm/attrnice/test.iso` | `4ed4d6b2f5aef6b52df00390c395763e24d73c1180fc16a3cae85c3f98beed01` |
| `states/p1-after-arm/attrquery/fixture.c` | `f964f8585bfbe91601cf581f04d25b1b02f2fd55e5dc31fa7782a9f9e6f60c3a` |
| `states/p1-after-arm/attrquery/init` | `43da21bb9f97a38755442078b7396f5ff8924e01ea9fac6117fc5cf86ed6f770` |
| `states/p1-after-arm/attrquery/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p1-after-arm/attrquery/serial.log` | `e5082d70a459b9d331ea1a217a61ead5d274dfe8976040371997595e4bdeb9d1` |
| `states/p1-after-arm/attrquery/test.iso` | `8321f74b0b87b0777a423a22f8e82eeba8ccf8c2fae8c3763c727f9419fc79e3` |
| `states/p1-after-arm/idleexit/fixture.c` | `dadb30c550b7716a17d8de2a95b7a7e452c899e9859fb6411ed855651301266e` |
| `states/p1-after-arm/idleexit/init` | `b43fe316b9a5b701483d30383eb00952437a76a37886a5e91222c2da9ba0bf36` |
| `states/p1-after-arm/idleexit/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p1-after-arm/idleexit/serial.log` | `fbf23eee8cf52a33597f795ec470580f9d6faaa33e4daa792a7236da5dfa16d2` |
| `states/p1-after-arm/idleexit/test.iso` | `aee32deba99e030a4d061260335e251b2144acb976fd5fc6ff9dcf5d890a51a8` |
| `states/p1-after-arm/kernel/bin/vinix` | `0d6e8e135e715f80284b87bea00bc509aec642fa85a9600b0fb8179983929f65` |
| `states/p1-after-arm/receipt.json` | `50b3767da676491834fa773b95b48557d4326fdf72925e6fe483b48b20f86faf` |
| `states/p1-after-arm/rrabi/fixture.c` | `8e8669868533c177310e4946be416d0a371d4ae6348e0045951861481682b48b` |
| `states/p1-after-arm/rrabi/init` | `c4fa4490cfc1f9997ab8018831a242c1c4fdc5099bb6c59bbccceb1b88890f5a` |
| `states/p1-after-arm/rrabi/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p1-after-arm/rrabi/serial.log` | `b6f1c07f4061be4b8161907bd3be112552782b39be6cc9eb0ce2f3ae456c5e62` |
| `states/p1-after-arm/rrabi/test.iso` | `39522991ec6e9aa986a11c8902dfbe060776de91a37393e021e2bb29c2d4bd7b` |
| `states/p1-after-arm/rtadmit/fixture.c` | `39de3142b70a4010c57ec795942e5d46789b82d4aeaa4f94fcc0d55cf4416b73` |
| `states/p1-after-arm/rtadmit/init` | `9ee0054e1cef050db8da9414801ad38bf4a2999da5c6ed5f825c85673d10db75` |
| `states/p1-after-arm/rtadmit/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p1-after-arm/rtadmit/serial.log` | `d899fa41454a5ab75cf100da765a680e620773dc398901508d8892250bbbdc6b` |
| `states/p1-after-arm/rtadmit/test.iso` | `f3aa588ef9c5b63c80d6fdf069e94264cd8f1310e096803d092bfddc1e37a65a` |
| `states/p1-after-arm/runtime/fixture.c` | `05967a3ff8bb35aafaf2e91e58e1203b35780818a33b84031590b52943d60128` |
| `states/p1-after-arm/runtime/init` | `a27160c033a470689dafc283d37636bb5b81b1344d19e93a2c6071701187e44b` |
| `states/p1-after-arm/runtime/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p1-after-arm/runtime/serial.log` | `9fe5b350e7dfce2a1660201b296f5eed6d7a38e1caee2cb850082f7cc16ec206` |
| `states/p1-after-arm/runtime/test.iso` | `29599666a41d52c92c81db1c03f400c3685fc902fc200d9584d425009806344f` |
| `states/p1-after-arm/schedabi/fixture.c` | `8fff587a11dd1c2fe123b264c674428e7330f509e70451d37fd572ee0ea5c154` |
| `states/p1-after-arm/schedabi/init` | `aaf0c1175a0b32bee276fc84f5619c7c468643a97337fb4ee44b45900b81af18` |
| `states/p1-after-arm/schedabi/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p1-after-arm/schedabi/serial.log` | `aba23cbdfcc179ebde593dbdd2bcd46d616c0c2b49b2af0e5642bbd1bec4b122` |
| `states/p1-after-arm/schedabi/test.iso` | `25a858547e3d7de08f3af8c22025ef65b10d0021782658481a5c7d86028369df` |
| `states/p1-after-arm/sources/attrclassfixture/core.v` | `527154129f3f9c53e4edc8b0594c1671773bdbf33ab82ece859a8f5f64ea9249` |
| `states/p1-after-arm/sources/attrnicefixture/core.v` | `42f45edd6322c95037aa848404275527503570ab70929f9678c60db82701fb59` |
| `states/p1-after-arm/sources/attrqueryfixture/core.v` | `ece9c957e365646f3f37aefef75b5ff7540c58da876a1764eb67fff46b557c9b` |
| `states/p1-after-arm/sources/idleexitfixture/core.v` | `0f972fdc0e42dba9ebff249c731c4cd884a9fd3430915a30dd0e2adaaea4e611` |
| `states/p1-after-arm/sources/rrabifixture/core.v` | `1dbb6631fbff3080966eaabecb56c4efa37b53bb3df2979ad68da9be7e8b874e` |
| `states/p1-after-arm/sources/rtadmitfixture/core.v` | `e35b0fe0a165cc8190f9a9637e10287888156c75d245d589db6cd14d5584a741` |
| `states/p1-after-arm/sources/runtimefixture/core.v` | `e23fb687c349c454bb7ad310c0c251e4968131781ff5eadb4b2488bd2fe7b6f6` |
| `states/p1-after-arm/sources/schedabifixture/core.v` | `de18a603b819a8534ec998e1229c6b6b5103bfe515bff8e81b81ee78b9c21d7d` |
| `states/p1-after-x86.log` | `9af2b46cde00817b0b89bbf6ff9432a81815e3dfa94b47d36ee91237dee48951` |
| `states/p1-after-x86/attrclass/fixture.c` | `5dcf494da018b6c9315e9c047881510061d3631fa40b27c1a089aa3ecbbb21d0` |
| `states/p1-after-x86/attrclass/init` | `3438d688b513a03233308a6c2fb418a3176a97a434bd387d10051f6c08028861` |
| `states/p1-after-x86/attrclass/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p1-after-x86/attrclass/serial.log` | `2cbccf3d4af3105dd5b54e962990afc332a6fdd303c4462899a03cefea212fbd` |
| `states/p1-after-x86/attrclass/test.iso` | `ed3f928dbf03921e51124a31f4de6d289ebeae3eef91e363fe1577d710425fe4` |
| `states/p1-after-x86/attrnice/fixture.c` | `16c678caf8594875e8a3cb4b663125e7d627aa73ec339e83d20c4850d812ce54` |
| `states/p1-after-x86/attrnice/init` | `d69ffafc9b23ce6ac63a458cf1de887959c250adad6131441ee236e56a86a6ff` |
| `states/p1-after-x86/attrnice/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p1-after-x86/attrnice/serial.log` | `9b5771ace176ed3b40e1ecfbf4e652a31e5c652ca0d307067627bfa3ab198879` |
| `states/p1-after-x86/attrnice/test.iso` | `1a965ad0594f0b0c7c5b7a778af89df02845772a901f24f6f8fa03dc7ae62451` |
| `states/p1-after-x86/attrquery/fixture.c` | `f964f8585bfbe91601cf581f04d25b1b02f2fd55e5dc31fa7782a9f9e6f60c3a` |
| `states/p1-after-x86/attrquery/init` | `b2423eca23720766ec649e5facedeba510dc23496bf84d67d4dcde523b749c22` |
| `states/p1-after-x86/attrquery/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p1-after-x86/attrquery/serial.log` | `d38724059f56982121e91b9275fd1f41df4a2ea05cb472595b7ca6d33c84e128` |
| `states/p1-after-x86/attrquery/test.iso` | `5dbb29f8e914ecec8d41d8ed733d5c21aae6234e052077c923cd451a2526771f` |
| `states/p1-after-x86/idleexit/fixture.c` | `dadb30c550b7716a17d8de2a95b7a7e452c899e9859fb6411ed855651301266e` |
| `states/p1-after-x86/idleexit/init` | `34bd20253e1208f5b2e2047528829541d1dd4e57fc82d50a40c1d7de56a59c8d` |
| `states/p1-after-x86/idleexit/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p1-after-x86/idleexit/serial.log` | `8afabbd784514586b761ee64b41a977f4fbff26831e3b8c8c136f01acd187cb1` |
| `states/p1-after-x86/idleexit/test.iso` | `d97c409ed9c5bf3e492568f544980fe7c53ac572426ddedd696c2606fddcb54a` |
| `states/p1-after-x86/kernel/bin/vinix` | `883309f6c15e8267647519ea56a10c9423ee7db58da8f7426bad3bb4f136332f` |
| `states/p1-after-x86/receipt.json` | `a7a1519fa6e04976fb556e2a475195299d6e8742e016bc15a7f0c787588029e4` |
| `states/p1-after-x86/rrabi/fixture.c` | `8e8669868533c177310e4946be416d0a371d4ae6348e0045951861481682b48b` |
| `states/p1-after-x86/rrabi/init` | `30dac28706d071bfc98643a65db8ec9ebea3854430f9f944bf7843140e7df680` |
| `states/p1-after-x86/rrabi/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p1-after-x86/rrabi/serial.log` | `624e788d876428e0aed4825c0c80d04190d07e69c027adf52f2fe693143e17b9` |
| `states/p1-after-x86/rrabi/test.iso` | `ff864518be1877416b8e7011bb16537804bc0bcc42fdf01e031cb18762ea85a9` |
| `states/p1-after-x86/rtadmit/fixture.c` | `39de3142b70a4010c57ec795942e5d46789b82d4aeaa4f94fcc0d55cf4416b73` |
| `states/p1-after-x86/rtadmit/init` | `0ccc1f8e6df0eb2884e161876c2c9f466fa60ab814839822c3448468d8df81a1` |
| `states/p1-after-x86/rtadmit/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p1-after-x86/rtadmit/serial.log` | `4e2f0082097e9b8b2e7f28f6e2b2711e539d23ea0cf7338d274467783fc5f155` |
| `states/p1-after-x86/rtadmit/test.iso` | `679288ba49d35a08dc3b0d7728a0008d61d6eb3df239bb1a1cb27e1e0484c419` |
| `states/p1-after-x86/runtime/fixture.c` | `283ee3218dbf04ee7c3289110ff0be3044906d48556453b06b7de972f4950e3b` |
| `states/p1-after-x86/runtime/init` | `3c22f6e44700a031e0c6e9bd04427095e423d595d3f9b81e09f07539d1ea3b9f` |
| `states/p1-after-x86/runtime/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p1-after-x86/runtime/serial.log` | `0a8088397a56749f4b5b8275d36d23b60de5eafe640a5f6e4470d7e66b45c8cd` |
| `states/p1-after-x86/runtime/test.iso` | `aecc830a4cac8b5e34fc4df2d924c4167a20bab347ecce1faaa76bb07af8d5cf` |
| `states/p1-after-x86/schedabi/fixture.c` | `8fff587a11dd1c2fe123b264c674428e7330f509e70451d37fd572ee0ea5c154` |
| `states/p1-after-x86/schedabi/init` | `6e0d896226ce58749fefe9d9fa411596aa5a9f1581f88b92c469574f541b3a8a` |
| `states/p1-after-x86/schedabi/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p1-after-x86/schedabi/serial.log` | `2e915e07cc814a90a3e7a7ac164a237bd5320b3d65ca90497240c582f2371ac7` |
| `states/p1-after-x86/schedabi/test.iso` | `09a0ab665718131fb98bc9ea7c0f92b1743c41f5fd50649607e356e168137c0f` |
| `states/p1-after-x86/sources/attrclassfixture/core.v` | `527154129f3f9c53e4edc8b0594c1671773bdbf33ab82ece859a8f5f64ea9249` |
| `states/p1-after-x86/sources/attrnicefixture/core.v` | `42f45edd6322c95037aa848404275527503570ab70929f9678c60db82701fb59` |
| `states/p1-after-x86/sources/attrqueryfixture/core.v` | `ece9c957e365646f3f37aefef75b5ff7540c58da876a1764eb67fff46b557c9b` |
| `states/p1-after-x86/sources/idleexitfixture/core.v` | `0f972fdc0e42dba9ebff249c731c4cd884a9fd3430915a30dd0e2adaaea4e611` |
| `states/p1-after-x86/sources/rrabifixture/core.v` | `1dbb6631fbff3080966eaabecb56c4efa37b53bb3df2979ad68da9be7e8b874e` |
| `states/p1-after-x86/sources/rtadmitfixture/core.v` | `e35b0fe0a165cc8190f9a9637e10287888156c75d245d589db6cd14d5584a741` |
| `states/p1-after-x86/sources/runtimefixture/core.v` | `e23fb687c349c454bb7ad310c0c251e4968131781ff5eadb4b2488bd2fe7b6f6` |
| `states/p1-after-x86/sources/schedabifixture/core.v` | `de18a603b819a8534ec998e1229c6b6b5103bfe515bff8e81b81ee78b9c21d7d` |
| `states/p1-before-arm.log` | `ad0fac9b07587a1af81620202cbbc5122af22ea06caad2b7aae9372089f1c014` |
| `states/p1-before-arm/attrclass/fixture.c` | `5dcf494da018b6c9315e9c047881510061d3631fa40b27c1a089aa3ecbbb21d0` |
| `states/p1-before-arm/attrclass/init` | `d71703b6b0c45ee1a9b07e388354747bfc3b0c085d6c4a0e5e7c82b6bf5cd742` |
| `states/p1-before-arm/attrclass/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p1-before-arm/attrclass/serial.log` | `bf9634179c22f27e0ef3dc2cb5920764e8a1b45a0ddacc310555f281a76012b4` |
| `states/p1-before-arm/attrclass/test.iso` | `0c79a994c7c07c4e45170270dc75d05e8e511cbc23bfbab4d5c842e62c46cec1` |
| `states/p1-before-arm/kernel/bin/vinix` | `84c85b63935356cf9aec7ffe40889ecdb8abfe0113e18f49d6ffa5f0e8e1f825` |
| `states/p1-before-arm/receipt.json` | `a5e5b2fa044fd123e21c4de1249ffbaa2cb70467af3b98b31e99556d62940832` |
| `states/p1-before-arm/sources/attrclassfixture/core.v` | `527154129f3f9c53e4edc8b0594c1671773bdbf33ab82ece859a8f5f64ea9249` |
| `states/p1-before-x86.log` | `ea9cbd36a22ccad8f48a04b709d7c8e10cef239e84a424371916a50805e380ca` |
| `states/p1-before-x86/attrclass/fixture.c` | `5dcf494da018b6c9315e9c047881510061d3631fa40b27c1a089aa3ecbbb21d0` |
| `states/p1-before-x86/attrclass/init` | `3438d688b513a03233308a6c2fb418a3176a97a434bd387d10051f6c08028861` |
| `states/p1-before-x86/attrclass/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p1-before-x86/attrclass/serial.log` | `e63974d9cfd621ebcbfbdce8f9bfccd8a933eea9c1809054544443081963b4a4` |
| `states/p1-before-x86/attrclass/test.iso` | `4c4e863875f951573bf8fc7df2d795b9ed3fd21aacdc901ff11d0520c07aac3f` |
| `states/p1-before-x86/kernel/bin/vinix` | `9e3c73b8d64cb3c3af1586108a1832b66bac4b2641eecfb26445a408a0f31707` |
| `states/p1-before-x86/receipt.json` | `e1f6fc5b905c8c49ab40e713182ebec3b51b2c7819c690ae689e589fd0ae923a` |
| `states/p1-before-x86/sources/attrclassfixture/core.v` | `527154129f3f9c53e4edc8b0594c1671773bdbf33ab82ece859a8f5f64ea9249` |
| `states/p1-reference-arm.log` | `a0445d5599be42ce1ed9077d0b197a021f939ba46e54e909298ecbdcc07dd19e` |
| `states/p1-reference-arm/fixture.c` | `de9742c72d6252601fccc23630b16f986ca93f0e683fba53707c7f48e7c6ca17` |
| `states/p1-reference-arm/init` | `a02cc983ada6ed30846ec96bcf5a4b9bb957d5722482829fc66607dcd51f5265` |
| `states/p1-reference-arm/initramfs.cpio` | `1d1d5e2bc087200aa1caf94b28257fc41f8d0d7c064f2d948326897cdf24be43` |
| `states/p1-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p1-reference-arm/probe` | `d71703b6b0c45ee1a9b07e388354747bfc3b0c085d6c4a0e5e7c82b6bf5cd742` |
| `states/p1-reference-arm/receipt.json` | `797db15f297b40671c72fcd54f95c093488b464ea4f4238893a3c69b887469a2` |
| `states/p1-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p1-reference-arm/serial.log` | `2c6012b7ea1f4ee16a1903f16a62ad73381c49eff3e40bf0ec1b7828ed35fb18` |
| `states/p1-reference-arm/source/attrclassreferenceinit/core.v` | `c3b852ec67e0de44e81a5deeb478706f9f7610484d243cbb0c3b9a17df8337f1` |
| `states/p1-reference-x86.log` | `97b0f5d14615a20f18840d04073699a18820edc3b2bccb728c50888b44f06749` |
| `states/p1-reference-x86/fixture.c` | `de9742c72d6252601fccc23630b16f986ca93f0e683fba53707c7f48e7c6ca17` |
| `states/p1-reference-x86/init` | `496311eb79e2bfef822019902e72c17b969bb1982ebca6d8a04bdc0d578a3b77` |
| `states/p1-reference-x86/initramfs.cpio` | `98c751a0d53a1a789a4c790ab1e921c60da837c34ad6bd159b599f0f2e9fa9fa` |
| `states/p1-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p1-reference-x86/probe` | `3438d688b513a03233308a6c2fb418a3176a97a434bd387d10051f6c08028861` |
| `states/p1-reference-x86/receipt.json` | `ded3d47f9d2883b2d75277ede85ef1ea634528086e9d6d29704d0c12707d9f10` |
| `states/p1-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p1-reference-x86/serial.log` | `d8e2b610cd5b035987ef1acc07c92488dd7f7c5b8f12a4d0b8b68b55554ece96` |
| `states/p1-reference-x86/source/attrclassreferenceinit/core.v` | `c3b852ec67e0de44e81a5deeb478706f9f7610484d243cbb0c3b9a17df8337f1` |
| `states/preflight1-attrclass-arm/fixture.c` | `5dcf494da018b6c9315e9c047881510061d3631fa40b27c1a089aa3ecbbb21d0` |
| `states/preflight1-attrclass-arm/init` | `d71703b6b0c45ee1a9b07e388354747bfc3b0c085d6c4a0e5e7c82b6bf5cd742` |
| `states/preflight1-attrclass-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/preflight1-attrclass-x86/fixture.c` | `5dcf494da018b6c9315e9c047881510061d3631fa40b27c1a089aa3ecbbb21d0` |
| `states/preflight1-attrclass-x86/init` | `3438d688b513a03233308a6c2fb418a3176a97a434bd387d10051f6c08028861` |
| `states/preflight1-attrclass-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `tests/linux-compat/attrclass-check.v` | `c62a774fcd5e35bf89cdecca4cbe84c7081f4d104a71ab61650813978c16e969` |
| `tests/linux-compat/attrclass-reference.v` | `6041e01dc239945fb70e58f4b16370d6176a60a13ec592b4f618d93ecb6251d3` |
| `tests/linux-compat/attrclassfixture/core.v` | `527154129f3f9c53e4edc8b0594c1671773bdbf33ab82ece859a8f5f64ea9249` |
| `tests/linux-compat/attrclassreferenceinit/core.v` | `c3b852ec67e0de44e81a5deeb478706f9f7610484d243cbb0c3b9a17df8337f1` |
| `tests/linux-compat/run.v` | `628c95b01b13e0bb3187ecb778c81a0e5ddf8214a2fc9fbd7215d5064637727a` |
| `watch` | `84c51d8dc0768ccc337d5a37021aa0bce764b71bab9174d7d9a6f6a294720ca7` |
| `watch-detached.log` | `dd026833b18cdf32b0073cc9ef53162f9cad6d281372c594cb80037eab317730` |
| `watch-retained-inputs.json` | `fc475cb78cbf5448a7ed02c5628df73569ddcf9cff5dae55703d17c78c48f100` |
| `watch.log` | `3bd85808cfa520cc0c2771fc29a6a8d7cb8023a2b626ec93ce2af266132950fd` |
| `watch.v` | `c0e4297b28bcb044e7e95e235b16fcac205eca0a9fb79726adcf8c747f96e90c` |
