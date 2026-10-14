Independent affabi lifetime review: PASS

Reviewed the native sched_getaffinity/sched_setaffinity change against frozen baseline `16be6d0a204b509c75d456930af478de0232c36b`, final V fixture/reference/controller/auditor sources, the original and corrected production C on both architectures, final preflight3 probes, p2 native captures and unchanged-ELF Linux references. No new lifetime blocker remains. This review covers native argument decoding, clipped affinity masks, caller errors, stable peer ownership/capability checks and observed stored masks; scheduler migration/execution and racing identities remain separate.

The only kernel changes are the two affinity syscall bodies/signatures, the scalar sched_affinity_permission helper and CAP_SYS_NICE=23. Independent assertions strip those exact definitions/prototypes and the capability macro, then require the remainder of each complete production C file to be byte-identical. Source checks separately require only those affinity functions/helper and the scalar constant to differ. Existing CPU filtering, final mask mutation, usercopy and allocator paths remain unchanged. No new allocation or free appears in the changed kernel bodies.

The caller process belongs to the running task. The permission helper validates the numeric TID before indexing, acquires the PID-table lock once, and keeps both target and owner borrows inside that lock. It returns only an errno scalar. Generated C releases the lock before each of the three guarded error returns and the final success return; V also emits an unreachable fifth defer release after that return. Its existing v_fixed_index bounds helper sees the already checked TID. No target/owner pointer, interface box or new allocation escapes. The effective caller capability bit is used explicitly, with no UID-zero exemption for a differently owned target.

Input-mask storage is a zero-initialized stack u64, synchronously borrowed for min(unsigned32 length,8) bytes. A zero-length import does not read its user pointer. Input faults precede target lookup, and target/owner/capability errors precede empty-present-mask validation. Getter length validation, including unsigned32 bit-count wrap, precedes lookup; only a resolved target reaches the synchronous output copy. Signed32 PID decoding is checked in source and actual production C. Permission and final mutation reacquire the table lock separately, and final mutation still checks MAC; same-domain TID/credential reuse races are not newly qualified.

Each final probe has twenty explicit alloca sites, fixed count arrays and a real 4096-byte stack observer buffer. Independent raw-C checks find no malloc, calloc, realloc, memdup, dynamic-array or fixed-index helper calls in the fixture. Each Query copies errno immediately. Unaligned mask words use memcpy/memcmp rather than typed unaligned accesses. The synchronous user buffers remain accessible through their calls and comparisons; each saved input read stays in the known accessible prefix.

The bitmap-width discovery is aligned and bounded to 8..4096 bytes, verifies the first active-mask word, zero higher words and untouched outer guards, and explicitly requires width=8 on native Vinix. The scratch buffer is width+16 bytes, so offsets 8/9 plus the largest copied prefix remain in bounds. Final Linux references report width=8 on AArch64 and width=32 on x86-64; their exact clipped prefixes and zero output tails are tested. A page-ending eight-byte prefix faults when the configured reference bitmap needs more bytes. Native exact eight-byte results remain strict. This describes the supplied reference kernel configuration, not a common bitmap width across kernels.

The Worker context, pthread handle and Fixture alloca storage outlive the worker until pthread_join completes. The worker reports its real non-main TID through the ready pipe before the parent queries it, then blocks on its command pipe. The parent releases it, joins it, reads its final status and closes the shared descriptors before returning. The UID/GID1001 peer is created before credential changes, reports readiness, blocks until released and is reaped before Fixture storage ends. The short reaped child executes only _exit after fork. The two outer credential children send their fixed Counts values while those values are live; the parent receives them before waiting and reporting.

CAP_SYS_NICE toggles preserve every other capability bit and are checked by capget. Both UID-zero and UID/GID1000 cohorts test a differently owned peer with that effective bit off/on. Before returning, the fixture restores caller, worker and peer masks and verifies the complete caller capability snapshot. Worker credential propagation and arbitrary real/effective UID transitions are outside this stable-owner qualification.

The slab observer stays open through warmup and both snapshots, closes on every nonfatal path after opening, and parses only the bounded pread result. Snapshot arrays hold at most 32 rows and their terminator write remains within the 4096-byte stack buffer. Mapping storage is unmapped only after all guarded calls, worker joining and peer reaping. Host process handles close after waits; independent hash files close and their bounded streaming buffers are freed after synchronous hashing. Host data is retained only for bounded one-shot sessions.

Counts independently recompute to [6080,12160,6080,388] per credential cohort: eight target classes, nineteen unsigned32 lengths, ten input/output forms, ordinary/two upper PID words and upper length controls, plus effective-capability and real musl-wrapper controls and final mask/capability restoration checks. That is 24708 per cohort and 49416 per architecture. Both CASES and FINAL sets are checked for exact counts, both cohorts, all four kinds and absence of duplicates. Final originals fail exactly [3098,8336,2302,198] per cohort, or 27868 controls per architecture. Corrected kernels and identical-ELF Linux 6.12.51 references pass every control. The fixture invokes real musl syscall and affinity wrappers; GNU libc wrappers are not qualified here.

Each final native cohort runs 32 warmups and 200 mask/permission cycles, with 13-second settling periods. All 18 AArch64 and 14 x86-64 slab classes remain flat, as do large pages 71/71 and 175/175 respectively. These measurements cover the bounded repeated affinity paths on retained tasks; they do not qualify all kernel allocation behavior. The before/after allocation scans identify the same 398/290 sites and retain their existing allowance refusals; exactly two container diagnostics move down one source line after the scalar constant is added. Independent checks normalize only those two known positions and require every other byte to match.

Independent receipt checks recompute native source, ELF, ISO and staged-kernel pins for both complete final eight-case profiles. The preflight3 ELF equals each original/corrected p2 native affinity probe and the actual Linux reference probe on its architecture. Reference receipts bind the kernel, probe, wrapper source/C/ELF, initramfs, serial adapter/transcript, QEMU binary and controller source and require passed=true, finished=true, forced=true and status=0. Successful probes pause until the controller stops QEMU. All 15146 compiler inputs and each private 64-input kernel coverage inventory are independently rehashed. Four fresh production build logs, eight host test files and four inventory passes are bound. The deliberately false assertion and passing ARM Linux capture supplied to the original-failure checker both actually exit 1; independent helpers are compiled without -prod.

The first pointer-type preflights contain generated C but no executable ELF. Earlier p1/preflight2 probes assumed an eight-byte reference bitmap: ARM Linux passed, while x86 Linux failed [288,576,288,0] per cohort, 2304 total; the failed x86 receipt has passed=false despite process status 0. Those probe C/ELFs, affinity source/ISO/serial captures and reference receipts remain preparation evidence. The p1 affinity cases pass on corrected kernels with flat storage, but their broader profiles encounter ENOSPC during later assembly/compilation; incomplete cases lack artifacts and do not count as regression passes. Independent review audits actual retained p1 affinity/reference artifacts and partial receipts only. Final p2/preflight3 probes use the bounded width-aware oracle and complete fresh profiles. Reviewer helper propagation, generated-format prediction, incomplete-profile assumptions, in-progress receipt and expected diagnostic-line shifts are retained as private preparation diagnostics rather than semantic failures.

Qualification remains native unpledged musl ELF64, stable tasks and the supplied small active CPU topology. More than 64 active CPUs, CPU hotplug, ARM CPU1 QoS, scheduler execution/migration, TID/credential races, PID/user namespaces, pledge/MAC policy combinations, GNU libc, translated/ELF32 callers and broader roadmap section 15 gates remain separate. This review writes only its owned repository report; implementation and committing remain with the parent.

SHA-256 pins below were independently recomputed after their producers completed. Paths are relative to `/Users/alex/.cache/vinix-linux-compat/affabi-20261014`, except repository paths beginning with `kernel/` or `tests/`.

| Artifact | SHA-256 |
| --- | --- |
| `after-arm.c` | `40bc6f34f780b4523e1ca61dbd7a3851ea8c4bff04e5d222ab3502eedcc59052` |
| `after-container.v` | `f66753325982603ea72a325798e309d627c910d76df03d4fbc5744fd94fd4018` |
| `after-gaps.v` | `e6862eeec7003d68048c651895bf68e437a5403e96c369c0266903204265e3ac` |
| `after-x86.c` | `6aa1ca69580c96281cd54b1ff0a017ae0356a7315a04949c6209f7cfa9012b25` |
| `allocs-after.log` | `f7ab3f9c16ab87a8f2fee496bae2f893220d0af762879c1b244f9fa97e608247` |
| `allocs-before.log` | `725b1149b9a52ae65192967b2f5210cb7972551a157cb92359ce42e795049d3f` |
| `base.txt` | `7f7a622284054f98ccae24c0c9cf0e5dbf88f04061928a878fc2350e3e4d9d0a` |
| `before-arm.c` | `11bfe71e671e1efb5982162437eb397d74cb3df1ef81f2d7963e4047f498e8ff` |
| `before-container.v` | `db3558d2cea2aeb8c5a483cd9cbade7ba37e2d9d13f5d3047874a9ce2319449a` |
| `before-gaps.v` | `de5c4bfe2c7b5528bc63c02b22720130d526699131d65b34b4e6a9f721eb569d` |
| `before-x86.c` | `8ebe7b3f160118517f8523f14042230a8aa839b8d28e4773500a267bd3002281` |
| `build-after-arm.log` | `f541bb0e4921974bcebff3b4d0bbd227e5ad3537d541cd54cb2d458780f0bbcf` |
| `build-after-x86.log` | `ce70b08209b4e10811d3fc972fef38f13df021b712b27e6cadd6c1efd21b6689` |
| `build-before-arm.log` | `5d3d28fbe72e58a7a30b0850926127779a6035aeccb6bf9138d504a7d4e1bb20` |
| `build-before-x86.log` | `7146c27c4a007cff4f5d328f36ac8688c32a5ad028016b8b34591f448afb9fc9` |
| `compile-reference.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `compile-run.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `coverage-check.log` | `f14b0219fd4094c269a82b893f4a2424ffc8461e1745db3f9971f06dd81031fb` |
| `host-tests.log` | `fec498e7cbf15a1fc0cace2f7e3774534e7934ff794304d1284f6f17613ddde4` |
| `independent-alloc-lines.v` | `dd8317a7dc79dcf5715a136c9bec7e933e3c98011a1bf1352cc81f9041f23265` |
| `independent-artifacts` | `96e598d2f07cc6dc6c36d925ed0478b7413c805f5aaba7181918f4816e117eba` |
| `independent-artifacts-compile.log` | `7c262d06a6a2a1b393b6fceec04988387268846c22efd6ea324e1d100330946e` |
| `independent-artifacts.log` | `e11d4eee8c10e5d9bf383411571194e35fb3065c12722019c85c8921a484ce11` |
| `independent-artifacts.v` | `7f26b04a54cdb8dde9a3ac42f7f7e4ed97e3e56982aa6ec6ad53a7e0196e3032` |
| `independent-baseline-control.log` | `c929c270bf3cddf2da70ad295ab501e4c4e8247731360a8c7731bc14a8b68c78` |
| `independent-capture-finalize.v` | `e130e8c907110ba6cbc8113a4c31d2834e97a87eddf71abda638c3d15ad18234` |
| `independent-code` | `f790f385f53f7797fe9cefde5f360d5982476c0e8dffd0639c075ee13962cc63` |
| `independent-code-compile.log` | `e420e514d0b6550c50765b1eb3a746408b955a4237dc06529b29659eb80c0a1f` |
| `independent-code.log` | `ec0519357cc2f52c3b677ada397ccaf045532864695b0924848019ed2eee8e95` |
| `independent-code.v` | `4eb01190ad048bb199d9fdaff9f6a9c9ab8df0e7d306f0431d28765a5f7be775` |
| `independent-compiler` | `3b349fb705c5de8193d2742d806f847d91fb80b74095217457bb553b4535e9da` |
| `independent-compiler-compile.log` | `31a90376f69b8619f7fd43087dcafceae97bae9090c0a8018c33881123f59b62` |
| `independent-compiler.log` | `eb721b4c25c58907c7cfc196e264be3d65fc20c35259451ef8681523b6e81424` |
| `independent-compiler.v` | `3f2bb25122c643711615b918c09c67c70f3b9f779ee00e4b88ba828f6e8df336` |
| `independent-controls` | `62ed18e5332c9e501af4dd1fa5b9a3ef2819aec1d32b44b21c9bcd4a0f91e1ff` |
| `independent-controls-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-controls.v` | `908b17b89f3c7bbd764d2d14331a8ccf7c21aa74e67f70c694c55a591e6350c5` |
| `independent-counts` | `e54cb3f44639a24cd23a1167c022ba50be3ba0fcd5c0c402e25591c112e1b2e5` |
| `independent-counts-after-arm.log` | `c14c8f16c5a26a9f4f4277ec1f2a107fd86a002e559d153bd6a0ca1091b65a2b` |
| `independent-counts-after-x86.log` | `ce1fa196ab04e789a2ecabfb9e95025c86fbf3d44d2fbf9cb0c892937ebabe03` |
| `independent-counts-before-arm.log` | `a2cc99fbe175cc5bf762ca558c8837e67b72a6cd2232188731e66cfed765380c` |
| `independent-counts-before-x86.log` | `591af167aaabc00c3fa90e442e002501abc40eeaaa192079b570fa4920a6b901` |
| `independent-counts-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-counts-reference-arm.log` | `f666611c7a50a064ffe377950e1e961fedef5c9c8eae0149b1c1d6020d1a1978` |
| `independent-counts-reference-x86.log` | `05a53bee486d339555d789a48dd28fea188a073a5e423ae8bbfd84d3891b0dd5` |
| `independent-counts.v` | `7b71102c0bbb7cb0b884f4cdceb1fa49c8ea2d89745a54c901302629a4ea5883` |
| `independent-execute` | `69828b2e811ed961310835ada70882e2103fe43ca8fc2ee2282bacc2d6a9ca8c` |
| `independent-execute.v` | `a263dc5523bff02cfc1cf4f892ef2be4650dc381ca044b372f9d06eee43c62c8` |
| `independent-false` | `04996169b3330806f2f8e92ff4fb9595856e77aa66f1e7824a0dfbaeb0dfaa72` |
| `independent-false-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-false.log` | `373ea0059dbe345ce540c9dfa2bb1cc69a156ddb301196628f48bfc5e4960ea4` |
| `independent-false.v` | `c2af5d63b16375d6365417921adee72efe89a1ec500431371173c49cb73a6e1a` |
| `independent-finalize-counts.v` | `eb2b774ed18de111ce90ed09317328a3d215f48874afa2f1639fc5f4a3328447` |
| `independent-fix-index.v` | `e2024dada6fbe5314e4482d1cf7b4e5352c62ad505b43e792e00301e0dcbd456` |
| `independent-fixture` | `89a3f539e2304da2e84906430d5afa4633aa3e9ee038762561b97e850efb58ef` |
| `independent-fixture-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-fixture.log` | `33f6d1bc76935f5711cc7177c164942aef635ba85645f0a1f14973a43d952880` |
| `independent-fixture.v` | `9cb5f1cbddd4d5aa48bb620fdfcc70341732346a9448759888ded365ebe5e249` |
| `independent-prep-bounds.v` | `62629b1ca2e30c9b7bab520442aa2ff17cf424288e1cebd88dff56ac3b4db611` |
| `independent-preparation-allocation-lines.log` | `14b99e208d79fcea714b7bf282a9f5fa679850d8afcac6e7ebf5d6ed521fc103` |
| `independent-preparation-allocation-lines.v` | `6b1529c5d0bebbbbdae1134c722ca1af401f15ada71ade1895826fbc79fa1ff8` |
| `independent-preparation-generated-format.log` | `9305d215a2adf97db1b40a67b983d18cd56c8b9749b934ffb3b7ed38385f75dc` |
| `independent-preparation-generated-format.v` | `e3935519e35af01ae0f2182ff9725c39c3014ae9967cfcde73b12bc365d2c6ea` |
| `independent-preparation-partial-receipt.log` | `8b14b6abd466381a8100399ebc7ba87d222efd28c8867913130063a48d842c55` |
| `independent-preparation-profile-assumption.log` | `e963acd887e3b7b9d13366946f912260bbd00b0f4cd30a63664dfff1a526b0a0` |
| `independent-preparation-profile-assumption.v` | `88fd2e0729ec44046b31294ce87c48c4b32642f1e01e17031c875b226ad52eeb` |
| `independent-preparation-propagation-compile.log` | `99ef160c1e68b77e4debb167ea1fb5a5c9f18bad262ced1e9a621f6b52c41d97` |
| `independent-preparation-propagation.v` | `d8d94244d4bb764906cb514a2ca0ceac63f190edaf59486196112f5c8550153f` |
| `independent-preparation-propagation2-compile.log` | `8f7608eb1d4eed1e2cb41a36755eb9725af68125bca2aab0fa9291e993fa0f39` |
| `independent-preparation-propagation2.v` | `a1953ed11f89f2c81211d2e4a53f27c251ac28769980e4df1d3a65ddf1ee6025` |
| `independent-preparations` | `09a8ee997ce0bfd9143888cf0853f5c42c2213bac10fb7317172ba35556a5fc7` |
| `independent-preparations-compile.log` | `c8bdd3cad83fb7d37978d034ab16e075d360319db9150c473cc0ad80337e5764` |
| `independent-preparations.log` | `948dcccf67cebf5c98aad851b1f7a90dc8c4f204a708e6772df4d9f8f9495265` |
| `independent-preparations.v` | `3dd02d0686dac7c8d6e5a2e07df3c7b354b9d9f02972cc9b0807d8e9d9e87aba` |
| `independent-prepare.v` | `136edeaa9fdd4cd501c095974a0ca01075ddf9bd8b724360dacb96f06409d581` |
| `independent-preserve-live.v` | `4f1c6160367a56d2576033cb8cdb872cd4b0ed1d425a85af5505633dc51437de` |
| `independent-provenance` | `80f16fbafaca169f4da031a65f06ec1af439f7bcb4d59a4422efed31f68dd087` |
| `independent-provenance-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-provenance.log` | `607119d825ba64d133af79212c61a4f1447825c24d815302975104e7f37270ba` |
| `independent-provenance.v` | `76a45c8ca5866fc5c6157f361af560c5176d3b0b6da5e62c4026319df6c7ba72` |
| `independent-refine.v` | `2df2f8f2a8eb76b9fdfb6cf78434423c8193f883113d271e9db89a09bacb4b37` |
| `independent-report-prose.md` | `bfcdd0571f2275e780481194fbbbbe22b583e1fc90e51ff5b5e6958969b5ec0e` |
| `independent-report.v` | `62907f42fa7fae22ceb04d7b8d41844429ae8fb7850e3d1d9910bf2c49545721` |
| `independent-setup.v` | `f41df4ec7e12198ca9a67c586f7b69500fb3db546cea8dcb245a4ad6477e4213` |
| `independent-width-update.v` | `5d813714c460bc5e624bf443d652ebe32c07f1836b2e3184a099bd6f9320bdce` |
| `kernel/proc/container.v` | `f66753325982603ea72a325798e309d627c910d76df03d4fbc5744fd94fd4018` |
| `kernel/syscall/table/gaps.v` | `e6862eeec7003d68048c651895bf68e437a5403e96c369c0266903204265e3ac` |
| `linux-sched-v6.12.c` | `a9c89bc6e1eca2587f39518718aa0a53fd8ef646f16927a0252e5fa7f25b5804` |
| `linux-source.sha256` | `828a563c1b01f45bf492129e1d6194103b5172fc520c49f1e8f224a449410d96` |
| `preparation-retained-inputs.json` | `5a1c5ec60a9a1836d774a7c5a4c9c5333b35dbe55cffc9e96b61f1b4016407cf` |
| `preparation-retire.log` | `ade8f34ca1d05d875465978205c9ee6ca908dacd10b27c16fb420b3958dd9fb1` |
| `preview-arm.c` | `5f078939b42a25668def6b7fd8bb25c20329df87d0aa27f33aa5b55da14cbd3e` |
| `preview-x86.c` | `5f078939b42a25668def6b7fd8bb25c20329df87d0aa27f33aa5b55da14cbd3e` |
| `reference` | `c49395f239705e20c60361a45f1ed016e8f8cc31b194d6b2232a20a0f7db26d4` |
| `run` | `13291d5ceb67365dfc204d8cb6c9cb3164c569abea850ff60f45963e44b36147` |
| `states/p1-after-arm.log` | `e2f02570c32182defaa9b4da1517dc8d9cfb36df04dd2e0fd8e7d1b5287aa0ab` |
| `states/p1-after-arm/affabi/fixture.c` | `ad258ec6d7a0f63fe806605260be35556f4504130d05ccf7b382e4c9ea7ea112` |
| `states/p1-after-arm/affabi/init` | `72b899faefb4c10e763f42cfae12e37a92cc3caaea58a338862477338296f503` |
| `states/p1-after-arm/affabi/serial.log` | `441c648faa2d3c9d540b3e6084e29c8be6155ea81bd477875d1a949dd5acf664` |
| `states/p1-after-arm/affabi/test.iso` | `91183739769074108f5bcc02f5127a21199e08bce22e11258a197d77f27307e4` |
| `states/p1-after-arm/kernel/bin/vinix` | `546e5ebd2882bf79e81265a9a911c76021c6e1a5d16b7e63a0d600a69d37531c` |
| `states/p1-after-arm/receipt.json` | `86d4e39d8036d5edf93be0ddb70e7e5a8fa7e4a5fc3d170698005461f65ab15b` |
| `states/p1-after-arm/sources/affabifixture/core.v` | `482d370ed1b1051e7a4c79cc8787e659d79ea9b22354b82237e2cbba0ab96bb9` |
| `states/p1-after-x86.log` | `a7437594076f667272123b1d95266aa743a2f95f37645468b55d0ba6ac66a8a4` |
| `states/p1-after-x86/affabi/fixture.c` | `ad258ec6d7a0f63fe806605260be35556f4504130d05ccf7b382e4c9ea7ea112` |
| `states/p1-after-x86/affabi/init` | `b63b6a7bac50745f65f7697be99200d75137e2faf3b44cae8a2f8749fc6c9ffd` |
| `states/p1-after-x86/affabi/serial.log` | `2e41f6e7d39d5ab62d5a62e07a5ab2090443c3b64dc96f6b5480e6f4a1580578` |
| `states/p1-after-x86/affabi/test.iso` | `29c5bedb22bf72976f823012a25cf2b6c230f07514ea6428b656da658b9fd05b` |
| `states/p1-after-x86/kernel/bin/vinix` | `4e31258bdf669c23555da50cae8a07d2c3411c25eac47e7802b2f2fc3fa9f8d7` |
| `states/p1-after-x86/receipt.json` | `0dfde4ce1ead6cbbf735646430a377635111a430c5abc1c9f2e7bfee040f0e54` |
| `states/p1-after-x86/sources/affabifixture/core.v` | `482d370ed1b1051e7a4c79cc8787e659d79ea9b22354b82237e2cbba0ab96bb9` |
| `states/p1-before-arm.log` | `2732dcbf8e438811f9010d4b61705ae36d0c53d45a97314a7c9010c2f05296d3` |
| `states/p1-before-arm/affabi/fixture.c` | `ad258ec6d7a0f63fe806605260be35556f4504130d05ccf7b382e4c9ea7ea112` |
| `states/p1-before-arm/affabi/init` | `72b899faefb4c10e763f42cfae12e37a92cc3caaea58a338862477338296f503` |
| `states/p1-before-arm/affabi/serial.log` | `7d2d81f566d9a74f4e16b7af464121411b33fc38659976ac1c9a2618adb68870` |
| `states/p1-before-arm/affabi/test.iso` | `cd9785ad08892e5bd33fe1cb588adaab6e6c92e84217d61d49efa1a533e74055` |
| `states/p1-before-arm/kernel/bin/vinix` | `8ef5fd3554a6753e3a6cc78acae609f472f814080e9a94255fb103baded4676e` |
| `states/p1-before-arm/receipt.json` | `686847efa082d5808a7968ec93423b7f9b53f4a6e1de6681cd61f867d874e220` |
| `states/p1-before-arm/sources/affabifixture/core.v` | `482d370ed1b1051e7a4c79cc8787e659d79ea9b22354b82237e2cbba0ab96bb9` |
| `states/p1-before-x86.log` | `ab2b52005fe87ff2e28bb5f0683f017bd10758041fe4d9c94515f2582319e0b3` |
| `states/p1-before-x86/affabi/fixture.c` | `ad258ec6d7a0f63fe806605260be35556f4504130d05ccf7b382e4c9ea7ea112` |
| `states/p1-before-x86/affabi/init` | `b63b6a7bac50745f65f7697be99200d75137e2faf3b44cae8a2f8749fc6c9ffd` |
| `states/p1-before-x86/affabi/serial.log` | `dd3e28ef072c3aa7d96081210447e9c5141fdbcbe3ddbdff7536a91af92c436d` |
| `states/p1-before-x86/affabi/test.iso` | `a7b79d05d13d34d73bcec6ecd3f3739e79b5129d3dba908a21d5e97e61b2c675` |
| `states/p1-before-x86/kernel/bin/vinix` | `b90e86d6c3da653fb7a48e0dc8a3d9efdd670af651c4095e8cef6de37f92bb7c` |
| `states/p1-before-x86/receipt.json` | `91787eeb90385ff1f3be36be31ebbd8a52f5a1c7584dc6ef45638485240f3b8b` |
| `states/p1-before-x86/sources/affabifixture/core.v` | `482d370ed1b1051e7a4c79cc8787e659d79ea9b22354b82237e2cbba0ab96bb9` |
| `states/p1-reference-arm.log` | `617338a80b47e173ce87ace1325cf213d4f51654b484b8f0a9ec0997bd8b5f72` |
| `states/p1-reference-arm/fixture.c` | `d1c50c94c8af53c0ef6608909a90eef9302425f9eba308972b34f2b51ac0d92b` |
| `states/p1-reference-arm/init` | `8be6d4e96b4457c24b114e6c3210c8a569cc3784d26c5b9c372fc2bb7e762564` |
| `states/p1-reference-arm/initramfs.cpio` | `706449474c3851fd59c9066bbaed9d5cb9ef7f6ef65e13f429e17fa22e541c29` |
| `states/p1-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p1-reference-arm/probe` | `72b899faefb4c10e763f42cfae12e37a92cc3caaea58a338862477338296f503` |
| `states/p1-reference-arm/receipt.json` | `cb6cd534d65cbf0748d8c37ebeab7f603e082c67d0d6f9042c5b01ba36ec8112` |
| `states/p1-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p1-reference-arm/serial.log` | `0469313694454104eb09f342e8b76dda644590bd5336824a30999080d0ee1c91` |
| `states/p1-reference-arm/source/affabireferenceinit/core.v` | `1fe05aaada655ff047ea022722430dfffbc3cea13d3b7d103d73e52d70b40528` |
| `states/p1-reference-x86.log` | `622cd0f5e9ec346593f44db4ef011c1a6f15e331fda0501d0032541e7f571788` |
| `states/p1-reference-x86/fixture.c` | `d1c50c94c8af53c0ef6608909a90eef9302425f9eba308972b34f2b51ac0d92b` |
| `states/p1-reference-x86/init` | `2a59c05b8b74fda90a0df60a83fd8589ff842c9aeef563afe870fb1b79049247` |
| `states/p1-reference-x86/initramfs.cpio` | `e02a5255e99a2313e5cd1f510857dea6d9db68cc4dac4d7e257d8570f8aba9f2` |
| `states/p1-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p1-reference-x86/probe` | `b63b6a7bac50745f65f7697be99200d75137e2faf3b44cae8a2f8749fc6c9ffd` |
| `states/p1-reference-x86/receipt.json` | `c78c85371b307dc067a2de3b1d8dbf956d953262d44cfce273044c9bf482b8ae` |
| `states/p1-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p1-reference-x86/serial.log` | `234e4fbc46f292a86d8ed5014aee0226b7a03773ec4230e9444c510a37ebdcd6` |
| `states/p1-reference-x86/source/affabireferenceinit/core.v` | `1fe05aaada655ff047ea022722430dfffbc3cea13d3b7d103d73e52d70b40528` |
| `states/p2-after-arm.log` | `9dca5dc1279e95139c32e58ec3df71ee1fb2bd8764df97d1634c59c3ec0bc312` |
| `states/p2-after-arm/affabi/fixture.c` | `5f078939b42a25668def6b7fd8bb25c20329df87d0aa27f33aa5b55da14cbd3e` |
| `states/p2-after-arm/affabi/init` | `170454ca46fa486d0c1fce09e7105e702710e1f42d9e90816bbb28cd0ba5fb14` |
| `states/p2-after-arm/affabi/serial.log` | `37827dd8f598d08e3bce58e480c191cfb39d2cf6d6710fd85d9cdd770f5ef353` |
| `states/p2-after-arm/affabi/test.iso` | `70a6476832761cc4dcdd36e3aa09b4db4c845bce2abed6247566c59244705c4e` |
| `states/p2-after-arm/kernel/bin/vinix` | `546e5ebd2882bf79e81265a9a911c76021c6e1a5d16b7e63a0d600a69d37531c` |
| `states/p2-after-arm/receipt.json` | `2dba35fb5fb53bf4d498f4882bc35b5a87d8c3d780cbc139f3e0979d37e2d80a` |
| `states/p2-after-arm/sources/affabifixture/core.v` | `d3f1524a56978720649930294770174cbf8803682882b1e10af880139643a00f` |
| `states/p2-after-x86.log` | `f84c7df25bc0c60c9ba3ca1bd1ec0c80b9f26d88e97c0cecc4982589d3b8240d` |
| `states/p2-after-x86/affabi/fixture.c` | `5f078939b42a25668def6b7fd8bb25c20329df87d0aa27f33aa5b55da14cbd3e` |
| `states/p2-after-x86/affabi/init` | `c4a5e5a6ba17781b026c420c6caae299a5b4ec9d8c682d19a3ecb059d07077a7` |
| `states/p2-after-x86/affabi/serial.log` | `bda77e2ed123f40e0056ebab0261fbc47aeee8a40189ae8bbe67c71c0611c726` |
| `states/p2-after-x86/affabi/test.iso` | `99d77c8027a6dd6e7997528663ed6b6475f7784865256a085f89f3841a8250cb` |
| `states/p2-after-x86/kernel/bin/vinix` | `4e31258bdf669c23555da50cae8a07d2c3411c25eac47e7802b2f2fc3fa9f8d7` |
| `states/p2-after-x86/receipt.json` | `af66c59fa37ecb04e16a95945225206ad8fbd3297947de81548b503e2c301354` |
| `states/p2-after-x86/sources/affabifixture/core.v` | `d3f1524a56978720649930294770174cbf8803682882b1e10af880139643a00f` |
| `states/p2-before-arm.log` | `33ca3dfefc3fa939ea31199351425f08bc13aec8d0bca570d750c3df7c5593de` |
| `states/p2-before-arm/affabi/fixture.c` | `5f078939b42a25668def6b7fd8bb25c20329df87d0aa27f33aa5b55da14cbd3e` |
| `states/p2-before-arm/affabi/init` | `170454ca46fa486d0c1fce09e7105e702710e1f42d9e90816bbb28cd0ba5fb14` |
| `states/p2-before-arm/affabi/serial.log` | `04b30e8ddac66f4aacd317c2b9cdfd98cf7b26150a1777807be77231986fffef` |
| `states/p2-before-arm/affabi/test.iso` | `fb42c505c45c612b60359f26fa53f4583416d421c88f353886e354e3e6ea5cb1` |
| `states/p2-before-arm/kernel/bin/vinix` | `8ef5fd3554a6753e3a6cc78acae609f472f814080e9a94255fb103baded4676e` |
| `states/p2-before-arm/receipt.json` | `b3d3e3f05cf3db6a2de5a7053aa4b5595dea658cbefb3f563c6182d9e5d69ed5` |
| `states/p2-before-arm/sources/affabifixture/core.v` | `d3f1524a56978720649930294770174cbf8803682882b1e10af880139643a00f` |
| `states/p2-before-x86.log` | `8f2a41abe206d8dacfd1b5218badc5cc50196c10209dfe7ba2fa08b86b41ad29` |
| `states/p2-before-x86/affabi/fixture.c` | `5f078939b42a25668def6b7fd8bb25c20329df87d0aa27f33aa5b55da14cbd3e` |
| `states/p2-before-x86/affabi/init` | `c4a5e5a6ba17781b026c420c6caae299a5b4ec9d8c682d19a3ecb059d07077a7` |
| `states/p2-before-x86/affabi/serial.log` | `d3fd9edf64ee1cb80683787621a2d81f711c1138a9dd8aa37cdabb2fdeae87a2` |
| `states/p2-before-x86/affabi/test.iso` | `faec16eaabe071f2450e22932e8409d1762dbf11300f1736731c72a398f93bac` |
| `states/p2-before-x86/kernel/bin/vinix` | `b90e86d6c3da653fb7a48e0dc8a3d9efdd670af651c4095e8cef6de37f92bb7c` |
| `states/p2-before-x86/receipt.json` | `fdcdab3770e3df58c8a92e2802fe05411fa0016e024fda465cafcdf1a0da6fac` |
| `states/p2-before-x86/sources/affabifixture/core.v` | `d3f1524a56978720649930294770174cbf8803682882b1e10af880139643a00f` |
| `states/p2-reference-arm.log` | `f5744175fbc5123e79f1ec9379489a225e2a86773d07812fa672524e14e39610` |
| `states/p2-reference-arm/fixture.c` | `d1c50c94c8af53c0ef6608909a90eef9302425f9eba308972b34f2b51ac0d92b` |
| `states/p2-reference-arm/init` | `8be6d4e96b4457c24b114e6c3210c8a569cc3784d26c5b9c372fc2bb7e762564` |
| `states/p2-reference-arm/initramfs.cpio` | `6a66531976763755f3ea0a5044eac0d7076dddd5dacf02d4f29257cf9cf943f1` |
| `states/p2-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p2-reference-arm/probe` | `170454ca46fa486d0c1fce09e7105e702710e1f42d9e90816bbb28cd0ba5fb14` |
| `states/p2-reference-arm/receipt.json` | `1279d6360f9049f74376756fdc09c6641f94d4d97c66b1c0bc7e6ce9ac6574ae` |
| `states/p2-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p2-reference-arm/serial.log` | `c4fc18a63ed73c1f273d3f4e84c6a2c679f14c05e618b0ac046254dc06dd27db` |
| `states/p2-reference-arm/source/affabireferenceinit/core.v` | `1fe05aaada655ff047ea022722430dfffbc3cea13d3b7d103d73e52d70b40528` |
| `states/p2-reference-x86.log` | `fcef2658dbf89fa49353af4a8b834e65f46a32f4e2ff126e1413d6d929db5171` |
| `states/p2-reference-x86/fixture.c` | `d1c50c94c8af53c0ef6608909a90eef9302425f9eba308972b34f2b51ac0d92b` |
| `states/p2-reference-x86/init` | `2a59c05b8b74fda90a0df60a83fd8589ff842c9aeef563afe870fb1b79049247` |
| `states/p2-reference-x86/initramfs.cpio` | `6c43fc173009cf67f0e6b3494eb74f255ba613b8cc58375858af18d1afa0d8be` |
| `states/p2-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p2-reference-x86/probe` | `c4a5e5a6ba17781b026c420c6caae299a5b4ec9d8c682d19a3ecb059d07077a7` |
| `states/p2-reference-x86/receipt.json` | `afa89d3077dffc37209ff617f0e5566a8d95046c1e8042c87c0321d4c3daf219` |
| `states/p2-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p2-reference-x86/serial.log` | `0986fa5fbc23b8b17b0701d672bca7681d0c6fb79ab11ccbc54533497177002e` |
| `states/p2-reference-x86/source/affabireferenceinit/core.v` | `1fe05aaada655ff047ea022722430dfffbc3cea13d3b7d103d73e52d70b40528` |
| `states/preflight1-affabi-arm/fixture.c` | `38ffca5f282e12758ce1fd9b474f663d6a47689a0a1ea591a47bf07ba7629371` |
| `states/preflight1-affabi-x86/fixture.c` | `38ffca5f282e12758ce1fd9b474f663d6a47689a0a1ea591a47bf07ba7629371` |
| `states/preflight2-affabi-arm/fixture.c` | `ad258ec6d7a0f63fe806605260be35556f4504130d05ccf7b382e4c9ea7ea112` |
| `states/preflight2-affabi-arm/init` | `72b899faefb4c10e763f42cfae12e37a92cc3caaea58a338862477338296f503` |
| `states/preflight2-affabi-x86/fixture.c` | `ad258ec6d7a0f63fe806605260be35556f4504130d05ccf7b382e4c9ea7ea112` |
| `states/preflight2-affabi-x86/init` | `b63b6a7bac50745f65f7697be99200d75137e2faf3b44cae8a2f8749fc6c9ffd` |
| `states/preflight3-affabi-arm/fixture.c` | `5f078939b42a25668def6b7fd8bb25c20329df87d0aa27f33aa5b55da14cbd3e` |
| `states/preflight3-affabi-arm/init` | `170454ca46fa486d0c1fce09e7105e702710e1f42d9e90816bbb28cd0ba5fb14` |
| `states/preflight3-affabi-x86/fixture.c` | `5f078939b42a25668def6b7fd8bb25c20329df87d0aa27f33aa5b55da14cbd3e` |
| `states/preflight3-affabi-x86/init` | `c4a5e5a6ba17781b026c420c6caae299a5b4ec9d8c682d19a3ecb059d07077a7` |
| `tests/linux-compat/affabi-check.v` | `cd25187d6e66e400f3d2be2dddad85764fb9cce0bcca2b79474c45338a69b3cc` |
| `tests/linux-compat/affabi-reference.v` | `a1de347ec28cf620fede55c61e121d963799db7b7ba5ec60fbe4c15040cdd815` |
| `tests/linux-compat/affabifixture/core.v` | `d3f1524a56978720649930294770174cbf8803682882b1e10af880139643a00f` |
| `tests/linux-compat/affabireferenceinit/core.v` | `1fe05aaada655ff047ea022722430dfffbc3cea13d3b7d103d73e52d70b40528` |
| `tests/linux-compat/run.v` | `53e67ab0a320f4aaafcf50f34b5fa2d6b4447275a6d41f3b575baea78a349d52` |
| `watch-p2-retained-inputs.json` | `112ed78133136c2be8eaa76ca3534133aa89790acfe265352b5f24718cb5a6f9` |
| `watch-p2.log` | `f1f93e7af61b3057f245d98ca44dc4f9a0825ea9b7c93299b39d94e9857b4b4a` |
