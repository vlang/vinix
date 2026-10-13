Independent fcntlsync lifetime review: PASS

Reviewed the isolated F_SETFL synchronization-status mask change, final strengthened probe, reference wrapper/controller, maintained case composer, both complete emitted kernel C files, exact module previews and completed native/Linux-reference captures. This independent review changed only this report and found no blocking new lifetime or lock-order concern. Artifacts are in `/Users/alex/.cache/vinix-linux-compat/fcntlsync-20261013`; the recorded baseline is `73f513e79eb61d5a67c094801da5ef922d19e1d0`. The root and both isolated `kernel/resource/resource.v` copies are identical.

The kernel change removes O_SYNC/O_DSYNC from `file_settable_flags_mask`, leaving O_APPEND/O_NONBLOCK mutable. `file_status_flags_mask` and open-description construction remain unchanged, so initial synchronization bits survive both open and F_SETFL. The complete generated-C difference on each architecture is exactly one constant macro replacement, from the append/nonblock/dsync/sync mask to append/nonblock. Restoring that macro restores the entire baseline C byte for byte. No function body, lookup/release, allocation, ownership transfer, publication, lock or error path changes. The existing F_SETFL FD/Handle temporary hold and paired release remain unchanged.

The final probe explicitly checks the initial synchronization bits and access modes of all 35 held descriptors before the setter matrix. Its O_PATH expectation uses `O_PATH & O_ACCMODE`, accounting for the bundled musl access-mode mask. Nine ordinary description classes each have original, dup and CLOEXEC aliases: read-only regular, write-only DSYNC, read/write DSYNC, read/write SYNC, plain read/write, SYNC directory, each pipe end, and unlinked SYNC regular. O_PATH file/directory aliases add six descriptors; held 64/65 alias the SYNC and plain read/write classes. The initial controls pass in both credentials on both baselines, candidates and Linux references, so setter qualification cannot conceal an incorrect initial status.

Both matching previews are byte-identical to the executed strengthened fixture C. Probe bodies contain seven explicit allocas: the parent descriptor array, child rlimit/state/count storage, synchronous stat scratch and two slab snapshots. The 36 State slots accommodate the 35 held descriptors plus temporary replacement 66. State slot 35 is captured before every valid use and is never read by the invalid-66 control. Fixed argument lists, pipe/byte arrays and the slab-parser buffer remain ordinary stack storage. No memdup, malloc, dynamic-array allocation or fixed-index call appears in probe bodies. Synchronous fstat borrows stack metadata only for its call; the reference wrapper borrows its stack argv only through synchronous execv.

Each setter result captures errno before later observations. Checks cover every tracked descriptor, including aliases and independent descriptions of the same inode. Restoration of the original status is attempted even when a check fails; restoration failure exits the whole child. Lowered soft limits eight and zero retain 64/65, and the child restores limit 128 before replacement controls. Temporary 66 is closed after each replacement sequence. Fatal setup, replacement or limit failures use child `_exit`; the parent waits for each child before its stack descriptor array ends. Passing cursor checks restore position three. The retention observer closes on every returning path and brackets both snapshots with the same open FD. The parent verifies file bytes and the untouched AB pipe queue, captures descriptor flags and closes all 35 descriptors even if a flag comparison fails. Initial parent setup failures rely on process-exit cleanup. No asynchronous borrow or fixture pointer survives its storage frame.

The four rows run separately under UID/GID 1000 with supplementary groups cleared and as root, on both architectures. Each candidate and actual Linux 6.12.51 reference has zero failures. References use the respective byte-identical native probe ELF with `--reference` and skip Vinix allocator accounting.

| Probe kind | Calls per credential | Baseline failures per credential |
| --- | ---: | ---: |
| Native ordinary descriptions, aliases and upper-word forms | 864 | 588 |
| Native invalid and O_PATH descriptors | 320 | 0 |
| Libc ordinary, invalid and O_PATH controls | 296 | 147 |
| Lowered limits and closed/replaced descriptor 66 | 256 | 132 |
| Total | 1736 | 867 |

Candidates and references each pass 3472 counted controls per architecture; each baseline reproduces 1734 failures. O_SYNC/O_DSYNC and access modes remain as opened; append/nonblock change on the shared description; creation flags, descriptor flags and unrelated descriptions stay intact. Invalid/O_PATH inputs retain EBADF. Metadata, descriptor flags, separate/shared cursors, file bytes and pipe readiness data are preserved. Both final native cohorts pass 200 measured cycles after 32 warmups and settling, with all 18 AArch64 and 14 x86-64 slab classes flat. Large pages remain 68/68 and 177/177 respectively in both credentials. Retention measures setter/restoration on held SYNC/plain descriptions and an invalid FD; it does not assert that earlier alias/setup work allocates nothing.

The final five-case regression artifacts are an explicit composition of actual successful cases on identical candidate kernel bytes. They are not a new five-case controller execution. Fresh strengthened sync-only runs supply `fcntlsync`. Successful unchanged related cases come from the original five-case runs, except AArch64 `fcntlpath`, supplied by its successful retry. The initial AArch64 fcntlpath attempt failed during ISO setup with ENOSPC before guest execution; that attempt and all provisional or failed earlier sync probes are excluded from qualification and retained as diagnostics.

| Final case | AArch64 origin | x86-64 origin |
| --- | --- | --- |
| `fcntlsync` | `new-after-arm` | `new-after-x86` |
| `fcntlabi` | `initial-after-arm` | `initial-after-x86` |
| `fcntlpath` | `initial-mask-new-after-arm` | `initial-after-x86` |
| `open` | `initial-after-arm` | `initial-after-x86` |
| `runtime` | `initial-after-arm` | `initial-after-x86` |

Reviewed `fcntlsync-compose.v`: it checks architectures and kernel hashes, exact original/fresh case lists, the fresh sync-only suite PASS, unique selected zero-exit rows, maintained/frozen source identity, ELF/ISO hashes and raw case PASS without case FAIL. It copies source, C, ELF and captures with byte-identity checks; ISOs are hardlinks to immutable selected originals. It records per-case origins and original/fresh log/receipt plus composer-source hashes. Independently compared selected captures and original/fresh/retry kernel binaries to the final copies and candidate kernels. Both final receipts contain five successful cases, and both composed logs end `Qualified guest case composition: PASS`; `compose.log` reports PASS for both architectures. This preserves the exact evidence provenance while avoiding repeated successful related probes.

This approves the isolated status-mask change and exercised native musl ELF64 behavior. Concurrent setters, close/replacement or limit changes, GNU wrappers, translated/ELF32 paths, other mutable status flags and additional filesystems remain separate qualifications. Preservation of synchronization status bits does not qualify physical write durability or persistence after power loss.

SHA-256 pins use repository-relative maintained-source paths and artifact-directory-relative frozen-source/build/capture paths. Shared rows were independently compared as identical.

| File | SHA-256 |
| --- | --- |
| `kernel/resource/resource.v`, both isolated `kernel-{arm,x86}/kernel/resource/resource.v` copies | `98da2dd3060d4ed74a2f000c87d0d726c9e1bcebafda2f33b9055adca6a4cc3b` |
| `tests/linux-compat/fcntlsyncfixture/core.v` | `50f3f5237c0a6bd62b6e9a2642f21b130844ef8d66a2b6d0bb97334210885c02` |
| `tests/linux-compat/fcntlsyncreferenceinit/core.v` | `ab9bf14db696004ee3f8ef6dac844cc70be905bfc5cece9bf8e698aa2ea7760b` |
| `tests/linux-compat/fcntlsync-reference.v` | `5cb18c04f8cdd40fb17e491479b117992e783c06462ce7db8caf9da4c72d9f5b` |
| `tests/linux-compat/results/2026-10-13/fcntlsync-compose.v` | `6ed07ca575bb3719094c42932b9ad824deb9460777d68bc7b05fd170d6cf0ce6` |
| `before-arm.c` | `e3f93ea7078ab351b0ae29c1c810ac0e56258d4ee2c323e98d63425893fc6733` |
| `before-x86.c` | `6acd1ed199163a245366e306165f189b66830a464b8c9a9a2668ecb5a89b9f80` |
| `kernel-arm/kernel/obj/blob.c` | `b2e5f0c4250ecbeef4b1a9eba6aace66d68a81628204d49cd22ada0755c13035` |
| `kernel-x86/kernel/obj/blob.c` | `cca2ecad3a6bfda4ffc356a11c0fac0c284a6a7511ef14417ec4a082687074ed` |
| `final-before-arm/kernel/bin/vinix` | `ddc79e74900a643feba7c918bbad5bbde3798a432188bac80857a218dc38d74f` |
| `final-before-x86/kernel/bin/vinix` | `fd6c9fb1e7e0b3c7c4d7506394798c77b186b390c90e55c51fcb348e6a3d87e3` |
| `kernel-arm/kernel/bin/vinix`, all selected AArch64 native kernel binaries | `59ca5505f55d93cf85d2012e7184bf71478504497ffac7f12feb59801f743dd1` |
| `kernel-x86/kernel/bin/vinix`, all selected x86-64 native kernel binaries | `7671f070cde5a3970ab19f2fedf0061262728f77b67f72fc27e08f46cb971d65` |
| `preview-arm.c`, `preview-x86.c`, both final native `fcntlsync/fixture.c` files | `93ee4af0ab2c2ee7be8a909df3a182383439c76de8716d717184a6f8a7b26b96` |
| `final-reference-arm/fixture.c`, `final-reference-x86/fixture.c` | `2ac1c3e492ea9b67ab4111be04bfb68b678498d3ba495e7f9e8f0f1574963dd4` |
| `final-after-arm/fcntlsync/init`, `final-reference-arm/probe` | `c098ccba02da4dfe3c57572d749f28b0352f87f5746fd9e8149cac462fe2d520` |
| `final-after-x86/fcntlsync/init`, `final-reference-x86/probe` | `c3539dcdada450b5792817408f8c59415cd7161681691fff69958441012795d4` |
| `final-reference-arm/init` | `cf7a2079a72cb714ad564e249885f87125753d5c07bc5788ea7826a106dfea11` |
| `final-reference-x86/init` | `402fb188793b7305cbcc318cb3bebae7ff39d7f9e65a4680467ec0035c8d90fb` |
| `final-before-arm/fcntlsync/serial.log` | `ff0227697dd3b345560408d540d999f4b8fd1974911b2d3ff80fbb4fb0cec4bc` |
| `final-before-x86/fcntlsync/serial.log` | `51b8974e4cb21d5c3cb30a7940064c70f7dd756c66fe27e0c729f940913bf74f` |
| `final-after-arm/fcntlsync/serial.log` | `3aa9b8a8c76b33cf9003125deb7aeaf6a0a2da3dd1af7bf92898d1c44553b261` |
| `final-after-x86/fcntlsync/serial.log` | `99b79abf94962dd5bf035fca128f353d8742285c8e169ba173d02623b1e0a84d` |
| `final-reference-arm/serial.log` | `905f7612434c96b63781da20536f2d695f6008f085aaa8915ebb51ae08976b19` |
| `final-reference-x86/serial.log` | `760937c66791b48f301e920c6eaf999ebf6e362bef721bacb302be109c5f8700` |
| `final-before-arm.log` | `7dd8aa16c8559d9039feae84b78c459fe1dc3cc56f4c08e962c455db0e902ce3` |
| `final-before-x86.log` | `b4006cec4b9edaefa29c3b0f824142bcc66018ac1f7abeb34421602134c53b7f` |
| Composed `final-after-arm.log` | `868736e1a6020f48bd4555f70a4ae6cac1d7af9e180e9110db9a1fa8cc0fc58e` |
| Composed `final-after-x86.log` | `655353f523d5d7f70383ba3712388581bee125e63923cc1aec24e0164c07d620` |
| `final-reference-arm.log` | `16db259e9bcaf69ce4602c933a9bc01a57dc9917b03de07b8e8bab57cf3d84ef` |
| `final-reference-x86.log` | `0704df8922988f977b2980c36c1fa1e5eccadd945179e867a438b176d50e5864` |
| `final-before-arm/receipt.json` | `2c02d573021f5f9656b67aac1747b2cdafa324a0858e978f0631e862cf15db31` |
| `final-before-x86/receipt.json` | `3248010e6c427ef4b48186974048fa086819e4f8bc6c990ab207c95156814071` |
| Composed `final-after-arm/receipt.json` | `cb0a19417fd27890100d6abcdd91af781e9978b10574c7336d2aba63632f1e31` |
| Composed `final-after-x86/receipt.json` | `d8fe91fea59f614203a9b306130d3bf6dccfcd17b08882d16fb62a4784e58317` |
| `final-reference-arm/receipt.json` | `7fa1f3f665f1f25f625c7e50edb94d197f546bea6d7964cb399fcbaa7ecf437c` |
| `final-reference-x86/receipt.json` | `9afe661c9ca704c6f5c9a28abcdee00d14114989c170091f2df2907de2ba0187` |
| `scope.v` | `50dc38ca845ad85e8851d385fddf8c57c0286d887de3cccacc6cd349da633da3` |
| `scope-check.log` | `83426cece1d060c1599563d5a7657146ca9e363d8d749e0fb42d2bbd404f51eb` |
| `compose.log` | `439f835b722ccefc97216a1f6341d21fe73c39d13de6aaf35eef7729ccd7417a` |
| Fresh `new-after-arm.log` | `fcac720fa9d29e2f0bd94acf2963d65addddda3fb7690904b32cf5e639c53a73` |
| Fresh `new-after-x86.log` | `7616140aa50c6b477724ce15d5f5965c519493bd605df47a3983587fa39e1c55` |
| Fresh `new-after-arm/receipt.json` | `703ace73783a53edd84dc6ef84d857cdbd5546f242afbae857b3783bf0f914dc` |
| Fresh `new-after-x86/receipt.json` | `f8c0d610f55c55a9966a083e7a02d5dd406b8e8a83573b49abde0e2c4dfeb9bf` |
| Original `initial-after-arm.log` | `3b66d340156939e7066c8c1af4acb6de0265674d6061fc3d2006ea614bb15748` |
| Original `initial-after-x86.log` | `f22031df659f6bf3cbcf89d314b33acc719ecd299285927e56c61253adbcaa35` |
| Original `initial-after-arm/receipt.json` | `03ad7cde65a5c12cabed81dc22b395d86fc57a7e0ab6804e002932db72b57011` |
| Original `initial-after-x86/receipt.json` | `91a5aeacad876dc914a0f666f945c935c07a576f5f064df06aed2bbb042222b7` |
| ARM fcntlpath retry `initial-mask-new-after-arm.log` | `9ebf6855cf3590fe59283e9d142410657aa4584a143a0a7423c227de19348380` |
| ARM fcntlpath retry `initial-mask-new-after-arm/receipt.json` | `14d2812f44f4c23d185131e75f8d2e50a92aafd0507e02bfd7f762e8a9912ca4` |
