Independent flocksame lifetime review: PASS

Reviewed the sole owned kernel change in `kernel/file/locks.v` against frozen baseline `84e6321ed2e61682b3a98ca3e6f9665f1f8e2380`, both ordinary and private scheduling-window source/C/kernel profiles, the native probe and Linux reference wrapper/controller, and all completed owned-case captures. This independent review found no blocking new lifetime or lock-order concern. An independently written V checker ran without `-prod`, with assertions active, and changed only this repository report. Artifact paths below are relative to `/Users/alex/.cache/vinix-linux-compat/flocksame-20261014`; maintained-source paths are repository relative.

`syscall_flock` checks the existing table for the same concrete resource, open-description owner, flock class and read/write kind under `advisory_locks_lock`. The new loop copies each `AdvisoryLock` into a scalar local. No pointer into the table survives its release. A match releases the table lock before returning success and before the existing deferred FD unref. Descriptor lookup retains both FD and Handle; the Handle retains its resource, so resource/owner identity remains valid through the scan and its exit. Both generated-C bodies confirm that release precedes exactly one FD unref on this path. There is no allocation, table mutation, ownership transfer, reclamation, notification, extra lock nesting or grace-period requirement in the new branch. Different-kind conversion, explicit unlock, conflict waits and final-description cleanup retain their existing code and lifetime rules. Arbitrary simultaneous shared-description mutation remains outside this qualification.

The maintained instrumenter produces only a private copy: it adds `import sched` and 32 reschedules after `release_description_locks(handle, true)` has returned for requests containing NB. No advisory-table lock is held there, and the in-flight FD/Handle remains retained. Removing this exact import/block restores the ordinary before/after source byte for byte. Independently removing exactly `syscall_flock` definition/prototype restores all remaining before/after generated C byte for byte for both profiles and architectures, with no whitespace normalization. Ordinary/window comparison additionally permits on x86 only one relocated, byte-identical contiguous 48-line mmap macro block. The production source has no scheduling instrumentation. Before/after allocation inventories are byte-identical: 659/655 files and 400/292 sites; existing allowance refusals remain, so this is not a globally passing allocation allowance audit.

Both native probe previews equal all executed before-window, ordinary-after and window-after C files. Generated C contains eleven explicit allocas and no memdup, malloc, dynamic-array allocation or fixed-index helper. Metadata scratch, tally, three pipe-FD pairs, Query results, pollfd and slab snapshots have bounded frame storage; parser/data arrays and wait status are stack values. Synchronous syscalls borrow these addresses without retaining them. Fork gives the contender its own frame/address space, and pipe transfers copy result bytes rather than publishing a pointer. The child closes inherited lock-owner aliases and observer FDs before opening a distinct description, reports readiness, blocks for EX, and retains that description until the parent explicitly requests release. Its 20-second alarm bounds fatal/hung paths. The parent polls a live stack pollfd, copies the completed Query, waits for the contender before returning, and closes pipe endpoints, alias, principal and observer. Fatal setup failures call `_exit`, so teardown closes successful acquisitions and no caller resumes using the frame; alarm/SIGPIPE failures likewise terminate the cohort rather than continuing. The wrapper argv alloca is borrowed only by synchronous execv, and failure returns while its frame is live.

Retention partial-open failures close every acquired FD. Its normal path unconditionally closes all three descriptions even after failed semantic checks, and the slab observer closes through defer on every return. The top-level parent creates/chowns the UID/GID 1000 regular file and directory before dropping credentials in a child, waits for both credential cohorts before unlink/rmdir on completed paths, and uses process-exit cleanup on fatal setup errors. No new kernel lifetime is freed earlier than before.

| Counted control | Calls per credential | Window baseline failures (ARM / x86 user / x86 root) |
| --- | ---: | ---: |
| Same-kind operation retains ownership | 192 | 192 / 192 / 191 |
| Independent waiter remains blocked | 192 | 192 / 192 / 191 |
| Ownership, waiter cleanup and unchanged file state | 240 | 12 / 12 / 12 |
| Sequential repetition, conversion and alias/final-close controls | 344 | 0 / 0 / 0 |
| Total | 968 | 396 / 396 / 394 |

All four completed candidate profiles and both Linux 6.12.51 references pass all 1,936 counted controls per architecture/run. These cover regular files/directories, SH/EX, original/dup/F_DUPFD_CLOEXEC aliases, native libc and raw upper fd/operation words, 24 observed sleeping independent contenders per credential with eight same-kind NB requests each, actual different-kind conversion, explicit unlock wakeup, nonfinal/final description close, unchanged bytes/metadata/flags and shared versus independent cursor behavior. The same ELF bytes execute on Linux, skipping Vinix-specific allocator accounting. The recorded private-window baselines reproduce 792 ARM and 790 x86 failures with all 688 sequential controls still correct; this does not assert deterministic failure of an uninstrumented production baseline. Both ordinary native receipts also bind five successful guest cases flocksame, lockaccess, ofdlocks, open and runtime. After 32 warmups and 13-second settling before/after, each profile/credential runs 200 mixed regular/directory acquisition, repeat, conversion, unlock and alias-close cycles. All 18 ARM / 14 x86 slab classes remain flat; large pages remain 63/63 and 160/160 in both cohorts and both profiles. These measurements qualify this sequence and do not prove arbitrary blocking or persistent-lock workloads leak-free.

Scope is native musl/raw ELF64 regular-file and directory paths on tmpfs. MAC/policy interactions, arbitrary shared-description concurrent mutation/close/fork/exec races, fairness/deadlock handling, other filesystems/backing resources/nonregular types, deprecated mandatory locks, GNU libc wrappers and foreign/translated/ELF32 paths remain unqualified. Three broad roadmap gates remain open.

SHA-256 pins were computed independently after all final producers completed. Shared rows assert exact byte identity before listing a common hash.

| File | SHA-256 |
| --- | --- |
| `kernel/file/locks.v`, `kernel-arm/kernel/file/locks.v`, `kernel-x86/kernel/file/locks.v` | `aca5b808837e39cc7e3bbdde8e6e3e13b86e34fa1570e18e1de925fdff992390` |
| `window-after-locks.v`, `window-arm/kernel/file/locks.v`, `window-x86/kernel/file/locks.v` | `3e9d890a8f230ad2e9ae7b9a6ca1ecddbc58031d31c917cf3f624a954ee763c6` |
| `tests/linux-compat/flocksamefixture/core.v` | `ad87937c51de361f5e3b8a148b33226b227e11b8bab554f1fa2d4f76cc784975` |
| `tests/linux-compat/flocksame-instrument.v` | `8c06e41f3d1591346853844708001ce69e824c43d95db0baebbf2ba800fcac4b` |
| `tests/linux-compat/flocksame-reference.v` | `8e039de34d847a20d9f630af0dda7261292d5b901bc345e0e4d3fe9e62210b92` |
| `tests/linux-compat/flocksamereferenceinit/core.v` | `ea6648d958042a2be3ab7adf7398b8eaf5c8c6c784867c7276f7327522918022` |
| `tests/linux-compat/run.v` | `c70c337247e563f9ec79b991c7629ad67f8c9154ec99dfa68923ad43c8f3b600` |
| `baseline-locks.v` | `11b538d799e2ffa6f995e3e14d2c8a6bba5f63582f504e33143a0fce7849843b` |
| `window-before-locks.v` | `055115cccbf5240b227553a957153301546c9af52a7e9c2f630c0c560e68cc37` |
| `scope.v` | `0aa3bf95034f53a371274731b531ed755b83b5cebc9ccaa38ecfbd24dd03889c` |
| `scope-check.log` | `7a657ea4e8eef2ec9515bbf7b44ed96c46c40fc0ee6ee18900bbb00a6aae9615` |
| `host-tests.log` | `84f8ddd1c4e34657ba4d4163c9300e88e6bfad0043a0f38064ee8343d1c07d4e` |
| `allocs-before.log`, `allocs-after.log` | `d6743dae52e54766573a62069eade227794097f31f02807d2d02d16048d407c7` |
| `preview-arm.c`, `preflight-arm/fixture.c`, `verified-before-window-arm/flocksame/fixture.c`, `verified-after-kernel-arm/flocksame/fixture.c`, `verified-after-window-arm/flocksame/fixture.c` | `dad5de6f7ccfaf1e25494b7edb54e6537153706764213126b2c7dea498f8f9c9` |
| `preflight-arm/init`, `verified-before-window-arm/flocksame/init`, `verified-after-kernel-arm/flocksame/init`, `verified-after-window-arm/flocksame/init`, `verified-reference-arm/probe` | `706b4560694b57f7a57fbfc03409fcf7a0d7cd69b17638b9db6324db28880fb8` |
| `tests/linux-compat/flocksamefixture/core.v`, `verified-before-window-arm/sources/flocksamefixture/core.v`, `verified-after-kernel-arm/sources/flocksamefixture/core.v`, `verified-after-window-arm/sources/flocksamefixture/core.v` | `ad87937c51de361f5e3b8a148b33226b227e11b8bab554f1fa2d4f76cc784975` |
| `before-kernel-arm.c` | `6db9353897fdd85aca109958a90127f2ea43ddc1efdaf947eecf5294937ab364` |
| `baseline-arm/kernel/bin/vinix` | `f6e6b95abfd3f2ba380ae6a04844c425d17d71d4bad1c833dc291601651bc491` |
| `build-kernel-before-arm.log` | `fb42cb2b0f67c914fa1d331c4f696be9e469470b50f1166817fdb6ed75a4d016` |
| `kernel-arm/kernel/obj/blob.c` | `484a7e23eb2e5f95f8dc35f88e480d5bdaca9743d048b888521e5831cf274cba` |
| `kernel-arm/kernel/bin/vinix` | `30597a678cd34d54a1b0b6591341c7c7356d6cb35fa5603ab64b7845614a1d7f` |
| `build-kernel-after-arm.log` | `ad69e464a0b9f481da3ce18a64d276c154f7562ac9804d6a9012a6c121ff1b05` |
| `before-window-arm.c` | `a79b56104914bb4a4c2d8332fba70a363d926c00e4125ae5bb66b5db26524b79` |
| `baseline-window-arm/kernel/bin/vinix` | `3470c86ba5fe11c9b89f2b452e22d13506794ce9b22ac54419794871f6868109` |
| `build-window-before-arm.log` | `15344a10eb4404c45d5622d8dc00a3266096af59881084ce85b18ba598968d1e` |
| `window-arm/kernel/obj/blob.c` | `f8c1b5e8440e337ff008f1743f111c2ebe5f3c087a5cff430f0f805a958f36ac` |
| `window-arm/kernel/bin/vinix` | `1b276897dd866f29ecf12bb952814d5fbe5c40f1ade4dbda1765ffee25bef58f` |
| `build-window-after-arm.log` | `c1e6ff91af1e90c0c8291f898a891779e8981690c614412c49a1efa70060cc11` |
| `verified-before-window-arm/flocksame/serial.log` | `6b18b2d095b71b417514fe100bf67fba74b431c9c3fc2f99e6951305f2360ea1` |
| `verified-before-window-arm/receipt.json` | `b6a5b0d0cf359d6553bb021c78ee3580dcfcb5a5bf223af4781e4fc345d4ff72` |
| `verified-after-kernel-arm/flocksame/serial.log` | `02673f4d7492eca19c971fb0514fd8fdb2771e0cabdd1df907f293db07e500c7` |
| `verified-after-kernel-arm/receipt.json` | `eb08aa6bbb2199efd984688148fa52aa4dedb43437c7032a99a3bf5cb6bddc48` |
| `verified-after-window-arm/flocksame/serial.log` | `53646c2a7b28dd7eaaeaefcd51318db87b003f884c467ebf4b128289ace1d6dd` |
| `verified-after-window-arm/receipt.json` | `34a03696b4241eb14f75a6bdfacdaa6e1880b26b28c57935715c776d5bfd67bd` |
| `verified-reference-arm/fixture.c` | `a6ed90e633a13e88efa03244189b6d87319318a6b51afe729fb29c1388a7c82a` |
| `verified-reference-arm/init` | `7dec46b120094122aa73ba0a4b601d63fbadd45a7cf00641749a34c81cd69577` |
| `verified-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `verified-reference-arm/serial.log` | `4895590687873a296898425b727b1e1653362b085d9425fd4319c4c7d131a79b` |
| `verified-reference-arm/receipt.json` | `522dc4d92b02ff3e8d3f7f42df5133b459a058b1481340c2fabe729c2f72fdc0` |
| `verified-reference-arm/initramfs.cpio` | `1ef0a3620e8d974c0280e52c8a95fad6df789d95342c857bfac7889acd13f7ee` |
| `verified-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `tests/linux-compat/flocksamereferenceinit/core.v`, `verified-reference-arm/source/flocksamereferenceinit/core.v` | `ea6648d958042a2be3ab7adf7398b8eaf5c8c6c784867c7276f7327522918022` |
| `preview-x86.c`, `preflight-x86/fixture.c`, `verified-before-window-x86/flocksame/fixture.c`, `verified-after-kernel-x86/flocksame/fixture.c`, `verified-after-window-x86/flocksame/fixture.c` | `dad5de6f7ccfaf1e25494b7edb54e6537153706764213126b2c7dea498f8f9c9` |
| `preflight-x86/init`, `verified-before-window-x86/flocksame/init`, `verified-after-kernel-x86/flocksame/init`, `verified-after-window-x86/flocksame/init`, `verified-reference-x86/probe` | `ec832239f75a6f25b13d111995f7a9b7d4947dcb1078a300de252945b829fecd` |
| `tests/linux-compat/flocksamefixture/core.v`, `verified-before-window-x86/sources/flocksamefixture/core.v`, `verified-after-kernel-x86/sources/flocksamefixture/core.v`, `verified-after-window-x86/sources/flocksamefixture/core.v` | `ad87937c51de361f5e3b8a148b33226b227e11b8bab554f1fa2d4f76cc784975` |
| `before-kernel-x86.c` | `b3ca309e550fa9071e8bd0cb31a3c06065a60e8bfe790296b88816aff1e61978` |
| `baseline-x86/kernel/bin/vinix` | `9f119de41608818b95bb3e310b5bf62282df783ee07ed7fa29d4fd54bb7385f6` |
| `build-kernel-before-x86.log` | `d5d61cfa136d1aa56737fdae99f7448f8229819305fc9815272c22b0f3c2f9aa` |
| `kernel-x86/kernel/obj/blob.c` | `7cbf29482d6566e75d62ce68908032f577c75ca261542a5905e5db005599ab51` |
| `kernel-x86/kernel/bin/vinix` | `db81d69db9f0351d9afa86e9d6d7a36a8f8084aa670434400489305ec2b05f0d` |
| `build-kernel-after-x86.log` | `422c22f78315081fe2ef0996dc2d6ef0faea35c977c487332ecff2006b4c44c7` |
| `before-window-x86.c` | `6f63bd9660d104528c354414d2dbecdbb94fba6f683038fc9625445befeb4be5` |
| `baseline-window-x86/kernel/bin/vinix` | `37e5b3aa71378c50e1d9e5c5f1867296d1c18473adaa7284e48d85e771faa7be` |
| `build-window-before-x86.log` | `98b85f8bac216cd37e940e7d270e182066ba7283a37a158776c4bdb53f3fffe6` |
| `window-x86/kernel/obj/blob.c` | `07c6ce61b4e17e19dcf7d14e33b2f1e572b2673bb2fd77590491c1c6a0886921` |
| `window-x86/kernel/bin/vinix` | `7a5241042900684154d4c7540005dc608458912434d743e37327ca69ceeb711f` |
| `build-window-after-x86.log` | `c2bb77d53b13e52d9e4d9abd22119d2627c884b7eb70acbcea4a360f1c6c917c` |
| `verified-before-window-x86/flocksame/serial.log` | `5b23b786e9554dda0e6766404bc0e5ba493f308dc45bf291b51e0061ade3fa68` |
| `verified-before-window-x86/receipt.json` | `958b77b7b94f6b71f4645c2c5cc7bf2414d8d8de863b95c1b2df2a90553c5e95` |
| `verified-after-kernel-x86/flocksame/serial.log` | `06bc48020516584bd20fb6cbd9a6e135781926e10592686a4a2fb7790319910d` |
| `verified-after-kernel-x86/receipt.json` | `4b1217c1eaacef18482b147a727cb7ce36ea00783cac2bd50723c3adb9aa9d82` |
| `verified-after-window-x86/flocksame/serial.log` | `06bc48020516584bd20fb6cbd9a6e135781926e10592686a4a2fb7790319910d` |
| `verified-after-window-x86/receipt.json` | `e41252ecbc292f6b5f1b5065723d086a80222c70e95dabd7220212f76bb920bf` |
| `verified-reference-x86/fixture.c` | `a6ed90e633a13e88efa03244189b6d87319318a6b51afe729fb29c1388a7c82a` |
| `verified-reference-x86/init` | `b42be938e709fb88fea677ce7f40bdcbe581dc31a677abce1c41b197753d3d09` |
| `verified-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `verified-reference-x86/serial.log` | `a69304dfffd71860792a4d6fa77c7750c33bd63b4b78d9c4d5cc2db02ab63fb2` |
| `verified-reference-x86/receipt.json` | `1ab6a58628e5cef59f45cb2f356595d9d09de2dfd18444af492a7202581bb4a7` |
| `verified-reference-x86/initramfs.cpio` | `f67158d17fcb923dbb43131b3b1c4abb6e9d7d7338d49a6e942aa6bd5e307cf3` |
| `verified-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `tests/linux-compat/flocksamereferenceinit/core.v`, `verified-reference-x86/source/flocksamereferenceinit/core.v` | `ea6648d958042a2be3ab7adf7398b8eaf5c8c6c784867c7276f7327522918022` |
