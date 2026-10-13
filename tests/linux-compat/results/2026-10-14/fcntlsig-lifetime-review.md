Independent fcntlsig lifetime review: PASS

Reviewed the new native conformance probe and Linux reference wrapper/controller, unchanged kernels at frozen revision `97e2f95bdad3acbf00ec27ada5ae38c09e25c6a6`, and completed diagnostic, fresh native regression and Linux reference receipts. No blocking new lifetime concern was found. No kernel implementation change remains. The private independent V checker ran without `-prod`, with assertions active; its negative assertion control was also executed. Repository writes are confined to this report. Paths below are relative to `/Users/alex/.cache/vinix-linux-compat/fcntlsig-20261014`; maintained paths are repository relative.

The existing native dispatcher already imports the low 32 bits for `F_SETSIG` into a scalar u64; the unchanged handler accepts 0–64 and rejects the unsigned encodings of negative low words with EINVAL. FD/command imports also retain their existing low-word semantics. Both source and generated C confirm this path. Lookup retains FD/Handle/resource through the branch; success and EINVAL paths each unref that FD exactly once, while missing and O_PATH descriptors return before signal validation. No new kernel allocation, borrowed pointer, lifetime change, ownership transfer, lock acquisition or reclamation exists in this qualification. The proposed redundant handler edit was reverted. Saved kernel C and runtime kernel binaries equal their worktree, initial diagnostic and fresh native copies byte for byte. The completed frozen-kernel allocation inventory reports 659/655 files and 400/292 sites with existing allowance refusals; this is not a globally passing allocation allowance audit.

Both executed native previews contain ten explicit allocas and no memdup, malloc, dynamic-array allocation or fixed-index helper. Descriptor storage is bounded to 27 slots; State has 28 slots including the reused FD 66 scratch snapshot; Count has five fixed categories; the slab parser bounds 32 rows and a 4 KiB buffer with explicit NUL termination. Query values, wait status, data buffers and fixed literals are stack values. All C pointer borrows are synchronous. Fork creates a separate child frame/address space; the parent waits each credential cohort before checking queued bytes and closing all 27 descriptors, then removes the regular file/directory. Setup failures terminate through main return and fatal matrix errors `_exit`, relying on process teardown to close acquired FDs and guest tmpfs teardown for created paths; no successful partial-cleanup claim is made. Each retention cycle closes its successful temporary alias before returning even after semantic failure, and observer defer closes on every storage return. The Linux wrapper’s three-entry argv stays live until synchronous execv replaces the process or fails.

| Counted control | Calls per credential | Failures |
| --- | ---: | ---: |
| Valid-description raw signal words | 810 | 0 |
| Missing and O_PATH descriptor precedence | 405 | 0 |
| Native libc controls | 243 | 0 |
| Getter argument and state preservation | 540 | 0 |
| Lowered limit, descriptor reuse and shared cursor | 362 | 0 |
| Total | 2,360 | 0 |

Both Linux 6.12.51 references and both fresh native suites pass 4,720 counted controls per architecture. The initial Vinix diagnostic runs also passed every control with flat storage. Their outer execution helper incorrectly expected exit 1 and asserted after the inner runner returned 0; the actual complete receipts record successful guest results. This host expectation mistake is not a reproduced kernel failure. The same native musl ELF bytes run in all initial/fresh Vinix and Linux environments. Cohorts use root and UID/GID 1000, six ordinary resource classes (read-only and read/write regular file, directory, both pipe ends and Unix stream socket), original/dup/F_DUPFD_CLOEXEC aliases, regular/directory O_PATH descriptions, upper argument/fd/command words, signed boundaries, missing/closed/reused descriptors and descriptors above lowered RLIMIT_NOFILE. Checks preserve alias signal state, FD/status flags, owner values, metadata, queued bytes, file content and shared cursor behavior. Both fresh native receipts also bind five passing guest cases: fcntlsig, fcntlabi, fcntlpath, open and runtime. After 32 warmups and 13-second settling before and after each 200-cycle cohort, all 18 ARM / 14 x86 slab classes remain flat; observed large pages (arm: root 70/70, UID/GID 1000 70/70; x86: root 181/181, UID/GID 1000 181/181) stay flat. These observations qualify the exercised sequence, rather than proving arbitrary asynchronous workloads leak-free.

Qualification covers native ELF64 musl/raw signal configuration and error semantics. Actual SIGIO/queued-signal delivery, ownership/security policy, concurrent mutations, GNU libc wrappers, other backing filesystems and foreign/translated/ELF32 paths remain unqualified. Three broad roadmap gates remain open.

SHA-256 pins were computed independently after all producers completed; common rows require exact byte identity.

| File | SHA-256 |
| --- | --- |
| `kernel/file/file.v`, `kernel-arm/kernel/file/file.v`, `kernel-x86/kernel/file/file.v` | `ded7a34cd242a6a862ac439511e49c3f4e042eb8b43494e709ad7dbbba99d14e` |
| `kernel/syscall/table/linux_common.v`, `kernel-arm/kernel/syscall/table/linux_common.v`, `kernel-x86/kernel/syscall/table/linux_common.v` | `e02ca1595fcc117e237c44cfd5634218184c328592f9e4fcb82af3be15047f68` |
| `tests/linux-compat/fcntlsigfixture/core.v` | `f35d4e360f663ca7bdc3d4e68fd9ea5ed398acd8c019b19aeb2c0c0cb04ae92e` |
| `tests/linux-compat/fcntlsig-reference.v` | `f4f9eb31fc1a24644da4bc885fb926daf31d9b455e05369cb6769c3c7f575518` |
| `tests/linux-compat/fcntlsigreferenceinit/core.v` | `11bd66fb5f2d064291a0e017e17477aa4c4198e6ef252bf46bbfb6519b638bf2` |
| `tests/linux-compat/run.v` | `d37782c868a27846d4f1e4ded0447f6b046347190b952422913990dfc134852f` |
| `allocs-before.log` | `d6743dae52e54766573a62069eade227794097f31f02807d2d02d16048d407c7` |
| `host-tests.log` | `cf16679dc4a121cbf5677e9b30010f79e7f607d8b3b2286e6ad4b6f582378b7c` |
| `preview-arm.c`, `preflight-arm/fixture.c`, `verified-before-arm/fcntlsig/fixture.c`, `verified-native-arm/fcntlsig/fixture.c` | `ad6d8b6abb8679d1b153d09b506b575c17854e9100ff1f4ca433c85b45b9b8b2` |
| `preflight-arm/init`, `verified-before-arm/fcntlsig/init`, `verified-native-arm/fcntlsig/init`, `verified-reference-arm/probe` | `00dcc362c0bf43412b3766e6d6a5a140bd9770433512f97cf65a2205d2b3f98c` |
| `tests/linux-compat/fcntlsigfixture/core.v`, `verified-before-arm/sources/fcntlsigfixture/core.v`, `verified-native-arm/sources/fcntlsigfixture/core.v` | `f35d4e360f663ca7bdc3d4e68fd9ea5ed398acd8c019b19aeb2c0c0cb04ae92e` |
| `before-arm.c`, `kernel-arm/kernel/obj/blob.c` | `484a7e23eb2e5f95f8dc35f88e480d5bdaca9743d048b888521e5831cf274cba` |
| `baseline-arm/kernel/bin/vinix`, `kernel-arm/kernel/bin/vinix`, `verified-before-arm/kernel/bin/vinix`, `verified-native-arm/kernel/bin/vinix` | `f949d9fc73abff139fab556c7482b44b4a492f95c3f2054e02f67763df8d2eac` |
| `build-before-arm.log` | `73763760fe35371d53ee9d0bae290d3f7b91e15f3c900a3dc3a598d111771dda` |
| `verified-before-arm/fcntlsig/serial.log` | `f4c2002ae91463813a3cdbcf0f5267400b425f17ffc416301995b3a351cd65e9` |
| `verified-before-arm/receipt.json` | `820255bb4fcc5a7c108104eeb4a3fc07df71a26d2bf1bc54008000237282a31f` |
| `verified-native-arm/fcntlsig/serial.log` | `fbeaa5ff3885efd191541d93207323ff287b910b91ff2855887c7952e192b9ca` |
| `verified-native-arm/receipt.json` | `438172236566e1a7971892d56230f8b83a5acea9e9e9f8be11c70812e505a444` |
| `verified-reference-arm/fixture.c` | `05701e025854ffcd8d70f48b430d6be9c11b5491a0a9cb3793ca676885bed9d7` |
| `verified-reference-arm/init` | `4172fae1ea382d8f060be008a23a610a68db060aba64f387c1d419ca9952295b` |
| `verified-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `verified-reference-arm/serial.log` | `bc3ac941f49f9d0632a002a31e91d154d52da733b64119de9fbc202662fc70e1` |
| `verified-reference-arm/receipt.json` | `840fdfc7d233da367ec22d01c32ed680c4d88668b9ae5463adea5134c15e4040` |
| `verified-reference-arm/initramfs.cpio` | `ce0168d068f157bbb845dceffab3a758ed81aaf137f9d433b99384b27420aab0` |
| `verified-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `tests/linux-compat/fcntlsigreferenceinit/core.v`, `verified-reference-arm/source/fcntlsigreferenceinit/core.v` | `11bd66fb5f2d064291a0e017e17477aa4c4198e6ef252bf46bbfb6519b638bf2` |
| `preview-x86.c`, `preflight-x86/fixture.c`, `verified-before-x86/fcntlsig/fixture.c`, `verified-native-x86/fcntlsig/fixture.c` | `ad6d8b6abb8679d1b153d09b506b575c17854e9100ff1f4ca433c85b45b9b8b2` |
| `preflight-x86/init`, `verified-before-x86/fcntlsig/init`, `verified-native-x86/fcntlsig/init`, `verified-reference-x86/probe` | `e69a440224dc8fe8981d484c7b32e31e9d0310454553968354de99b79063b8bb` |
| `tests/linux-compat/fcntlsigfixture/core.v`, `verified-before-x86/sources/fcntlsigfixture/core.v`, `verified-native-x86/sources/fcntlsigfixture/core.v` | `f35d4e360f663ca7bdc3d4e68fd9ea5ed398acd8c019b19aeb2c0c0cb04ae92e` |
| `before-x86.c`, `kernel-x86/kernel/obj/blob.c` | `7cbf29482d6566e75d62ce68908032f577c75ca261542a5905e5db005599ab51` |
| `baseline-x86/kernel/bin/vinix`, `kernel-x86/kernel/bin/vinix`, `verified-before-x86/kernel/bin/vinix`, `verified-native-x86/kernel/bin/vinix` | `3437ce8610f906c5f2a7587af232cefd619691fd3020a9b39b09e41651ced53b` |
| `build-before-x86.log` | `23b51f99848cc0668c8338ed2ae787540ede31745ee487a49138dc9cad784187` |
| `verified-before-x86/fcntlsig/serial.log` | `655a42a95cc4413f6f1fc6ede3f633f0d58929f8de20bc9ac13692ad834d9500` |
| `verified-before-x86/receipt.json` | `8e80c389a3318a5bc5e14631d0bd7e712af5f061af22ea8959db0467d92845a3` |
| `verified-native-x86/fcntlsig/serial.log` | `655a42a95cc4413f6f1fc6ede3f633f0d58929f8de20bc9ac13692ad834d9500` |
| `verified-native-x86/receipt.json` | `825dcbd99f3da04c236fad6bde318815a067d02bd20e1b335bc0d64f9c51e241` |
| `verified-reference-x86/fixture.c` | `05701e025854ffcd8d70f48b430d6be9c11b5491a0a9cb3793ca676885bed9d7` |
| `verified-reference-x86/init` | `8ffaa2979f2307d9bd63f502960a5daa4bf6f76b7fa846d7c3aaedc7437267b2` |
| `verified-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `verified-reference-x86/serial.log` | `6115a09d6adf07b7507fda50ff0eb6ecdcd21bf14c57eb599005b083e7d4edaa` |
| `verified-reference-x86/receipt.json` | `319bff2fc8d839bd545126436c0d5ad2ff1e2e31e69b20db91a560802d777de2` |
| `verified-reference-x86/initramfs.cpio` | `ae503bdbd3e4d2f0531c72d2bf9089f3f4e29619402bf844679562697349dbb1` |
| `verified-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `tests/linux-compat/fcntlsigreferenceinit/core.v`, `verified-reference-x86/source/fcntlsigreferenceinit/core.v` | `11bd66fb5f2d064291a0e017e17477aa4c4198e6ef252bf46bbfb6519b638bf2` |
