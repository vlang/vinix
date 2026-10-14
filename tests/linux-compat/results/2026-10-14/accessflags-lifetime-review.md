Independent accessflags lifetime review: PASS

Reviewed `kernel/syscall/table/linux_compat.v`, `kernel/pipe/pipe.v`, the updated low-word access fixture, native V accessflags fixture and Linux reference wrapper/controller. Frozen baseline `d00fe874ad9db66c958e35692fbb18c0a18c15bf` reproduces 3,623 failures in 6,430 controls per architecture; both completed native candidates and actual Linux 6.12.51 references pass. The independent V checker compiled without `-prod` and executed assertion-failure and passing-reference-as-failing-baseline negative controls. Generated C and runtime files were consumed only after producer completion. Build paths below are relative to `/Users/alex/.cache/vinix-linux-compat/accessflags-20261014`; completed profiles/preflights were read from `/Users/alex/.cache/vinix-linux-compat/accessflags-20261014/states`.

The syscall change truncates flags through `u32` before allowed-bit validation and forwarding; it adds one scalar local and no allocation, reference, lock, user-pointer dereference or free. The existing VFS permission, descriptor/path/cwd retention and cleanup paths are unchanged. The pipe change reads the executing process effective UID/GID into the private pipe inode before the existing Resource interface copies its stat fields. Pipe.create has only the syscall_pipe caller, which already uses the executing thread process; that synchronous scalar borrow does not escape or require a new pin. Both original Pipe/Resource allocations and all failure, descriptor construction, alias retention, unref and freeing paths are byte unchanged. Named FIFO construction is unchanged.

Independent staged comparisons prove baseline-to-word production C differs only in the faccessat2 function body/prototype and word-to-final C differs only in Pipe.create body/prototype on both architectures. Removing exactly those existing units leaves byte-identical production C, including VFS access, pipe close/unref and every other function, type and global. Final Pipe.create is exactly its prior body with three scalar statements inserted before the existing Resource memdup; no hidden allocation was introduced.

The accessflags fixture has nine explicit stack allocas and no heap/helper allocations in both generated previews. Fixed C.stat records use the target headers, and UID/GID observations are synchronous scalar reads. Each child keeps all 12 original/dup/CLOEXEC descriptors and its writer live through queries, metadata/offset/queued-byte checks and storage snapshots, then closes them. Counts are copied through a pipe and the parent waits before returning; early setup failures call _exit and descriptor reclamation is left to ordinary process exit. Literal paths and the deliberately invalid address 1 are passed only to synchronous raw syscalls; the fixture never dereferences that address. The Linux wrapper keeps its three-entry argv alloca live until synchronous execv and returns failure if mounting or exec fails. The updated access fixture adds one stat alloca per pipe-owner child, six live aliases for both pipe endpoints, 72 low-word permission observations across two credential cases, and closes every successful alias before _exit; the parent completes waitpid before its frame returns. Neither fixture creates an asynchronous borrowed pointer.

Root and UID/GID 1000 each run [2800,400,15] controls: allowed flags with five upper-word patterns, genuine invalid low flags, and retained metadata/FD flags/offset/data state. Baseline failures are [1792,0,0] for root and [1828,0,3] for UID/GID 1000, totaling 6,430 calls/3,623 failures per architecture. The owner regression independently checks both equal real/effective IDs 1000 and real 1000/effective 0, inode UID/GID/type/mode, both read/write ends and all aliases; AT_EMPTY_PATH uses real credentials and AT_EACCESS uses effective credentials. Final native accessflags/access/procpid/open/runtime profiles pass on both architectures. Preview/preflight/baseline/candidate accessflags C is byte-identical, as are preflight/baseline/candidate/actual-Linux probe ELF bytes per architecture. Initial QMP-path failures occurred before probe execution and are retained as diagnostics; initial word-only runs used a superseded probe without owner assertions and are excluded from the final qualification.

Native retention runs 32 warmups and 200 measured cycles per credential with 13-second settling around snapshots; all 18 ARM and 14 x86 slab classes and measured large pages remain flat (arm [ordinary=0: 68/68; ordinary=1: 68/68]; x86 [ordinary=0: 177/177; ordinary=1: 177/177]). Completed allocation scans preserve 400 ARM and 292 x86 sites across 662/658 copied sources and the same existing refusal list; eight host test files and native dispatch coverage pass. This does not change or qualify existing pipe-create descriptor-failure cleanup, arbitrary concurrent credential/descriptor mutation, named FIFO ownership, process/node/mount churn reclamation, GNU libc, foreign/translated or ELF32 paths. No new reclamation or ownership/free path was introduced. The broader roadmap compatibility gates remain open.

SHA-256 pins were computed independently after completed producers; common rows require exact byte identity.

| File | SHA-256 |
| --- | --- |
| `kernel/syscall/table/linux_compat.v`, `kernel-arm/kernel/syscall/table/linux_compat.v`, `kernel-x86/kernel/syscall/table/linux_compat.v` | `e5520b162e48c2e60c8c58aea46886d77b29dff0d24460a69a28c30953126912` |
| `kernel/pipe/pipe.v`, `kernel-arm/kernel/pipe/pipe.v`, `kernel-x86/kernel/pipe/pipe.v` | `0eb36d158d556636588cb0a742f5dbb50bbc0bf1168b82b1dc0d5ec08a5a967d` |
| `kernel-arm/kernel/fs/vfs.v`, `kernel-x86/kernel/fs/vfs.v` | `e27dcac748be89e9e949156b5b03b3b3a0d431774066af4e762ee76004d143da` |
| `tests/linux-compat/accessflagsfixture/core.v` | `454ce7fef06370b8b26b5391fc4b7b01a926e941e208d179b2dfa5f541296c28` |
| `tests/linux-compat/accessfixture/core.v` | `cdaa33ac986280d744438ec8329ad9a61df0ba4dd7d23a6028abb2e86ad288ab` |
| `tests/linux-compat/accessflags-reference.v` | `c2083b9203eac7298d729a72fca89ef5593078ddc58f8ba17277cb66cbd036d8` |
| `tests/linux-compat/accessflagsreferenceinit/core.v` | `ecd5f9c3fd7a6c0db03880e70a203f3709c22c933495493664aff528e0ca8492` |
| `tests/linux-compat/run.v` | `96882936eceb1d9fc1d7d1d850ae2d06f4da7e15f0dd4d4910f7e54e14c4a7f8` |
| `host-tests.log` | `703079e943fa8100e35fe061d0a8455eb7de738763d515e6caba52b8bcdfdceb` |
| `allocs-before.log` | `f4bbbad9f8d9dc0c178aa1290ce6dac2a7a9f6625b255d60d584e78b70092c0c` |
| `allocs-after.log` | `f3de032141c046f3f4e57043f7f7d95ecf7fdfb3dc3cd8627ba9e95770d95a7e` |
| `coverage-check.log` | `69bb46dfa95fa8be3fb8e97dff4d507b970e7afde4592f4c6aa02cc32c66540b` |
| `scope-check.log` | `6cb0c144f036ecc616339283f01feaf5d9cf02e5d636ebdfab4a0b581cf2cc95` |
| `independent-scope.log` | `7422226c21422554ee2ad5ab477b1761fa3564950ca2e66800f4e808b003007c` |
| `independent-review.v` | `7c75567a572d610795c25204fae6ba0b91f9c0fb0b1f19abb144e339675a5630` |
| `independent-review` | `15ea2395eee3bfe0eb21e96954892faaec2377fe5d3b7db75f39480e8eeaf826` |
| `independent-build-controls.log` | `cc29b825be651cd5732d5708d0db1877ed8c529005cea734a2475a868c74d526` |
| `independent-assert-control.log` | `67125d688d561928bda44d51d950501503aed6125f7ec24912fcec3008f9cdb4` |
| `independent-passing-counts-control.log` | `1e68cd6ff0373d470d9c00b515604aa44fe523710655257046b38ea600015ea0` |
| `independent-preview.log` | `57c89aab185abfd0314c9da1b180614ed0a62ba46b0d33fc67f242614ffb6380` |
| `independent-baselines.log` | `ac33e452f61098c5ed15c1e50941544a2b94c1d8a1b5093ab80e35b7f56790e1` |
| `independent-before-reference.log` | `882abff622ebb81d4494671174c5644ddc6fded963f48b527499d957e73b46d1` |
| `independent-elf.log` | `abb38fec3e04de972357afa047ab3ac0d5261ee14a3823e3765b795a1caac9b4` |
| `preflight-drift-pins.json` | `75d98df10413cdc9a71ee290f457a7aea53f8fc958aeaf83bde8bda88ad16d44` |
| `candidate-inputs.json` | `a0eff314b237dcd07857099dfa5ed7ba7b549e9bcc60645872f95442674bdd3b` |
| `/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v` | `9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b` |
| `preview-arm.c`, `preflight-accessflags-arm/fixture.c`, `v2-before-arm/accessflags/fixture.c`, `v2-after-arm/accessflags/fixture.c` | `90473343afa843b70c5003ee5b106885e1514b208c0fe60dfc8bf5caadab8637` |
| `preflight-accessflags-arm/init`, `v2-before-arm/accessflags/init`, `v2-after-arm/accessflags/init`, `v2-reference-arm/probe` | `64c41b233437c5fe70004d13cf2c14e6df7327e5d8c59e80dcdfc2af85adaa08` |
| `tests/linux-compat/accessflagsfixture/core.v`, `v2-before-arm/sources/accessflagsfixture/core.v`, `v2-after-arm/sources/accessflagsfixture/core.v` | `454ce7fef06370b8b26b5391fc4b7b01a926e941e208d179b2dfa5f541296c28` |
| `before-arm.c` | `ed96898078a6f9febb457492ff189ea220867f29ad8e8e8584d36fc887d225bd` |
| `word-arm.c` | `a0193109677b9ae51f4affc09fa5898176d05e0fd6319b8768257ee69a2ab950` |
| `kernel-arm/kernel/obj/blob.c` | `d7943a14d73270a565594bd8077965f89815e3b484210d3f4b909f473ada747b` |
| `baseline-arm/kernel/bin/vinix`, `v2-before-arm/kernel/bin/vinix` | `9621f2a7d10397544c8ed8a216d11ff1b8d8d053a33e1e68dfdb5a9c668982ad` |
| `word-arm.vinix` | `d0db61a71eeb4df147365d53e44e2d16ce57a29ad5d162bd35ce826c8e9f1f77` |
| `kernel-arm/kernel/bin/vinix`, `v2-after-arm/kernel/bin/vinix` | `0308977f51b1ec20d31e0a6326cf6f8b1d87c5baeb7b06f735b3ae282e99eede` |
| `build-before-arm.log` | `18e5f493bc0a89043f2bd45f92a6b8aa436e85b87a39aa666448f209fdf8b6f3` |
| `word-build-arm.log` | `02965e33e4445fa8f77f72f7196afda81d72ba092e1b7a7520f1d498a1c3f9a9` |
| `build-after-arm.log` | `02965e33e4445fa8f77f72f7196afda81d72ba092e1b7a7520f1d498a1c3f9a9` |
| `v2-before-arm/accessflags/serial.log` | `e6ab8eac082e86aa1e9c9129473ff23d7aad0e198aa9009d015698c47336435c` |
| `v2-before-arm/receipt.json` | `d14eb16861efa94e01b9188b939bebe999e89a9c770b76ee3f4ac620f9c8cc92` |
| `v2-after-arm/accessflags/serial.log` | `28087eb202c552bdd2abb733f52719c1f5c8baa3b8cfa5a25bbcd5ba9f68893d` |
| `v2-after-arm/receipt.json` | `4a90b975f1ff2b3e410235ee88c707603e25e0dfd6b0a9c40c158b245645a627` |
| `v2-after-arm/access/fixture.c` | `53998280afb32ec26809a7bfb1f9b6e7b24f5e326e7b2e2755d6f8bdf9e4b599` |
| `v2-after-arm/access/init` | `913381428a4adcc149d2e55098b8658d385310a39b75507d7ad20db6404874ab` |
| `v2-after-arm/access/serial.log` | `8573f4e2c2efa05785e42091649278bdf2360ab24decf9d9d8842db1d4bb09c4` |
| `v2-after-arm/procpid/fixture.c` | `e8bfab01df0eaaf6c753215a7ea651cdb6b3486f652a79cdc0b5f2ab91c271ec` |
| `v2-after-arm/procpid/init` | `5079f2675fd725c4ae05891dbdd42617fe534660a26ac87a6ca20179cd7c479a` |
| `v2-after-arm/procpid/serial.log` | `00d90926e2d3d16a646f0ea0f0aa406c285ac31937dd2be3acf46fb1f89ae997` |
| `v2-after-arm/open/fixture.c` | `b2d362c322a5a63aa9dd819e342ec30c0384972bdc55f9e59b7c81398ac41eb9` |
| `v2-after-arm/open/init` | `b41456ec1e04ca2e2e83e39ac5f01da498edfc8011f4eb71541bbc9ec9ec7c6a` |
| `v2-after-arm/open/serial.log` | `520a0bb723ae89dc83f53bbb18c50557149cb86a8c5ba7782572d5c638cbe97f` |
| `v2-after-arm/runtime/fixture.c` | `05967a3ff8bb35aafaf2e91e58e1203b35780818a33b84031590b52943d60128` |
| `v2-after-arm/runtime/init` | `a27160c033a470689dafc283d37636bb5b81b1344d19e93a2c6071701187e44b` |
| `v2-after-arm/runtime/serial.log` | `f9e13f34a5593f710ccf520eaf82f933d32c1976406b553c86f3cdda2187652f` |
| `v2-reference-arm/fixture.c` | `b8e0902598a3a897d98905902c66bcf6ac68eb66322daf2604282e0fa73662f8` |
| `v2-reference-arm/init` | `6e7ea5d0283c4758e05efcc3867c82e63d6640d9ac910fbd5754a64337ee88da` |
| `v2-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `v2-reference-arm/serial.log` | `cd15651f92d0cdce6a83790a6c9cf388ec977dcdfe36f3c806158ae91b2a3442` |
| `v2-reference-arm/receipt.json` | `24dc55d1129b9ea23b5f14cc39ae8abf74f7dae5aef41819e543fab98ffad68a` |
| `v2-reference-arm/initramfs.cpio` | `448767fb710c879bc2a2bfa0a4542f1886f6c042bd19bf4b7c7bb202777f3915` |
| `v2-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `tests/linux-compat/accessflagsreferenceinit/core.v`, `v2-reference-arm/source/accessflagsreferenceinit/core.v` | `ecd5f9c3fd7a6c0db03880e70a203f3709c22c933495493664aff528e0ca8492` |
| `preview-x86.c`, `preflight-accessflags-x86/fixture.c`, `v2-before-x86/accessflags/fixture.c`, `v2-after-x86/accessflags/fixture.c` | `90473343afa843b70c5003ee5b106885e1514b208c0fe60dfc8bf5caadab8637` |
| `preflight-accessflags-x86/init`, `v2-before-x86/accessflags/init`, `v2-after-x86/accessflags/init`, `v2-reference-x86/probe` | `76220f7e07d1b50c99bf541facac02679052948676ce348394029f40ac4ef12c` |
| `tests/linux-compat/accessflagsfixture/core.v`, `v2-before-x86/sources/accessflagsfixture/core.v`, `v2-after-x86/sources/accessflagsfixture/core.v` | `454ce7fef06370b8b26b5391fc4b7b01a926e941e208d179b2dfa5f541296c28` |
| `before-x86.c` | `9d0659ccedf82843e8395330e275fc625c4e49214b81c42310b3de06873474ea` |
| `word-x86.c` | `ef359c0dfd8245f4af6b7aec626b1d05baea9272334a98633c6fef9e34ddfd3e` |
| `kernel-x86/kernel/obj/blob.c` | `505bd8b414bf4d98d0e9a7c6763119aed44cc89964b0f00d3abec9c71e3bbc09` |
| `baseline-x86/kernel/bin/vinix`, `v2-before-x86/kernel/bin/vinix` | `be2b4cd606a891740375c46fc119e98b912d53cd96cf718caab587aee05d34d4` |
| `word-x86.vinix` | `0e93fff0c245e52cb21e64b2d3641933aa0b8830697433af2976f07c4b02d544` |
| `kernel-x86/kernel/bin/vinix`, `v2-after-x86/kernel/bin/vinix` | `f8f7c139290358f0b8e89ada5190e1efa30aeba63389b7a4f3448e38bf542be8` |
| `build-before-x86.log` | `9b5c2149faf05cc3eb802ce72a3ba300430e871023c5d6b596d8cd7ba97276e1` |
| `word-build-x86.log` | `bd625018d36ea93cc7080b0b781801c4b1dc1bfd0c7c8ee2f2b76067302e90f2` |
| `build-after-x86.log` | `bd625018d36ea93cc7080b0b781801c4b1dc1bfd0c7c8ee2f2b76067302e90f2` |
| `v2-before-x86/accessflags/serial.log` | `cc0b51b6ad6cbcce671a9b8cc6f7f39b9ab7605f04ddbadfabe2015424a836ac` |
| `v2-before-x86/receipt.json` | `0f1c3cc1d3e20b6a34fe516513eef63afc4259cadd966bcbb9b443b905059d66` |
| `v2-after-x86/accessflags/serial.log` | `c7e4d66a4e385b545653e53f415646a0cbf29bee930d14a0f5a2d208fa06dae5` |
| `v2-after-x86/receipt.json` | `a3d50edebc13546bf464f2dea69278185411b9724c46d2df82dd6c23b8b17b86` |
| `v2-after-x86/access/fixture.c` | `53998280afb32ec26809a7bfb1f9b6e7b24f5e326e7b2e2755d6f8bdf9e4b599` |
| `v2-after-x86/access/init` | `87b5e511b3b759b08dd182c459faab3cf9839920656c8a612efe9d94eeb026fb` |
| `v2-after-x86/access/serial.log` | `d3a9ebb7cbc7ab8df87bc0659f8d4e468be2e3e169b1631930aa88592da7538a` |
| `v2-after-x86/procpid/fixture.c` | `e8bfab01df0eaaf6c753215a7ea651cdb6b3486f652a79cdc0b5f2ab91c271ec` |
| `v2-after-x86/procpid/init` | `35a1ef7e62fc82f259a0bf3d3e6dcee715de103223c74648714a01882cbccb6e` |
| `v2-after-x86/procpid/serial.log` | `d08d791adce0a75a9adc6f475541c1dec98edd7b90f81fbeba6e470554e2fc1f` |
| `v2-after-x86/open/fixture.c` | `b2d362c322a5a63aa9dd819e342ec30c0384972bdc55f9e59b7c81398ac41eb9` |
| `v2-after-x86/open/init` | `377071b25bf7f8a9b3a048c8eab9ec87c689beb7ca5791e8439a46a4131f222a` |
| `v2-after-x86/open/serial.log` | `54eb6cbab773e3769ff502ca83030b75856525c7380a3238ab6a7b6d0fde5457` |
| `v2-after-x86/runtime/fixture.c` | `283ee3218dbf04ee7c3289110ff0be3044906d48556453b06b7de972f4950e3b` |
| `v2-after-x86/runtime/init` | `3c22f6e44700a031e0c6e9bd04427095e423d595d3f9b81e09f07539d1ea3b9f` |
| `v2-after-x86/runtime/serial.log` | `0a8088397a56749f4b5b8275d36d23b60de5eafe640a5f6e4470d7e66b45c8cd` |
| `v2-reference-x86/fixture.c` | `b8e0902598a3a897d98905902c66bcf6ac68eb66322daf2604282e0fa73662f8` |
| `v2-reference-x86/init` | `faee3723231fbf67f44eb4366a700a9213cb12377ace425c6ed2dcb4542cd60c` |
| `v2-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `v2-reference-x86/serial.log` | `e73d05ed88fbae1d2f5424ee89a2c1ea83ce12e619512e59bf5578f8f573d41d` |
| `v2-reference-x86/receipt.json` | `b35aa0a4be4438dc10f3f22c3146625c0a8a9c26b159d8c80a44843a102210d0` |
| `v2-reference-x86/initramfs.cpio` | `53b609c55c677eced8ae2c4a3bf57a1207b768fcd5013a561b177afebb0d69f9` |
| `v2-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `tests/linux-compat/accessflagsreferenceinit/core.v`, `v2-reference-x86/source/accessflagsreferenceinit/core.v` | `ecd5f9c3fd7a6c0db03880e70a203f3709c22c933495493664aff528e0ca8492` |
