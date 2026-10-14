Independent rrabi lifetime review: PASS

Reviewed the native RR interval query fix against frozen baseline `509d83f1903c9b968bd942a487754f16356e2a73`, the final V fixture/reference/controller/auditor sources, original and corrected production C on both architectures, preflight1 probe C/ELFs, original/Linux p1 captures, fresh corrected p2 captures and both completed six-case p2 native receipts. No lifetime blocker remains. This review qualifies signed pid_t decoding, task-before-output error precedence, interval-copy guards and the bounded observed state; it does not qualify general scheduler execution.

The kernel change narrows the incoming register word through unsigned32 and signed32, then uses the existing target lookup and copied scheduling parameters. It removes the early null-output return so negative/absent task errors precede output faults. The corrected source also describes Vinix interval durations without asserting that every Linux scheduler reports zero for non-RR policies. Independent source assertions require exactly these replacements. Independent complete-C assertions remove exactly the RR query definition and normalize only its renamed prototype parameter; all remaining production C is byte-identical per architecture. The changed body is exactly its original body with the early null check replaced by the scalar conversion.

The existing proc.thread_sched_params() validates the TID, acquires the PID table lock, copies t.sched into an Option value, and releases the lock before returning. No Thread pointer escapes. The query keeps a value copy of the parameters and a stack TimeSpec live through the existing synchronous copy_to_user. There is one unchanged output-copy call and no allocator, free, scheduler mutation or deferred borrow in the changed body. The scalar conversion adds no lifetime. This scope does not establish race or cross-task permission conformance.

Probe previews and staged native/preflight C are byte-identical on both architectures. Independent assertions require eight explicit alloca sites, fixed C arrays, a real 4096-byte stack snapshot buffer, stack scanf scalars/wait statuses/sched_param/timespec values, and no malloc/calloc/realloc, memdup, dynamic-array or v_fixed_index calls. Query copies errno before any state observation. Raw syscalls and the genuine bundled-musl sched_rr_get_interval wrapper borrow output pointers synchronously. interval() copies into an aligned local timespec before reading, so unaligned output tests do not perform unaligned typed loads. No stack pointer is stored for later use.

Each cohort owns a three-page anonymous mapping. It initializes all pages while writable, makes the middle page read-only and the last page inaccessible, and retains the mapping through every query/guard check. The fixture never directly reads the inaccessible page. A valid target cross-page fault may modify only its accessible prefix; task-validation errors must leave that prefix and the other observed guards untouched. All nonfatal paths unmap the complete mapping before result reporting. Setup failures terminate the cohort and rely on process cleanup; they cannot report success.

Root and UID 1000 cohorts run in sequential forked children. RR priority 1 is installed and verified while privileged; the ordinary child then drops supplementary groups, GID and UID and verifies real/effective credentials before querying the unchanged RR state. After realtime controls each child restores OTHER before the main matrix. The temporary exited target is waited/reaped before its PID is used as an absent-task case. Each result pipe closes unused ends in both processes. Child Counts is zero-initialized and remains live through qualification and its single synchronous 64-byte write. Parent read uses identical sizeof(Counts), examines data only after an exact read, closes its reader and waits/reaps the cohort before proceeding. A short transfer or nonzero child status fails the test. Fatal paths exit and release their process-owned descriptors/mapping. No worker, callback or escaping alloca is added.

The slab observer opens once per successful native cohort and closes on every nonfatal return after opening, including cycle/snapshot failures. Its before/after snapshots are stack alloca values initialized by snapshot() and retained through comparison/reporting. Parsing bounds the read before the terminator write, caps rows at 32 and traverses the buffer within its length. The reference wrapper has one three-pointer argv alloca that remains live through synchronous execv; success replaces the image, failure returns an explicit error. Host reference/controller/auditor work uses existing bounded sessions and closes process/file handles; the auditor streaming hash buffer is freed after its synchronous use. Host allocations are bounded to the one-shot host process.

Counts are [60,360,60,19] per cohort: six PID targets, ten output forms and one canonical raw word, six alternate upper-register forms, one genuine musl wrapper form, plus sixteen successful RR interval queries and three final state/guard controls. This yields 499 controls per cohort and 998 per architecture: 960 guarded OTHER queries, 32 RR queries and six final controls. Targets include zero/self, negative IDs, positive absent and reaped-child IDs; output forms include valid/aligned, unaligned, end-of-page, null/low invalid, read-only/inaccessible/cross-page and full-width invalid pointers. Native expected durations remain 5ms RR and zero OTHER. Actual Linux reference durations are scheduler/configuration dependent, so the reference requires normalized nonnegative timespecs and positive RR rather than equality with Vinix.

Independent count assertions require all CASES and FINAL rows, both cohorts, all four kinds, exact counts and no duplicates. Each original native kernel fails exactly [4,240,4,12] per cohort, or 520 per architecture, without a setup failure. Corrected native kernels and unchanged-ELF Linux 6.12.51 references pass every control. Both corrected cohorts run 32 warmups and 200 measured query/error/state cycles separated from snapshots by thirteen-second settling intervals. All 18 ARM and 14 x86 slab classes are present, unique and exactly flat per cohort; large pages are 63/63 ARM and 160/160 x86. Failing originals and reference mode skip native storage observations. These observations establish bounded repeated-call storage behavior, not general leak freedom.

The completed native profiles each contain six zero-status cases: rrabi, runtime, schedabi, schext, open and fcntlabi. Independent artifact assertions recompute every case source/ELF/ISO pin and staged-kernel pin. Each architecture uses its identical probe ELF for original/corrected native, preflight1 and actual Linux reference. Independent Linux receipts bind the supplied kernel, probe, wrapper source/C/ELF, initramfs, serial adapter/transcript, QEMU binary and controller source. passed=true, finished=true, forced=true and status=0 are required: the successful probe pauses and the controller stops QEMU after PASS. This is semantic reference qualification.

All independent assertions were compiled without -prod. A deliberately false assertion exited 1 with the rrabi assertion-control marker. Feeding the passing Linux ARM capture to the original-baseline checker also exited 1, at failures=0 versus required 4. Independent source/complete C/compiler-pin checks, all six count/storage checks and complete artifact assertions exited 0. The maintained auditor source was independently inspected, including its actual negative controls and source/C/ELF/receipt bindings; its publishing execution remains with the parent. All 15146 pinned compiler inputs were independently rehashed. Comment-only rebuild C is identical to corrected C. The existing allocation-allowance refusals are unchanged and are not represented as a globally passing allocation policy.

The first corrected p1 profiles encountered host filesystem exhaustion while preparing their last case: ARM has an explicit xorriso No space left on device failure, and the x86 driver could not save its aggregate. Their RR captures independently pass, but those profiles are preparation diagnostics and are not counted as completed six-case qualification. Both retained receipts and the ARM aggregate are pinned below. Fresh p2 profiles supply the complete corrected qualification. An independent helper rebuild also encountered the same full filesystem and was recompiled successfully after space was reclaimed; no fixture/kernel preparation failure is treated as a semantic regression.

Qualification remains bounded to native unpledged musl ELF64 callers, these output/error/interval controls and observed caller state. Complete scheduling attributes, capabilities/RLIMIT rules, races and peer permissions, FIFO/deadline/EXT execution, GNU libc, translated/ELF32 paths and broader roadmap section 15 gates remain separate. This review changes only its owned report in the repository and does not commit implementation.

SHA-256 pins below were independently recomputed after all relevant producers completed. Paths are relative to `/Users/alex/.cache/vinix-linux-compat/rrabi-20261014`, except repository paths beginning with `kernel/` or `tests/`. Identical probe/C pins are enforced across each architecture's original/corrected/reference captures.

| File | SHA-256 |
| --- | --- |
| `kernel/syscall/table/linux_compat.v` | `c925dde7b04e8fb6798b48b5b0afa7007d5e43c74505e2f10bc9e8d2c9e3e688` |
| `tests/linux-compat/rrabifixture/core.v` | `1dbb6631fbff3080966eaabecb56c4efa37b53bb3df2979ad68da9be7e8b874e` |
| `tests/linux-compat/rrabireferenceinit/core.v` | `9dc14cd7baf11b884466a5de31327f18524d2c13325593e7e5f2a5121348824a` |
| `tests/linux-compat/rrabi-reference.v` | `ca0057dbae2aba4d22937f6d872a799881075c23da4829579b29655cb59264ba` |
| `tests/linux-compat/rrabi-check.v` | `be2c1695557bed4e74c7a57e9b0898e425fe07813335df8cb8c95b384ef768d4` |
| `tests/linux-compat/run.v` | `18aca42bb8a12a816c6214833b264344f26e7e17baba6ef47ee675ec50896916` |
| `base.txt` | `2cb906f6cbec2f8fa85051d467f08bd91a7cf8cbb3488ffcfb0358c3ea2c15dd` |
| `before-linux_compat.v` | `014f8ce8e4c9bf6e39c07ce378e37ddd2821b6a66ac926ccb15799a6a0d6eda4` |
| `after-linux_compat.v` | `c925dde7b04e8fb6798b48b5b0afa7007d5e43c74505e2f10bc9e8d2c9e3e688` |
| `before-arm.c` | `72d504ee19730171150dd81aed210189c337237934de5b906166863f37c94980` |
| `before-x86.c` | `247ce15a0f4fde9242b43c88eb25a8c36cc0408c6d80c1574d7a82622ee7f861` |
| `after-arm.c` | `9c28673c39af042e43dfb8a1924ee8b2c9a6691d6762b0050fddd039f4c7a176` |
| `after-x86.c` | `4054621bdbd4e80a7c182ecfaf020e7069b94c5d0586a6d76cefc088ead49890` |
| `comment-preparation-after-arm.c` | `9c28673c39af042e43dfb8a1924ee8b2c9a6691d6762b0050fddd039f4c7a176` |
| `comment-preparation-after-x86.c` | `4054621bdbd4e80a7c182ecfaf020e7069b94c5d0586a6d76cefc088ead49890` |
| `preview-arm.c` | `8e8669868533c177310e4946be416d0a371d4ae6348e0045951861481682b48b` |
| `preview-x86.c` | `8e8669868533c177310e4946be416d0a371d4ae6348e0045951861481682b48b` |
| `independent-code.v` | `1f9f7c8f3f3dfe84138f939ca15143c2be162ddb3c43bb49f84ef002af143cb2` |
| `independent-counts.v` | `e3e44a252505a7b0a20e95e0a66f9da903407c4744c8d3ebcc8595d0e4f0247d` |
| `independent-artifacts.v` | `7980cc8e5b89b3ea57257005604b3062264ae1e7653d17aedc8d5bf0f3337529` |
| `independent-controls.v` | `91e2acd93b6fe4ad209c37be289bcf7da91c78b48f23f3a14bd64ede12e78a36` |
| `independent-false.v` | `ad24309ad3bb390243c95b894dc952e995a502812f158242e6d4242bdb800e52` |
| `independent-code` | `c4bc85fccc43def4c77927647d1c782ecc96d1337e3f9c869cc566081e38e946` |
| `independent-counts` | `29e115b8129e451b412762e6a73692955417f6de1beb688f4b2fa3c8a76ea444` |
| `independent-artifacts` | `d54b15b7ab5a3b8301e781398fe7975763ab055932926da9eb7752d97075d9c9` |
| `independent-controls` | `2e059c84cfae9a83c23f6302f5e43c3e03bedf397162d8685d7a47ada3ba7d77` |
| `independent-false` | `ed97cc8b93b529e6d61eb0f70fc6ea28641b06a2c2ae71e1ffbd45f83199b0e1` |
| `independent-code.log` | `e6a4193560e76b0a2e7f71823c64a058cca7d3b4b302fb7210b77266b6a7ff41` |
| `independent-artifacts.log` | `3a4b66d15794b552191e3181c95777bc6e958d1d8483049771ed18adad63138d` |
| `independent-false.log` | `e7712fd70a666e5297809df982ae0b70234bd3a35584bfd328034f5a9fc583fd` |
| `independent-baseline-control.log` | `c691578b73cf6addb7364e341b704a91ce64ce6e04d04b8d4343876ada69caa1` |
| `states/preflight1-rrabi-arm/init` | `c4fa4490cfc1f9997ab8018831a242c1c4fdc5099bb6c59bbccceb1b88890f5a` |
| `states/p1-before-arm/kernel/bin/vinix` | `c84ef58e3bbfce142bf0ba442cc85ba1ec740903922b378d0199ac32f8b2b6f4` |
| `states/p1-before-arm/rrabi/init` | `c4fa4490cfc1f9997ab8018831a242c1c4fdc5099bb6c59bbccceb1b88890f5a` |
| `states/p1-before-arm/rrabi/serial.log` | `a6424a2d254837a44a433a77460969806b3bc8b62c707a6d28779341d16ba0b9` |
| `states/p1-before-arm/receipt.json` | `cd7f4f39e2e801be902b2988814351789afd31ed6e0465d71e6b81044a147984` |
| `states/p2-after-arm/kernel/bin/vinix` | `02cfdf36f0f917367b8228408bf6e5ad3c421c0b364f3b1174754117f506291f` |
| `states/p2-after-arm/rrabi/init` | `c4fa4490cfc1f9997ab8018831a242c1c4fdc5099bb6c59bbccceb1b88890f5a` |
| `states/p2-after-arm/rrabi/serial.log` | `e59c34856dbae48c5987a6f3735018017e4007077760f3046aaa426a204fff3b` |
| `states/p2-after-arm/receipt.json` | `375f78e03e8657684993b72bca9410de19d8dda95d296a0630026b1c423cdd2d` |
| `states/p1-after-arm/receipt.json` | `502000432e371f9a02a47758df3ecd904e9f2b869cd6d393b68c9a78169f19b8` |
| `states/p1-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p1-reference-arm/probe` | `c4fa4490cfc1f9997ab8018831a242c1c4fdc5099bb6c59bbccceb1b88890f5a` |
| `states/p1-reference-arm/fixture.c` | `4c30a5e3e30e4813e7ebc43c706da60a598c1d93bf8b298c283fcf98537c9968` |
| `states/p1-reference-arm/init` | `9abfe3d2e45c451edf7d9b765b7d08d33a95019ac695848428815fac4d1bdc1e` |
| `states/p1-reference-arm/initramfs.cpio` | `c4eed2cf763059f1531754f74b13ce13a6bdc6ba130ab0e460056874952f999a` |
| `states/p1-reference-arm/serial.log` | `58a9189f9d5d92a600d1851ffa7bd4bde0aee828c83a0f5835c5dedaca3ea56d` |
| `states/p1-reference-arm/receipt.json` | `c5f84b69fbac4bfaf738997f628d645d028dc06c6091f68b624cf18e8836baee` |
| `independent-counts-before-arm.log` | `9216f92ac6ca76507a80eae6cd134c15b23979b51c10bcc2fc630524f6953d61` |
| `independent-counts-after-arm.log` | `db1028d3704a40ade6ac4a67890a186721a6c6a387c7b8e988dc176489cb8ebc` |
| `independent-counts-reference-arm.log` | `5ce14ee4254302edb31f8d712d4615f8db5fd766362b8052d1040057fac80e1a` |
| `states/preflight1-rrabi-x86/init` | `30dac28706d071bfc98643a65db8ec9ebea3854430f9f944bf7843140e7df680` |
| `states/p1-before-x86/kernel/bin/vinix` | `45b4b73248030dccda9fc231e7fd8862f7d361f6bfab30d3dc5665ec46b940f2` |
| `states/p1-before-x86/rrabi/init` | `30dac28706d071bfc98643a65db8ec9ebea3854430f9f944bf7843140e7df680` |
| `states/p1-before-x86/rrabi/serial.log` | `2cb623bc71c69dfe6f063f40644a6cee44da4a801b922a5a79fc09b9ddc1f90f` |
| `states/p1-before-x86/receipt.json` | `9935730e6ea09cc48caf57d45cba9c2983a485e9636bb607339ba16f6a7c2663` |
| `states/p2-after-x86/kernel/bin/vinix` | `cf687e02f2ef3f35f5dde6b6e618651fc34b030173f5a9b858395382cf9e26ad` |
| `states/p2-after-x86/rrabi/init` | `30dac28706d071bfc98643a65db8ec9ebea3854430f9f944bf7843140e7df680` |
| `states/p2-after-x86/rrabi/serial.log` | `624e788d876428e0aed4825c0c80d04190d07e69c027adf52f2fe693143e17b9` |
| `states/p2-after-x86/receipt.json` | `2eb4cfe427492c4016f42b1a022dc144a02048715b0c783e601f282ab8cac514` |
| `states/p1-after-x86/receipt.json` | `ee9a98a3a7e383eaf4e16c06c58586d50df6a14f7f5aac9fb92bbdcfddeee6a3` |
| `states/p1-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p1-reference-x86/probe` | `30dac28706d071bfc98643a65db8ec9ebea3854430f9f944bf7843140e7df680` |
| `states/p1-reference-x86/fixture.c` | `4c30a5e3e30e4813e7ebc43c706da60a598c1d93bf8b298c283fcf98537c9968` |
| `states/p1-reference-x86/init` | `440d2075ce8dbdad73090bd148894f035c9b260014ba02be503e307286447ae5` |
| `states/p1-reference-x86/initramfs.cpio` | `7b9f1c7518372616268456156c89a19f728da22e152384d01a4de33c79d76bdf` |
| `states/p1-reference-x86/serial.log` | `1522730dd479a37b096253ffa02b4bffd515bfdc4ea4595aee8b53a7a12718bd` |
| `states/p1-reference-x86/receipt.json` | `fce860d755d011638ede62163efeefac37e1b1191e35e7aa4e2a0c5b30cca68a` |
| `independent-counts-before-x86.log` | `90ad7dc23e49a21f3685281abae87c8b51eb3185582aafd3023a39e32cdcb990` |
| `independent-counts-after-x86.log` | `6ccae41a1ce172210e184129451bc3620e3715cd986f0cf2d0143094de47c668` |
| `independent-counts-reference-x86.log` | `4750d2cf14799c62318f34bf4523dd80cc149faca990d07d0c9e2af19c75f547` |
| `states/p1-after-arm.log` | `65c1c57d13ef9dd5e5d59891f342ee7be3abf722903b45fef2367acd3469105b` |
| `../proctask-20261014/compiler/v` | `9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b` |
| `../proctask-20261014/compiler-inputs.json` | `fbcba16306f70092c3b0df0cad3776ab7c3e8be13ef1a4797a07b21f3dd71074` |
