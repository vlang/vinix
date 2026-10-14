Independent attrimport lifetime review: PASS

Reviewed the native sched_setattr import change against frozen baseline `9e884558a291c38cbf550fc85a90052ecdb04e80`, final V fixture/reference/controller/auditor sources, original and corrected production C on both architectures, final preflight2 native C/ELFs, p3 native captures and unchanged-ELF Linux references. No new lifetime blocker remains. This review covers native attribute import, its errors and writeback, guarded caller input, and observed self-task policy/priority transitions; general scheduler execution and permissions remain separate.

Independent assertions remove exactly the setter definition/prototype and the two new import helper definitions/prototypes: all remaining production C is byte-identical per architecture. The existing V scheduler mutation body is also byte-identical after removing the relocated utilization-flag declaration and short-layout guard. Generated C changes only the existing deadline division's scratch names from _t1/_t2 to _t3/_t4 because the new mixed-sign errno comparison consumes those names; the maintained auditor checks the precise two/three occurrences and then requires exact mutation-body equality. No scheduler ownership, allocation or release path is introduced.

The size-error helper keeps its four-byte known-size value on the stack through synchronous copy_to_user, deliberately ignoring a failed writeback before returning E2BIG. The tail helper keeps one aligned eight-byte word on the stack through each synchronous copy_from_user; neither checked-copy routine retains the kernel buffer. Generated C confirms actual local scalar declarations and direct address borrows, without malloc/calloc/realloc, memdup, dynamic-array, free or new index-helper calls. The setter's existing local size, zero-initialized SchedAttr and copied SchedParams remain values. The existing target/owner pointers are borrowed only under the unchanged PID table lock; the parameter getter returns a copied value and the setter validates/relooks up its TID under that lock. There is no deferred user-pointer or stack borrow and no new free requiring a grace period.

Signed low32 PID decoding and NULL/negative/flag entry checks precede import. The fetched size is normalized from zero to 48, then bounded between 48 and the native page size. Full advertised-range validation prevents wrap and user-half crossing before extension arithmetic; consequently attr_ptr + copy_size and the extension length are bounded. An aligned tail start subtracts only its low three address bits, and its remaining count adds at most seven. The first-word skip and final-word masks shift by at most 56 bits, and the cursor advances only while at least another word remains. Independent V assertions check 1,635,216 byte-selection and bounded-traversal controls across 4 KiB/16 KiB pages and all alignments. Both native architectures are little-endian ELF64. Nonzero extension bytes return E2BIG before a later-word fault; the kernel copies the known min(requested_size,56) prefix only after a zero extension passes. Negative policy and short utilization layouts precede target lookup; existing later policy/permission behavior is retained. Linux's [check_zeroed_user](https://github.com/torvalds/linux/blob/v6.12/lib/usercopy.c) uses aligned words and masks in this order; [sched_copy_attr and sched_setattr](https://github.com/torvalds/linux/blob/v6.12/kernel/sched/syscalls.c) establish the size/writeback/import ordering.

Final preview C and staged native/preflight C are byte-identical on each architecture. Independent assertions require nine explicit alloca sites, fixed C count arrays, the real 4096-byte stack slab buffer and no heap or fixed-index helper calls in the fixture. Unaligned syscall inputs are initialized/compared with memcpy/memcmp, rather than typed unaligned accesses. Each Query copies errno immediately. Attribute and saved-input buffers remain live through their synchronous calls and comparisons, and each initialized or compared byte is within the mapped readable prefix or the local buffer.

Each cohort owns a four-page anonymous mapping. Its last page stays PROT_NONE; the preceding page is temporarily writable for setup and becomes read-only before each syscall. The matrix never directly reads the inaccessible page. Writable E2BIG cases require only the four-byte supported-size header to change; read-only E2BIG cases require the original header to remain unchanged despite the failed best-effort writeback. Nonzero extension controls retain their tail marker and preceding guard. The read-only PAGE_SIZE input that begins eight bytes into the third page correctly requires EFAULT when its extension reaches the inaccessible fourth page. The full mapping stays live through the matrix, final guards and storage observations, then is unmapped before reporting. Fatal setup/cleanup paths terminate without PASS and rely on process cleanup.

Root and UID/GID 1000 cohorts run sequentially in forked children. Both begin in OTHER; the ordinary child drops supplementary groups and verifies real/effective UID before exercising self BATCH transitions. Successful setter cases verify BATCH with priority zero, and rejected cases verify OTHER with priority zero; every case restores OTHER afterward. A separate child is waited/reaped before its PID becomes an absent target. Both processes close unused pipe ends. The child initializes Counts, sends its exact fixed size synchronously and closes its writer; the parent inspects Counts only after the exact transfer, closes its reader and waits/reaps the cohort. Short transfers or nonzero child status fail. The Linux wrapper's three-pointer argv alloca stays live through execv; success replaces the process and failure is explicit.

The slab observer descriptor stays open through warmup and both snapshots and closes on all nonfatal return paths after opening. Parsing bounds pread and the terminator write, caps rows at 32 and never passes the returned length. The before/after Slabs values stay live through comparison/reporting. Host process handles close after waiting; the independent artifact checker and maintained auditor close hash files and free their bounded streaming buffers after synchronous hashing. Host data is retained only for bounded one-shot sessions.

Counts are [2304,4608,2304,39] per credential cohort: six targets, sixteen sizes, two flag values, twelve input forms and four word variants, plus 36 policy/utilization/unsupported-flag precedence controls and three final state/input checks. That is 9255 per cohort and 18510 per architecture. Both CASES and FINAL sets are independently checked for exact counts, both cohorts, all four kinds and absence of duplicates. Fresh p3 originals fail exactly [414,1814,414,20] per cohort, or 5324 controls per architecture. Corrected kernels and identical-ELF Linux 6.12.51 references pass every control. The fixture invokes the real musl syscall entry; no dedicated libc or GNU libc wrapper qualification is claimed.

Corrected native cohorts run 32 warmup and 200 measured success/error/restore cycles with thirteen-second settling intervals on both sides. Both cohorts include all 18 ARM or 14 x86 slab classes, with unique size classes and exactly equal live counts. Large-page totals are also flat: 63/63 ARM and 160/160 x86. These are bounded repeated-call storage observations. They do not establish general kernel leak freedom. The complete seven-case profiles contain attrimport, runtime, schedabi, rrabi, attrquery, open and fcntlabi with zero statuses on each architecture. Host tooling passes eight tests, the coverage checks pass four times, and before/after allocator scans are byte-identical at 398 ARM/290 x86 existing sites; their existing allowance refusals are not a whole-kernel allocation approval.

Independent receipt checks recompute every native source, ELF, ISO and staged kernel pin. The final preflight2 ELF is identical to the p3 original/corrected native and actual Linux reference probe on each architecture. Reference receipts bind the supplied kernel, probe, wrapper source/C/ELF, initramfs, serial adapter/transcript, QEMU binary and controller source, and require passed=true, finished=true, forced=true and status=0. A successful probe pauses until its controller stops QEMU. All 15146 compiler inputs are independently rehashed. Independent helpers are compiled without -prod: the false assertion and the passing ARM Linux capture supplied to the baseline checker both actually exit 1. The maintained auditor source and its negative-control, scope, capture, storage and publication bindings have been separately inspected; publishing remains with the parent.

Earlier p2 references fail exactly [4,8,4,0] per cohort because their fixture omitted the read-only PAGE_SIZE extension fault from its oracle. Those receipts, transcripts, preflight1 C/ELFs and matching p2 native inputs remain preparation evidence. Final p3/preflight2 artifacts use the corrected oracle. Initial ENOSPC builds and their missing-vsrc-symlink diagnostics are retained and did not produce semantic captures. Independent reviewer helper Result-propagation/include compile diagnostics are retained privately and do not count as conformance failures. Qualification remains native unpledged musl ELF64 self-task import. Nice clamping, capabilities/RLIMITs, peer/race/namespace behavior, scheduler timing/classes, GNU libc, translated/ELF32 callers and the broader roadmap section 15 gates remain separate. This review writes only its owned repository report; the parent owns implementation and committing.

SHA-256 pins below were independently recomputed after their producers completed. Paths are relative to `/Users/alex/.cache/vinix-linux-compat/attrimport-20261014`, except repository paths beginning with `kernel/` or `tests/`.

| File | SHA-256 |
| --- | --- |
| `after-arm.c` | `71e4612ada9924966312e4130f3ffed87611fbedfa1677ebd58cd71e54a45b02` |
| `after-gaps.v` | `de5c4bfe2c7b5528bc63c02b22720130d526699131d65b34b4e6a9f721eb569d` |
| `after-x86.c` | `bd9e8d938ce2cb55f540b92cd7ec5e496b6020547cc33d96ef699466c09962e4` |
| `allocs-after.log` | `005f305d6417f17e435d5c113b0a4965d1c889e69c4f097f5bcef38c1f65bae7` |
| `allocs-before.log` | `005f305d6417f17e435d5c113b0a4965d1c889e69c4f097f5bcef38c1f65bae7` |
| `base.txt` | `b1f46c9dae96a8f6ab2108107c016b3c6595fb561c376339d7ebb3ad49cdbf4d` |
| `before-arm.c` | `5c48429ed995e8b42f81a23c2c170d7da2ec423383c37c5cfd1f3bdfd859f538` |
| `before-gaps.v` | `4c7577f75dbcb06f5efdcdbcb1ea6be2a6452d104497837c4c30ed4ed0d92c84` |
| `before-x86.c` | `6f39d22a67d3da618282b8e725e73d5ea44190bcf98162e09814afb39f620187` |
| `build-after-arm.log` | `e947f4bc04ef9d32fb96011da61b361bc25d9cd7b0f677c33b8f1aeb1a09257c` |
| `build-after-x86.log` | `96ab83f387875a4f1482f4b80c619633ab061aa1e13812c834b8e1a18605c233` |
| `build-before-arm.log` | `cdc5e851ec2c9903630c9b8e284374727b67357de7331f3a0719aab36a309b35` |
| `build-before-x86.log` | `6842d1cb28f4cd0b45d4159be740688c754ce4445c9702d0b4a09991da2b8dd9` |
| `build-preparation-space-arm.log` | `79d4068863dcd8ca87c7e4b2c439f86c49f7e68894ac4121846294ae5c03d03f` |
| `build-preparation-space-x86.log` | `e1aa0d27b42fa4b7e3cc2f39d2ee2917a2f7d471873aa0b98f1285bdedd732eb` |
| `coverage-check.log` | `f14b0219fd4094c269a82b893f4a2424ffc8461e1745db3f9971f06dd81031fb` |
| `host-tests.log` | `74003b86bbae78c5fc95b0a7b8a2d1b8f858a2027420fe1a3fb1601851863856` |
| `independent-artifacts` | `16aac67449252efc082ee585cb4a84f41f80dca37c36fcaa5994fd4a5ca3c79d` |
| `independent-artifacts.log` | `93a98926bb6bdb9e8ecb5ced441e029f8671e6beefa149a5b05769055a204abc` |
| `independent-artifacts.v` | `df6714249e2571be1dde320baf8181ac9333926e84de847c0d48b792f52163a1` |
| `independent-baseline-control.log` | `5bd8f8588cb7a86345c072fcf898a4cbc93db404d17d4c3abfbbfbd56884a585` |
| `independent-code` | `eb07225daf8c1dfbcc0d50f09b2746fd5817b2b80166547dff2c1fec8c27e6fb` |
| `independent-code.log` | `f82cb2a74ef9fdd379efb0424931172ac937353be47f3e91c00bd3a21a4144d7` |
| `independent-code.v` | `6be3beddbe872f451b65623443ef1fe36524542a4c4b2972af0354a0c63e192b` |
| `independent-compile.v` | `76fe1cafd77fe289ea434645603f849483f6827a0c183015ef45a8de927193e0` |
| `independent-controls` | `ab73e49b3307bca3a82bbed51b3ee08f22ec06d85da27b0b5495575bf3cee44f` |
| `independent-controls.v` | `964ead5c11625c8095fb821e7bac99d7a424cbeec4df09bdea4c367bf8447570` |
| `independent-counts` | `5134bacaab669aea7525404b63f7e1926e23c57d9bcbdea3870f9a9a3b422087` |
| `independent-counts-after-arm.log` | `f9c7bc23089b7f878a19fdd73e9bdf29250b1325bd838f244016b09e996e9726` |
| `independent-counts-after-x86.log` | `3cc21a23d5833bc1f65b0181f3e795dc65f5132e59166c2038a8fa7ddc4f6221` |
| `independent-counts-before-arm.log` | `c276a9be60eb8faeb40004302139759b1b029b73f8b012b886b35944a9fd79ff` |
| `independent-counts-before-x86.log` | `131e7b518274500ea5d514b3a5913848a8f3cf88642823a449d733e984765c19` |
| `independent-counts-reference-arm.log` | `a5fb0ede814c3ce0df4608957cd78132ac8d162eb5a8e3bec7391e2e9b7d3eaf` |
| `independent-counts-reference-x86.log` | `44897060231227daec5d5bdce027345179cfcb2846bd200cdfba2e7b96f72d8f` |
| `independent-counts.v` | `cc4d52a076598969dc2d4eb36d9bf835f13564cfb4a82e2e2678adc6ed5c432e` |
| `independent-false` | `d64d49a2e04eef24e0ed9022c847917a311cf6f6c58d0765d4eb999be0cbcb60` |
| `independent-false.log` | `39d5a7de68355d44466fcf0737a9dbad9198c577699b0e119fb9044b384174ae` |
| `independent-false.v` | `c2af5d63b16375d6365417921adee72efe89a1ec500431371173c49cb73a6e1a` |
| `independent-masks` | `7f434e8ac8b2c0acfe81fa5fb08b796126679fc550cc00ada67cbf24a20cacc0` |
| `independent-masks.log` | `b4d298f9249b24e5e7a56402a8dc4b57847ab2a9bf4d7ec14429f82ac8eedc21` |
| `independent-masks.v` | `8f8f90cd184ed4e6f8da4fbbac28d9ed70970fc0f6b1e9e5be1621f6bae24d90` |
| `independent-preparation-include-compile.log` | `5c65b11995d56d28856b0a99f188b7f16c95be23e03db8e2b73019895ca6cf74` |
| `independent-preparation-include.v` | `ac67dc547f95658cad96b792dad59b3feb031acccf9cfb60c2a1688fe2c954b0` |
| `independent-preparation-propagation-compile.log` | `132274207abff46935da59be49a653795fcc602a08729f38542eb6a361cffa70` |
| `independent-preparation-propagation.v` | `73bcfe4117be07850d4cb62ab3bc5d121eaebb2fefb33d984dc77f16dcbf9b8f` |
| `independent-preparation-propagation2-compile.log` | `365516e302ff5f6faaeeb6d8757486435ac26814000a90e571904f06d64673ac` |
| `independent-preparation-propagation2.v` | `cb5443b5cfb63673366affa1d4275a8d47a3506d631b0c590d8fa049326cce38` |
| `independent-preparations` | `72f801c584b311f145e6b147f1787fd9a6d1aa402836f26ea5fa605a6589c862` |
| `independent-preparations.log` | `95d7f25012f25dc0ce526b0e2929e00748d7f20d31d73cb4948cd14c4f6b5596` |
| `independent-preparations.v` | `f310e1d20ebbc90107384cdf7ac48c76ffc03715532dcd7d8288388d387d5f8e` |
| `independent-prepare.v` | `1ccfba8ae68c3a67a5197d6d41fa858016367e5dba7a7a24c79eb54090ce91ad` |
| `independent-report-prose.md` | `e462dff01d3dfe641974060814947e18f269ac54ee528c013a84e973085d6489` |
| `independent-report.v` | `7ae3b1c282ff82737f51a150c7f605c7728552410593c3ddc16b6a9436bcc218` |
| `kernel/syscall/table/gaps.v` | `de5c4bfe2c7b5528bc63c02b22720130d526699131d65b34b4e6a9f721eb569d` |
| `preparation-extension-preview-arm.c` | `b3ac898149b0746538a3a0922e4148726dbfcfb04fd9956f42f09ea50ffbd290` |
| `preparation-extension-preview-x86.c` | `b3ac898149b0746538a3a0922e4148726dbfcfb04fd9956f42f09ea50ffbd290` |
| `preview-arm.c` | `962a0933bd5988449c889075854dda060a5b4ff362847bb3f50b050d92a5889d` |
| `preview-x86.c` | `962a0933bd5988449c889075854dda060a5b4ff362847bb3f50b050d92a5889d` |
| `states/p2-before-arm/attrimport/fixture.c` | `b3ac898149b0746538a3a0922e4148726dbfcfb04fd9956f42f09ea50ffbd290` |
| `states/p2-before-arm/attrimport/init` | `a5e20c356ed8d6ab611f738e4d212a4324bb7e71972787e348f71bb986e2076a` |
| `states/p2-before-arm/attrimport/serial.log` | `bbfb14be7f66b4ffe667895e9cb21a21b87db712331d41d5e6282dea38de41e2` |
| `states/p2-before-arm/receipt.json` | `eca7de4f5eb42c24ef53191a4c3fe6ec5b14bf0d3b057fb885dfd90c16d1ec26` |
| `states/p2-before-arm/sources/attrimportfixture/core.v` | `022448ec79c62706e80d08d359e98f2d961297738f3418e2e4649b5f2409edfa` |
| `states/p2-before-x86/attrimport/fixture.c` | `b3ac898149b0746538a3a0922e4148726dbfcfb04fd9956f42f09ea50ffbd290` |
| `states/p2-before-x86/attrimport/init` | `8058adcbd6e0dc91a28e217bb1a981b71b97442138b31d2a7aa68a3af32d9c21` |
| `states/p2-before-x86/attrimport/serial.log` | `344e262eec25a9fc3e29b3bfc4511a2aad646074dcdda034f8a4411ffca4042c` |
| `states/p2-before-x86/receipt.json` | `b05ee18070ae596119c41a5e62e5c03ad89f98fbd5c7e8d013aad6fb7451f41b` |
| `states/p2-before-x86/sources/attrimportfixture/core.v` | `022448ec79c62706e80d08d359e98f2d961297738f3418e2e4649b5f2409edfa` |
| `states/p2-reference-arm.log` | `2bfe832478e6c1018d2389578c164b0a59f3722a7ed38b410a492e77d1452cf2` |
| `states/p2-reference-arm/fixture.c` | `d562f74ef560851e1b38e014b1449d75356d1d12fde673083acaae437593c331` |
| `states/p2-reference-arm/init` | `ef96d160263fc2ade86a4490dbcb1787081319f15b33ae816d4bd00be8312fc4` |
| `states/p2-reference-arm/initramfs.cpio` | `b7a200ebf3f9b2770030bb3c0e2d23eb9f6e4cb6805567dc89f338344387e1bb` |
| `states/p2-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p2-reference-arm/probe` | `a5e20c356ed8d6ab611f738e4d212a4324bb7e71972787e348f71bb986e2076a` |
| `states/p2-reference-arm/receipt.json` | `d48f7b9427772acef685096177c92c95d997a359f7966163213a07e4a9c9c19b` |
| `states/p2-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p2-reference-arm/serial.log` | `990ff3d7e800bdd35fba33bc2be0bd338ed4e82922e5d4d540266a4778449468` |
| `states/p2-reference-x86.log` | `f6f449ac870e94792f276678efa3ac2de5cced40aee77114f3eaa15f34cd691d` |
| `states/p2-reference-x86/fixture.c` | `d562f74ef560851e1b38e014b1449d75356d1d12fde673083acaae437593c331` |
| `states/p2-reference-x86/init` | `f83f938247b002346295d12f502d96ced157b7312c361d18ab8bc8bb589d1a0b` |
| `states/p2-reference-x86/initramfs.cpio` | `6997cfe9ea4a62ce00b19f95c665c8a208d6564aa5f9a78dc06d34a1d2805d68` |
| `states/p2-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p2-reference-x86/probe` | `8058adcbd6e0dc91a28e217bb1a981b71b97442138b31d2a7aa68a3af32d9c21` |
| `states/p2-reference-x86/receipt.json` | `2ccb262e1cdd42aee44d9a5d6c4daa13309b4033ef82cf796e8620f011631e27` |
| `states/p2-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p2-reference-x86/serial.log` | `b0bfc6f06589c794647b155d9f63601c50517d8bdde95db4e313ebb3bcfe9fa8` |
| `states/p3-after-arm.log` | `9a8b948357f74002184998f74f01e4e518ff946f892e5c8f5195d7085ef41703` |
| `states/p3-after-arm/attrimport/fixture.c` | `962a0933bd5988449c889075854dda060a5b4ff362847bb3f50b050d92a5889d` |
| `states/p3-after-arm/attrimport/init` | `4805664d48a3609e91df4d388b3d2caed44459b9496d450b0f93e96c5d819d1a` |
| `states/p3-after-arm/attrimport/serial.log` | `48513dccac93340a6887f41097bfd33d75ebad7860079ded02656a04c48aa10d` |
| `states/p3-after-arm/attrimport/test.iso` | `358da2ff01c2c2e871cedc145aa42d9822a992caa75e455b26eafadd76f67a8b` |
| `states/p3-after-arm/kernel/bin/vinix` | `a8bd258d6ec0c49e4ba091615d5d86bc0216e390c2eb52c028132ce765d5d381` |
| `states/p3-after-arm/receipt.json` | `e99fbd184dee7d542fa7f0344880ab1694f690e824d384ce1ecb5121dbf376bd` |
| `states/p3-after-x86.log` | `49085c4adce3190ca658cd17bcc6f3b3e7eb4ca8f0298f7be99fd30d8628c0f8` |
| `states/p3-after-x86/attrimport/fixture.c` | `962a0933bd5988449c889075854dda060a5b4ff362847bb3f50b050d92a5889d` |
| `states/p3-after-x86/attrimport/init` | `44c4e4bbbde3ebf4f527ae712af747cd53e066bfd73e9a00825afe070ae21917` |
| `states/p3-after-x86/attrimport/serial.log` | `c6dea594a1831c456686257fbdeddc24cff8b21f66e592773122a9f1855da075` |
| `states/p3-after-x86/attrimport/test.iso` | `c857b664ba953129501c9dd5d4f4d5bbd17d668dbe8fbbb18fc3d0af67e4a567` |
| `states/p3-after-x86/kernel/bin/vinix` | `8bc62bb3f1df92e965c426b35f0563482e3b9f7a000dd6a8a9e8b26311c0a108` |
| `states/p3-after-x86/receipt.json` | `83738ae6b0b30e079c049501735569e6cedb49bdf578c78f00c857b89874b67a` |
| `states/p3-before-arm.log` | `c5b116734b205dfca84f9afeeb95f4395dc7caa153356a70cc809a094f1f6ac0` |
| `states/p3-before-arm/attrimport/fixture.c` | `962a0933bd5988449c889075854dda060a5b4ff362847bb3f50b050d92a5889d` |
| `states/p3-before-arm/attrimport/init` | `4805664d48a3609e91df4d388b3d2caed44459b9496d450b0f93e96c5d819d1a` |
| `states/p3-before-arm/attrimport/serial.log` | `a3e731c21f07a0357b7500cbc4bcbb16f7024c83cb32ab72a2e8f834690169ad` |
| `states/p3-before-arm/attrimport/test.iso` | `33844210e4bac4414fa519f6f867d04248349955271f297eb9640d6a76deac06` |
| `states/p3-before-arm/kernel/bin/vinix` | `e40c9603b56fe78caf54fbe2b5489a9780a5c5ea8807139aa96f857cb6a3d657` |
| `states/p3-before-arm/receipt.json` | `875f801db5c3b0a5eeeddd237d85229f7c076a4401e5407777788630cffc3b92` |
| `states/p3-before-x86.log` | `9b625075aa2c98fe045fbd231bc2318547ce56d6c6ab19fd35d51ce93e7935a6` |
| `states/p3-before-x86/attrimport/fixture.c` | `962a0933bd5988449c889075854dda060a5b4ff362847bb3f50b050d92a5889d` |
| `states/p3-before-x86/attrimport/init` | `44c4e4bbbde3ebf4f527ae712af747cd53e066bfd73e9a00825afe070ae21917` |
| `states/p3-before-x86/attrimport/serial.log` | `79ac333e2012e3cf2f4b48db68f429bf4976d2d508a037580383c0657d1ae181` |
| `states/p3-before-x86/attrimport/test.iso` | `e63c00480581b8555e803101eff13b0de88ae192228991d0f7c45380340e6000` |
| `states/p3-before-x86/kernel/bin/vinix` | `1306489ac51df1fa675a7b9ff52764c3d3731e788302a7d1582c1724c8313e3e` |
| `states/p3-before-x86/receipt.json` | `8b91f1132a7d4a59129847efab70c13e211395c8ae1ed0eb692341c290fda51d` |
| `states/p3-reference-arm.log` | `41a50178642def23d421d65fee8f7202197aa9d7b337fba2ac9a6cdffc172ddb` |
| `states/p3-reference-arm/fixture.c` | `d562f74ef560851e1b38e014b1449d75356d1d12fde673083acaae437593c331` |
| `states/p3-reference-arm/init` | `ef96d160263fc2ade86a4490dbcb1787081319f15b33ae816d4bd00be8312fc4` |
| `states/p3-reference-arm/initramfs.cpio` | `0a768dfa0b4e684b2cbb77aeba0742052e9341183a7de118d30f0d2f80c4efdb` |
| `states/p3-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p3-reference-arm/probe` | `4805664d48a3609e91df4d388b3d2caed44459b9496d450b0f93e96c5d819d1a` |
| `states/p3-reference-arm/receipt.json` | `458a31dd6ab462bd7a78bbe6da8bbd175c2d027990fd610e6eecbea6b378fc59` |
| `states/p3-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `states/p3-reference-arm/serial.log` | `eb2591d863cda2916911831d504c3b2838231163571c7775fd7af3ac5d5dddb1` |
| `states/p3-reference-x86.log` | `41d34ef0b3bec325068d8f4d2ce5a80aaed210454055dcda14cce410135d1404` |
| `states/p3-reference-x86/fixture.c` | `d562f74ef560851e1b38e014b1449d75356d1d12fde673083acaae437593c331` |
| `states/p3-reference-x86/init` | `f83f938247b002346295d12f502d96ced157b7312c361d18ab8bc8bb589d1a0b` |
| `states/p3-reference-x86/initramfs.cpio` | `d518c352945f1244a41d0246e8ba25a82afff3a324842aaf8b8958ee347471e5` |
| `states/p3-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p3-reference-x86/probe` | `44c4e4bbbde3ebf4f527ae712af747cd53e066bfd73e9a00825afe070ae21917` |
| `states/p3-reference-x86/receipt.json` | `bf8e17ae9061f194b84055c03e091c7699489f4ff0ee27f22555d7e4410e9c67` |
| `states/p3-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `states/p3-reference-x86/serial.log` | `80173fb2195a091a46c0503ce164e4775190b3e8508c550e51810f296d709e8c` |
| `states/preflight1-attrimport-arm/fixture.c` | `b3ac898149b0746538a3a0922e4148726dbfcfb04fd9956f42f09ea50ffbd290` |
| `states/preflight1-attrimport-arm/init` | `a5e20c356ed8d6ab611f738e4d212a4324bb7e71972787e348f71bb986e2076a` |
| `states/preflight1-attrimport-x86/fixture.c` | `b3ac898149b0746538a3a0922e4148726dbfcfb04fd9956f42f09ea50ffbd290` |
| `states/preflight1-attrimport-x86/init` | `8058adcbd6e0dc91a28e217bb1a981b71b97442138b31d2a7aa68a3af32d9c21` |
| `states/preflight2-attrimport-arm/fixture.c` | `962a0933bd5988449c889075854dda060a5b4ff362847bb3f50b050d92a5889d` |
| `states/preflight2-attrimport-arm/init` | `4805664d48a3609e91df4d388b3d2caed44459b9496d450b0f93e96c5d819d1a` |
| `states/preflight2-attrimport-x86/fixture.c` | `962a0933bd5988449c889075854dda060a5b4ff362847bb3f50b050d92a5889d` |
| `states/preflight2-attrimport-x86/init` | `44c4e4bbbde3ebf4f527ae712af747cd53e066bfd73e9a00825afe070ae21917` |
| `tests/linux-compat/attrimport-check.v` | `1b0c85a174b3fba0045bdb6bffa7a2e40bcd91727b43cc737b9649005acdb6c3` |
| `tests/linux-compat/attrimport-reference.v` | `a28acfbda1e80cb88ea7f7b29756b6382d78a53c8098a3e1b06aebbeb592e0a0` |
| `tests/linux-compat/attrimportfixture/core.v` | `ea50d5decd874adb05f39d61b06e650f4163647c3fb7df84795333d55d1d62aa` |
| `tests/linux-compat/attrimportreferenceinit/core.v` | `33cb022697565610bd1ea01a2ca1965a047e8ea5605dd446e0e1d2c0d90c854d` |
| `tests/linux-compat/run.v` | `ade19dba228ce2297f0bfddbe1900819535d2d138ca59e5a66fc6c9b42734046` |
