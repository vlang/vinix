Independent rtadmit lifetime review: PASS

Reviewed the native realtime admission change against frozen baseline `37cfa0db2a2af906eb621733a3d4c0ead6ac48e9`, original/corrected production V/C, final fixture/reference/controller/auditor source, matching preflight C/ELFs and actual native/Linux captures on both architectures. No new lifetime blocker remains. Qualification covers stable single-thread process leaders, target resource limits and observed policy/priority/nice state.

Kernel source changes only may_set_sched_params and its adjacent comment. After removing this one definition, source matches with that exact comment replacement. Generated production C matches byte for byte outside the one existing helper, without compiler identifier normalization. No allocator, usercopy, scheduler mutation or task lookup implementation changes. The helper still borrows its caller through the running task and target/owner under the existing PID-table lock, then returns only a bool. Target RLIMIT_RTPRIO, current policy and priority are scalar reads. Generated C retains one lock and changes nine unlock sites to ten solely for the new zero-limit policy-switch return, including the existing unreachable final defer release. No pointer escapes or new allocation/free occurs.

The target's aligned soft limit is read through the unchanged proc.soft_limit helper. Validated FIFO/RR priorities are admitted within the target limit or at/below current priority; changing RT policy with a zero target limit requires effective CAP_SYS_NICE. Existing MAC, real/effective owner, capability, deadline and ordinary-class checks remain exact. Authorization and subsequent scheduler mutation acquire the table lock separately; identity, credential, limit and concurrent scheduling races remain unqualified. Linux's pinned v6.12 user_check_sched_setscheduler reads the target limit and uses the same zero-limit switch/current-priority conditions. Actual supplied Linux 6.12.51 kernels provide separate behavioral references.

Each final probe has exactly 25 explicit alloca sites matching V source. Independent C checks find no heap, dynamic-array or fixed-index helpers; preview C equals actual preflight1 C on both architectures. Attr, sched_param, Limit, Message and Counts storage stays live through synchronous syscalls and pipe I/O. The new broker action 4 uses the reviewed exchange: positive registered child/peer PID, initial OTHER0/nice0 restoration, OTHER0 or FIFO/RR1..99 request validation, requested-state verification and then acknowledgement. No stack pointer crosses the pipe or survives the synchronous call. The privileged parent restores state despite ordinary credentials or original-kernel defects.

Peers close inherited broker ends, signal readiness and block until released. Registered same-owner and UID1001 peers keep soft RTPRIO limits 20/40 and hard 99; callers cycle soft limits 0/20/40 with hard 99. Actual single-thread leaders include self, same/cross-owner peers, absent and already-reaped controls. The test uses current OTHER0, FIFO20/99 and RR40/99 through all three raw setter APIs, with real scheduler/getattr/raw and musl getpriority observations. Each Query immediately snapshots errno. Repeated paths preserve nice0. Full capability snapshots and caller final limits/state are checked; peers are released and reaped, mappings unmapped, final Counts transferred before storage expires, and the parent waits before reporting.

Guarded mapping has three pages, with the final page inaccessible. Aligned, unaligned, read-only, inaccessible and NULL input forms stay within the mapped readable prefix when compared. memcpy/memcmp avoids unaligned structure dereferences; input bytes and eight-byte guards remain unchanged. Upper PID/policy/flag words, signed low-word extremes and actual error ordering are exercised. Five logical operation choices cover FIFO/RR sched_setscheduler, sched_setparam, and FIFO/RR sched_setattr.

Counts independently recompute to [5400,1440,7680,1039] per cohort, 15559 each and 31118 per architecture. Kind 3 contains 480 negative-PID/priority/buffer checks, 72 invalid-flag checks, 480 extreme-priority checks and seven default/final controls. CASES and FINAL rows require exact counts, unique cohort/kind keys and equal outcomes. Both original kernels fail [434,74,148,0] in each root/UID1000 cohort, 1312 total per architecture. Both corrected kernels and identical-ELF Linux 6.12.51 references pass all 31118 with zero failures. Native ARM uses 16384-byte pages and x86/Linux use 4096-byte pages; actual peer IDs and both UIDs are checked.

Both native cohorts run 32 warmups and 200 retained-task cycles, with 13-second settling periods before snapshots. Cycles cover same-policy lowering above zero limit, denied zero-limit class switch, target-limit admission/refusal independent of caller limit, and privileged cross-owner admission. All 18 ARM/14 x86 slab classes remain flat, as do large pages 85/85 and 216/216. The observer remains open through snapshots and closes on nonfatal paths. Its local 4096-byte stack buffer bounds pread and termination, and snapshot arrays cap rows at 32. Measurements qualify these retained leader/broker paths; they do not qualify full process creation/exit or scheduler timing.

Independent provenance checks rehash all 15146 pinned compiler inputs, both private 64-input inventories, four fresh production build outputs and native/reference receipts. Eight host test files and four inventory checks pass. Before/after allocation reports are byte-identical at 398 ARM/290 x86 sites; existing allowance refusals remain explicit. Preflight ELFs match original/corrected native and actual Linux probes. References bind supplied kernel, probe, wrapper source/C/ELF, initramfs, serial adapter/log, QEMU and controller, requiring passed/finished/forced=true and status=0. Wrapper argv is one stack allocation valid through execv. Hash readers close files and free scratch buffers; host process handles close after synchronous completion.

Both full eight-case native receipts and aggregates pass: rtadmit, runtime, schedabi, rrabi, attrquery, attrimport, attrnice and fcntlabi. The watchdog records exactly 18 distinct native captures: two originals and sixteen corrected cases. Every actual source/C/ELF/ISO/kernel/serial/receipt is bound, and retained files are rehashed after only unbound boot staging and firmware variables are retired.

All 310 retained preparation files independently rehash. Initial baseline producers and the allocation scanner could not open their output logs during disk pressure; no producer output, build/scan verdict or baseline kernel was retained, and that output cannot be reconstructed. Existing regular generated objects were copied before fresh successful builds/scans. First preflight import attempts refused before creating probe state/C/ELF; private module symlinks were corrected before genuine successful preflights. These preparations remain separate from final builds and guest verdicts. The reviewer also retained its early missing-preflight identity refusal with source, executable and output; the final preflight proof passes after actual artifacts exist. No failed preparation is interpreted as a semantic verdict.

Independent helpers are compiled without -prod. A false assertion and the passing ARM Linux capture supplied as an original-failure capture both actually exit 1. The maintained auditor's source/C scope, exact counts, storage, compiler/inventory, receipt and publication protocol were inspected independently. Implementation, publication audit and commit remain with the parent; this review changes only its owned report.

Worker-thread qualification, target/credential/limit races, complete realtime timing/execution, IDLE exits, reset/deadline/utilization transitions, namespaces and MAC configurations, GNU libc, translated/ELF32 and broad roadmap section 15 gates remain open.

SHA-256 pins were independently recomputed after producers completed. Paths are relative to `/Users/alex/.cache/vinix-linux-compat/rtadmit-20261015`, except repository paths starting with `kernel/` or `tests/` and absolute compiler paths.

| Artifact | SHA-256 |
| --- | --- |
| `/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler-inputs.json` | `fbcba16306f70092c3b0df0cad3776ab7c3e8be13ef1a4797a07b21f3dd71074` |
| `/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v` | `9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b` |
| `after-arm.c` | `a058adc524a11bd400d0689d5acb049619f0fc9b6fa27f542aa4e6e42755184e` |
| `after-gaps.v` | `4378a6f9d70ab72f884c5d5725ce900d67c310a63976cbc7ee561ef361cafdfd` |
| `after-x86.c` | `d41ce1bb8b5efe9c075c8665f9e85ebc1b7ae987fb5d534ed762ccae2a48f71d` |
| `allocs-after.log` | `b2b9a4202b7ae0a9f9a3785ec54e09f7854cd5f313b23f0b89a1091b42ffd403` |
| `allocs-before.log` | `b2b9a4202b7ae0a9f9a3785ec54e09f7854cd5f313b23f0b89a1091b42ffd403` |
| `base.txt` | `e114322884226f07b8bd9d54d6ee760b369e5718a8bedc1e4c395adb25a252c6` |
| `before-arm.c` | `827de7632e275b3472108b1808c4d1d9c2d84bc58eb81e653ef7900f63c5e076` |
| `before-gaps.v` | `a8b4735d5226e9b9d551b18963486b90edc34fd5ebf946e620f48de7badfe1d0` |
| `before-x86.c` | `0cb7194e6ce960dc40eeb900e442e659b34539c4606b541bafd9e1ff3c918bd2` |
| `build-after-arm.log` | `a11246a93f1421c6375fb37f807b796a878559dab720dcffa46bc3717c2beea0` |
| `build-after-x86.log` | `2d5e10d2f6994608b4a9216cb7e54aceba405a617cf5a655123a9c6f25618fb5` |
| `build-before-arm.log` | `fe285537a011dbe27b9040e6f351b2c18cd43a8193a20ec40592db90aa90bee8` |
| `build-before-x86.log` | `8a124cbc7e5ca102672623711715eaa824e430217061f41127430c08b669112e` |
| `compile-reference.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `compile-run.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `coverage-check.log` | `f14b0219fd4094c269a82b893f4a2424ffc8461e1745db3f9971f06dd81031fb` |
| `host-tests.log` | `725d44a0d783f108875585de217ea5d4ab8770f4546a1735ede0069d0504c2a6` |
| `independent-artifacts` | `b2a11934bd7f663cc2b485742d10bcee12d364f14e70870cb9a1e9024b40a3df` |
| `independent-artifacts-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-artifacts-final.log` | `57ffb0a7d1dbff7e81aa9ae1511f3f3e4d19451749ec2e75ff958df7209578fa` |
| `independent-artifacts-initial.log` | `957ce7ba3f44a7ef07b3d4059a6c85b1faa092cbc32bba53e07564a4fa2b3655` |
| `independent-artifacts.v` | `268926da45e8c3f615a4bae154f2082d0ec96669f07a12be00cc90584d13dcac` |
| `independent-baseline-control.log` | `0b8e1c60406a731bf8d59f0a92ba6b17ed4e5d15114d19dbc8d9e4d66cff3ec5` |
| `independent-code` | `b69d0b5fd0fae6b023b784d7fdfa48b176648ea535d0bb66441f4567281da339` |
| `independent-code-c.log` | `86c4700b50db4fd5492c44fbad678d4d7ef5fe8ca9c007c0031ee6fed9128f6d` |
| `independent-code-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-code-compiler.log` | `398fee3bbf1a348631f989e6d5a8d81dc843adbd64ea98941bd5e364135eced2` |
| `independent-code-fixture.log` | `cb5ede0d9957d2d360b538c2c25959168d7a0b5cf042c4e8cecda85ce8b689d0` |
| `independent-code-source.log` | `6e72c35afc4518f9bc15eac0a5d37a73e0e50ce43aeb8895e005a4e0c5d8129a` |
| `independent-code.v` | `3dfd6e82c5179bc263cd6218f8d5b2f5a201d2b5dbbdb1b582f5f25a6523b7b9` |
| `independent-controls` | `844488071a4d13f57030d75725ce516fe1162e5fba2b11a1296ae414d27fd6e4` |
| `independent-controls-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-controls.v` | `5b47b1a46a7c538c0af0891134f659df60341a49455b907b68cfeaca98379713` |
| `independent-counts` | `54d3a41dcaa47e82b982bb9f843c3978cf2299c59534586bd34daf93e4479ea3` |
| `independent-counts-after-arm.log` | `566f2e68f1868b8daef4262eddecaf0055eaf79033ab77b65e2137ffdbce07e2` |
| `independent-counts-after-x86.log` | `40e72c4878d90d349c774379aaa6d2b9d2506e82e51d952449740771c3e22481` |
| `independent-counts-before-arm.log` | `ba473730f4b3c261c27572a3589a8903f7c3972340439a2a12c16c11d484e7a6` |
| `independent-counts-before-x86.log` | `f4293254aaab8a3b7d011eb34188b71e645d18ab2da159b4789ac96db58b9def` |
| `independent-counts-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-counts-reference-arm.log` | `dbbbe017d3ddf0276779e01ce902f68609d677eecfa34a58142bcb2dd04dfa04` |
| `independent-counts-reference-x86.log` | `2b28fd2026dcbd3b2c48d0c772148d5c688fed53b183b0eb4adedbd6cceb161b` |
| `independent-counts.v` | `f1cc64e8fb114a54bc2ff9450ab2eaa825ceaa86e862fd9ac0d8227dacc5cb3c` |
| `independent-execute` | `1ced367aeaffa86e6a4ce2907c0a3963f55a2c9c74054cdf1521e2b4bf11cf78` |
| `independent-execute.v` | `121de9630f0ffdba7af20c93caaeb8a37168c4786fca654b5278041f25e63ea8` |
| `independent-false` | `8c8d235dc95412a97f4f4aad9e5c0ee11d07335bc0f5fd8225deefe7bf8a71fa` |
| `independent-false-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-false.log` | `03c533bc0e64154997739e27ee42adfcefa8ee09b35c3c3a14e147bea3cabb68` |
| `independent-false.v` | `10edad0aff1b8bb77a8adf701d2706489abbc09d1eae694c6ba6ddee209b6081` |
| `independent-provenance` | `41cfde8d708fc5f439eaaed17832a44df834c52fb23118199c217eea38cf0aa5` |
| `independent-provenance-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-provenance.log` | `735c2d79fd750390a0035a5c261d7a4c380cff89897c32c3a6a57b9c41780e30` |
| `independent-provenance.v` | `2df2da67f62630a4785b11a489885d5005e0f875d38c2fc2aa2ac0ec90990aec` |
| `independent-report` | `9b15bd6537e93ef9620c292e70d3004dd023fa2d35842804c507dfe0cee566bf` |
| `independent-report-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-report-prose.md` | `b6a86d15084b6a6ec095509312437d64b187b039a9cc0cfb571cd2f66ab99d61` |
| `independent-report.v` | `251b714e274bf4919966e1660051b2787a72416360e4fd08b3fe2b63b2d3ec9a` |
| `independent-retained` | `c609f9d99b1fa09ce9f1e7998c832820c77d6679209c32b10427591d7b8900ba` |
| `independent-retained-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-retained-final.log` | `90a9da8fc2a67e714762bc31223848c742c7ec1001c6358eca2e47626eb6047a` |
| `independent-retained-preparation.log` | `12c5627b32f1aab1dc28f5d0021fa2da457055772a8204f83c50e854a072c5ad` |
| `independent-retained.v` | `b2f145cbd32d5fce4d96689350de71fe4145cacee06dcb579638fb7a17e7fb63` |
| `kernel-arm/docs/linux-syscall-coverage.json` | `55a34610a72546634f0202ea1b0b75d0cf8e95a0900c6907ca8f475ced7a8067` |
| `kernel-arm/kernel/proc/container.v` | `f66753325982603ea72a325798e309d627c910d76df03d4fbc5744fd94fd4018` |
| `kernel-arm/kernel/proc/proc.v` | `81154124ce64e42994efe289fa371262a953eaa9cf01a37074b123a2e54a8a58` |
| `kernel-x86/docs/linux-syscall-coverage.json` | `55a34610a72546634f0202ea1b0b75d0cf8e95a0900c6907ca8f475ced7a8067` |
| `kernel-x86/kernel/proc/container.v` | `f66753325982603ea72a325798e309d627c910d76df03d4fbc5744fd94fd4018` |
| `kernel-x86/kernel/proc/proc.v` | `81154124ce64e42994efe289fa371262a953eaa9cf01a37074b123a2e54a8a58` |
| `kernel/syscall/table/gaps.v` | `4378a6f9d70ab72f884c5d5725ce900d67c310a63976cbc7ee561ef361cafdfd` |
| `linux-sched-v6.12.c` | `a9c89bc6e1eca2587f39518718aa0a53fd8ef646f16927a0252e5fa7f25b5804` |
| `linux-source.sha256` | `828a563c1b01f45bf492129e1d6194103b5172fc520c49f1e8f224a449410d96` |
| `preparation-inputs.json` | `9cfe88aa86f210df22adb51ff85b2dce5a97aebc3239a9025d839e509429e50f` |
| `preparations/build0/observed-failures.log` | `ba8fc3534445fb893734e1b83de5ee2d4d813072c5cce635908761b2498b996e` |
| `preparations/independent-preflight-pending/context.log` | `01b8988c7f1f1dca503c6446241e428630e7e16d18d8f351601a58cf94f6452c` |
| `preparations/independent-preflight-pending/independent-code` | `b69d0b5fd0fae6b023b784d7fdfa48b176648ea535d0bb66441f4567281da339` |
| `preparations/independent-preflight-pending/independent-code-fixture.log` | `67276ab87625450c6c197f49f9eb92f1dd50664e7bf20bf90ce67650e3dae70f` |
| `preparations/independent-preflight-pending/independent-code.v` | `3dfd6e82c5179bc263cd6218f8d5b2f5a201d2b5dbbdb1b582f5f25a6523b7b9` |
| `preparations/preflight-import.log` | `6d37c48097d0bc676b81a6add12b808b377935601a413d38e5a1499705c79cb8` |
| `preview-arm.c` | `39de3142b70a4010c57ec795942e5d46789b82d4aeaa4f94fcc0d55cf4416b73` |
| `preview-arm.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `preview-x86.c` | `39de3142b70a4010c57ec795942e5d46789b82d4aeaa4f94fcc0d55cf4416b73` |
| `preview-x86.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `reference` | `a0dc753ff22c9767126a8f9cd6a93b0a0ba60740deba65c660429d2122cc391d` |
| `run` | `2eff96eca2b59a4e6eff589f25023758fb2c83df93f029e43f0293ebe52f6820` |
| `states/p1-after-arm.log` | `163907c8452f4fc109898d8cf067b515e8c0791d5c1017cbd3c7c949641f1033` |
| `states/p1-after-arm/attrimport/fixture.c` | `962a0933bd5988449c889075854dda060a5b4ff362847bb3f50b050d92a5889d` |
| `states/p1-after-arm/attrimport/init` | `4805664d48a3609e91df4d388b3d2caed44459b9496d450b0f93e96c5d819d1a` |
| `states/p1-after-arm/attrimport/serial.log` | `aecbf6df7d3363af2a6008cd6e822750a31a168ffc37a307498f6193aa1dcc09` |
| `states/p1-after-arm/attrimport/test.iso` | `cec637314c4a637def427fa1aa5405b289f75f1f27700b2f9ebd3d8e49e35a9c` |
| `states/p1-after-arm/attrnice/fixture.c` | `16c678caf8594875e8a3cb4b663125e7d627aa73ec339e83d20c4850d812ce54` |
| `states/p1-after-arm/attrnice/init` | `cc88302a486072416ef3c9b193a008ed10d1b074f23d0ed032e586200e20afeb` |
| `states/p1-after-arm/attrnice/serial.log` | `30abfd238cce54408752cdb2d2064523240e9553e9a4cd841f450e8e08edfb5b` |
| `states/p1-after-arm/attrnice/test.iso` | `a06e6b7edafd8eba2e884dee2e618ded334d008487777d2d29d2b6ce98088341` |
| `states/p1-after-arm/attrquery/fixture.c` | `f964f8585bfbe91601cf581f04d25b1b02f2fd55e5dc31fa7782a9f9e6f60c3a` |
| `states/p1-after-arm/attrquery/init` | `43da21bb9f97a38755442078b7396f5ff8924e01ea9fac6117fc5cf86ed6f770` |
| `states/p1-after-arm/attrquery/serial.log` | `4321b1540859061e728232cc02b6591c7e8dc4d9a75a078ef1d5e3e70f51d5e7` |
| `states/p1-after-arm/attrquery/test.iso` | `1cebe4d7bed990b7eda51ec8db0d8b61ee8ba5f79730326b7a9f16d0899dda77` |
| `states/p1-after-arm/fcntlabi/fixture.c` | `214391504c640d251498205116f3dd9473925931e8a068e6a15ffb349965fb09` |
| `states/p1-after-arm/fcntlabi/init` | `b92892f1860ff4aae349f27924922645aed79becbcff2dd00a0a18fc797fd3fd` |
| `states/p1-after-arm/fcntlabi/serial.log` | `69e47c365ad74e339bfcd4a99906b3989a13bf831e02ebc1f72cafdfa5883796` |
| `states/p1-after-arm/fcntlabi/test.iso` | `19ec781eefb9f2c0295780668b74d83919f48e1e79e09b7fb98d3c08f6af552d` |
| `states/p1-after-arm/kernel/bin/vinix` | `623f52d8964d4c742965633cd460974364fa576f88804139493127ee10b2017b` |
| `states/p1-after-arm/receipt.json` | `1b5966f774161eec9657618685408c0e8cf0f4e9016a60e35d239b0513be5838` |
| `states/p1-after-arm/rrabi/fixture.c` | `8e8669868533c177310e4946be416d0a371d4ae6348e0045951861481682b48b` |
| `states/p1-after-arm/rrabi/init` | `c4fa4490cfc1f9997ab8018831a242c1c4fdc5099bb6c59bbccceb1b88890f5a` |
| `states/p1-after-arm/rrabi/serial.log` | `6de86c14301f1767be8c72a36991bf25df113ce36d91c36c35555389cd4513b4` |
| `states/p1-after-arm/rrabi/test.iso` | `be5d8f424011b84b366ec4345c1e0770e20e937fbd262a88201e302a73f0219d` |
| `states/p1-after-arm/rtadmit/fixture.c` | `39de3142b70a4010c57ec795942e5d46789b82d4aeaa4f94fcc0d55cf4416b73` |
| `states/p1-after-arm/rtadmit/init` | `9ee0054e1cef050db8da9414801ad38bf4a2999da5c6ed5f825c85673d10db75` |
| `states/p1-after-arm/rtadmit/serial.log` | `da37d9b8bdd17228ddd04c931b0c2446b6952da3d25cb23c83063615604250a9` |
| `states/p1-after-arm/rtadmit/test.iso` | `ac733f78ca4bda77df94af53d53ecea15e7a1c79d49ba019fb07e467eda6045f` |
| `states/p1-after-arm/runtime/fixture.c` | `05967a3ff8bb35aafaf2e91e58e1203b35780818a33b84031590b52943d60128` |
| `states/p1-after-arm/runtime/init` | `a27160c033a470689dafc283d37636bb5b81b1344d19e93a2c6071701187e44b` |
| `states/p1-after-arm/runtime/serial.log` | `9fe5b350e7dfce2a1660201b296f5eed6d7a38e1caee2cb850082f7cc16ec206` |
| `states/p1-after-arm/runtime/test.iso` | `dbe7b7ee65bae675bb327acdef1ecc2e6e7cdfa9a7b081f36c60f90832df76aa` |
| `states/p1-after-arm/schedabi/fixture.c` | `8fff587a11dd1c2fe123b264c674428e7330f509e70451d37fd572ee0ea5c154` |
| `states/p1-after-arm/schedabi/init` | `aaf0c1175a0b32bee276fc84f5619c7c468643a97337fb4ee44b45900b81af18` |
| `states/p1-after-arm/schedabi/serial.log` | `d9e1c9f357479a40d894a02d9ff1f63d163d78777d89433f370091e9a8649289` |
| `states/p1-after-arm/schedabi/test.iso` | `bc7e9e0cbebb705feb5aacc12583b57ae94e1f376e0c58d716c72382753222f5` |
| `states/p1-after-arm/sources/attrimportfixture/core.v` | `ea50d5decd874adb05f39d61b06e650f4163647c3fb7df84795333d55d1d62aa` |
| `states/p1-after-arm/sources/attrnicefixture/core.v` | `42f45edd6322c95037aa848404275527503570ab70929f9678c60db82701fb59` |
| `states/p1-after-arm/sources/attrqueryfixture/core.v` | `ece9c957e365646f3f37aefef75b5ff7540c58da876a1764eb67fff46b557c9b` |
| `states/p1-after-arm/sources/fcntlabifixture/core.v` | `6f70bc290dff8671cbde66025806b7b5d99d82468dc6e7098ec86a27cc43c3ac` |
| `states/p1-after-arm/sources/rrabifixture/core.v` | `1dbb6631fbff3080966eaabecb56c4efa37b53bb3df2979ad68da9be7e8b874e` |
| `states/p1-after-arm/sources/rtadmitfixture/core.v` | `e35b0fe0a165cc8190f9a9637e10287888156c75d245d589db6cd14d5584a741` |
| `states/p1-after-arm/sources/runtimefixture/core.v` | `e23fb687c349c454bb7ad310c0c251e4968131781ff5eadb4b2488bd2fe7b6f6` |
| `states/p1-after-arm/sources/schedabifixture/core.v` | `de18a603b819a8534ec998e1229c6b6b5103bfe515bff8e81b81ee78b9c21d7d` |
| `states/p1-after-x86.log` | `11ee2ce4725bfae29be1fd43d00009979fd6be86c563dba23cbe365021bd50ec` |
| `states/p1-after-x86/attrimport/fixture.c` | `962a0933bd5988449c889075854dda060a5b4ff362847bb3f50b050d92a5889d` |
| `states/p1-after-x86/attrimport/init` | `44c4e4bbbde3ebf4f527ae712af747cd53e066bfd73e9a00825afe070ae21917` |
| `states/p1-after-x86/attrimport/serial.log` | `c6dea594a1831c456686257fbdeddc24cff8b21f66e592773122a9f1855da075` |
| `states/p1-after-x86/attrimport/test.iso` | `2c396bca14869ff5ccb30987547d2e27fc5f586b1e4534a9297f1b218bab8180` |
| `states/p1-after-x86/attrnice/fixture.c` | `16c678caf8594875e8a3cb4b663125e7d627aa73ec339e83d20c4850d812ce54` |
| `states/p1-after-x86/attrnice/init` | `d69ffafc9b23ce6ac63a458cf1de887959c250adad6131441ee236e56a86a6ff` |
| `states/p1-after-x86/attrnice/serial.log` | `90c96c65e415db194a0f2cdd81e12082665f77c599103cf64f6a35609598d55a` |
| `states/p1-after-x86/attrnice/test.iso` | `4177234adf4b5da4bd17f95de52e86ec83d8f09d3f6a6edbe93fc14137a66eb6` |
| `states/p1-after-x86/attrquery/fixture.c` | `f964f8585bfbe91601cf581f04d25b1b02f2fd55e5dc31fa7782a9f9e6f60c3a` |
| `states/p1-after-x86/attrquery/init` | `b2423eca23720766ec649e5facedeba510dc23496bf84d67d4dcde523b749c22` |
| `states/p1-after-x86/attrquery/serial.log` | `d38724059f56982121e91b9275fd1f41df4a2ea05cb472595b7ca6d33c84e128` |
| `states/p1-after-x86/attrquery/test.iso` | `4af2a29e2d5938d1f78a40cbf23c620d75be3af7627e18fba739c26aa3746454` |
| `states/p1-after-x86/fcntlabi/fixture.c` | `214391504c640d251498205116f3dd9473925931e8a068e6a15ffb349965fb09` |
| `states/p1-after-x86/fcntlabi/init` | `d627872a0a61cbe541ae88541b21efe49f0ae214e13801f1828a0cd19cb8dc16` |
| `states/p1-after-x86/fcntlabi/serial.log` | `fb0f6b4a53a70a2345a2577acfadf9023db79e6ee9c55e65c169903af212d54f` |
| `states/p1-after-x86/fcntlabi/test.iso` | `58852b82258557102a3e732c3f53fcce7cb07e6bc7a52f1543cb8a8326114728` |
| `states/p1-after-x86/kernel/bin/vinix` | `727649b14e4e0b64932c581e2d0ba0c9e7e0c5dcdd8a0cf38a10ca999a899803` |
| `states/p1-after-x86/receipt.json` | `24235c06c4e38e08476f21762c3ece94429a4a0e854d11dc6c6578f6efa5b7ef` |
| `states/p1-after-x86/rrabi/fixture.c` | `8e8669868533c177310e4946be416d0a371d4ae6348e0045951861481682b48b` |
| `states/p1-after-x86/rrabi/init` | `30dac28706d071bfc98643a65db8ec9ebea3854430f9f944bf7843140e7df680` |
| `states/p1-after-x86/rrabi/serial.log` | `624e788d876428e0aed4825c0c80d04190d07e69c027adf52f2fe693143e17b9` |
| `states/p1-after-x86/rrabi/test.iso` | `2122308bdd78ecb91d6b915c2294dc8b8b5fca1226d3449f8c3af9cb14073461` |
| `states/p1-after-x86/rtadmit/fixture.c` | `39de3142b70a4010c57ec795942e5d46789b82d4aeaa4f94fcc0d55cf4416b73` |
| `states/p1-after-x86/rtadmit/init` | `0ccc1f8e6df0eb2884e161876c2c9f466fa60ab814839822c3448468d8df81a1` |
| `states/p1-after-x86/rtadmit/serial.log` | `ebee9fb34ed155d8d8c1a93e6cefae300c4ce5d6a0c6fd49b9680182e278701d` |
| `states/p1-after-x86/rtadmit/test.iso` | `a63288f2d058dee967be307257326949a55893b786a3299662dc5e1b392f1a37` |
| `states/p1-after-x86/runtime/fixture.c` | `283ee3218dbf04ee7c3289110ff0be3044906d48556453b06b7de972f4950e3b` |
| `states/p1-after-x86/runtime/init` | `3c22f6e44700a031e0c6e9bd04427095e423d595d3f9b81e09f07539d1ea3b9f` |
| `states/p1-after-x86/runtime/serial.log` | `0a8088397a56749f4b5b8275d36d23b60de5eafe640a5f6e4470d7e66b45c8cd` |
| `states/p1-after-x86/runtime/test.iso` | `b35b8fa90ac68e3f4ced7f58c2f7056dfce4c46be3d01ce42e49f79679a4b145` |
| `states/p1-after-x86/schedabi/fixture.c` | `8fff587a11dd1c2fe123b264c674428e7330f509e70451d37fd572ee0ea5c154` |
| `states/p1-after-x86/schedabi/init` | `6e0d896226ce58749fefe9d9fa411596aa5a9f1581f88b92c469574f541b3a8a` |
| `states/p1-after-x86/schedabi/serial.log` | `2e915e07cc814a90a3e7a7ac164a237bd5320b3d65ca90497240c582f2371ac7` |
| `states/p1-after-x86/schedabi/test.iso` | `83ce7435839d7b8deeb6c540dcd93afa4552bb46c27edac23c23a9f3a348dc3e` |
| `states/p1-after-x86/sources/attrimportfixture/core.v` | `ea50d5decd874adb05f39d61b06e650f4163647c3fb7df84795333d55d1d62aa` |
| `states/p1-after-x86/sources/attrnicefixture/core.v` | `42f45edd6322c95037aa848404275527503570ab70929f9678c60db82701fb59` |
| `states/p1-after-x86/sources/attrqueryfixture/core.v` | `ece9c957e365646f3f37aefef75b5ff7540c58da876a1764eb67fff46b557c9b` |
| `states/p1-after-x86/sources/fcntlabifixture/core.v` | `6f70bc290dff8671cbde66025806b7b5d99d82468dc6e7098ec86a27cc43c3ac` |
| `states/p1-after-x86/sources/rrabifixture/core.v` | `1dbb6631fbff3080966eaabecb56c4efa37b53bb3df2979ad68da9be7e8b874e` |
| `states/p1-after-x86/sources/rtadmitfixture/core.v` | `e35b0fe0a165cc8190f9a9637e10287888156c75d245d589db6cd14d5584a741` |
| `states/p1-after-x86/sources/runtimefixture/core.v` | `e23fb687c349c454bb7ad310c0c251e4968131781ff5eadb4b2488bd2fe7b6f6` |
| `states/p1-after-x86/sources/schedabifixture/core.v` | `de18a603b819a8534ec998e1229c6b6b5103bfe515bff8e81b81ee78b9c21d7d` |
| `states/p1-before-arm.log` | `0571670c02554698fc3dfffeac7c45d87e21a27b93a5c401e4c0937768dca406` |
| `states/p1-before-arm/kernel/bin/vinix` | `452c2dde8ab24762ffa13e92b029336e931b6abb492f6001a81116fb26a19bc8` |
| `states/p1-before-arm/receipt.json` | `bcc0a5074e39006ea520fccf44eb03a3158dc4dc57500bbf7b25a70ea04e4770` |
| `states/p1-before-arm/rtadmit/fixture.c` | `39de3142b70a4010c57ec795942e5d46789b82d4aeaa4f94fcc0d55cf4416b73` |
| `states/p1-before-arm/rtadmit/init` | `9ee0054e1cef050db8da9414801ad38bf4a2999da5c6ed5f825c85673d10db75` |
| `states/p1-before-arm/rtadmit/serial.log` | `7bcbd1a7aff819446710ae9a625ec76f022b12658e1ed29cb0ac8ba040baf346` |
| `states/p1-before-arm/rtadmit/test.iso` | `37b9b850ffedeeec66697ab0e55ba3b8821a6baa05ddaef7f30d7851de64747f` |
| `states/p1-before-arm/sources/rtadmitfixture/core.v` | `e35b0fe0a165cc8190f9a9637e10287888156c75d245d589db6cd14d5584a741` |
| `states/p1-before-x86.log` | `23df53babd7e404c697e559697d459bf8d5714d7df513cb1fa018824fd5677fc` |
| `states/p1-before-x86/kernel/bin/vinix` | `67e1c497dda195359323e7ce44a5b7d3e921c074f9f24c2e837eaf24eb9c0b67` |
| `states/p1-before-x86/receipt.json` | `aa4aaf19ce26405189a0860b5de7d4711f065b73170a4aa18c66e4152374ec25` |
| `states/p1-before-x86/rtadmit/fixture.c` | `39de3142b70a4010c57ec795942e5d46789b82d4aeaa4f94fcc0d55cf4416b73` |
| `states/p1-before-x86/rtadmit/init` | `0ccc1f8e6df0eb2884e161876c2c9f466fa60ab814839822c3448468d8df81a1` |
| `states/p1-before-x86/rtadmit/serial.log` | `bcd2ab3e4611a73bd808a28ae888678b16f375373edffc33e8a5995ee36b304a` |
| `states/p1-before-x86/rtadmit/test.iso` | `b4beb88ed9d590d64ca0479837535ce5acba2473ef3bc626291b2837482d0ad1` |
| `states/p1-before-x86/sources/rtadmitfixture/core.v` | `e35b0fe0a165cc8190f9a9637e10287888156c75d245d589db6cd14d5584a741` |
| `states/p1-reference-arm.log` | `8a34ad84820659df09318290014ec03c34857220d6a47de634b7460f58b4c9b9` |
| `states/p1-reference-arm/fixture.c` | `93f10ce80bf6ca0a576b3059263d3f7f1ed73c81252ca69900eb894166c84f12` |
| `states/p1-reference-arm/init` | `a935168895552464ed0d32860bb65b60e7e81622972599109d4288228b9392c8` |
| `states/p1-reference-arm/initramfs.cpio` | `a412c4d26a7bf7614d4471efc14b9833f0c4fce6fb7139685b3e8e21d5e8e895` |
| `states/p1-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p1-reference-arm/probe` | `9ee0054e1cef050db8da9414801ad38bf4a2999da5c6ed5f825c85673d10db75` |
| `states/p1-reference-arm/receipt.json` | `726104205089f908e04e811489eedae6e63aa6157111714510e94640309e349d` |
| `states/p1-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p1-reference-arm/serial.log` | `87486697000a6152230af97b92b5a676b9cc6e26c301db0d9d337209198e3d6d` |
| `states/p1-reference-arm/source/rtadmitreferenceinit/core.v` | `c1085a5fbe36132eb761849d454026f8d7964a8fdd8e7bda8e90f33d84ea3006` |
| `states/p1-reference-x86.log` | `d63013163197363eddc7dc30ab43c5b7a9a5c6fef1b9c12506de38cb083c8f7e` |
| `states/p1-reference-x86/fixture.c` | `93f10ce80bf6ca0a576b3059263d3f7f1ed73c81252ca69900eb894166c84f12` |
| `states/p1-reference-x86/init` | `e807869e6992aee92a66f7a6c7c27ea4d6bc2593ba590425e48e2599119bb4fe` |
| `states/p1-reference-x86/initramfs.cpio` | `91be51e3ea0fb3859013dafc436acc5e7eb204a64ed57998325aaf92c8b59256` |
| `states/p1-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p1-reference-x86/probe` | `0ccc1f8e6df0eb2884e161876c2c9f466fa60ab814839822c3448468d8df81a1` |
| `states/p1-reference-x86/receipt.json` | `1a18af1d6eb8ab4ca970f88d3abf1fb1e5c7346c09c1ff143a61f80c7cd59b3c` |
| `states/p1-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p1-reference-x86/serial.log` | `7fd392b696f2430b3e7794b815201c98ced00a138435461c2565fdf87191f570` |
| `states/p1-reference-x86/source/rtadmitreferenceinit/core.v` | `c1085a5fbe36132eb761849d454026f8d7964a8fdd8e7bda8e90f33d84ea3006` |
| `states/preflight1-rtadmit-arm/fixture.c` | `39de3142b70a4010c57ec795942e5d46789b82d4aeaa4f94fcc0d55cf4416b73` |
| `states/preflight1-rtadmit-arm/init` | `9ee0054e1cef050db8da9414801ad38bf4a2999da5c6ed5f825c85673d10db75` |
| `states/preflight1-rtadmit-x86/fixture.c` | `39de3142b70a4010c57ec795942e5d46789b82d4aeaa4f94fcc0d55cf4416b73` |
| `states/preflight1-rtadmit-x86/init` | `0ccc1f8e6df0eb2884e161876c2c9f466fa60ab814839822c3448468d8df81a1` |
| `tests/linux-compat/rtadmit-check.v` | `988e8989d8c9a305e93bac71d1eba2e0ba2be489bb9b2d85296be00b89574a66` |
| `tests/linux-compat/rtadmit-reference.v` | `ab1cfa445571425618be0cb872e34d1ba9bf879ea0c4ad7ef5bc69cdfb0921cd` |
| `tests/linux-compat/rtadmitfixture/core.v` | `e35b0fe0a165cc8190f9a9637e10287888156c75d245d589db6cd14d5584a741` |
| `tests/linux-compat/rtadmitreferenceinit/core.v` | `c1085a5fbe36132eb761849d454026f8d7964a8fdd8e7bda8e90f33d84ea3006` |
| `tests/linux-compat/run.v` | `788ab2c6f62ef34087287f020a9f64a11bc3a04b59c6c3904feb304d3e9f1907` |
| `watch` | `cab05bcde212491f6bd0b402edea824976f7c838a5728d0646557786e57605e7` |
| `watch-detached.log` | `6066eefcd13609392f874383310ff39e0af7ed77acd510810882c1fdc3acec1a` |
| `watch-retained-inputs.json` | `858cfb319367b9e791d3cec17e5f0904232de271b2cf1c5539ca8589f7bd5afa` |
| `watch.log` | `b739b8be57e3fa82e93a9d74ad4c589451e4b23e97630df5165fc1905fc2a373` |
| `watch.v` | `40bc244badccea1d7e4b96485f7c82151e52958c53d3a76833f87e78f27f2371` |
