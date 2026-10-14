Independent pipecmd lifetime review: PASS

Reviewed the three pipe-only fcntl errno corrections and the synchronous PipeCapacityResource capability borrow against frozen baseline `f6d7c868c15bee486447baea44d0ea04aaa215cf`, the maintained pipecmd fixture, the Linux wrapper/controller and completed producer evidence. The errno-only change was committed separately as `98c0df505`; it passed semantics but exposed a real storage leak, so its receipt is retained as a diagnostic failure. Final native and actual Linux 6.12.51 controls pass on both architectures. All source, production C, receipt, ELF, drift, allocation, tracked-site and two corrected-kernel AArch64 performance captures below were consumed after their producers completed. Independent V assertions are compiled without -prod; the deliberately false assertion and a passing candidate submitted as the failing baseline both fail. Paths are relative to `/Users/alex/.cache/vinix-linux-compat/pipecmd-20261014`.

The errno changes preserve the original FD.unref operations. fd_from_fdnum takes both a descriptor and an open-file Handle reference while holding the descriptor-table lock. The Handle retains its underlying Pipe throughout the complete capability call, and fcntl drops that lookup only after success or the Option refusal returns. Concurrent descriptor close cannot release the retained underlying object during this call. Getter fallback still returns EBADF; setter refusal still saves backend errno before unref. No new free or ownership transfer appears in this fix.

Each new local capability is a non-owning 16-byte type/object interface wrapper. The unsafe address borrower points only to that function-local wrapper. Generated dispatch reads its type and invokes the concrete method using the retained Pipe object pointer; neither method receives the wrapper address. The wrapper is never stored, returned, registered with an event or passed to an asynchronous operation. Getter lock/read/unlock and every setter success/error path complete synchronously before the wrapper leaves scope. The unchanged setter may resize a ring and trigger an event, but those operations use the Pipe and its existing event, rather than the wrapper. This avoids the old per-call anonymous memdup box without freeing anything another reader could still observe.

Removing only the fcntl body/prototype and the two capability helper bodies/prototypes leaves byte-identical baseline/final production C on both architectures: exactly six units. Comparing the errno-only kernel with the final kernel needs only the four capability units removed. Each old helper contains one memdup of sizeof(PipeCapacityResource); each final helper emits a local wrapper and one pointer to it, followed by the same scalar/Option dispatch, with no memdup, allocation, free or escape. Interface types/dispatchers, FD lookup/destruction, Handle destruction, concrete Pipe getter/setter and the low-word syscall decoder remain byte-identical.

The fixture has twelve explicit allocas and fixed arrays, with no generated heap allocation, V array mutator or bounded-index helper. Its parent Bank and 29 retained aliases plus the socket peer stay live through both forked cohorts. A child receives its own forked address-space copy and only synchronously borrows Bank, Counts, stat, rlimit, ioctl and slab scratch. Parent aliases stay open until each child protocol and wait completes. The temporary pair scratch is consumed before reuse; every prepared scalar/metadata field used by a query is captured first, and capacity reads are guarded by the pipe-index predicate. Errno is copied to the scalar Query immediately after the real syscall/libc call.

Each child closes its result reader, initializes Counts, performs the finite matrix and storage calls, writes the full Counts object synchronously, closes the writer and exits. The parent closes its writer, reads Counts only when all 64 bytes arrive, closes the reader and waits before starting the next cohort. A short read or failed child therefore cannot expose uninitialized Counts to the report. Alias cycles always close the known duplicate before returning a semantic failure. The slab observer closes on snapshot/cycle failure and after successful bounded snapshots. Setup failure exits the child and uses existing process-exit descriptor cleanup. The parent closes all retained aliases and the peer before its verdict/pause. Queued AB/CD/GH bytes are checked before being drained, allowing the parent to seed the next cohort. Linux-wrapper argv storage stays live through synchronous execv.

Each root/UID-GID-1000 cohort performs [950,250,338,48] controls, totaling 3,172 per architecture. Nonpipe descriptors cover linked/unlinked regular files, a directory, /dev/null, UNIX stream socket and O_PATH; valid capacities cover anonymous read/write ends and a named FIFO. Original, dup and CLOEXEC aliases, fixed descriptors 64/65, five upper-register patterns, ignored getter arguments, libc calls, invalid descriptors, lowered soft limits 8/0 and closed/regular/pipe/reclosed descriptor 66 are checked. Final checks preserve metadata, status/FD flags, regular XYZ bytes and cursor 1, queued AB/CD/GH and the 80-slot vector. Setter positives request only the existing capacity. Both original baselines fail exactly [800,0,62,0] per cohort, 1,724 failures per architecture. Final five-case profiles (pipecmd, fcntlabi, fcntlpath, open, runtime) pass on both architectures, as do actual Linux references using the same probe ELF. Baseline/candidate/preview C is identical; preflight/baseline/candidate/errno-only/Linux probe ELFs match. Complete raw preflight C drift is separately pinned. Initial compiler-parentheses/pointer-signedness failures and the first Linux CPIO missing /dev/null are setup diagnostics, with no semantic baseline attributed to them.

The errno-only kernels pass every semantic row but retain exactly 4,000 size-16 objects in each of four architecture/credential storage cohorts; every other slab class and large-page count remains unchanged. Each measured cycle has twenty successful capability calls, so 200 cycles predict that growth. A production ALLOC_TRACK AArch64 root-only diagnostic resets the tracker after warmup and retains exactly two sites of 2,000 allocations times 16 bytes each, with live 4005 and dropped 0. The named stacks identify the fcntl getter/setter capability boxing. Its expected storage FAIL is preserved as diagnostic evidence. The diagnostic source/probe and tracked kernel are pinned separately from final qualification.

Final retention uses 32 warmups and 200 measured cycles per credential, settling thirteen seconds around each snapshot. Cycles duplicate/query/close regular, socket, O_PATH, anonymous-pipe and FIFO aliases across all five register patterns; supported getter/setter calls preserve existing capacity and queued data. All 18 ARM and 14 x86 slab classes and large pages remain flat: arm [ordinary=0: 75/75; ordinary=1: 75/75]; x86 [ordinary=0: 198/198; ordinary=1: 198/198]. Eight host test files pass. The 64 frozen dispatch input fingerprints agree; resource/cache.v is separately bound in both candidate trees, yielding 65 qualified source inputs; final scans preserve the existing 400 ARM/292 x86 allocation-site inventory and unchanged allowance failures.

Two fresh corrected-kernel AArch64 general controls complete: ops/churn/cache and idle/apps/drag. All 36 common operations retain zero bytes over 200 calls, and all four churn programs retain zero bytes over 300 runs; the cache workload writes 32 MiB. The three desktop scenarios complete. Actual FAT-staged kernel, measure ELF/source, config and frozen desktop were retained before cleanup and independently matched the production kernel/input pins. The production harness stages normally; its explicit callback skips only automatic shared-checkout cache pruning. No fresh general before-performance run or new x86 desktop run is claimed. The direct errno-only controls supply the measured leak baseline on both architectures.

Qualification is bounded to inherited descriptors, these finite commands and same-capacity setters. Ring resize/occupancy behavior, privileged ceilings, allocation-budget injection, unsupported FIFO-shaped getter capability fallback, setter-capability fallback, concurrent descriptor close/reuse/resize stress, GNU libc, translated/foreign and ELF32 paths and broad roadmap completion gates remain unqualified. Getter fallback was source-reviewed; the fixture does not create a FIFO-shaped resource without that capability. No broad section 15 gate is asserted.

SHA-256 pins were independently recomputed after completed producers; common rows require exact byte identity.

| File | SHA-256 |
| --- | --- |
| `kernel/file/file.v`, `kernel-arm/kernel/file/file.v`, `kernel-x86/kernel/file/file.v` | `bb05660fb6b07f7ae2e63d96fc4682f2581ebf350e2baa09cab5c3fbed204672` |
| `kernel/resource/cache.v`, `kernel-arm/kernel/resource/cache.v`, `kernel-x86/kernel/resource/cache.v` | `4a34a2f02113c56b7ea915d73959e03ab89ea3b25f55333b0e4ee366de5c6945` |
| `kernel/pipe/pipe.v` | `db8f9e83758af3fc974c15329c74f0bccaf8d3030e49eb8175faec420a4888e4` |
| `kernel/pipe/usercopy.v` | `7af5925a4de313f7d8847269f2e07a293cbfb9c585eeaf2ab926d712983cad9b` |
| `tests/linux-compat/pipecmdfixture/core.v` | `e2fc512dc614e13af04f2fee6fbe5b2d98e3c795ab111a9b1d878ed2b8fcd25d` |
| `tests/linux-compat/pipecmd-reference.v` | `a8c40447a7322713ab5b0975b5e855f1d4c2469816f9def5664a71d0e70aa9b2` |
| `tests/linux-compat/pipecmdreferenceinit/core.v` | `d5b65566ed351bd7f71bd6c493533644743025fff7dd28ac1c88855e3c525c86` |
| `tests/linux-compat/run.v` | `ff8ff1463ea08b31d155eba50715a241c28535f4aa7704fce2ee845da7032e39` |
| `independent-review.v` | `796b07cf5aed0b68a3fc6dcb4dd7f106328eee2fc7338cbbcef3ac5f49e0aae5` |
| `independent-review` | `6efbfe34378c1dbd0b7f356b2e51bbfe28d13207234e20ffe70dd2cd8e9bc14c` |
| `independent-controls.v` | `86adeb032309ebe45d90836540bc72c086e6a53a66accadb48338f565ee8b8cd` |
| `independent-controls` | `45354f565a6fbe5527e8d6a3c55080f38a7427354f186646cc67db54888d319d` |
| `independent-compile.log` | `f1988fdae6f334aaf1bad35da97ef11dec81c852663472bff84ed4530bcb64a3` |
| `independent-scope.log` | `536ee2ac70a92e5f1709c718fe66f9053b3deab79f4c933acdea6a4bd23c814e` |
| `independent-preview.log` | `b7d7e373b259fb5c92a52cf38e33a6318014b6aef19bbae0b38e2bd72342fcd5` |
| `independent-native.log` | `9802a8d7f4ea6ef48e24ab001c74486a669a5f150ea9f471ad123887a5e88897` |
| `independent-elf.log` | `c6e35db371a13c9bf9caacf5ba8ce96c1e1c5c8d6a0c88c46b8e450af674221b` |
| `independent-diagnostics.log` | `29ae5c87fa10636eafe0f687e93d0674686a848a3bed07146e6feb6ff01d211a` |
| `independent-performance.log` | `7f8c71b59a437f3f06e5e0e541ee31e9943d57c88ade48f27a4e6b47b2d38775` |
| `independent-assert-control.log` | `af278b546028e0954b394c5fc6e5043a0a7ebefac1d96068f32f14afedeae5f4` |
| `independent-passing-counts-control.log` | `084f142c8b00d4cac5f39e2070e3c5481d5f3804792b3c34e8b8d0205f2cb9a4` |
| `host-tests.log` | `f228b7e11e657a46f838bbbd67eb83c737152926bbe4a268930f6d9ae6fcbb4b` |
| `allocs-before.log` | `5717f7d842c4478c844af1e3a615d2ff0da3d5543c6dbd1ca0626a69aaf9551a` |
| `allocs-after.log` | `5717f7d842c4478c844af1e3a615d2ff0da3d5543c6dbd1ca0626a69aaf9551a` |
| `coverage-check.log` | `f14b0219fd4094c269a82b893f4a2424ffc8461e1745db3f9971f06dd81031fb` |
| `candidate-inputs.json` | `5f07ed7a1ad5c8373e677bbd01ef9907a208edd974b7c04c06ffe14ed3211fe5` |
| `preflight-drift-pins.json` | `5e0eec6556dff44ce2d7b98dd821711c53ff3ff0adc08d43bf20df265d572302` |
| `errno-commit.txt` | `138294e0b1f63f6a16a7d9430d185c17201fd945088defc9e15f83d7f309abe6` |
| `kernel-arm/docs/linux-syscall-coverage.json` | `a9da831c31ee3d6ac4f43885691f08b0adc2481ac6e472e49d91891edfeefa48` |
| `preview-arm.c`, `states/p2-before-arm/pipecmd/fixture.c`, `states/p3-after-arm/pipecmd/fixture.c`, `states/p2-after-arm/pipecmd/fixture.c` | `1926e87824d2470d226def03d3b2af768bb85cbbe5f4d67b4208577b96e89d70` |
| `states/preflight2-pipecmd-arm/init`, `states/p2-before-arm/pipecmd/init`, `states/p3-after-arm/pipecmd/init`, `states/p3-reference-arm/probe`, `states/p2-after-arm/pipecmd/init` | `9ee4eb9c29faa09b82e43560391879fef8ed3ffe0da112ab9cf67040f06a62da` |
| `tests/linux-compat/pipecmdfixture/core.v`, `states/p2-before-arm/sources/pipecmdfixture/core.v`, `states/p3-after-arm/sources/pipecmdfixture/core.v` | `e2fc512dc614e13af04f2fee6fbe5b2d98e3c795ab111a9b1d878ed2b8fcd25d` |
| `before-arm.c` | `e72a75ed5df39c6e365d2292fc5cc2a310f841c104586ba0179cc510e2154d34` |
| `errno-only-arm.c` | `6fc2009443c40e1e51df48308c897ec131ab7347db3ba1272288aecdf6988172` |
| `kernel-arm/kernel/obj/blob.c` | `1b41a7679a9a0a7a38c7eee6b3340702e4efd2e068f24bbec445cbf67a50ea0f` |
| `build-before-arm.log` | `827c875dc2592f8d86aaf47f6c3abea832e9b202d5eeb3f4eae61172b1d011ab` |
| `build-errno-arm.log` | `8371368948fd0599910e51bbadfa65c4dbefefe83aa0dbd507b014f16d5fe5f7` |
| `build-after-arm.log` | `9338cd8557801a370376b599e51c8b1eb1f0afc5cd34d7dae6fe63ea2070ae2a` |
| `preflight-drift-aarch64.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `baseline-arm/kernel/bin/vinix`, `states/p2-before-arm/kernel/bin/vinix` | `6e8e36cf94396325ce502a7eba7d9c35251b847d33deae48b81eb9c275a7838d` |
| `states/p2-before-arm/receipt.json` | `f7f1dd4cca5e95a477ce192012df29a2ba34a7721ef31f80f2174af304230590` |
| `states/p2-before-arm.log` | `8279436f91ece0851d2c9804f94fd5fa6b8735ed871494aa81df54c03896f536` |
| `states/p2-before-arm/pipecmd/fixture.c` | `1926e87824d2470d226def03d3b2af768bb85cbbe5f4d67b4208577b96e89d70` |
| `states/p2-before-arm/pipecmd/init` | `9ee4eb9c29faa09b82e43560391879fef8ed3ffe0da112ab9cf67040f06a62da` |
| `states/p2-before-arm/pipecmd/serial.log` | `10d1b737d567029c42849b82f297f13393ea1f3dbe8fa5f07984e26286c01e36` |
| `states/p2-before-arm/pipecmd/test.iso` | `00eeacaa4edb0325896020b71e4b9292ed7c4c738b7007ab8588e53412662157` |
| `kernel-arm/kernel/bin/vinix`, `states/p3-after-arm/kernel/bin/vinix` | `4c256c7435fef8052ccd08b07cbe9a4d5208af758ed97ce9f4e3b871545f396c` |
| `states/p3-after-arm/receipt.json` | `33eba3f616c4841ab257fa2be14b41e0ede4f3b4e284bfa76c054ef5c7aa3d62` |
| `states/p3-after-arm.log` | `acf4438d0603d1f65306031d47eaec85720dddd0c92e24e8a590d6dc70be376d` |
| `states/p3-after-arm/pipecmd/fixture.c` | `1926e87824d2470d226def03d3b2af768bb85cbbe5f4d67b4208577b96e89d70` |
| `states/p3-after-arm/pipecmd/init` | `9ee4eb9c29faa09b82e43560391879fef8ed3ffe0da112ab9cf67040f06a62da` |
| `states/p3-after-arm/pipecmd/serial.log` | `4d324043ef63de2ef016b2c0f3fd95845ce168116c7e23efcc34086b8651348c` |
| `states/p3-after-arm/pipecmd/test.iso` | `ec85f4789ee29b9a30b5ce368fa6f4d90f26adadbc2f5750071b1a3a59f498de` |
| `states/p3-after-arm/fcntlabi/fixture.c` | `214391504c640d251498205116f3dd9473925931e8a068e6a15ffb349965fb09` |
| `states/p3-after-arm/fcntlabi/init` | `b92892f1860ff4aae349f27924922645aed79becbcff2dd00a0a18fc797fd3fd` |
| `states/p3-after-arm/fcntlabi/serial.log` | `e202ff21f9e3f68b1dcd1c235cbb6afb3be3b47eb1fd96124b86756c5bb0836b` |
| `states/p3-after-arm/fcntlabi/test.iso` | `c5c1c76d5b32ac6b32b0db7c933fd3c4feaada0333712b630b0f1a82041a5e3c` |
| `states/p3-after-arm/fcntlpath/fixture.c` | `957fa07d680e3f01976bbb2b7a737cfdfb91019874dd8bcf45781101a30744c5` |
| `states/p3-after-arm/fcntlpath/init` | `11b8c3ffb5a640d607c362244b6b3816acb3b7315c83b9f6c0d6ba8add464510` |
| `states/p3-after-arm/fcntlpath/serial.log` | `bbe03665fa6c8746081f3d3766a2944646ce435d7d30725f441d9edebdb88b49` |
| `states/p3-after-arm/fcntlpath/test.iso` | `5624553d0d23f6853e101c9efcdc6e6a671717943a2b4b45b4376e3996fa79e4` |
| `states/p3-after-arm/open/fixture.c` | `b2d362c322a5a63aa9dd819e342ec30c0384972bdc55f9e59b7c81398ac41eb9` |
| `states/p3-after-arm/open/init` | `b41456ec1e04ca2e2e83e39ac5f01da498edfc8011f4eb71541bbc9ec9ec7c6a` |
| `states/p3-after-arm/open/serial.log` | `6664d28c79f7b586109559289ccef0c41f824bb0f7491655317299e80a971669` |
| `states/p3-after-arm/open/test.iso` | `7c76ee05145030a9902648b527706f18c2dd1f535e5f59c0c22f3e3e0a544e7a` |
| `states/p3-after-arm/runtime/fixture.c` | `05967a3ff8bb35aafaf2e91e58e1203b35780818a33b84031590b52943d60128` |
| `states/p3-after-arm/runtime/init` | `a27160c033a470689dafc283d37636bb5b81b1344d19e93a2c6071701187e44b` |
| `states/p3-after-arm/runtime/serial.log` | `fc87645828771f25abb88f59799cc161fcec52dcb4613894b69a3640a0bece8a` |
| `states/p3-after-arm/runtime/test.iso` | `4e300bc2647bbe74bf096227058b0e3e54dc66289b5501aa8e21fc03888f1c11` |
| `errno-only-arm/kernel/bin/vinix`, `states/p2-after-arm/kernel/bin/vinix` | `b25b88fbaca72e956782557e132d32c4d16742f07dd3f88514ee84a79abd011d` |
| `states/p2-after-arm/receipt.json` | `08ad14e8fd12029ca83ece2ffa730372c1a25be8a4d130f9ee12ee3431998901` |
| `states/p2-after-arm/pipecmd/serial.log` | `925750c82f83fe1d220967255b8814c51361964ceb61ab0f5d994ddf5a91a459` |
| `states/p2-after-arm.log` | `4baf3c3a02132c6ae80fc3c243dd2cb5107db23bdde44104e84c964d105b3e80` |
| `states/p3-reference-arm/fixture.c` | `d3e81a84174187733f4aeea3d76dc188c8b5a641b5797667d20a3e28a174b356` |
| `states/p3-reference-arm/init` | `ec07dd65c371171f54dd92698ce978dff46fbba46b22b1d1f76a64c16b4a5595` |
| `states/p3-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p3-reference-arm/serial.log` | `6a0d5e260e728a3940542471a833b57a2bdc39f795cb33d06c09ac428da2d531` |
| `states/p3-reference-arm/receipt.json` | `2696f2d23ced5018b4577a464e092817a4670ad85e71a344e32234657548d440` |
| `states/p3-reference-arm/initramfs.cpio` | `a0a8a56053dd4f72a61bba70e8347b06af4fe9b0a33ebbc72559a044f18e7deb` |
| `states/p3-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `tests/linux-compat/pipecmdreferenceinit/core.v`, `states/p3-reference-arm/source/pipecmdreferenceinit/core.v` | `d5b65566ed351bd7f71bd6c493533644743025fff7dd28ac1c88855e3c525c86` |
| `kernel-x86/docs/linux-syscall-coverage.json` | `a9da831c31ee3d6ac4f43885691f08b0adc2481ac6e472e49d91891edfeefa48` |
| `preview-x86.c`, `states/p2-before-x86/pipecmd/fixture.c`, `states/p3-after-x86/pipecmd/fixture.c`, `states/p2-after-x86/pipecmd/fixture.c` | `1926e87824d2470d226def03d3b2af768bb85cbbe5f4d67b4208577b96e89d70` |
| `states/preflight2-pipecmd-x86/init`, `states/p2-before-x86/pipecmd/init`, `states/p3-after-x86/pipecmd/init`, `states/p3-reference-x86/probe`, `states/p2-after-x86/pipecmd/init` | `36cadd5a60bff77b6febc7db3cb8a0eaa19a997f37e9be2d27b971134a72b629` |
| `tests/linux-compat/pipecmdfixture/core.v`, `states/p2-before-x86/sources/pipecmdfixture/core.v`, `states/p3-after-x86/sources/pipecmdfixture/core.v` | `e2fc512dc614e13af04f2fee6fbe5b2d98e3c795ab111a9b1d878ed2b8fcd25d` |
| `before-x86.c` | `5d89b50cdf6e3c252e6d08d3847f29e326a2d7f30c8d0245f4e9f713d2a60b5a` |
| `errno-only-x86.c` | `58e27ebd1900f5e0be23e7eb360e29696391e2eb3672463e8a1a1eeb5f6d58d4` |
| `kernel-x86/kernel/obj/blob.c` | `849ec23d5440b99e094f963b2be26b2cee5e00f1d3239eaf2a5426fb7f587d54` |
| `build-before-x86.log` | `d1e3a142deaab43b28f8518d0712dc10a164a6b87165dd567d0c10a89458f031` |
| `build-errno-x86.log` | `735dc4885035f8cb41cf0de29e9072f62ab83eaefdb59bbb2736d9dd6d28b71b` |
| `build-after-x86.log` | `33f0008cb777d80139254030f854ebf89c02f802e0b5440ac78d151c9f5316c6` |
| `preflight-drift-x86_64.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `baseline-x86/kernel/bin/vinix`, `states/p2-before-x86/kernel/bin/vinix` | `b3a9a76eec1fd10d3a1f92a2dfc1a7a65526a6c687353d12ca5458428df17dad` |
| `states/p2-before-x86/receipt.json` | `e3b27a6db929711fb3efabcf08a9756f0e454ec72525a02bf82cac06f7d1ede5` |
| `states/p2-before-x86.log` | `1990881811f671b511732ee6e647ba585de99ba821912421fa7b21687a5b781d` |
| `states/p2-before-x86/pipecmd/fixture.c` | `1926e87824d2470d226def03d3b2af768bb85cbbe5f4d67b4208577b96e89d70` |
| `states/p2-before-x86/pipecmd/init` | `36cadd5a60bff77b6febc7db3cb8a0eaa19a997f37e9be2d27b971134a72b629` |
| `states/p2-before-x86/pipecmd/serial.log` | `07380ffba73749bdf9b74021592eb06005fac6d9c621532efe343561f0c1d4fc` |
| `states/p2-before-x86/pipecmd/test.iso` | `f1525c6ff816fe0c46dd8af6698be2f053c86ba2f6ceb98483ee028089553b2c` |
| `kernel-x86/kernel/bin/vinix`, `states/p3-after-x86/kernel/bin/vinix` | `77fb6d0d12400bad9a71f56342f9f4683c933a8b668f890ba20146d5862733a7` |
| `states/p3-after-x86/receipt.json` | `a4cd28617c57ddb01cbb8dccac7eaba3c8550de2d9284cd71423324c2a23f919` |
| `states/p3-after-x86.log` | `767659e2f3e95ddcac83f3fa8d2121bbeb92b1c3e29b30249046e00bc1eea1f6` |
| `states/p3-after-x86/pipecmd/fixture.c` | `1926e87824d2470d226def03d3b2af768bb85cbbe5f4d67b4208577b96e89d70` |
| `states/p3-after-x86/pipecmd/init` | `36cadd5a60bff77b6febc7db3cb8a0eaa19a997f37e9be2d27b971134a72b629` |
| `states/p3-after-x86/pipecmd/serial.log` | `04cba44234f3cf387612328410e85577c8ca56e5db6a309fed5d618e91abb5d3` |
| `states/p3-after-x86/pipecmd/test.iso` | `6036e745096c6f289534bf664613c8bd6b05c4cbfd97ab59313f2e5f8c022bf7` |
| `states/p3-after-x86/fcntlabi/fixture.c` | `214391504c640d251498205116f3dd9473925931e8a068e6a15ffb349965fb09` |
| `states/p3-after-x86/fcntlabi/init` | `d627872a0a61cbe541ae88541b21efe49f0ae214e13801f1828a0cd19cb8dc16` |
| `states/p3-after-x86/fcntlabi/serial.log` | `fb0f6b4a53a70a2345a2577acfadf9023db79e6ee9c55e65c169903af212d54f` |
| `states/p3-after-x86/fcntlabi/test.iso` | `7f8d4d3ba5a6437fda08e9cc0dfac2d641a48b50493b07b065094f02706b2623` |
| `states/p3-after-x86/fcntlpath/fixture.c` | `957fa07d680e3f01976bbb2b7a737cfdfb91019874dd8bcf45781101a30744c5` |
| `states/p3-after-x86/fcntlpath/init` | `b0c820d141e0b7e7af9801761069655abf591d2e6e114c54cbcaba61b9555126` |
| `states/p3-after-x86/fcntlpath/serial.log` | `ab79f1ac4ccd2204361be55dcf5738087122d47b7bcb6fe8746fe9b0e9c1ea9a` |
| `states/p3-after-x86/fcntlpath/test.iso` | `d08f14f4d3a834fbc7aa6afbb652b590f24c8058d5a8173bce09e6328573c420` |
| `states/p3-after-x86/open/fixture.c` | `b2d362c322a5a63aa9dd819e342ec30c0384972bdc55f9e59b7c81398ac41eb9` |
| `states/p3-after-x86/open/init` | `377071b25bf7f8a9b3a048c8eab9ec87c689beb7ca5791e8439a46a4131f222a` |
| `states/p3-after-x86/open/serial.log` | `54eb6cbab773e3769ff502ca83030b75856525c7380a3238ab6a7b6d0fde5457` |
| `states/p3-after-x86/open/test.iso` | `e9862b476eb0159c206b17a2e71e72c1af20d6bc90109fee5cd00cec9c5fab10` |
| `states/p3-after-x86/runtime/fixture.c` | `283ee3218dbf04ee7c3289110ff0be3044906d48556453b06b7de972f4950e3b` |
| `states/p3-after-x86/runtime/init` | `3c22f6e44700a031e0c6e9bd04427095e423d595d3f9b81e09f07539d1ea3b9f` |
| `states/p3-after-x86/runtime/serial.log` | `0a8088397a56749f4b5b8275d36d23b60de5eafe640a5f6e4470d7e66b45c8cd` |
| `states/p3-after-x86/runtime/test.iso` | `c4d1f95453df41ef6672b767ea5706e8b44126510cb2fafeec47e7daf1ee3c8f` |
| `errno-only-x86/kernel/bin/vinix`, `states/p2-after-x86/kernel/bin/vinix` | `b3582d850625248ca947b6e323c1c04af57683f20facfce3da9c01be61232ea7` |
| `states/p2-after-x86/receipt.json` | `2558d5ff5b078d3ac31cefd20741c55c04bb802ed4266cde22e9457a3615b2a6` |
| `states/p2-after-x86/pipecmd/serial.log` | `4b3e23be6d359cff1bf229076054514f528502e681b3ae7a617771ec1af5444d` |
| `states/p2-after-x86.log` | `a4b21c3156833a99cc1e6e4b935e4cc186d61de5d9e786cd589352b2df87ac10` |
| `states/p3-reference-x86/fixture.c` | `d3e81a84174187733f4aeea3d76dc188c8b5a641b5797667d20a3e28a174b356` |
| `states/p3-reference-x86/init` | `dadb3d9f25358014977d0366d39c3f2cf082374e2f927f49ceb9579d94e2e54b` |
| `states/p3-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p3-reference-x86/serial.log` | `a2591091b6431571fbf37d0a201d7bb20e82b0e229fc980d487a554c73c1beea` |
| `states/p3-reference-x86/receipt.json` | `7198baad597911a637817a1223b2849276e27aedf10e20612f75385ff9bd9565` |
| `states/p3-reference-x86/initramfs.cpio` | `3dadb9c7277662bb0fe80ae540a69e46ecf2ac57b4da0a128afd760c10c46fd2` |
| `states/p3-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `tests/linux-compat/pipecmdreferenceinit/core.v`, `states/p3-reference-x86/source/pipecmdreferenceinit/core.v` | `d5b65566ed351bd7f71bd6c493533644743025fff7dd28ac1c88855e3c525c86` |
| `build-track-arm.log` | `9f530e622a29d9a0ad1d0b9963425241999f2d5cce591bd5ed9941afc0f842e1` |
| `track-arm.c` | `36b65f2ff0664806d2f928d0f4d983f27c449ec085d90eae8c66227543173a63` |
| `tracked-arm/kernel/bin/vinix` | `59476a9e866c7b9a54b188e9bbc80cc12224dbe9d3166f456237e699dd6d2bb8` |
| `track-source/pipecmdfixture/core.v` | `48269c93ab92534c606ec534354c424a778321d81d4c389e092636368d8182ae` |
| `states/track-arm/fixture.c` | `f333dc0b6488f0168b57ba6e407c68bfa06c01c7909a091afd8c9a355cdbeddf` |
| `states/track-arm/init` | `825fb6e1c38c5df4c51965d9d384c7f98ef2b9f28cc2921ec5a27a601b792471` |
| `states/track-arm/serial.log` | `ca6e713371a29fbc8c4eb8b89b03ac322cb9d79fe329804c6634a016c95e67d0` |
| `states/track-arm/test.iso` | `0558b8577d1b6996f3ec3737d274642a5cea2f96d09a0f996031e332b08362ab` |
| `track-sites.log` | `a40cc652fbccacff032bd2e90c208bb822720cb8a554b539d004049fc2b76b63` |
| `track-named-sites.log` | `ba2cbfa94f8775fe1480a16333870ad996552799c511b18200600dcba22d60ad` |
| `track.v` | `7079f53a3b206537aa962879b9563f0649d186623452830e2785eafaaef5f8c6` |
| `track-guest.v` | `6657d5b2f73e5d1bb64d60380b4a05a2f7ad6edce13c9a07ed8c0a52c65cc624` |
| `track-convert.v` | `a0a64e41c388797e3a46a1b5db201297b7405183baeb206d29bdb4162da81f10` |
| `track-name.v` | `e0087b9061bf246ae03b6f5957d25f168fc8c00b85b29a0d5bebf44cd553412b` |
| `perf-after-ops.log` | `a287f905c2f6ceab351bc0470f1d29148c046a3533bd22fd14f4b6f43bb12a6d` |
| `pf-after-ops/serial.log` | `8d45a77d48b1e772d87dcd22b12cc7dbbcfdff7e9cc8cf63a5d0137cef7f393e` |
| `pf-after-ops/result.json` | `07bfa67302d2a50043630e276415a9f123414876beb0a072fecc546b7aa785e0` |
| `pf-after-ops/stage-pins.json` | `25ea76628aa2fb26be61e445063f9aabe07212974bb59506618238d12087938c` |
| `pf-after-ops/artifacts/kernel` | `4c256c7435fef8052ccd08b07cbe9a4d5208af758ed97ce9f4e3b871545f396c` |
| `pf-after-ops/artifacts/measure` | `ed5856050a1053bb96e36905e28b13e65e1bae86d815bcac5e1c5bd959b7cdb4` |
| `pf-after-ops/artifacts/measure.c` | `2490bc0e69142080f52a469e241cbb37d61d0e0687a191618654a3b617b68771` |
| `pf-after-ops/artifacts/config` | `8aade1ee295749bd4bb45b3419511888a5985d481bc1e6ad0dedccb60c186d04` |
| `pf-after-ops/artifacts/vinix-desktop-new` | `293830fc291de6f9ce0ba13227259a3ccf3360105037181884c86de5b575abfb` |
| `perf-after-desktop.log` | `d0948f68adf007157f178abcb585462e80318754faa84f2d11f89d77ad9bb55b` |
| `pf-after-desktop/serial.log` | `5c813e2309e4729ac5e09a67829cb2a0484978d163fb37150fda20ce7425ba6e` |
| `pf-after-desktop/result.json` | `bac224d03e283199b1a02c895b8f4cf8fcb06d5cbba96fc0c37123e91c35f116` |
| `pf-after-desktop/stage-pins.json` | `14b192f963319baa05feb25e840dccdab0888d97179b42a234839e0d90b2fd49` |
| `pf-after-desktop/artifacts/kernel` | `4c256c7435fef8052ccd08b07cbe9a4d5208af758ed97ce9f4e3b871545f396c` |
| `pf-after-desktop/artifacts/measure` | `ed5856050a1053bb96e36905e28b13e65e1bae86d815bcac5e1c5bd959b7cdb4` |
| `pf-after-desktop/artifacts/measure.c` | `2490bc0e69142080f52a469e241cbb37d61d0e0687a191618654a3b617b68771` |
| `pf-after-desktop/artifacts/config` | `0ce84cffbbba028da343ffd038b627a7db3c139f0f2f5413f4ee15ddbc46bd1e` |
| `pf-after-desktop/artifacts/vinix-desktop-new` | `293830fc291de6f9ce0ba13227259a3ccf3360105037181884c86de5b575abfb` |
| `perf-inputs/image.tar` | `d491b349c45b1fb2b5052b4a41fbb90857cf68488c0e6b17caafbe1d879843a9` |
