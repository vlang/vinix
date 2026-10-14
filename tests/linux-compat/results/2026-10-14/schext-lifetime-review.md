Independent schext lifetime review: PASS

Reviewed the fixed SCHED_EXT priority-bound metadata change against frozen baseline `4142e9a49e2a4b317272e73cc98c5b698cad8d4f`, the final V fixture/reference sources, both fresh original and corrected production C builds, preflight2 probe C/ELFs, all six p1 native/Linux captures and both completed five-case native receipts. No lifetime blocker remains. This review qualifies the two priority queries and their bounded controls; it does not qualify SCHED_EXT installation, BPF scheduling or general scheduler behavior.

The kernel change adds one scalar constant and one SCHED_EXT predicate to each existing priority-query zero-bound arm. Signed 32-bit policy decoding, realtime bounds and invalid-policy EINVAL returns stay unchanged. Independent complete-C assertions remove exactly the two query definitions and the single constant definition; the remaining production C is byte-identical on each architecture, including the unchanged prototypes, setters, queue/lifecycle code, locks, user-copy and allocation paths. Each changed definition is exactly its original body plus the predicate and contains no allocator, free, user-copy or scheduling-mutation calls. There is no new kernel allocation, borrowed pointer or deferred lifetime.

Fixed priority metadata does not establish that a scheduling class can be installed. Linux names policy 7 SCHED_EXT, and util-linux documents that its zero priority maximum is exposed even without CONFIG_SCHED_CLASS_EXT. The change and probe leave installation outside their scope. See the [Linux v6.12 UAPI](https://github.com/torvalds/linux/blob/v6.12/include/uapi/linux/sched.h) and the [util-linux runtime-policy probe correction](https://kernel.googlesource.com/pub/scm/utils/util-linux/util-linux.git/+/a4c2ee5f7e0d5241f681ea1878a81db509476f15%5E%21/).

The final probe C is byte-identical across the architecture previews and all native/preflight2 staging copies. It has six explicit alloca sites, fixed C arrays and no malloc, memdup, dynamic-array or v_fixed_index calls. The scanf scalars, 4 KiB snapshot buffer and wait status are genuine C stack values. normal() initializes its sched_param, synchronously obtains the caller's priority and only reads it after a successful getter. Query errno is copied before those observations can change it. No pointer is stored for asynchronous use.

Root and UID 1000 cohorts execute in sequential forked children. The child verifies its real/effective UID after dropping supplementary groups and setting GID/UID. Each result pipe closes unused ends in both processes. Child Counts is zero-initialized, remains live throughout qualification and its synchronous 64-byte write, and uses the identical sizeof(Counts) as the parent read. The parent never reads a partial result, closes its reader and waits/reaps the child before proceeding. Fatal paths exit through process cleanup. No worker, mapped region, callback or escaping stack borrow is introduced.

The slab observer closes on every nonfatal failure and completed path. Both snapshots are stack alloca values, are zero-initialized by snapshot(), and remain live through comparison and reporting. Fixed arrays are traversed within their literal bounds; slab parsing caps its rows at 32 and bounds the input buffer before writing its terminator. The reference wrapper's three-pointer argv alloca stays live through synchronous execv; successful exec replaces the image, and a failed exec returns with an explicit failure. The host controller uses the existing bounded one-shot guest session and receipt path.

The arithmetic is [180,14,30,1] controls per cohort: sixteen policies, both min/max queries, six raw register-word forms and one genuine bundled-musl wrapper form, plus the final ordinary-policy/priority guard. The fifteen non-EXT policies supply 180 raw and 30 libc controls; policy 7 supplies 14 controls. This is 225 controls per credential cohort and 450 per architecture. Ordinary, realtime, batch, idle and deadline bounds, reserved/unknown/negative policies, reset-on-fork/high-bit forms and signed low-word decoding are covered. Raw calls also supply unused arguments containing bad-pointer values. No successful scheduling-class transition is attempted.

Independent V count assertions require every CASES and FINAL row, exact counts, both cohorts/kinds, no duplicates and the expected failures. Each original native kernel fails exactly [0,14,0,0] per cohort, or 28 per architecture. Corrected native kernels and actual Linux 6.12.51 references pass every control. The same architecture-specific probe ELF is used for original/corrected native phases, preflight2 and its actual Linux reference.

Each corrected native cohort executes 32 warmups and 200 measured priority-query/error/state cycles, with thirteen-second settling intervals. Every one of 18 ARM and 14 x86 slab classes is present, unique and exactly flat in each cohort; both storage summaries are required. Large pages are 63/63 ARM and 160/160 x86. Original kernels do not execute this measurement because their matrix fails, and Linux reference mode deliberately skips native slab observations. This establishes bounded storage behavior for these repeated calls, rather than general leak freedom.

The two completed native profiles each contain five zero-status cases: schext, runtime, schedabi, open and fcntlabi. Independent assertions recomputed every source/ELF/ISO/staged-kernel receipt pin and bound each case to its frozen source. Both Linux reference receipts independently bind the same probe, supplied Linux kernel, wrapper source/C/ELF, initramfs, serial adapter, serial transcript, QEMU binary and controller source. They have passed=true, finished=true, forced=true and status=0: the successful probe pauses, then the existing controller stops QEMU after observing PASS. This is semantic reference qualification, not guest self-shutdown qualification.

The first standalone preflights lacked a v_fixed_index definition and failed C preparation; neither produced a probe ELF. Their C and independent compiler-error replays are preserved as preparation diagnostics. The final literal-bounded loops use explicit unsafe traversal, and fresh preflight2/raw C identity checks pass without helper-block normalization. These preparation errors are not semantic baselines.

All independent assertions were compiled without -prod. A deliberately false assertion exited 1 with `schext independent review assertion control`. Feeding the passing Linux ARM capture to the same original-baseline count checker also exited 1, at failures=0 versus the required 14. Source/C, all native/reference count/storage and complete artifact checks exited 0. The review did not modify implementation or commit files.

Qualification remains bounded to native unpledged musl ELF64 callers, these pure queries and the observed ordinary policy/priority state. Complete scheduling attributes, capability/RLIMIT rules, races, realtime/deadline execution, SCHED_EXT/BPF installation, GNU libc, translated/ELF32 paths and the existing AArch64 multi-CPU QoS failure remain separate. No broad roadmap section 15 completion gate is asserted.

SHA-256 pins below were independently recomputed after all relevant producers completed. Paths are relative to `/Users/alex/.cache/vinix-linux-compat/schext-20261014`, except repository paths beginning with `kernel/` or `tests/`. Original/corrected/reference probe rows for each architecture require exact identity. Kernel sources in both corrected worktrees equal the repository gaps.v and after-gaps.v pin.

| File | SHA-256 |
| --- | --- |
| `kernel/syscall/table/gaps.v` | `94bfa493ebaa165a44cc3f4c786817778752f035bbfd91d6a5a604505c7a39d0` |
| `tests/linux-compat/schextfixture/core.v` | `355b497a5984b728a3838c352a99bcc75b9f4ee294c1cca2fc62e0eea3425536` |
| `tests/linux-compat/schext-reference.v` | `171c656eb9a68d1f2eb0e9ac05940e5e12496d694949baa709aa2f982eef7c0a` |
| `tests/linux-compat/schextreferenceinit/core.v` | `395d663713e51788c735f0736acab40b615e29ff2ff3d6440f0c7300252838bd` |
| `tests/linux-compat/run.v` | `dd105857d529a81802b7604671a48ab134a650a9b465da3f6f546ec36dd90ff2` |
| `before-gaps.v` | `838bf03a0110d5ec8f46b65cda1be48f547490c3efb7554684595e32f88a5cee` |
| `before-arm.c` | `c0ab2c38bd9e30ce18770e0dac60a175f0d94c68d04eabb1c3c38b55018e6973` |
| `before-x86.c` | `990eac03bdc48730fbf218c01e0d4c77bd70e5a2166f01025edcb1a7cdf2bb7b` |
| `after-arm.c` | `c59f9df560c8803fd6a408ace9b515ee75c3b803dbae2cac5684df517d4822f4` |
| `after-x86.c` | `f606e32b8f55fc1f2e1733c6d8303e6982273d14cd5b772f9b41b2c45e115929` |
| `preview-arm.c` | `cdc923d79ef8633001653505667bffb12330bb5db5896261cbffabe75fbd7a74` |
| `preview-x86.c` | `cdc923d79ef8633001653505667bffb12330bb5db5896261cbffabe75fbd7a74` |
| `independent-false.v` | `a462136f00975c0974b85c7a8bb1fe3bbead85533353be9ecc4df43deec261c5` |
| `independent-false.log` | `ebe2f15f80101d5a5378872fecabf1a20cf2f7ad24b58b7a2dc99f927a67e8d3` |
| `independent-baseline-control.log` | `2921268f17767fe6811bdfdd7d9db588f764d07686586ccbe07474ad9f93ba5e` |
| `independent-code.log` | `5ddac35d869bf271ae2717c7741d684afcb5be095525331f9919e9ddcc0b5e6b` |
| `independent-artifacts.log` | `c54b220fe8fdd74feaf8a593fd665ace945fa129e2b17688fb4dbf72c8888996` |
| `states/preflight2-schext-arm/init` | `a5535c690f40ecc1f971fa572ed37c705c52d0e0b3117d9eca38407d09c5f55d` |
| `states/p1-before-arm/kernel/bin/vinix` | `c9d23cdb6e35cb4a297e8198f2bb97cede7425f5218ee76734a4d8129dfb793b` |
| `states/p1-before-arm/schext/init` | `a5535c690f40ecc1f971fa572ed37c705c52d0e0b3117d9eca38407d09c5f55d` |
| `states/p1-before-arm/schext/serial.log` | `072c06c64b6439f0d79689ea1b42b87de42f68e9e2250d5128f5c3019e8d3f8a` |
| `states/p1-before-arm/receipt.json` | `ce2a604aadbe6f7bcf8bd3a7511312a08cac6820c2ce9f18b3e3faa2785d0c9b` |
| `states/p1-after-arm/kernel/bin/vinix` | `82a95bcf2d315749c0ba4250b03857c484588e9ce09a438ebed01c4e071afb68` |
| `states/p1-after-arm/schext/init` | `a5535c690f40ecc1f971fa572ed37c705c52d0e0b3117d9eca38407d09c5f55d` |
| `states/p1-after-arm/schext/serial.log` | `293ffed1983ad9637b13b5881bb4589c469654d7890a6ced4e9c29c062d2d009` |
| `states/p1-after-arm/receipt.json` | `d6d61547f8e17fbbe73dbe1b5f5573a8b4efd13277da382079a1c320be729d5a` |
| `states/p1-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p1-reference-arm/probe` | `a5535c690f40ecc1f971fa572ed37c705c52d0e0b3117d9eca38407d09c5f55d` |
| `states/p1-reference-arm/fixture.c` | `e7c9e6ec686d04e8c45374c25ddb4139d19f05555c043eaaf932e25a9b712db7` |
| `states/p1-reference-arm/init` | `6edad02074f62f859e93c5256f1605cf8c23f04b5b0c0ea7c058bd7fbf8ceb65` |
| `states/p1-reference-arm/initramfs.cpio` | `27317fecdd9c50fc6ab6677b31ea71cea26947692bbd37fc9c97634b24d2fb53` |
| `states/p1-reference-arm/serial.log` | `46b3a264ecc5f560c730c424b9261482cc82d6b80ff0962118c8fc5191bc0bd1` |
| `states/p1-reference-arm/receipt.json` | `be76746a4c925b00cfe35c86ad468a548a21a9c1204d7ac21b745595a62bedbc` |
| `states/preflight2-schext-x86/init` | `f0ee6e8f60a1092ec5a7e42c70ebcc2ea3180ab641690e7432373e05950233d1` |
| `states/p1-before-x86/kernel/bin/vinix` | `0fb02d5bf1bb0544afd52d73430e933386e67dfbe306776dc04203e24846b344` |
| `states/p1-before-x86/schext/init` | `f0ee6e8f60a1092ec5a7e42c70ebcc2ea3180ab641690e7432373e05950233d1` |
| `states/p1-before-x86/schext/serial.log` | `6da65a73f12c7c4e03de65b9e04b7c3d3edebbfcf4438e3db995fb52fb96aaec` |
| `states/p1-before-x86/receipt.json` | `7609ccbaf9f93201d6dff53317de480afca3feda0763a63c8232b4364a12f927` |
| `states/p1-after-x86/kernel/bin/vinix` | `fa42b084ce47d23c20f38a7492c91cd8358f5a0b8911eb88586db07047701ab8` |
| `states/p1-after-x86/schext/init` | `f0ee6e8f60a1092ec5a7e42c70ebcc2ea3180ab641690e7432373e05950233d1` |
| `states/p1-after-x86/schext/serial.log` | `d2e06154905795ca2059228434666927990827a673487513253a0778bbed2912` |
| `states/p1-after-x86/receipt.json` | `25efb06e80b8072c4f013bdf5a1d0699841ac0e1edb0441e708b9545c9cd038c` |
| `states/p1-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p1-reference-x86/probe` | `f0ee6e8f60a1092ec5a7e42c70ebcc2ea3180ab641690e7432373e05950233d1` |
| `states/p1-reference-x86/fixture.c` | `e7c9e6ec686d04e8c45374c25ddb4139d19f05555c043eaaf932e25a9b712db7` |
| `states/p1-reference-x86/init` | `53234570d834f4ecf5aa73d4a2a6181ac066b7b0d231988bbeeeaaa0b935a71e` |
| `states/p1-reference-x86/initramfs.cpio` | `73962835ac153c5c03996d956fea0679865ae25bfb2f7a7ca6c25cd219b1ebff` |
| `states/p1-reference-x86/serial.log` | `556af72c99b2c28db508c152b11409a7a01e19ce77b7c5f3f5a211532961a884` |
| `states/p1-reference-x86/receipt.json` | `9fa4692485ddf78a060392441c67b7ef2c99e6b82304f08360ce534713b4b731` |
| `../proctask-20261014/compiler/v` | `9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b` |
