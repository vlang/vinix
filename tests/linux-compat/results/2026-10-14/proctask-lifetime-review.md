Independent proctask lifetime review: PASS

Reviewed the cached procfs task lookup change in `kernel/fs/procfs.v`, the scalar attachment predicate in `kernel/proc/pidns.v`, the native V fixture and Linux reference wrapper/controller. Frozen baseline `1a9c4c4981cb0f0b2a5b31f08504150410226afe` fails the exercised cached-gone paths on both architectures; both final native candidates and both actual Linux 6.12.51 references pass. The private independent V checker compiled without `-prod`; its executed assertion and passing-reference-as-failing-baseline controls refuse false qualification. Final production C, ELFs, serial logs and receipts were consumed only after their producers completed. Kernel/build paths below are relative to `/Users/alex/.cache/vinix-linux-compat/proctask-20261014`; profile/preflight paths were read from `/Users/alex/.cache/vinix-linux-compat/proctask-20261014/scratch-completed`.

Cached lookup copies the child pointer while holding procfs_lock and validates the child's stored kernel PID/TID before returning it. task_attached bounds both IDs, holds pid_lock through every process/thread-table dereference and returns only bool; no borrowed process/thread pointer, pin/reference or namespace ownership escapes. Main-task identity remains present while the Process slot exists, including zombie lifetime; a non-main table thread must point to that same Process. The helper takes no threads_lock, so it avoids thread_ids()' try-lock/main-only fallback. procfs_lock → pid_lock matches existing refresh/mount ordering. Attachment uses pid_lock → threads_lock without procfs entry, and the directory-release callback reachable from free_pid only atomically updates a retained node timestamp, with no VFS/procfs lock acquisition.

The scalar predicate releases pid_lock before namespace deletion/resource unref. drop_procfs_directory extracts the prior prune operations: clear magic_target, delete the named child, adjust parent and child link counts, and unref(nil) once. The map changes remain under procfs_lock and copied child pointers never refer to movable map-value storage. ProcFSResource.unref(nil) only atomically decrements refcount; it does not free the resource or VFS node. Retained nodes, dot entries, names, subtree pointers and resources therefore remain safe for concurrent path walkers, open descriptors, cwd/root pointers and mount routes under the existing lifetime. No orphan/removed/retired flags, retirement queues or new reclamation are introduced. Erasing only changed lookup/prune bodies and prototypes plus the two new helper bodies/prototypes leaves byte-identical complete production C on each architecture. Both new helpers are allocation-free in production C. task_attached emits exactly two existing v_fixed_index calls, each after explicit 0 < ID < 65536 guards; the helper returns its input without allocation for valid indices. An initial reviewer check incorrectly prohibited these bounded calls after ARM remainder equality passed. That failed reviewer-check diagnostic is retained separately; the revised check requires both guards/calls and passes on both architectures without a kernel edit.

The fixture uses twenty-one explicit allocas for fixed Counts, Worker, Bank, Slabs, path and record storage, with no hidden memdup, malloc, dynamic arrays or fixed-index helpers in the executed preview C. The 18 parent aliases and 18 held worker file/directory aliases remain open through inode/mode/descriptor-flag checks after task removal, then all 36 close. Every query closes a successful FD, even when absence was expected; temporary cycle aliases close on check failures and the slab observer closes through defer. C pointer borrows are synchronous except Workers passed to pthread_create. Both Worker frames remain live until release/join; setup, bad TID, failed join and protocol failures terminate through fatal → _exit before an unsafe unwind. Forks precede thread launch and children own copied frames. Child pipes are closed and child/zombie processes are observed with WNOWAIT then reaped; cohort Counts cross the parent pipe by value. Setup failures rely on process/guest teardown for residual descriptors and mounted trees. The Linux wrapper keeps its three-entry argv alive through synchronous execv.

Successful pthread_join can precede table detachment. The fixture independently requires tgkill(self,TID,0) to succeed while live, then return ESRCH after join (at most 1,000 bounded attempts), before expecting procfs disappearance; it never polls procfs to establish that boundary. Each of four root/UID-GID-1000 × initial/one-level-PID-namespace cohorts runs [270, 180, 180, 99, 27, 90] controls, 846 per cohort and 3,384 per architecture. The baseline fails [0, 180, 0, 0, 18, 0] per cohort: 792 per architecture. Controls cover warm live main/sibling nodes, repeated absence after worker detachment, surviving siblings, other-process TIDs, live/zombie/reaped process-main nodes, explicit/self paths, three proc mounts, libc/raw high-word opens, descriptor aliases and retained inode/mode/FD flags. The same native musl ELF bytes run against the baseline, candidate and actual Linux kernel on each architecture.

Native retention checks prime the finite procfs tree and run 32 warmups plus 200 measured lookup/alias cycles per cohort, with 13-second settling around snapshots. All 18 ARM and 14 x86 slab classes remain flat, as do measured large pages (arm [ordinary=0, namespace=0: 65/65; ordinary=1, namespace=0: 65/65; ordinary=0, namespace=1: 71/71; ordinary=1, namespace=1: 71/71]; x86 [ordinary=0, namespace=0: 164/164; ordinary=1, namespace=0: 164/164; ordinary=0, namespace=1: 175/175; ordinary=1, namespace=1: 175/175]). This measures repeated lookups of a fixed live/retired task set. Existing procfs retained-node, namespace-view/mount and dynamic task-churn reclamation is not changed or qualified; the retained allocations remain. Exact simultaneous lookup/detach races, numeric PID/TID reuse, arbitrary concurrent descriptor/mount mutation, deeper namespaces, GNU libc and foreign/translated/ELF32 paths remain unqualified. These checks qualify opens and retained descriptor metadata, not stat/status contents or reads through an already-open retired file. Cwd safety is reviewed from unchanged retention; no new cwd conformance claim is made. Three broad roadmap gates remain open.

SHA-256 pins were computed independently after all producers completed; common rows require exact byte identity.

| File | SHA-256 |
| --- | --- |
| `kernel/fs/procfs.v`, `kernel-arm/kernel/fs/procfs.v`, `kernel-x86/kernel/fs/procfs.v` | `2231fc4750b9a2243e9501c81b27e350ca3b85fdef3456b07f781f17b7feb0d7` |
| `kernel/proc/pidns.v`, `kernel-arm/kernel/proc/pidns.v`, `kernel-x86/kernel/proc/pidns.v` | `45b6d1038abd9f0e7fd63690f4466e6329e4ead34d3172a4076e70494ed39870` |
| `kernel/syscall/table/linux_common.v`, `kernel-arm/kernel/syscall/table/linux_common.v`, `kernel-x86/kernel/syscall/table/linux_common.v` | `e02ca1595fcc117e237c44cfd5634218184c328592f9e4fcb82af3be15047f68` |
| `tests/linux-compat/proctaskfixture/core.v` | `f94e62701cdbb1e16594a22947f73aa29f5a7633cd51a8870b12ae09ba5b80a0` |
| `tests/linux-compat/proctask-reference.v` | `7f4615aba29a3cf1a17265a0f122dd35440bc957c9d16b5cbc3652c636923076` |
| `tests/linux-compat/proctaskreferenceinit/core.v` | `1522eb217f7856ab8c9dfb66ca1059401d7e12a5d1a8f6a083748eb08714bbb2` |
| `tests/linux-compat/run.v` | `1fca85f97160b7deb9053cc86bfce605d0487f70f2d6cb847cbbd510967fce7c` |
| `compiler-inputs.json` | `fbcba16306f70092c3b0df0cad3776ab7c3e8be13ef1a4797a07b21f3dd71074` |
| `compiler-recovery.json` | `26325a85a49fb9e5abb131e653fb455897d1db6c6425ca3860e84e5379eeb358` |
| `compiler/v` | `9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b` |
| `independent-review.v` | `01a26b8ef9bc6d13434ad1749728609d5a67b44529cab0c3201b4c028287ce4e` |
| `host-tests.log` | `35e40984fa5739e04d0f875292b872229e662d177abb2e91653e7b7d8c5ad454` |
| `allocs-before.log` | `6c09af7b6bfc0ec5d32cb0561ed2f6ec7e20ae124441b7f11abd04e956983813` |
| `allocs-after.log` | `da4fc93d5a19541757009956aa96448bc66539c3721d5f888982d5675878ab4f` |
| `scope-check.log` | `a3fec6fdc2fe3d6704da93155c8e06a3894e575a782579dac9df6aaaeb694fb9` |
| `scope-fixed-index-diagnostic.log` | `3fcaea67a1892d1085cc5f93b7711a1a0ee876436125b39f917931c78b7e698b` |
| `scope-fixed-index-diagnostic.md` | `892ce1dd426cd316ee68067431127d1c20335b4f2701b6b07ff60fdaf8a217dd` |
| `preview-arm.c`, `final-proctask-before-arm/proctask/fixture.c`, `final-proctask-after-arm/proctask/fixture.c` | `8eebdb7e8b576386938912a837baa5879800cfe561503089dd06a3264b5a14f6` |
| `preflight-proctask-arm/fixture.c` | `8eebdb7e8b576386938912a837baa5879800cfe561503089dd06a3264b5a14f6` |
| `preflight-proctask-arm/init`, `final-proctask-before-arm/proctask/init`, `final-proctask-after-arm/proctask/init`, `final-proctask-reference-arm/probe` | `194594c91cd191769556b0bc2be9918a57a5cf6ddfc7055fd9f01b1ec29856da` |
| `tests/linux-compat/proctaskfixture/core.v`, `final-proctask-before-arm/sources/proctaskfixture/core.v`, `final-proctask-after-arm/sources/proctaskfixture/core.v` | `f94e62701cdbb1e16594a22947f73aa29f5a7633cd51a8870b12ae09ba5b80a0` |
| `before-arm.c` | `ebfa8ac66cd260b053c2b9a7d31264e9b5438b4d99d3547a6dafa604cb38d2f0` |
| `kernel-arm/kernel/obj/blob.c` | `452264d523299dba7fb8841ef8827f868add67ba33d2e42894d5fef98317c4fa` |
| `baseline-arm/kernel/bin/vinix`, `final-proctask-before-arm/kernel/bin/vinix` | `be799802210ab42c59c3c26a2091576a682f60dd5c003d427d393585fdd271f8` |
| `kernel-arm/kernel/bin/vinix`, `final-proctask-after-arm/kernel/bin/vinix` | `854d619ff1e1b3555708e033b2f89a26ec2a0795e1f063b37dbbd0412c3006af` |
| `build-before-arm.log` | `dcd1697a714f238ae2faa1b5113cf65937919e466ae128a6d2bea54556ba1865` |
| `build-after-arm.log` | `3530a5c7211aaf88bd30b5704974ebbf198509863157208bb0c8520066a890a9` |
| `final-proctask-before-arm/proctask/serial.log` | `8d4677f11dc6237b1a50ad87da5635e2aafc9341fbf4aac4616b5072bcf365b4` |
| `final-proctask-before-arm/receipt.json` | `47a885974db66ba11c4221b990620944e38d80475200e6f99a9a185e3a48b65d` |
| `final-proctask-after-arm/proctask/serial.log` | `b8d2c20aaceea406430f9c58952d734411ce8654e2d78d92d07d7902450fe9d4` |
| `final-proctask-after-arm/receipt.json` | `f193b103ad70a250df06216b65ae5209ff6abf6f6e3f4dfa0772d5898d767156` |
| `final-proctask-reference-arm/fixture.c` | `3b7ab2526e5817583507d8531e8a15533997526da111b49df16ebbe5ba577214` |
| `final-proctask-reference-arm/init` | `649e65dfd4d133d49cf4f24678c37307ec4b50ab806c3b3dceae33ff70b65c52` |
| `final-proctask-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `final-proctask-reference-arm/serial.log` | `3c92a5139a2cd475884170d08546a3ebd6ab879443d87ae92f83c9ad9d62fd45` |
| `final-proctask-reference-arm/receipt.json` | `889ea468996a01a7409cacc825de0c5813326a3c1fcbeb9677d8f768eb94e536` |
| `final-proctask-reference-arm/initramfs.cpio` | `fe42197fd69eacfb171d36e7d624596745dafa6342fa99e1c7698fe1f7293a74` |
| `final-proctask-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `tests/linux-compat/proctaskreferenceinit/core.v`, `final-proctask-reference-arm/source/proctaskreferenceinit/core.v` | `1522eb217f7856ab8c9dfb66ca1059401d7e12a5d1a8f6a083748eb08714bbb2` |
| `preview-x86.c`, `final-proctask-before-x86/proctask/fixture.c`, `final-proctask-after-x86/proctask/fixture.c` | `8eebdb7e8b576386938912a837baa5879800cfe561503089dd06a3264b5a14f6` |
| `preflight-proctask-x86/fixture.c` | `8eebdb7e8b576386938912a837baa5879800cfe561503089dd06a3264b5a14f6` |
| `preflight-proctask-x86/init`, `final-proctask-before-x86/proctask/init`, `final-proctask-after-x86/proctask/init`, `final-proctask-reference-x86/probe` | `df35275cb03eca7dba84f38cf9f89aeaf6567a465b20b9766154d094499a452c` |
| `tests/linux-compat/proctaskfixture/core.v`, `final-proctask-before-x86/sources/proctaskfixture/core.v`, `final-proctask-after-x86/sources/proctaskfixture/core.v` | `f94e62701cdbb1e16594a22947f73aa29f5a7633cd51a8870b12ae09ba5b80a0` |
| `before-x86.c` | `f3d870075336fcc84866db501b14d8dcfa4efede4f96fffea7099e4f3f881da2` |
| `kernel-x86/kernel/obj/blob.c` | `3de1d1973ba279976a43f9d80a4277448cc6cb666aa2cfd4d0358a2abf044d09` |
| `baseline-x86/kernel/bin/vinix`, `final-proctask-before-x86/kernel/bin/vinix` | `c9420223d11031e7ea416e9dc6842132d3b7aae5c9451857e29b0023387ae415` |
| `kernel-x86/kernel/bin/vinix`, `final-proctask-after-x86/kernel/bin/vinix` | `6db3bb5b572df7b5662249136380b4cb4fc9eccd0208e3c4177a192bf69fc4d3` |
| `build-before-x86.log` | `3aad1aa3173277bf5a1820ffdd40184813a283773c0ed6c4bb4b93adc38c7927` |
| `build-after-x86.log` | `7014fc5f58a4633ef55021c066e494322d5166607cd961a019e65d91fcd47184` |
| `final-proctask-before-x86/proctask/serial.log` | `ed224a8c654ff478b090381ddd7c9dc63b290395fac8797327e1990d8537f7f7` |
| `final-proctask-before-x86/receipt.json` | `d9929050163890420d344788350d1a89137851af92a0eda6e477caa30a99fa99` |
| `final-proctask-after-x86/proctask/serial.log` | `9d2d49e7993288a173b70558050faa55869b736e1baacf78d5a3f3aa451a54ce` |
| `final-proctask-after-x86/receipt.json` | `b6fe870ecac1238a98d004663e26ad70494c82b8dae148640814923dac5f08cc` |
| `final-proctask-reference-x86/fixture.c` | `3b7ab2526e5817583507d8531e8a15533997526da111b49df16ebbe5ba577214` |
| `final-proctask-reference-x86/init` | `ddb3eefebd78c6255741ac0116d0d5f752f6ae391a7b20c1245c917e3fd4be61` |
| `final-proctask-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `final-proctask-reference-x86/serial.log` | `7f90302e5ef3242093f3bc471256f980370731c3dddab8693cdceff3f230adfa` |
| `final-proctask-reference-x86/receipt.json` | `aefe995c0b2469f2638c05c52e9f28173030f46fe8ea079ecc3b165d601ab6c4` |
| `final-proctask-reference-x86/initramfs.cpio` | `8c310eeff3d8d8f19a06533ad35d34ab5e8bbe80372d6b61ddc07e4db4bafe06` |
| `final-proctask-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `tests/linux-compat/proctaskreferenceinit/core.v`, `final-proctask-reference-x86/source/proctaskreferenceinit/core.v` | `1522eb217f7856ab8c9dfb66ca1059401d7e12a5d1a8f6a083748eb08714bbb2` |
