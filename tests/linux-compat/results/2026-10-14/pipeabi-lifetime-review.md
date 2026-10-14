Independent pipeabi lifetime review: PASS

Reviewed only the pipe2 flag-decoding/error diff against frozen baseline `09d9bbd210cb89f082a6019d69e508199d9501b7`, native V pipeabi fixture and Linux reference wrapper/controller. Both baseline profiles finish with 3,904 failures in 4,186 native controls per architecture; both complete native candidates and actual Linux 6.12.51 references pass. Independent V assertions execute without `-prod`; a deliberate assertion and a passing native candidate presented as a failing baseline both fail. Production builds, generated C, semantic profiles, reference receipts and drift evidence were consumed after their producers finished. Build paths below are relative to `/Users/alex/.cache/vinix-linux-compat/pipeabi-20261014`.

The kernel adds one scalar lower-word flags local, rejects unknown low bits with EINVAL, refuses notification pipes with ENOPKG and packet pipes with EOPNOTSUPP, and forwards the decoded scalar. All early refusals precede the existing pointer check and pipe allocation. No allocation, retain/release, lock, asynchronous borrow or free was added or removed. The existing two-i32 stack scratch is passed only through the synchronous pipe constructor and checked copy; copy-fault descriptor closes are unchanged. The native notification/packet refusal row is separate from Linux conformance and is not a claim that those Linux modes are implemented.

On both architectures removing exactly the existing pipe__syscall_pipe_checked body and its prototype leaves byte-identical production C. Pipe.create, FD construction/publication, Pipe.unref, usercopy helpers and all other functions, types and globals therefore remain unchanged. The changed generated body has only the scalar decode/error checks and the changed scalar constructor argument; no hidden heap allocation appears.

The fixture uses 12 explicit allocas and fixed arrays, with no generated heap/helper allocation. Its retained three-page mapping remains live until all synchronous queries, state checks and storage snapshots finish. Only the first writable page is reset or inspected; the PROT_NONE/readonly/cross-page/invalid destinations are passed to the raw syscall. Unexpected success on a bad destination returns false before dereferencing it; writable outputs are memcpy-copied into aligned i32 stack scratch before typed access. Faulted ordinary calls permit partial copy, so the fixture does not assert unchanged bytes for EFAULT. Unknown/unsupported flags check writable canaries. An unexpected success on a valid destination closes both returned ends, while pair_good closes all known original/dup/CLOEXEC read and write aliases even when metadata/status checks fail. Stat access uses short-circuit syscall success and a zeroed original record. No query retains a stack pointer.

Each child retains nine regular-file/pipe aliases through the final metadata, FD flag, offset, queued-byte, data and 64-slot FD-vector checks, then closes all nine and unmaps the three pages. Ordinary UID/GID 1000 is set before pipes are created; its regular file intentionally remains inherited root-owned storage. The storage observer closes on every ordinary return path, and the bounded Slabs parser checks its 32-row capacity before writes. Setup failures terminate the child through _exit, relying on process exit for resource cleanup. The child writes its initialized fixed Counts through the result pipe synchronously, closes its result endpoint and exits; the parent reads only a complete copied record and waits before continuing to the next cohort. The Linux wrapper keeps its three-slot argv alloca live through synchronous execv and reports mount/exec failure. No new asynchronous borrowed pointer or ownership transfer is introduced.

Each native root/UID cohort has [160,1600,320,13] controls with baseline failures [32,1600,320,0]. Both native candidates have zero failures in 4,186 controls each, and complete pipeabi/accessflags/access/open/runtime profiles pass. Each Linux cohort has [160,1600,0,13] controls and zero failures, totaling 3,546 per architecture; kind 2 is deliberately skipped and is explicitly printed with zero calls. Preview/baseline/candidate C is byte-identical; preflight/baseline/candidate/actual-Linux probe ELFs are byte-identical per architecture. Native/preflight function bodies are equal and the complete raw C drift is pinned separately. The initial MAP_FAILED V type diagnostic is retained and was corrected before any probe execution.

Native retention runs 32 warmups and 200 measured cycles per credential, settling 13 seconds around snapshots; each cycle covers five upper-register patterns, finite ordinary pipe allocation/data/alias/EOF/close, and four early error kinds. All 18 ARM and 14 x86 slab classes and large pages remain flat (arm [ordinary=0: 68/68; ordinary=1: 68/68]; x86 [ordinary=0: 177/177; ordinary=1: 177/177]). Completed scans retain the same 400 ARM/292 x86 allocation sites across 662/658 copied sources and the same existing refusal list; eight host test files and native dispatch coverage pass. Both generated coverage manifests contain exactly the same 64 SHA-256 inputs, including the newly fingerprinted dispatched kernel/pipe/usercopy.v wrapper and modified coverage generator. Every other input is byte-identical to the frozen baseline; candidate diffs contain only that kernel wrapper and that generator. This bounds the measured operations only. Existing partial pipe-construction descriptor failure cleanup, concurrent FD publication/closure races, descriptor-limit precedence, packet/watch-queue operation, arbitrary descriptor churn, GNU libc, translated/foreign and ELF32 paths remain unqualified. No reclamation path was changed, and the broad roadmap gates remain open.

SHA-256 pins were computed independently after completed producers; common rows require exact byte identity.

| File | SHA-256 |
| --- | --- |
| `kernel/pipe/usercopy.v`, `kernel-arm/kernel/pipe/usercopy.v`, `kernel-x86/kernel/pipe/usercopy.v` | `d06b69c1d6f813f3f4fbfeb264e76184d44924cb2d04dd7810a9c988c56d4284` |
| `kernel-arm/kernel/pipe/pipe.v`, `kernel-x86/kernel/pipe/pipe.v` | `0eb36d158d556636588cb0a742f5dbb50bbc0bf1168b82b1dc0d5ec08a5a967d` |
| `tests/linux-compat/pipeabifixture/core.v` | `97a8a834119de69016bd8186717baf2fbaac43d37d949c10f58b6cf62165c7de` |
| `tests/linux-compat/pipeabi-reference.v` | `019595613bf618ee19e38900810ea8a7d5b2658a1b4eb33b6be885582d8e8d07` |
| `tests/linux-compat/pipeabireferenceinit/core.v` | `bcbd33865027c4b179936a776327b4b2d97dd44b3bc1546f17b86d93def235f4` |
| `tests/linux-compat/run.v` | `7ea6cad4ea47bd2ba6c94bf29f6b01094cdf66818f797551b9066f89e0b9d1d8` |
| `tools/linux-compat/coverage.v` | `4fb6092f7dad93f14a8f10eb51ba587df3cd847ea91f30b0dd73dd28d923970e` |
| `host-tests.log` | `9d703c6cb3f598caa4da631433b8208cdd63c0ce83dac631499a07c86f55ba6e` |
| `allocs-before.log` | `697f18091e714cf4ddf12becbb5890aa369cf4a321f0c92ee19d8bbf7f8b3b89` |
| `allocs-after.log` | `697f18091e714cf4ddf12becbb5890aa369cf4a321f0c92ee19d8bbf7f8b3b89` |
| `coverage-check.log` | `f14b0219fd4094c269a82b893f4a2424ffc8461e1745db3f9971f06dd81031fb` |
| `scope-check.log` | `11cf5776fd0955c1065b71f52fb58d66f322b8d196394284a661b9057bdec25c` |
| `independent-review.v` | `996bf996f82ed5b7c1043f6fffb442725a5dd38cb30b1599357fde4968a9eb80` |
| `independent-review` | `c8601354883b5b0fab4f0e9f4ae6dd146fc475a8195ee2710349a2b59d59129d` |
| `independent-controls.v` | `fe743d7e71aeab929986cfc5f680fa99fd287f2a323b66202d75870e02c0e52e` |
| `independent-compile.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `independent-scope.log` | `460c77008ff07716b033b6f8441a6f4df9766324ef9d6dac5b14637f9df82466` |
| `independent-preview.log` | `b8296416a16504f77d286311d96285a17f767cf03dae93cb77b456c3c452f63e` |
| `independent-assert-control.log` | `cdbe9a2a4c65b1b9f9f6671878d964cd609206a6e6b08472bee3f8de8affc1dd` |
| `independent-passing-counts-control.log` | `3733283325ec1382fde77a09e768bf2a901400dc9207349f4628390e590b5501` |
| `independent-elf.log` | `0d2a85e4483d1e2b7556642f36505b2f4ed808d815d239599139e175c81f6256` |
| `preflight-drift-pins.json` | `e1838966b2bb3caa98a4156d75fabdd93b81fb15daf60d1e64947fa46a4d2f15` |
| `candidate-inputs.json` | `960443cd066fdfd6af461b992abbbfa3c410f8cd8a6e84cfb1d186847308526a` |
| `diagnostic-preview-arm.log` | `fa926c09376935de0d9f1c3716321aec9d2bec66479388836ffd69e109460b52` |
| `diagnostic-source.v` | `80d7ffca5e50270fd6019e9a0d3866e5e18fb6b30670273bb6f9a445f97b492a` |
| `/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v` | `9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b` |
| `kernel-arm/docs/linux-syscall-coverage.json` | `30ab0e9d6c7df0216ca4754173aaf99ff89616da44515372f703347ff48d250d` |
| `preview-arm.c`, `states/p-before-arm/pipeabi/fixture.c`, `states/p-after-arm/pipeabi/fixture.c` | `79a79dda28535e28be10be21c8847f756f589a38286b120c6ec23e7356675520` |
| `states/preflight-pipeabi-arm/fixture.c` | `79a79dda28535e28be10be21c8847f756f589a38286b120c6ec23e7356675520` |
| `states/preflight-pipeabi-arm/init`, `states/p-before-arm/pipeabi/init`, `states/p-after-arm/pipeabi/init`, `states/p-reference-arm/probe` | `bad77855f6efd4731ad1d66bf7c7569ac3d5fa647d5a13b03cbe9289d6a13ae0` |
| `tests/linux-compat/pipeabifixture/core.v`, `states/p-before-arm/sources/pipeabifixture/core.v`, `states/p-after-arm/sources/pipeabifixture/core.v` | `97a8a834119de69016bd8186717baf2fbaac43d37d949c10f58b6cf62165c7de` |
| `before-arm.c` | `74c04604aab8f942f3242372e0b6da00be1c4267feee264c0fb071d505df1f5e` |
| `kernel-arm/kernel/obj/blob.c` | `3682a6b86c56338a3f51c5b40acca58d30dd81b2df098db9fd8e1ee139d58ea8` |
| `build-before-arm.log` | `06e441a6b316262da23220b5d145e873a6ae4caf3e70ad07eb3c9b259f061912` |
| `build-after-arm.log` | `1b1ec9361c1106ad9ec0d7429b76c49e1eed2340070c9623cf0d9aaefddf0c4a` |
| `preflight-drift-aarch64.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `baseline-arm/kernel/bin/vinix`, `states/p-before-arm/kernel/bin/vinix` | `9c68813f3c9d03fe2703d2139ba57d5c681526a0ee972945814d6cd9167db7f1` |
| `kernel-arm/kernel/bin/vinix`, `states/p-after-arm/kernel/bin/vinix` | `534842d0e13738fd9572e2e79fdb7573d1376dc9da5af6bd268b687e779edcba` |
| `states/p-before-arm/pipeabi/serial.log` | `757b986664fcfc17fb06faf43d4d55038172fe25c9ea1823f47bf22ca362d3a9` |
| `states/p-before-arm/receipt.json` | `013f95d678dabc03aaa89f9c1dc7182ffbc48b89d3c4d90f4a35abbac53b7bd4` |
| `states/p-after-arm/pipeabi/serial.log` | `2ca0086ec1e2c50a4f044f7b7658750a6b9f7922ee3d29e80e556a0c0d01941a` |
| `states/p-after-arm/receipt.json` | `e406294510354000059f8bba838d012730b5799b8ecc693da28d3c075155d208` |
| `states/p-after-arm/accessflags/fixture.c` | `90473343afa843b70c5003ee5b106885e1514b208c0fe60dfc8bf5caadab8637` |
| `states/p-after-arm/accessflags/init` | `64c41b233437c5fe70004d13cf2c14e6df7327e5d8c59e80dcdfc2af85adaa08` |
| `states/p-after-arm/accessflags/serial.log` | `576d201e099e2233cf96e76c8e8d1f207d3207135bcc9ad1c97d78f759fd4c56` |
| `states/p-after-arm/access/fixture.c` | `53998280afb32ec26809a7bfb1f9b6e7b24f5e326e7b2e2755d6f8bdf9e4b599` |
| `states/p-after-arm/access/init` | `913381428a4adcc149d2e55098b8658d385310a39b75507d7ad20db6404874ab` |
| `states/p-after-arm/access/serial.log` | `8573f4e2c2efa05785e42091649278bdf2360ab24decf9d9d8842db1d4bb09c4` |
| `states/p-after-arm/open/fixture.c` | `b2d362c322a5a63aa9dd819e342ec30c0384972bdc55f9e59b7c81398ac41eb9` |
| `states/p-after-arm/open/init` | `b41456ec1e04ca2e2e83e39ac5f01da498edfc8011f4eb71541bbc9ec9ec7c6a` |
| `states/p-after-arm/open/serial.log` | `02af6f0f40e046b44004e7fa7bbbbf42922a57a7d4b3119dffa87846cb98af84` |
| `states/p-after-arm/runtime/fixture.c` | `05967a3ff8bb35aafaf2e91e58e1203b35780818a33b84031590b52943d60128` |
| `states/p-after-arm/runtime/init` | `a27160c033a470689dafc283d37636bb5b81b1344d19e93a2c6071701187e44b` |
| `states/p-after-arm/runtime/serial.log` | `d2b10c6171709910cf8458748df7059066450ee508e5baebc298df1b62cb03ed` |
| `states/p-reference-arm/fixture.c` | `9a00c674f577f482eee7294e17779efff23dfdc1266dc9f4c3f2a5447a0dd182` |
| `states/p-reference-arm/init` | `821ff8e6962e8486cc5769ea85db3515b89aafbb4ed576f12c58845994656a03` |
| `states/p-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p-reference-arm/serial.log` | `7b678465a77992f4989ff72dcfa83b863658ef6ed5bdaa95a82b6537c1bc988d` |
| `states/p-reference-arm/receipt.json` | `9d3246650a0d403b07a8d9d52ae7d8ebd77e2bdef2bfbe3ef69529c7732be68a` |
| `states/p-reference-arm/initramfs.cpio` | `d1edb38eb06d852d17da075acaf04eb34ef25afc5c330b9844689618733b2d31` |
| `states/p-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `tests/linux-compat/pipeabireferenceinit/core.v`, `states/p-reference-arm/source/pipeabireferenceinit/core.v` | `bcbd33865027c4b179936a776327b4b2d97dd44b3bc1546f17b86d93def235f4` |
| `kernel-x86/docs/linux-syscall-coverage.json` | `30ab0e9d6c7df0216ca4754173aaf99ff89616da44515372f703347ff48d250d` |
| `preview-x86.c`, `states/p-before-x86/pipeabi/fixture.c`, `states/p-after-x86/pipeabi/fixture.c` | `79a79dda28535e28be10be21c8847f756f589a38286b120c6ec23e7356675520` |
| `states/preflight-pipeabi-x86/fixture.c` | `79a79dda28535e28be10be21c8847f756f589a38286b120c6ec23e7356675520` |
| `states/preflight-pipeabi-x86/init`, `states/p-before-x86/pipeabi/init`, `states/p-after-x86/pipeabi/init`, `states/p-reference-x86/probe` | `f911107fb89f3639529caf225841eeecf9c888367531c3323cd3f8eb64283132` |
| `tests/linux-compat/pipeabifixture/core.v`, `states/p-before-x86/sources/pipeabifixture/core.v`, `states/p-after-x86/sources/pipeabifixture/core.v` | `97a8a834119de69016bd8186717baf2fbaac43d37d949c10f58b6cf62165c7de` |
| `before-x86.c` | `19319889a878712c4e8802476db4b4fd8a30c3c34e1d6485a358b839b8fbeabb` |
| `kernel-x86/kernel/obj/blob.c` | `705d82d5da109148ac2279a9cfa84a08134d99b42176fece1791dbc1bbe803f6` |
| `build-before-x86.log` | `fb5d20071a56a9e655d176d7d492a0a15e6e5011c306aadf406381e3c2e4a6ca` |
| `build-after-x86.log` | `1c8b5b26dd76d58204c7dc8ea9c4402e579246dd53c825742e801fe5f8bef487` |
| `preflight-drift-x86_64.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `baseline-x86/kernel/bin/vinix`, `states/p-before-x86/kernel/bin/vinix` | `4e9f271e1285bf2718104b16483def8a4a269e99ce906b43a781583388dafbcc` |
| `kernel-x86/kernel/bin/vinix`, `states/p-after-x86/kernel/bin/vinix` | `4d5b973e555c091e92ebcc740181d217c7b17f68b5cf8429d2f339da92f66fcb` |
| `states/p-before-x86/pipeabi/serial.log` | `8db29bda32ee709929ade9deb2640929d33abfad56fff3c9a6a49d67d0b9a73f` |
| `states/p-before-x86/receipt.json` | `ec03fe53eb5f223355dc83b908e791b4ac11c0cd900a280c06ab23f83940e0ad` |
| `states/p-after-x86/pipeabi/serial.log` | `25df572876f64fb6f8caf0c58c16f552161b7f05c47fdb46e7b762fa56f1277c` |
| `states/p-after-x86/receipt.json` | `194b1658d40f8a5860b42cd4f6da3365e180954bdc0665eda476044c3e39f97e` |
| `states/p-after-x86/accessflags/fixture.c` | `90473343afa843b70c5003ee5b106885e1514b208c0fe60dfc8bf5caadab8637` |
| `states/p-after-x86/accessflags/init` | `76220f7e07d1b50c99bf541facac02679052948676ce348394029f40ac4ef12c` |
| `states/p-after-x86/accessflags/serial.log` | `c7e4d66a4e385b545653e53f415646a0cbf29bee930d14a0f5a2d208fa06dae5` |
| `states/p-after-x86/access/fixture.c` | `53998280afb32ec26809a7bfb1f9b6e7b24f5e326e7b2e2755d6f8bdf9e4b599` |
| `states/p-after-x86/access/init` | `87b5e511b3b759b08dd182c459faab3cf9839920656c8a612efe9d94eeb026fb` |
| `states/p-after-x86/access/serial.log` | `d3a9ebb7cbc7ab8df87bc0659f8d4e468be2e3e169b1631930aa88592da7538a` |
| `states/p-after-x86/open/fixture.c` | `b2d362c322a5a63aa9dd819e342ec30c0384972bdc55f9e59b7c81398ac41eb9` |
| `states/p-after-x86/open/init` | `377071b25bf7f8a9b3a048c8eab9ec87c689beb7ca5791e8439a46a4131f222a` |
| `states/p-after-x86/open/serial.log` | `54eb6cbab773e3769ff502ca83030b75856525c7380a3238ab6a7b6d0fde5457` |
| `states/p-after-x86/runtime/fixture.c` | `283ee3218dbf04ee7c3289110ff0be3044906d48556453b06b7de972f4950e3b` |
| `states/p-after-x86/runtime/init` | `3c22f6e44700a031e0c6e9bd04427095e423d595d3f9b81e09f07539d1ea3b9f` |
| `states/p-after-x86/runtime/serial.log` | `0a8088397a56749f4b5b8275d36d23b60de5eafe640a5f6e4470d7e66b45c8cd` |
| `states/p-reference-x86/fixture.c` | `9a00c674f577f482eee7294e17779efff23dfdc1266dc9f4c3f2a5447a0dd182` |
| `states/p-reference-x86/init` | `e3841c5cf0c0b4e571a9c7775bbbd332b8d79da03a9ee1fdb7f00a42a563666b` |
| `states/p-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p-reference-x86/serial.log` | `1ca2f32a79265fd28c87fd6198bcf025bccc1982fd321e3c98c2d88c6e3d0dd1` |
| `states/p-reference-x86/receipt.json` | `e301be9b98a7af4a744390288db66a6cc6bf6b1c56d8560653651475b20fdb8f` |
| `states/p-reference-x86/initramfs.cpio` | `33cbb3360c5970dd23c8a94aeed2930174a69a32013c6b143006e8e59b7c0ec1` |
| `states/p-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `tests/linux-compat/pipeabireferenceinit/core.v`, `states/p-reference-x86/source/pipeabireferenceinit/core.v` | `bcbd33865027c4b179936a776327b4b2d97dd44b3bc1546f17b86d93def235f4` |
