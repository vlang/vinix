Independent lockaccess lifetime review: PASS

Reviewed the sole owned kernel change in `kernel/file/locks.v` against frozen baseline `0c12e1656b633b2f7d8365a47361a812414d4eb1`, both isolated copies, before/after generated C and kernel bytes, the probe and reference wrapper/controller, and completed native/Linux-reference captures. This independent review found no blocking new lifetime or lock-order concern and changed only this repository report. Private V verification helpers ran without `-prod`, with assertions active. Artifact paths below are relative to `/Users/alex/.cache/vinix-linux-compat/lockaccess-20261014`; maintained-source paths are repository relative.

`syscall_flock` now imports descriptor and operation words through unsigned 32-bit scalars, computes a scalar operation kind, rejects combinations other than exactly SH/EX/UN with optional NB, and checks O_PATH/read/write eligibility before MAC or lock-table work. Generated C on both architectures confirms `(i64)((u32)(fdword))` and `(i64)((u32)(opword))`. No pointer, interface box, array or heap value is introduced. Existing descriptor lookup retains the FD/Handle; the new access rejection executes the existing deferred FD unref. Inspection of generated C confirms that this is one additional unref exit, while all previous exits still retain their unref. Invalid operations rejected before lookup own no descriptor reference. The record-read access guard is scalar and precedes PID validation/mutation as before. Queries and unlock requests retain their separate eligibility behavior.

Advisory ownership, conflict selection, description identity, table allocation/freeing, notifications, final-handle cleanup, blocking waits and lock ordering are unchanged. No allocation, ownership transfer, new reclamation or grace-period requirement was added. Independently removing exactly the two changed definitions and their two prototypes restores the complete remaining generated C byte for byte on both architectures, without whitespace normalization or helper removal. Allocator and lock-acquire/release call counts inside the changed bodies are invariant. Before/after allocation reports are byte-identical: 659/655 source files and 400/292 allocation sites. Their existing allowance refusals remain; this does not claim a globally passing allocation allowance audit.

The probe's generated C has eleven explicit allocas and no memdup, malloc, dynamic-array allocator or fixed-index helper. Both previews equal all four executed native C files byte for byte. Flock buffers/saved headers, metadata scratch, tally and slab snapshots use bounded frame storage; fixed access/operation tables and parser/data buffers are stack arrays. Synchronous fcntl, fstat, memcpy and pread calls borrow this storage without retaining it. Return Query values copy scalar fields. The reference wrapper's three-element argv allocation is borrowed only by synchronous execv; a failed exec returns before the frame disappears.

Each record/whole-file matrix case closes its distinct alias, original, seed and observer descriptors before returning. Fatal setup/seed errors terminate the cohort through `_exit`, so process teardown closes all successful acquisitions and no caller continues using its frame. Retention partial-open failures close every acquired FD. The normal retention path unconditionally closes all five descriptors even after a failed semantic check, and its slab observer closes through defer on every returning path. Parent setup prepares/chowns the UID/GID 1000 file before either cohort, waits for both children before unlinking, and relies on process-exit cleanup on fatal setup failures. No thread or asynchronous reader of probe frame storage is introduced.

Both credentials exercise O_RDONLY, O_WRONLY, O_RDWR, Linux access mode 3 and O_PATH through direct/dup/F_DUPFD_CLOEXEC aliases. The six POSIX/OFD record commands test read/write/unlock, PID/whence/range/type combined errors, libc and raw native upper-word fd/command forms, complete 32-byte request preservation/returned fields, independently observed acquired/preserved locks, unchanged bytes/metadata/flags and shared versus independent cursors. Whole-file controls cover sixteen operations in libc/raw native forms, including SH/EX/UN with NB, invalid mixed unlock/acquisition kinds, unsupported bits and upper operation-word garbage. The same native probe ELF for each architecture is executed by Linux 6.12.51 with `--reference`, skipping Vinix-specific allocator accounting.

| Probe kind | Calls per credential | Baseline failures per credential |
| --- | ---: | ---: |
| Record access, errno and complete header | 2700 | 48 |
| Whole-file access and operation errors | 480 | 165 |
| Retained/acquired locks, bytes, metadata, flags and cursors | 3180 | 516 |
| Total | 6360 | 729 |

Both completed candidates and Linux references pass all 12,720 counted controls per architecture. The unchanged baselines reproduce 1,458 failures in the same 12,720 controls. Both final native receipts contain the five successful cases lockaccess, lockrange, ofdlocks, open and runtime with empty details and exit0; their kernel hashes match the reviewed final binaries. After 32 warmups and 13-second settling before/after, each credential runs 200 measured mixed OFD/flock acquisition, rejected request, query, unlock and alias-close cycles. All 18 AArch64 and 14 x86-64 slab classes remain flat, and large pages remain 63/63 and 160/160 respectively. These measurements qualify this sequence and do not prove arbitrary persistent-lock or blocking workloads leak-free.

Qualification is limited to native musl/raw ELF64 regular-file paths on the two architectures. Nonregular objects and other filesystem/backing-resource behavior, LOCK_MAND and historical mandatory-lock flags, MAC/policy interactions, concurrent open/cursor/close/set/fork/exec races, PID reuse/namespaces, fairness/deadlock handling, GNU libc wrappers and foreign/translated/ELF32 paths remain unqualified here. The unchanged ownership/table implementation retains the scope and limits of the preceding OFD review.

SHA-256 pins were independently computed after both final producers completed. Shared rows assert exact byte identity before listing a common hash.

| File | SHA-256 |
| --- | --- |
| `kernel/file/locks.v`, `kernel-arm/kernel/file/locks.v`, `kernel-x86/kernel/file/locks.v` | `11b538d799e2ffa6f995e3e14d2c8a6bba5f63582f504e33143a0fce7849843b` |
| `tests/linux-compat/lockaccessfixture/core.v`, `verified-before-arm/sources/lockaccessfixture/core.v`, `verified-after-arm/sources/lockaccessfixture/core.v`, `verified-before-x86/sources/lockaccessfixture/core.v`, `verified-after-x86/sources/lockaccessfixture/core.v` | `b5fd936dc832038917edfb496857d0bc5ed490cc8755e8aa69f7ef9f373b3107` |
| `tests/linux-compat/lockaccessreferenceinit/core.v`, `verified-reference-arm/source/lockaccessreferenceinit/core.v`, `verified-reference-x86/source/lockaccessreferenceinit/core.v` | `0559ed7d9ed1d9d67a51e7001de5ac5ef048a18964ac524598eac97b0592588d` |
| `tests/linux-compat/lockaccess-reference.v` | `255585f4f781ebff4049346184ccb13cd9566e105eb21359aa9fbeaa8bd7ebbe` |
| `tests/linux-compat/run.v` | `bc915a0a2e1eae958a8c5d6bf3f750e1531894133cb9dcdba0a8e0b7e778db2a` |
| `preview-arm.c`, `preview-x86.c`, `verified-before-arm/lockaccess/fixture.c`, `verified-after-arm/lockaccess/fixture.c`, `verified-before-x86/lockaccess/fixture.c`, `verified-after-x86/lockaccess/fixture.c` | `1ffe56487126c509d83df375822bfff4b6ba37cc4473ed4905b495f63104eecb` |
| `verified-reference-arm/fixture.c`, `verified-reference-x86/fixture.c` | `f4492f82e0511b69b4e357717f8ad98622f947d9eb8ee8edf36049c31c0add0a` |
| `before-arm.c` | `6f231bff4aa7857a1999eabdbc3d27b6ee7beefbeebb02ff39d0d009d69b55a3` |
| `kernel-arm/kernel/obj/blob.c` | `76ec2c164332d18c2cc6b883cdcb1c6d15c36650c3d4bf483aef0210269920ee` |
| `baseline-arm/kernel/bin/vinix`, `verified-before-arm/kernel/bin/vinix` | `77a62bb4fc62a5a85b74043b634c59d63a442e45da221efb75533d626ae6dd2f` |
| `kernel-arm/kernel/bin/vinix`, `verified-after-arm/kernel/bin/vinix` | `b9f6a97a7d545dff93d9041823fe37379338c953d62bd95edcb58a421ceeb4dd` |
| `verified-before-arm/lockaccess/init`, `verified-after-arm/lockaccess/init`, `verified-reference-arm/probe` | `1bf302cc78809d6a576e1a29bf1a003a1d66ee93c3cb1fe24687beaf76f211c0` |
| `verified-reference-arm/init` | `be142e53465976444899c519eb829e5a6106224ba03394ddc6682cb9194fb64a` |
| `verified-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `verified-before-arm/lockaccess/serial.log` | `ed7daadaf0a231c9117a08cf77279fad032b684e7aa33c6670aad7c72cca21c0` |
| `verified-before-arm/receipt.json` | `0b8014527b8960485d48ab712da854a62cc2a4e11c13f361ad26d4ca25311dea` |
| `build-before-arm.log` | `53a3a019f2a9d0b6086b64d75f22f60488df3723eafd8496af0becffb5f823ce` |
| `verified-after-arm/lockaccess/serial.log` | `7cd375d18e8066990c05776fb1bfd27148fef983994f9d0e57fc3c8b080c6f16` |
| `verified-after-arm/receipt.json` | `e10e4357bad8295bed09bfff054fc60d8884ec411220ba7a89892e57aab6f203` |
| `build-after-arm.log` | `d5f20725a4b4e5033a4042506d58eb3f9edb190471197a5ff14b2fe3f17990e7` |
| `verified-reference-arm/serial.log` | `5d7107f9d88c9a76888cfb1e57c678d8ba982ebbe639cb562290cdf9c62b81b1` |
| `verified-reference-arm/receipt.json` | `53994c2c6bf45fb19a5c6934fe26d9dbee59154cb204cf6ec164ea2d009a1043` |
| `before-x86.c` | `5b52051cd600468f2259ffd8bf7f20283ceb7f00334ee3fc8ff12358d28b5c39` |
| `kernel-x86/kernel/obj/blob.c` | `7c1e80449721e7ae68ceeb773e177957a821052f41a2fbed5803e60a04e4c91f` |
| `baseline-x86/kernel/bin/vinix`, `verified-before-x86/kernel/bin/vinix` | `f4369c311f34ec8e603754176c13e6c60327ffccdcd3ac2181df0cc7e344531d` |
| `kernel-x86/kernel/bin/vinix`, `verified-after-x86/kernel/bin/vinix` | `001de3e9c3ceae08aedc4943b70bfb17a1f18412402d62a3bdba855fbce78579` |
| `verified-before-x86/lockaccess/init`, `verified-after-x86/lockaccess/init`, `verified-reference-x86/probe` | `02d20685ddf6ff49abb998356c1ea4147bb13179fb41804c0760b57d12cf9a23` |
| `verified-reference-x86/init` | `7e5a31630e2ca20590444bd3ca5d1ff6c9ad574cac6111339edb12a63c8713b5` |
| `verified-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `verified-before-x86/lockaccess/serial.log` | `8c690dd4119d5b0fc90f3ae339ee7dd8f79b76c2064a53b4f27a879f60211daa` |
| `verified-before-x86/receipt.json` | `6af6e9df4f8fae5d7bd8c205b22b2b97a9c4be0f3337a0095d2d99bd1556443a` |
| `build-before-x86.log` | `d09c2c9088cc4fec00ad70735840c787be76b739c3d400f41e3ba3965800ea63` |
| `verified-after-x86/lockaccess/serial.log` | `e0946ca44969dc1188605796a1d16cdc31be43bc5d3334b6d92cff50ff5d49bc` |
| `verified-after-x86/receipt.json` | `4384b834d3e41b35fc47b10cbc7a4b5bbf14ce584cf1b6e0ffc5cc91d04adaaa` |
| `build-after-x86.log` | `17c37b41cfb8225654b425a4526838f2aee1c5c9aac48918a0795547032523bf` |
| `verified-reference-x86/serial.log` | `018ea290f8b0ff72237c31c711d6c273a6eabab87e1020252760c68ef77ca582` |
| `verified-reference-x86/receipt.json` | `c43791b64db3dea4225e70be49ad008619b53e1b3c8f94fe8b0533094aac7a20` |
| `scope.v` | `459b76b455b7fe1046473134c67ba17b4c9d05767319c205ea4584e6a56fe834` |
| `scope-check.log` | `59215849ea05783aa80c1144c2b5ea3433f0b2b34967201aeadd5a4a760d1318` |
| `allocs-before.log`, `allocs-after.log` | `d67238cfced2149555dfe195eec4c1ac8f34f3fd2df465da06b2a1868f15241d` |
| `host-tests.log` | `20c607ced25a47817463026345c613bab1aa124e56cc10a6ea6885927a8b589a` |
