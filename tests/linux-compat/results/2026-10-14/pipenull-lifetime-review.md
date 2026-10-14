Independent pipenull lifetime review: PASS

Reviewed only removal of the early nil-output EFAULT branch in kernel/pipe/usercopy.v against frozen baseline `d44681e1a45cb23eacfa8c3b85ab4bcc8b7f014b`, the V nil-pressure fixture, Linux reference wrapper/controller and completed qualification evidence. Production builds, preview/source identity, all native profiles, actual Linux references, complete drift evidence, allocation scans and inventories were consumed after producers completed. Independent V assertions execute without -prod; a deliberate assertion and a passing candidate presented as the failing baseline both fail. Paths below are relative to `/Users/alex/.cache/vinix-linux-compat/pipenull-20261014`.

Nil now reaches the existing private pipe/endpoint construction and the unchanged pair-installation helper. A zero/one-slot refusal leaves both endpoints private, saves errno and drops both FD references exactly once through the existing constructor cleanup. No scratch word is read when construction refuses. When construction succeeds, both scratch numbers are initialized before return and the table owns both references. usercopy.valid_user_range rejects the nonzero-length zero address before pagemap lookup, locking, page resolution or physical copy. The unchanged checked-copy failure branch then closes both numbers synchronously and returns EFAULT. No new allocation/free primitive, retain/release, interface box, scratch storage or asynchronous borrow was introduced. The existing immediate private-endpoint reclamation and table-reference closes are appropriate for the single-threaded qualification. Shared-table output-copy/rollback races remain separate.

On both architectures, removing only syscall_pipe_checked body and its prototype leaves byte-identical production C. Pipe construction, FD pair adoption, FD constructors/destructors, Pipe.unref and every user-copy helper are byte-identical to baseline. The changed body removes only the early nil conditional; its existing two-i32 stack alloca, synchronous constructor/copy calls and two FD-number closes remain. It adds no hidden heap allocation. The zero-address range guard is present before the pagemap lock in the unchanged generated user-copy helper.

The fixture exactly matches the committed pipepair fixture after module/marker/path label changes, the added nil destination, the eighth destination loop entry, nil selection for zero/one-slot storage cycles and one extra nil EFAULT query after both slots can be installed. The added nil_copy Outcome is a scalar value; all four booleans are checked and no pointer is retained. The fixture retains 16 explicit allocas, fixed arrays and zero generated heap or V runtime helpers. The three-page mapping remains live for all synchronous calls and observations; nil/inaccessible/noncanonical/readonly/cross-page outputs are never dereferenced. Only successful writable outputs are copied with memcpy into aligned i32 scratch. EMFILE refusals and bytes outside valid successful outputs check writable canaries; EFAULT permits a partial copy. The table vector is checked before repairing only the known temporary holes. The original limit is restored while finite pipe aliases, data and EOF are checked, all known aliases close, then filler descriptors and their flags are restored. The observer closes after bounded snapshots; nine retained aliases keep metadata, flags, regular-file cursor and queued bytes through final state checks before cleanup/unmap. Setup failure exits the child. Counts are initialized and synchronously written/read through a result pipe; the parent inspects only complete records and waits before the next cohort. The Linux wrapper borrows stack argv only through synchronous execv.

Each root/UID-GID-1000 cohort has [1280,1280,2560,13] checks, totaling 10,266 per architecture on native and actual Linux 6.12.51. Baselines have exactly [80,0,0,0] failures per cohort: nil wrongly returns EFAULT instead of EMFILE with zero/one free slot. Both final six-case profiles (pipenull, pipepair, pipeabi, access, open, runtime) pass. Preview/baseline/candidate fixture C is byte-identical; preflight/baseline/candidate/actual-Linux probe ELF is byte-identical per architecture. Preflight/native function bodies match, with complete raw drift logs and eight pins independently checked. Semantic nil EFAULT calls with available slots verify that both temporary table entries disappear before filler repair.

Fresh candidate pressure retention uses 32 warmups and 200 measured cycles per credential with 13-second settling around snapshots. Each cycle covers five upper-register patterns, nil with zero/one free slot, an ordinary pipe with two slots and aliases/data/EOF, cross-page EFAULT with three slots and an additional nil EFAULT query with three slots. The latter directly exercises synchronous cleanup of both installed descriptors for nil, and checks behavior, table state, applicable canaries and filler restoration. All 18 ARM and 14 x86 slab classes and large pages remain flat: arm [ordinary=0: 68/68; ordinary=1: 68/68]; x86 [ordinary=0: 177/177; ordinary=1: 177/177]. Completed allocation scans retain 662 ARM/658 x86 copied sources and the same 400/292 sites and existing allowance refusals; eight host test files and exact frozen 64-input inventories pass. No fresh general ops/churn/cache or desktop performance result is claimed for this kernel.

Qualification is bounded to soft limits 48/64, ordinary pipe flags, the tested lower/upper argument words and single-threaded output/cleanup controls. Table expansion and growth-budget refusal, injected constructor-budget failures, concurrent limit changes, shared-table output-copy/rollback races, copy-before-publication, packet/watch-queue modes, arbitrary descriptor churn, GNU libc, translated/foreign and ELF32 paths remain unqualified. No broad roadmap completion gate is asserted.

SHA-256 pins were independently recomputed after completed producers; common rows require exact byte identity.

| File | SHA-256 |
| --- | --- |
| `kernel/pipe/usercopy.v`, `kernel-arm/kernel/pipe/usercopy.v`, `kernel-x86/kernel/pipe/usercopy.v` | `7af5925a4de313f7d8847269f2e07a293cbfb9c585eeaf2ab926d712983cad9b` |
| `kernel-arm/kernel/file/file.v`, `kernel-x86/kernel/file/file.v` | `267ad1533ded8aea20b52f7f7caab2f1893dfe56f3e1cf80f67dd56644b4a578` |
| `kernel-arm/kernel/pipe/pipe.v`, `kernel-x86/kernel/pipe/pipe.v` | `db8f9e83758af3fc974c15329c74f0bccaf8d3030e49eb8175faec420a4888e4` |
| `kernel-arm/kernel/usercopy/usercopy.v`, `kernel-x86/kernel/usercopy/usercopy.v` | `4c36b49cd3abe25aa70897981d0d1695edc1244c2d449c4c849fb0750e712f9e` |
| `tests/linux-compat/pipenullfixture/core.v` | `2cc1789b47299720fffa60a5455939ba8843b33ed332c56dfd7ac354a5b88fea` |
| `tests/linux-compat/pipenull-reference.v` | `b88cd17517fa1962ebad77f305a5a78e0efa0f0efc1f5171e623259fdd08112c` |
| `tests/linux-compat/pipenullreferenceinit/core.v` | `1b796e581a9fd609cbcd8d462b919eca8ee3b9f076f61a80166034d734a25e4c` |
| `tests/linux-compat/run.v` | `45a78743a71c6f681e182f35b2d78a5cbdc3609126cc0cf9aad2ce80971bd320` |
| `independent-review.v` | `39ba3d9cbb36a4a7f947756511634ae1f6a424acba24b09f737029e3b2ae8cf9` |
| `independent-review` | `62f54ea02e958ee8ac042f258fb33ae0010b8ea2348bc574bf24ca36e186e1eb` |
| `independent-controls.v` | `0e7f180ad1c3779da8bc6a462fe0766e11a3f5569570742fc47de43bacc5582b` |
| `independent-controls` | `7059fa77a4a75e8a957ee84e6decc4108a41e112d86dcf5afc7a58b59688db37` |
| `independent-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-scope.log` | `43da21d1b558bc3381480e87ff20216c916085734a8b3512c67241af4666e161` |
| `independent-preview.log` | `ebbb6dd20c4697d6057f2fad9cb2998f541e8924e6a56e27f3da7decf344f73b` |
| `independent-native.log` | `d4b10ca15916a48b296255b8c9eb5757f2586a891a7e695831c662f9713484a8` |
| `independent-elf.log` | `0d2a85e4483d1e2b7556642f36505b2f4ed808d815d239599139e175c81f6256` |
| `independent-assert-control.log` | `c930233d4d78d01031ba6c46c462e1c31cdc08a7bfda74cc98d5f4f09f923ccc` |
| `independent-passing-counts-control.log` | `375e9dd0925a280958dd70c14de7ea0c7dc74e73d498bcbcb7b136137c5a410f` |
| `host-tests.log` | `6dabc637afb2d9828cbb6a8abc730206e8dc7df5b6470b4fefa2c572acbb2d78` |
| `allocs-before.log` | `970d1fac314ca39b9c52025be13f0e924a7831b3ca3b8acf69e55478c5258356` |
| `allocs-after.log` | `970d1fac314ca39b9c52025be13f0e924a7831b3ca3b8acf69e55478c5258356` |
| `coverage-check.log` | `f14b0219fd4094c269a82b893f4a2424ffc8461e1745db3f9971f06dd81031fb` |
| `candidate-inputs.json` | `55716c5f69e6cb8ea54c87b39589204e53d80f969433463737a414b489229d49` |
| `preflight-drift-pins.json` | `b8a0490bae38d1163db36ff2211d7c0560d803b8c978ca3fd560a3663f36816a` |
| `kernel-arm/docs/linux-syscall-coverage.json` | `477c3b0262041320ca06121738fb2d4bb81833974847e15539bd7fff75faae26` |
| `preview-arm.c`, `states/p5-before-arm/pipenull/fixture.c`, `states/p5-after-arm/pipenull/fixture.c` | `e22cbf39b7b029c121e45fe9174f97d8a7197210d9578f709582cb21f2a59283` |
| `states/preflight5-pipenull-arm/init`, `states/p5-before-arm/pipenull/init`, `states/p5-after-arm/pipenull/init`, `states/p5-reference-arm/probe` | `79592f1fd42fc4810de5135275b8e51d125bbcb9a15592cdef68bc935e66a985` |
| `tests/linux-compat/pipenullfixture/core.v`, `states/p5-before-arm/sources/pipenullfixture/core.v`, `states/p5-after-arm/sources/pipenullfixture/core.v` | `2cc1789b47299720fffa60a5455939ba8843b33ed332c56dfd7ac354a5b88fea` |
| `before-arm.c` | `dcecfcf27af75cb7affdbd146b739e8b59f29a0703af81791d0d57cf256fd224` |
| `kernel-arm/kernel/obj/blob.c` | `857bbfa2aa0282d3f4bfdc98d76e4fcc816c8ec290f2bd11008d2335c549cc88` |
| `build-before-arm.log` | `3225df7730079f84ad420565f928708f13eb581db81898260a271d10b515993d` |
| `build-after-arm.log` | `c9c96375ee6aa85d5b980b97216678a817268a902f68d7d82f5a81e8063af592` |
| `preflight-drift-aarch64.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `baseline-arm/kernel/bin/vinix`, `states/p5-before-arm/kernel/bin/vinix` | `babf435fc9a4f6b7b7562dea9366295d8275228e6232865f8f6b66fc5485059a` |
| `states/p5-before-arm/receipt.json` | `cf5faf83abb8825e2bf3134cddcbad38fb34aad2c3cbdb9d6bfb7462b0e6a487` |
| `states/p5-before-arm/pipenull/fixture.c` | `e22cbf39b7b029c121e45fe9174f97d8a7197210d9578f709582cb21f2a59283` |
| `states/p5-before-arm/pipenull/init` | `79592f1fd42fc4810de5135275b8e51d125bbcb9a15592cdef68bc935e66a985` |
| `states/p5-before-arm/pipenull/serial.log` | `ed707500645b2b8ea0814c3252e775db8f80a97081fdce0f6071d103951862f2` |
| `states/p5-before-arm/pipenull/test.iso` | `05cba33ab40de13b40b8caeb4ae82464ecbf34d7665bc4002db1027ab61d23c7` |
| `kernel-arm/kernel/bin/vinix`, `states/p5-after-arm/kernel/bin/vinix` | `29ea79334f1fb428876e6c3d3b5837421071df7a5f67632d100865ec523e366f` |
| `states/p5-after-arm/receipt.json` | `061a907640653077d868325ea59f90916e7b1038ac2a9880429b7e6f439ed0db` |
| `states/p5-after-arm/pipenull/fixture.c` | `e22cbf39b7b029c121e45fe9174f97d8a7197210d9578f709582cb21f2a59283` |
| `states/p5-after-arm/pipenull/init` | `79592f1fd42fc4810de5135275b8e51d125bbcb9a15592cdef68bc935e66a985` |
| `states/p5-after-arm/pipenull/serial.log` | `4f84b034a876f8334bdb229eaae2f26ad26e3b34fc84b394a73c41391755360c` |
| `states/p5-after-arm/pipenull/test.iso` | `80acbffcb58c49cb685ee2bbc50caee845a216dcbea0abebd4e6d95e1fb44e2b` |
| `states/p5-after-arm/pipepair/fixture.c` | `c1ad49d7434cb46007a984e1fe1adacb73f378fe95418fd679798f6a5799b903` |
| `states/p5-after-arm/pipepair/init` | `243ab552266dd6eb16a8ef6ff1791feaec3e1aa9393d90878d5bfd720d483590` |
| `states/p5-after-arm/pipepair/serial.log` | `d4c0187709af5277127ac6767630e97c848175d5578f56b74ff7b11bf4504e7b` |
| `states/p5-after-arm/pipepair/test.iso` | `cdaca6c67f0a9b80dfeb4b238836dae674ee70d43385a135399cf65aae9a77d5` |
| `states/p5-after-arm/pipeabi/fixture.c` | `79a79dda28535e28be10be21c8847f756f589a38286b120c6ec23e7356675520` |
| `states/p5-after-arm/pipeabi/init` | `bad77855f6efd4731ad1d66bf7c7569ac3d5fa647d5a13b03cbe9289d6a13ae0` |
| `states/p5-after-arm/pipeabi/serial.log` | `7adab853ee4148fa56651580b24705b5c2fe178c1759f7d229685f5f00782828` |
| `states/p5-after-arm/pipeabi/test.iso` | `43351dff0b83626737f02b73e00baee3d1d6006b038ff299bf56f933679558a3` |
| `states/p5-after-arm/access/fixture.c` | `53998280afb32ec26809a7bfb1f9b6e7b24f5e326e7b2e2755d6f8bdf9e4b599` |
| `states/p5-after-arm/access/init` | `913381428a4adcc149d2e55098b8658d385310a39b75507d7ad20db6404874ab` |
| `states/p5-after-arm/access/serial.log` | `8573f4e2c2efa05785e42091649278bdf2360ab24decf9d9d8842db1d4bb09c4` |
| `states/p5-after-arm/access/test.iso` | `9623e192818993fb5dfa48c89191a0d078d2028381c8ab48413755043c068ce6` |
| `states/p5-after-arm/open/fixture.c` | `b2d362c322a5a63aa9dd819e342ec30c0384972bdc55f9e59b7c81398ac41eb9` |
| `states/p5-after-arm/open/init` | `b41456ec1e04ca2e2e83e39ac5f01da498edfc8011f4eb71541bbc9ec9ec7c6a` |
| `states/p5-after-arm/open/serial.log` | `02af6f0f40e046b44004e7fa7bbbbf42922a57a7d4b3119dffa87846cb98af84` |
| `states/p5-after-arm/open/test.iso` | `b47442b44289ce16b52901159cef9d0928bba9b3d78d70836dd91697bfb42669` |
| `states/p5-after-arm/runtime/fixture.c` | `05967a3ff8bb35aafaf2e91e58e1203b35780818a33b84031590b52943d60128` |
| `states/p5-after-arm/runtime/init` | `a27160c033a470689dafc283d37636bb5b81b1344d19e93a2c6071701187e44b` |
| `states/p5-after-arm/runtime/serial.log` | `d2b10c6171709910cf8458748df7059066450ee508e5baebc298df1b62cb03ed` |
| `states/p5-after-arm/runtime/test.iso` | `56c6bfa15bd09cfb83d1f86eb7b62c28fef11e5e934e250dda842c73a080691f` |
| `states/p5-reference-arm/fixture.c` | `2a3e1c565292ade38bcf24e238a2ca58f12bb585ea4fc6606b09d1cafcf8fa18` |
| `states/p5-reference-arm/init` | `37af0950111f816454973091bb24dfdac077b4b5320fa3229f53bed0d4bc5ac3` |
| `states/p5-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p5-reference-arm/serial.log` | `200d597282f2121a3f47cbafe13cc15fd53c9d2d5d70954bc67fc344906ec500` |
| `states/p5-reference-arm/receipt.json` | `bddbb3df30d5c0ccf5b029750e9fca3b0065ec353aa4d2d5c4a28b87d8b89eec` |
| `states/p5-reference-arm/initramfs.cpio` | `c53e34ee3234a9bfdfe5824a287baade71f4cbf176d4fe65d40d454178f722cc` |
| `states/p5-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `tests/linux-compat/pipenullreferenceinit/core.v`, `states/p5-reference-arm/source/pipenullreferenceinit/core.v` | `1b796e581a9fd609cbcd8d462b919eca8ee3b9f076f61a80166034d734a25e4c` |
| `kernel-x86/docs/linux-syscall-coverage.json` | `477c3b0262041320ca06121738fb2d4bb81833974847e15539bd7fff75faae26` |
| `preview-x86.c`, `states/p5-before-x86/pipenull/fixture.c`, `states/p5-after-x86/pipenull/fixture.c` | `e22cbf39b7b029c121e45fe9174f97d8a7197210d9578f709582cb21f2a59283` |
| `states/preflight5-pipenull-x86/init`, `states/p5-before-x86/pipenull/init`, `states/p5-after-x86/pipenull/init`, `states/p5-reference-x86/probe` | `f8e6a86cda19507ec532ba9df0a831c76bcb213b525ee6114279e3561e4ffd10` |
| `tests/linux-compat/pipenullfixture/core.v`, `states/p5-before-x86/sources/pipenullfixture/core.v`, `states/p5-after-x86/sources/pipenullfixture/core.v` | `2cc1789b47299720fffa60a5455939ba8843b33ed332c56dfd7ac354a5b88fea` |
| `before-x86.c` | `a48b2dcffe6178704e2b49e9385559e222e4876260b010ee06eba26c8e021530` |
| `kernel-x86/kernel/obj/blob.c` | `5b23b793e22b4b916cc137c8ff1b58a4e3ce8efe021fa834c198dcfa94a7d01f` |
| `build-before-x86.log` | `1ab94a9699dbb7fd9d8b87d744f33e612c3d248e8d3864362ed7cba0587a7266` |
| `build-after-x86.log` | `2cc59003cb221c1034e00b932890c605d16366824690f58a1b62362a98cda534` |
| `preflight-drift-x86_64.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `baseline-x86/kernel/bin/vinix`, `states/p5-before-x86/kernel/bin/vinix` | `0f7ad0de38168fefaa482d1765aa11fd2383797889c8a50f7b36f31d273992d7` |
| `states/p5-before-x86/receipt.json` | `8ccabf66370316902a17e24e3c45bea42274c497514d242d9b0be2497efc644b` |
| `states/p5-before-x86/pipenull/fixture.c` | `e22cbf39b7b029c121e45fe9174f97d8a7197210d9578f709582cb21f2a59283` |
| `states/p5-before-x86/pipenull/init` | `f8e6a86cda19507ec532ba9df0a831c76bcb213b525ee6114279e3561e4ffd10` |
| `states/p5-before-x86/pipenull/serial.log` | `5ce806edf8180ca950f0487bea46f3bc49682fb22374b5efdb09a037ed6da71c` |
| `states/p5-before-x86/pipenull/test.iso` | `b82ee8ee6ed4eef9aa2372cef97e38d12005709f50a303bf4181be18006ad2c5` |
| `kernel-x86/kernel/bin/vinix`, `states/p5-after-x86/kernel/bin/vinix` | `1e6bd83f147be92d72bef66619f701baf9aae9a51af26dd7369da317cf02bdd6` |
| `states/p5-after-x86/receipt.json` | `915fde60f262ee283fb8c8e8955b1c3b23312409e630e22441d2c3b2acdc59b1` |
| `states/p5-after-x86/pipenull/fixture.c` | `e22cbf39b7b029c121e45fe9174f97d8a7197210d9578f709582cb21f2a59283` |
| `states/p5-after-x86/pipenull/init` | `f8e6a86cda19507ec532ba9df0a831c76bcb213b525ee6114279e3561e4ffd10` |
| `states/p5-after-x86/pipenull/serial.log` | `831f9b94a68865ed54979c9a1aa00fa970e253975b28fcc602c4e8d8a0deb51d` |
| `states/p5-after-x86/pipenull/test.iso` | `3bef95c6d97a7082fac491ad223221e4b0be4fa9de25008335c6c0ecc4a5b7f0` |
| `states/p5-after-x86/pipepair/fixture.c` | `c1ad49d7434cb46007a984e1fe1adacb73f378fe95418fd679798f6a5799b903` |
| `states/p5-after-x86/pipepair/init` | `c756d702ffd2b6fa5eaa7e2cea24ad319148978173f8cea545210ec2f2e5ddb9` |
| `states/p5-after-x86/pipepair/serial.log` | `68637e4b85fc4a6bfed236ee2776d7ae7b1d0ea6b2682acc257c899310062968` |
| `states/p5-after-x86/pipepair/test.iso` | `b4f2e7d7dc6361ff0cc7ad25643c0576f1fcb6c672a3421eeda20fd3efc9da9b` |
| `states/p5-after-x86/pipeabi/fixture.c` | `79a79dda28535e28be10be21c8847f756f589a38286b120c6ec23e7356675520` |
| `states/p5-after-x86/pipeabi/init` | `f911107fb89f3639529caf225841eeecf9c888367531c3323cd3f8eb64283132` |
| `states/p5-after-x86/pipeabi/serial.log` | `25df572876f64fb6f8caf0c58c16f552161b7f05c47fdb46e7b762fa56f1277c` |
| `states/p5-after-x86/pipeabi/test.iso` | `57c499b2bdc53cc6bf998afde615d9045dd4c582a9d7ee2e9ab96dec3c6680a5` |
| `states/p5-after-x86/access/fixture.c` | `53998280afb32ec26809a7bfb1f9b6e7b24f5e326e7b2e2755d6f8bdf9e4b599` |
| `states/p5-after-x86/access/init` | `87b5e511b3b759b08dd182c459faab3cf9839920656c8a612efe9d94eeb026fb` |
| `states/p5-after-x86/access/serial.log` | `d3a9ebb7cbc7ab8df87bc0659f8d4e468be2e3e169b1631930aa88592da7538a` |
| `states/p5-after-x86/access/test.iso` | `c2ae059440e539557c10a83b82d1772559210e5c102a1eabf20de8bea95eead2` |
| `states/p5-after-x86/open/fixture.c` | `b2d362c322a5a63aa9dd819e342ec30c0384972bdc55f9e59b7c81398ac41eb9` |
| `states/p5-after-x86/open/init` | `377071b25bf7f8a9b3a048c8eab9ec87c689beb7ca5791e8439a46a4131f222a` |
| `states/p5-after-x86/open/serial.log` | `54eb6cbab773e3769ff502ca83030b75856525c7380a3238ab6a7b6d0fde5457` |
| `states/p5-after-x86/open/test.iso` | `2b1139eef9f1bd02e0233255ef5df3f714afc6d8010b57106c53f6da013d284c` |
| `states/p5-after-x86/runtime/fixture.c` | `283ee3218dbf04ee7c3289110ff0be3044906d48556453b06b7de972f4950e3b` |
| `states/p5-after-x86/runtime/init` | `3c22f6e44700a031e0c6e9bd04427095e423d595d3f9b81e09f07539d1ea3b9f` |
| `states/p5-after-x86/runtime/serial.log` | `533365cc1f92b6694ad0a2db14d8efa0eed8272e38d66c226dfd24505e7ed140` |
| `states/p5-after-x86/runtime/test.iso` | `38fac4bbb4295141f0ca4090cee1463957a3fd96083a08c95eecc81cfa19f37a` |
| `states/p5-reference-x86/fixture.c` | `2a3e1c565292ade38bcf24e238a2ca58f12bb585ea4fc6606b09d1cafcf8fa18` |
| `states/p5-reference-x86/init` | `6c3e52eccb792cc28a2a1fe913776c01abc92b87f97f017880b1ea75c6845b5d` |
| `states/p5-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p5-reference-x86/serial.log` | `aa67024796d9440de073e207a3e60ec278f087487a60c534bc9729df50a45fba` |
| `states/p5-reference-x86/receipt.json` | `62e0c4ad2b553c965783607fe29b25dda31c784eb35dcaa418adde6d5c91d288` |
| `states/p5-reference-x86/initramfs.cpio` | `7143afe9d783918f66d5430f19043050d2bb5261a48ca32c09cd8206174ce2f8` |
| `states/p5-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `tests/linux-compat/pipenullreferenceinit/core.v`, `states/p5-reference-x86/source/pipenullreferenceinit/core.v` | `1b796e581a9fd609cbcd8d462b919eca8ee3b9f076f61a80166034d734a25e4c` |
