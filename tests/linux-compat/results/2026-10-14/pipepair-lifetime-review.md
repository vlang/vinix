Independent pipepair lifetime review: PASS

Reviewed only kernel/file/file.v fdnum_create_pair and kernel/pipe/pipe.v syscall_pipe against frozen baseline `d6a33ce248887d5dd8e400eb6d3b78d315a6567d`, the native V pressure fixture, Linux wrapper/controller, and completed qualification evidence. Native and actual Linux 6.12.51 controls pass on both architectures. Production builds, previews, receipts, ELF/source identity, drift, allocation scans and all four performance runs were consumed after completed producers. Independent V assertions run without -prod; a deliberate assertion and a passing candidate presented as the failing baseline both fail. Paths below are relative to `/Users/alex/.cache/vinix-linux-compat/pipepair-20261014`.

The first endpoint stays private while the writer is constructed. Its Handle owns one retained pipe reference, so no shared FD table can close the first endpoint and free the pipe during writer construction. Existing fd_create_from_resource retains before fallible budget reservations; release_unopened_resource returns a refused reference using synchronous stack Handle storage with the original access mode. First-reader construction failure therefore frees the otherwise unowned pipe; writer construction failure returns the writer reference and leaves the private reader for the caller to unref. The caller saves errno before that unref. This constructor-budget path is source-reviewed, without fault-injection qualification.

The new pair helper finds two distinct lowest free slots below the existing capped soft limit while holding fds_lock. It grows the table only after both numbers are available, using unchanged grow_fd_table under the same lock policy. Refusal leaves slots and the caller scratch unchanged and returns both FD references to the caller, which saves errno and drops each reference exactly once. These failed endpoints were never published or registered with an asynchronous observer, so immediate existing FD.unref reclamation is appropriate. On success the table adopts both references under one lock hold; the caller neither releases nor accesses either FD after publication. Both scratch words are written before releasing the lock. The two-i32 scratch remains borrowed only by synchronous constructor/copy calls. No new deferred or asynchronous borrow is introduced.

On both architectures, removing only syscall_pipe body/prototype and the new fdnum_create_pair body/prototype leaves byte-identical production C. Pipe.create, FD construction/destruction, Pipe.unref, grow_fd_table and the checked user-copy wrapper remain byte-identical. The new helper emits scalar locals and synchronous array setters, one lock acquisition and releases on refusal/success; V also emits an unreachable fall-through defer. No hidden heap allocation or resource-interface box appears in either changed function. The generated refusal paths preserve the intended one/two FD.unref operations and save errno first.

The fixture has 16 explicit allocas, fixed arrays and no generated heap or V runtime helper. Its three-page mapping stays live through every synchronous query, state check and storage snapshot. Inaccessible/noncanonical/readonly/cross-page destinations are passed only to the raw syscall; unexpected success on such a destination never dereferences it. Writable returned words are memcpy-copied into aligned i32 scratch. Canary checks cover EMFILE refusals and bytes outside writable successful outputs; ordinary EFAULT permits partial copy. The table vector is inspected before repairing only the known temporary filler holes. Restoring the original soft limit permits finite read/write duplicate aliases, real data transfer and EOF checks; all known aliases close before filler restoration. Retained regular-file and pipe aliases keep metadata, status/FD flags, cursor, queued bytes and original 64-slot vector through the final state checks. The observer closes after its bounded 32-row snapshots, then retained descriptors close and the mapping is unmapped. Setup failure exits the child, relying on process-exit cleanup. Counts are initialized, synchronously copied through a result pipe, and read only when complete; the parent closes the result descriptor and waits before starting the next credential cohort. The Linux wrapper keeps its argv alloca live through synchronous execv.

Each root/UID-GID-1000 cohort runs [1120,1120,2240,13] checks, totaling 8,986 per architecture on native and Linux. Both baselines have exactly [0,280,0,0] failures per cohort: a one-slot refusal returns EMFILE but leaves a reader published. The fixture detects that table state before cleanup. Both final five-case native profiles (pipepair, pipeabi, access, open, runtime) pass, and the same ELF per architecture passes actual Linux references. Preview/baseline/candidate C matches, preflight/baseline/candidate/Linux probe ELF matches, and preflight/native function bodies match with complete raw C drift separately pinned. Earlier host temporary-directory and undeclared bounded-index failures are diagnostics, with no semantic qualification attributed to their receipts.

Candidate pressure retention uses 32 warmups and 200 measured cycles per credential, settling 13 seconds around snapshots. Each cycle covers all five upper-register patterns and zero/one/two/three free slots, including both EMFILE refusals, a real ordinary pipe with aliases/data/EOF and a cross-page EFAULT rollback. All 18 ARM and 14 x86 slab classes and large pages remain flat: arm [ordinary=0: 68/68; ordinary=1: 68/68]; x86 [ordinary=0: 177/177; ordinary=1: 177/177]. Completed scans keep the existing 400 ARM/292 x86 allocation sites and unchanged allowance refusals; eight host test files and 64-input dispatch fingerprints pass. Actual FAT-staged AArch64 kernels, measure ELF/source, configuration and frozen desktop are retained before runtime cleanup. Both baseline/candidate ops/churn/cache and idle/apps/drag profiles complete. All 36 common operations retain zero bytes per 200-call operation, and all four 300-run churn programs retain zero bytes, on both kernels. The production harness compiles/stages normally; only automatic shared-checkout cache pruning is skipped.

Qualification is bounded to the measured operations and soft limits 48/64. The initial table has 1,024 slots, so table expansion and growth-budget refusal are source-reviewed but unmeasured. Concurrent prlimit updates, injected constructor-budget failures, shared-table output-copy/rollback races, copy-before-publication, nil-pointer/limit precedence, packet/watch-queue pipes, arbitrary descriptor churn, GNU libc, translated/foreign and ELF32 paths remain unqualified. No broad roadmap completion gate is asserted.

SHA-256 pins were independently recomputed after completed producers; common rows require exact byte identity.

| File | SHA-256 |
| --- | --- |
| `kernel/file/file.v`, `kernel-arm/kernel/file/file.v`, `kernel-x86/kernel/file/file.v` | `267ad1533ded8aea20b52f7f7caab2f1893dfe56f3e1cf80f67dd56644b4a578` |
| `kernel/pipe/pipe.v`, `kernel-arm/kernel/pipe/pipe.v`, `kernel-x86/kernel/pipe/pipe.v` | `db8f9e83758af3fc974c15329c74f0bccaf8d3030e49eb8175faec420a4888e4` |
| `kernel/pipe/usercopy.v` | `d06b69c1d6f813f3f4fbfeb264e76184d44924cb2d04dd7810a9c988c56d4284` |
| `tests/linux-compat/pipepairfixture/core.v` | `cea70041030602399ac531ac7525424381f3031e310f98c022d1d2bcf285166d` |
| `tests/linux-compat/pipepair-reference.v` | `254d6d8fe3c18b6579e9036c3656575ba94b648c55fca231995c718e1a1460c4` |
| `tests/linux-compat/pipepairreferenceinit/core.v` | `d5723f4b71a24a9fc425b65a033527e4b663bb77b0e28596fcdd7dbcfdde5264` |
| `tests/linux-compat/run.v` | `90474dcb7375ecc138c4b710157194fd128f00387a39f568644a16b3bf024eee` |
| `independent-review.v` | `6589ceeb14c165a21e8798d797396118cf97c606acba179929d393eff18bb23c` |
| `independent-review` | `947e7905f263c8e213dc3c1620f87358bb5edd2186efb13a1b5a8ed294df0e99` |
| `independent-controls.v` | `88949772ff26477c4bc0835590553c83b72f462867312e73a24bc1ee8d498543` |
| `independent-controls` | `a9c6d944883a615d843b9c782212565f4624794f9566825b07ee6a88ccec320f` |
| `independent-compile.log` | `862e9d68b4890cd432266afe7546b2dda4508465cc0833481fe83f763938efbe` |
| `independent-scope.log` | `f42d3a57bffb49761d0fd8a131ba83839deb45f2ea8b38e928c40ef066c7d388` |
| `independent-preview.log` | `f3278e6ab80814a586fc85cbf9b176ccfb6f8b603943803c8fe477485dfe73f4` |
| `independent-native.log` | `176b0424fa34f1d041735ff0d59083d9d487121602427b219d8618e1fbe56113` |
| `independent-elf.log` | `0d2a85e4483d1e2b7556642f36505b2f4ed808d815d239599139e175c81f6256` |
| `independent-assert-control.log` | `34cb9b1963bad105404b4e596a3411e3d802ac6ffa1fd825a633e665d18f281b` |
| `independent-passing-counts-control.log` | `f408da3001fac2f26e04fad9fda86efba5fd73b0914c5ea3973204d8a0376ce9` |
| `host-tests.log` | `46deee1f82b69d1795f46da16dc7da663d694319646865d3529b9d071a415fba` |
| `allocs-before.log` | `6e0671e47a70e0f72baa54d9f546f475cef8aecae788f8aa22d1ccfa68fefcd6` |
| `allocs-after.log` | `9244fd516dd139549e311ea72b1647dba0e3a8e3c6cd0093a831cef9d886ec8d` |
| `coverage-check.log` | `f14b0219fd4094c269a82b893f4a2424ffc8461e1745db3f9971f06dd81031fb` |
| `candidate-inputs.json` | `b6d08c77275b66e315b9b47d0d4f8ae1a98529c1d2e025df42dfc62b7de2e999` |
| `preflight-drift-pins.json` | `8cf63bb944e7049681026a649f25dd303f28ea391887ab4164916a893f9f163c` |
| `kernel-arm/docs/linux-syscall-coverage.json` | `c28462465404cffeb96b2d5274a6f9825a0ded8bbf0ba42176accdd3eb2c5a31` |
| `preview-arm.c`, `states/p4-before-arm/pipepair/fixture.c`, `states/p4-after-arm/pipepair/fixture.c` | `c1ad49d7434cb46007a984e1fe1adacb73f378fe95418fd679798f6a5799b903` |
| `states/preflight4-pipepair-arm/init`, `states/p4-before-arm/pipepair/init`, `states/p4-after-arm/pipepair/init`, `states/p4-reference-arm/probe` | `243ab552266dd6eb16a8ef6ff1791feaec3e1aa9393d90878d5bfd720d483590` |
| `tests/linux-compat/pipepairfixture/core.v`, `states/p4-before-arm/sources/pipepairfixture/core.v`, `states/p4-after-arm/sources/pipepairfixture/core.v` | `cea70041030602399ac531ac7525424381f3031e310f98c022d1d2bcf285166d` |
| `before-arm.c` | `366c4f72b275b0da5918bfbe8100ce78007cfca1dfccd7171e25e4aa039d426d` |
| `kernel-arm/kernel/obj/blob.c` | `69f1d059d9c5c8052268288ef5078f01be7beae90fe0cdcf347b838545285fa0` |
| `build-before-arm.log` | `9b01a7b17b309cc9e3fed37c97e19fbc243668f1346eae5bf51268540221bdf1` |
| `build-after-arm.log` | `600bb962e0d138104cee9da008a7145f4f0727a6408412fe57b3f4b45260abb9` |
| `preflight-drift-aarch64.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `baseline-arm/kernel/bin/vinix`, `states/p4-before-arm/kernel/bin/vinix` | `05da448986ad0d7d3da9484866e71e8846e68198f0248be178ca111a3cf03fcf` |
| `states/p4-before-arm/receipt.json` | `b064af41dceda4bc3ff595797e20fb9ece646c63e7e3bdc540b5d9e52615e865` |
| `states/p4-before-arm/pipepair/fixture.c` | `c1ad49d7434cb46007a984e1fe1adacb73f378fe95418fd679798f6a5799b903` |
| `states/p4-before-arm/pipepair/init` | `243ab552266dd6eb16a8ef6ff1791feaec3e1aa9393d90878d5bfd720d483590` |
| `states/p4-before-arm/pipepair/serial.log` | `5ca9dc77f12d957fcdf26eb09447134619fa8f668e564c16be301b36130bdea7` |
| `states/p4-before-arm/pipepair/test.iso` | `bb996ad6f0f2bda7dcbe892e2a3d522ebb1baa8432ae88b2fe2da3fe0b105ad3` |
| `kernel-arm/kernel/bin/vinix`, `states/p4-after-arm/kernel/bin/vinix` | `911284a78a53d9c38cd85bc71bab88eb7abd857e74335204c819d41995d8fe1d` |
| `states/p4-after-arm/receipt.json` | `21977bb333905a73eab1472a1f71d9f7c1953cc6671d5361a3ac506f9138d104` |
| `states/p4-after-arm/pipepair/fixture.c` | `c1ad49d7434cb46007a984e1fe1adacb73f378fe95418fd679798f6a5799b903` |
| `states/p4-after-arm/pipepair/init` | `243ab552266dd6eb16a8ef6ff1791feaec3e1aa9393d90878d5bfd720d483590` |
| `states/p4-after-arm/pipepair/serial.log` | `8f24d9d5f3d5e545b03de5f7355a8a0d42c346969711b5c64e95d35a381e19c1` |
| `states/p4-after-arm/pipepair/test.iso` | `24f5dd4e2572f337d104a67017227207b756fd68f226e1bc7d7c130c9817f184` |
| `states/p4-after-arm/pipeabi/fixture.c` | `79a79dda28535e28be10be21c8847f756f589a38286b120c6ec23e7356675520` |
| `states/p4-after-arm/pipeabi/init` | `bad77855f6efd4731ad1d66bf7c7569ac3d5fa647d5a13b03cbe9289d6a13ae0` |
| `states/p4-after-arm/pipeabi/serial.log` | `6901e986b7738a607b4ecd3a81e376e801add6ec09adcd27b26110d9b0575361` |
| `states/p4-after-arm/pipeabi/test.iso` | `e24a963175fa23ce4de3b72271f238dba266e1ff68c8fd739e020cabf34f92fc` |
| `states/p4-after-arm/access/fixture.c` | `53998280afb32ec26809a7bfb1f9b6e7b24f5e326e7b2e2755d6f8bdf9e4b599` |
| `states/p4-after-arm/access/init` | `913381428a4adcc149d2e55098b8658d385310a39b75507d7ad20db6404874ab` |
| `states/p4-after-arm/access/serial.log` | `8573f4e2c2efa05785e42091649278bdf2360ab24decf9d9d8842db1d4bb09c4` |
| `states/p4-after-arm/access/test.iso` | `d322b8ee681fd145abf8d7d40d36abdc4dc547c5239b4557125760b170ca3db8` |
| `states/p4-after-arm/open/fixture.c` | `b2d362c322a5a63aa9dd819e342ec30c0384972bdc55f9e59b7c81398ac41eb9` |
| `states/p4-after-arm/open/init` | `b41456ec1e04ca2e2e83e39ac5f01da498edfc8011f4eb71541bbc9ec9ec7c6a` |
| `states/p4-after-arm/open/serial.log` | `02af6f0f40e046b44004e7fa7bbbbf42922a57a7d4b3119dffa87846cb98af84` |
| `states/p4-after-arm/open/test.iso` | `682c4303f859671c2c4a9ab8ad5f7b6885a5b02f651c29b460d0f312405e19c6` |
| `states/p4-after-arm/runtime/fixture.c` | `05967a3ff8bb35aafaf2e91e58e1203b35780818a33b84031590b52943d60128` |
| `states/p4-after-arm/runtime/init` | `a27160c033a470689dafc283d37636bb5b81b1344d19e93a2c6071701187e44b` |
| `states/p4-after-arm/runtime/serial.log` | `d2b10c6171709910cf8458748df7059066450ee508e5baebc298df1b62cb03ed` |
| `states/p4-after-arm/runtime/test.iso` | `b217765052f3a8c448e8ba732b9069187eec5bcb33a579cb2d1a4d93a504f818` |
| `states/p4-reference-arm/fixture.c` | `d286914c85d4fe3231a6dd8615640407ff9a95327b7312b0b6cba86180aecd2d` |
| `states/p4-reference-arm/init` | `336d257f56dd657f2118f3fc9c80d912b776a8c15dca3e17bf4ead9bcfc2e616` |
| `states/p4-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p4-reference-arm/serial.log` | `9f857cd78c455c4804bb6d4f008f0d06bfbf63067d9f0e162149071ce87e9e61` |
| `states/p4-reference-arm/receipt.json` | `5a097575a3be6239a400f7410a574328fe880e9e0f499ae24e3e768b9dbe30e7` |
| `states/p4-reference-arm/initramfs.cpio` | `c4faaa712c6c4c4807583692689eb1a47fe15b60994a02201b3cb2bf2799730a` |
| `states/p4-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `tests/linux-compat/pipepairreferenceinit/core.v`, `states/p4-reference-arm/source/pipepairreferenceinit/core.v` | `d5723f4b71a24a9fc425b65a033527e4b663bb77b0e28596fcdd7dbcfdde5264` |
| `kernel-x86/docs/linux-syscall-coverage.json` | `c28462465404cffeb96b2d5274a6f9825a0ded8bbf0ba42176accdd3eb2c5a31` |
| `preview-x86.c`, `states/p4-before-x86/pipepair/fixture.c`, `states/p4-after-x86/pipepair/fixture.c` | `c1ad49d7434cb46007a984e1fe1adacb73f378fe95418fd679798f6a5799b903` |
| `states/preflight4-pipepair-x86/init`, `states/p4-before-x86/pipepair/init`, `states/p4-after-x86/pipepair/init`, `states/p4-reference-x86/probe` | `c756d702ffd2b6fa5eaa7e2cea24ad319148978173f8cea545210ec2f2e5ddb9` |
| `tests/linux-compat/pipepairfixture/core.v`, `states/p4-before-x86/sources/pipepairfixture/core.v`, `states/p4-after-x86/sources/pipepairfixture/core.v` | `cea70041030602399ac531ac7525424381f3031e310f98c022d1d2bcf285166d` |
| `before-x86.c` | `4f1d209c218b50be36e299acdc32fb294c1ce65e883286f58d39290934f39752` |
| `kernel-x86/kernel/obj/blob.c` | `09c5c549ecfcd2917ccdbb2e9e9875099f23640657c2d5991ad5408fa612cffa` |
| `build-before-x86.log` | `8a4bd815be3db0c11fb915b0d86bacb8a447808de5bb727432730656489513bf` |
| `build-after-x86.log` | `09a8112e62f1cf97d7c600e9b741d36f2c38d7b1170bd940ca878d419d23e8bd` |
| `preflight-drift-x86_64.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `baseline-x86/kernel/bin/vinix`, `states/p4-before-x86/kernel/bin/vinix` | `e54ac174095c02e6372c62de33edd8b7d2235841287f5e3d2e9d04f7cb37615c` |
| `states/p4-before-x86/receipt.json` | `e0fec9ea2a5820321f3eaf46bc8677371e5af74bd9122efd35d4f010c3c64ab9` |
| `states/p4-before-x86/pipepair/fixture.c` | `c1ad49d7434cb46007a984e1fe1adacb73f378fe95418fd679798f6a5799b903` |
| `states/p4-before-x86/pipepair/init` | `c756d702ffd2b6fa5eaa7e2cea24ad319148978173f8cea545210ec2f2e5ddb9` |
| `states/p4-before-x86/pipepair/serial.log` | `6975a217ad091ddc10efe474960a4b668ab46da5da8c99d88844c2e60dd0fe07` |
| `states/p4-before-x86/pipepair/test.iso` | `37a442d2c2343bb5393b52e41fd7529688aca8b1b18f85acd67d006fa0ed489d` |
| `kernel-x86/kernel/bin/vinix`, `states/p4-after-x86/kernel/bin/vinix` | `4907a8796130b87887886ac467aafa4d38b385d49531b8b464c5c62db0cf3f73` |
| `states/p4-after-x86/receipt.json` | `009716d9ae641ec9e197cb93f42418214d1edb82da63518793902ea41131c5c8` |
| `states/p4-after-x86/pipepair/fixture.c` | `c1ad49d7434cb46007a984e1fe1adacb73f378fe95418fd679798f6a5799b903` |
| `states/p4-after-x86/pipepair/init` | `c756d702ffd2b6fa5eaa7e2cea24ad319148978173f8cea545210ec2f2e5ddb9` |
| `states/p4-after-x86/pipepair/serial.log` | `68637e4b85fc4a6bfed236ee2776d7ae7b1d0ea6b2682acc257c899310062968` |
| `states/p4-after-x86/pipepair/test.iso` | `d3bc7c6f9341ca9d58cab65f4b86f6fd72d09630dd302b66d10d1942d4501fca` |
| `states/p4-after-x86/pipeabi/fixture.c` | `79a79dda28535e28be10be21c8847f756f589a38286b120c6ec23e7356675520` |
| `states/p4-after-x86/pipeabi/init` | `f911107fb89f3639529caf225841eeecf9c888367531c3323cd3f8eb64283132` |
| `states/p4-after-x86/pipeabi/serial.log` | `25df572876f64fb6f8caf0c58c16f552161b7f05c47fdb46e7b762fa56f1277c` |
| `states/p4-after-x86/pipeabi/test.iso` | `39eded978e3beed32a3679b1c907b49ccc3eccdd7be7a327a436c7e8c51234a0` |
| `states/p4-after-x86/access/fixture.c` | `53998280afb32ec26809a7bfb1f9b6e7b24f5e326e7b2e2755d6f8bdf9e4b599` |
| `states/p4-after-x86/access/init` | `87b5e511b3b759b08dd182c459faab3cf9839920656c8a612efe9d94eeb026fb` |
| `states/p4-after-x86/access/serial.log` | `d3a9ebb7cbc7ab8df87bc0659f8d4e468be2e3e169b1631930aa88592da7538a` |
| `states/p4-after-x86/access/test.iso` | `eed616de20e70a07999cab1a4c5a8e07de9152dbe195b29a5b2f8a32be50b46a` |
| `states/p4-after-x86/open/fixture.c` | `b2d362c322a5a63aa9dd819e342ec30c0384972bdc55f9e59b7c81398ac41eb9` |
| `states/p4-after-x86/open/init` | `377071b25bf7f8a9b3a048c8eab9ec87c689beb7ca5791e8439a46a4131f222a` |
| `states/p4-after-x86/open/serial.log` | `54eb6cbab773e3769ff502ca83030b75856525c7380a3238ab6a7b6d0fde5457` |
| `states/p4-after-x86/open/test.iso` | `66773050f7490a8cd47a32a073aec4e3a1503d811f97a4cf2543b7c83e059425` |
| `states/p4-after-x86/runtime/fixture.c` | `283ee3218dbf04ee7c3289110ff0be3044906d48556453b06b7de972f4950e3b` |
| `states/p4-after-x86/runtime/init` | `3c22f6e44700a031e0c6e9bd04427095e423d595d3f9b81e09f07539d1ea3b9f` |
| `states/p4-after-x86/runtime/serial.log` | `0a8088397a56749f4b5b8275d36d23b60de5eafe640a5f6e4470d7e66b45c8cd` |
| `states/p4-after-x86/runtime/test.iso` | `63b7b4d5a6ff9d24a29f66ec5e00282300ca7a620499130cfaf741d64b87ab62` |
| `states/p4-reference-x86/fixture.c` | `d286914c85d4fe3231a6dd8615640407ff9a95327b7312b0b6cba86180aecd2d` |
| `states/p4-reference-x86/init` | `b6c542477d07518d7c13d787abfe874992a8a537fe0fe9939b86fa7283d84e89` |
| `states/p4-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p4-reference-x86/serial.log` | `03edae4a92fb051b514620a7048fa22e7f5128a5f286effffdce2ea0748b180a` |
| `states/p4-reference-x86/receipt.json` | `b2288ddb63b36c4015b723cdc3d79d682d5c18285453261236787e0b5d5761a0` |
| `states/p4-reference-x86/initramfs.cpio` | `71430f6ace080c94b3f3a4c1761b257c74677f553204eee7154c5cb38a4ef3f8` |
| `states/p4-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `tests/linux-compat/pipepairreferenceinit/core.v`, `states/p4-reference-x86/source/pipepairreferenceinit/core.v` | `d5723f4b71a24a9fc425b65a033527e4b663bb77b0e28596fcdd7dbcfdde5264` |
| `perf-before-ops.log` | `22a8b6a26a523fb35ecb81f631e13eb5315ed5db48dbb631fd576755b0b6c463` |
| `pf-before-ops/serial.log` | `3dfb0726b8282621e7a9e30c215103efe39ad702dbb010d343c71011c451e330` |
| `pf-before-ops/result.json` | `b6b3ea96c06fdb836bec92a94e5b51e19923b00057dc7913a08dc5d528e3e957` |
| `pf-before-ops/stage-pins.json` | `70097a2d797135502d720e9297edcecac739e92ea08b04f633409deb16c310f2` |
| `pf-before-ops/artifacts/kernel` | `05da448986ad0d7d3da9484866e71e8846e68198f0248be178ca111a3cf03fcf` |
| `pf-before-ops/artifacts/measure` | `ed5856050a1053bb96e36905e28b13e65e1bae86d815bcac5e1c5bd959b7cdb4` |
| `pf-before-ops/artifacts/measure.c` | `2490bc0e69142080f52a469e241cbb37d61d0e0687a191618654a3b617b68771` |
| `pf-before-ops/artifacts/config` | `8aade1ee295749bd4bb45b3419511888a5985d481bc1e6ad0dedccb60c186d04` |
| `pf-before-ops/artifacts/vinix-desktop-new` | `293830fc291de6f9ce0ba13227259a3ccf3360105037181884c86de5b575abfb` |
| `perf-before-desktop.log` | `bb7e7adb7b4c466d4e9ee20a15a610337f6eded490c9eb8dbc252c400c571281` |
| `pf-before-desktop/serial.log` | `2cc3ef68ac2f92786e50729fd4431621b2c7dcbdcbd5897b36d7eae02af80207` |
| `pf-before-desktop/result.json` | `674e94af771f21489293d8e8c158b7482f5a05a124b6c16bda825fb0aadab979` |
| `pf-before-desktop/stage-pins.json` | `4253c6c06f617609df7958819ce7218d4a3afa3c1156cb0fdee4e94a57830553` |
| `pf-before-desktop/artifacts/kernel` | `05da448986ad0d7d3da9484866e71e8846e68198f0248be178ca111a3cf03fcf` |
| `pf-before-desktop/artifacts/measure` | `ed5856050a1053bb96e36905e28b13e65e1bae86d815bcac5e1c5bd959b7cdb4` |
| `pf-before-desktop/artifacts/measure.c` | `2490bc0e69142080f52a469e241cbb37d61d0e0687a191618654a3b617b68771` |
| `pf-before-desktop/artifacts/config` | `0ce84cffbbba028da343ffd038b627a7db3c139f0f2f5413f4ee15ddbc46bd1e` |
| `pf-before-desktop/artifacts/vinix-desktop-new` | `293830fc291de6f9ce0ba13227259a3ccf3360105037181884c86de5b575abfb` |
| `perf-after-ops.log` | `ae3a6d213da1508ae78b6296918f616df9d87500d7e025eac584f78072edc950` |
| `pf-after-ops/serial.log` | `d129e41c518ae73fcf7ef0b2e495f47bf318b2eb87657dc9a3bc368d1d3503c6` |
| `pf-after-ops/result.json` | `3ce8cf4e40d645ce61e4eaea23dc78dc8f702a7ea987e83df462e1849519b420` |
| `pf-after-ops/stage-pins.json` | `43b925f0a604446aa82f0ccc2245abc4ccb579b95c7fdb716aed90aaa7f1e07e` |
| `pf-after-ops/artifacts/kernel` | `911284a78a53d9c38cd85bc71bab88eb7abd857e74335204c819d41995d8fe1d` |
| `pf-after-ops/artifacts/measure` | `ed5856050a1053bb96e36905e28b13e65e1bae86d815bcac5e1c5bd959b7cdb4` |
| `pf-after-ops/artifacts/measure.c` | `2490bc0e69142080f52a469e241cbb37d61d0e0687a191618654a3b617b68771` |
| `pf-after-ops/artifacts/config` | `8aade1ee295749bd4bb45b3419511888a5985d481bc1e6ad0dedccb60c186d04` |
| `pf-after-ops/artifacts/vinix-desktop-new` | `293830fc291de6f9ce0ba13227259a3ccf3360105037181884c86de5b575abfb` |
| `perf-after-desktop.log` | `97ce6e786960c69254f5b36f4f20728ad5349272924ad3aaea77747d18df2bf4` |
| `pf-after-desktop/serial.log` | `8edd78045e8f6309c6cef81083761d56144e176131cc6dde9dee955d9ed02e38` |
| `pf-after-desktop/result.json` | `f16e0788cd3b245d75bb61b6326e624660e08c8425392a76b08b909b8f37aa68` |
| `pf-after-desktop/stage-pins.json` | `0c47e577090f2980bc6dd24fcfa41541c887c8c525517c144ad48a2a9d69b7db` |
| `pf-after-desktop/artifacts/kernel` | `911284a78a53d9c38cd85bc71bab88eb7abd857e74335204c819d41995d8fe1d` |
| `pf-after-desktop/artifacts/measure` | `ed5856050a1053bb96e36905e28b13e65e1bae86d815bcac5e1c5bd959b7cdb4` |
| `pf-after-desktop/artifacts/measure.c` | `2490bc0e69142080f52a469e241cbb37d61d0e0687a191618654a3b617b68771` |
| `pf-after-desktop/artifacts/config` | `0ce84cffbbba028da343ffd038b627a7db3c139f0f2f5413f4ee15ddbc46bd1e` |
| `pf-after-desktop/artifacts/vinix-desktop-new` | `293830fc291de6f9ce0ba13227259a3ccf3360105037181884c86de5b575abfb` |
| `perf-inputs/image.tar` | `d491b349c45b1fb2b5052b4a41fbb90857cf68488c0e6b17caafbe1d879843a9` |
