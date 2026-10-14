Independent ownerquery lifetime review: PASS

Reviewed native owner setters/getters in `kernel/file/file.v`, both scalar PID-number helpers in `kernel/proc/pidns.v`, the V native fixture and Linux reference wrapper/controller. Frozen baseline revision `905c838513a0939fb8d269786487346fbd62d7a1` reproduces the owner-query failures on both architectures; both final native candidates and both Linux 6.12.51 references pass. No blocking new lifetime concern remains. The private independent V checker ran without `-prod`, with assertions active and executed negative assertion and passing-as-failure controls. Kernel/build paths below are relative to `/Users/alex/.cache/vinix-linux-compat/ownerquery-20261014`; profile/preflight paths were read from `/Volumes/VinixOwnerQueryScratch` after their producers completed. Maintained paths are repository relative.

FD lookup retains the descriptor and shared Handle, dropping fds_lock before any owner/PID lock. Every new success/refusal/copy-failure branch releases the FD once. Setters resolve the caller-visible number under pid_lock, release it, then update the scalar kind/kernel-number pair under Handle.l. Getters snapshot that pair under Handle.l, release it, then map under pid_lock. Neither lock nests inside the other. All process/thread/group/namespace-map dereferences occur while the table lock protects their lifetime; no target pointer escapes and no target pin/reference, allocation or reclamation path is introduced. The current running process retains its immutable numbered_in namespace. Group/session membership changes and slot removals use the same table lock. Getters require a task attached to the requested TID/PID/group kind and map only into a caller namespace that can see it. Groups survive their leader through their remaining members. Erasing exactly the changed fcntl body/prototype, renamed lookup body/prototype and new getter body/prototype leaves byte-identical generated C on each architecture.

The executed fixture has twenty-six explicit allocas and no hidden memdup, malloc, dynamic-array allocation or fixed-index helper. Its 11 FD slots cover nine aliases plus the pipe/socket writers; nine State slots and five-category Counts use fixed storage. The slab parser bounds 32 rows and a 4 KiB terminated buffer. C pointer borrows are synchronous except the Worker passed to pthread_create: that frame remains live until release/join, with fatal failure paths terminating the cohort before any unsafe unwind. Forked children have their own copied frames. Successful child protocols close both pipe directions and wait for each child; nested PID-namespace counts cross pipes by value. Cohorts are waited for before final data/queued-byte checks, closing all eleven FDs and unlinking the file. Temporary retention aliases close even after a reset/check failure; the observer closes through defer. Setup/fatal failures rely on process/guest teardown for residual FDs and paths. The reference wrapper retains its three-entry argv through synchronous execv.

A completed earlier x86 Linux reference reported one root kind-2 failure because successful pthread_join can precede PID detachment. A later independent cached /proc/self/task/TID/stat predicate passed on Linux but stopped both native baselines and candidates: existing task children are not refreshed on every direct lookup. That separate procfs limitation remains open. The final fixture establishes live membership after launch and, after successful join, waits for absence in fresh /proc/self/task getdents64 snapshots before zero-owner/ESRCH checks. task_snapshot has bounded 64-byte decimal-name and 4 KiB record buffers, validates the header/reclen/NUL before strcmp, requires EOF within 32 blocks, and closes every opened directory. task_entry attempts at most 1,000 independent snapshots and never polls an owner getter. This is an observed bounded task-list settling condition, not a universal PID-detach barrier: Vinix removes a thread from its process list before clearing its table slot and a busy thread-list lock can report only the main thread. Exact exit races remain unqualified. The earlier profiles remain diagnostics.

The preview and both executed native fixture C files are byte-identical on each architecture. Separately compiled preflight C differs in stderr scaffolding: it adds v3_eprint_begin/end and v3_eprintf around v3_eprint_lit/v3_eprintln_string, while native C uses direct fprintf. No probe function differs in the raw diff. This C drift is retained and separately pinned, without normalization or replacing native previews. Despite that separate C emission, preflight, native baseline/candidate and actual Linux probe ELF bytes are identical per architecture.

Raw allocation-scanner seed counts change from 659 ARM/655 x86 source files before to 1,304/1,315 after: the preserved obj-persistent/vsrc copy is traversed because GNUmakefile excludes only obj/*. Allocation-site totals remain 400/292, and the NEW allowance rows are identical; the complete production-C scope check also remains exact. Both raw logs are separately pinned. The added staged source files limit the dry-run seed inventory comparison, and existing allowance failures remain; this is not a globally passing allocation allowance audit.

Each root or UID/GID 1000 cohort executes [405, 135, 135, 225, 315] controls: 1,215 per cohort and 2,430 per architecture. Baseline failure categories are [135, 105, 120, 150, 135], totaling 1,290 per architecture. The controls compare libc and raw extended/scalar getters, upper descriptor/command words, aliases, live main/non-main task-kind attachment, reaped process/joined thread, group leader/member lifetime and inner/outer PID-namespace mapping. Both native candidates and both actual Linux references execute identical per-architecture native ELF bytes. Native retention checks run 32 warmups plus 200 measured cycles per credential, with 13-second settling on either side; all 18 ARM and 14 x86 slab classes stay flat, as do measured large pages (arm: root 72/72, UID/GID 1000 72/72; x86: root 185/185, UID/GID 1000 185/185). These observations qualify the exercised sequence.

Qualification covers bounded native ELF64 musl/raw getter task-kind/liveness and PID-namespace behavior. Retained PID identity across recycling, exact simultaneous target-exit races, arbitrary concurrent configuration/descriptor mutation, owner credentials/security policy, actual SIGIO delivery, GNU libc wrappers, deeper nested namespaces and foreign/translated/ELF32 paths remain unqualified. Three broad roadmap gates remain open.

SHA-256 pins were computed independently after all producers completed; common rows require exact byte identity.

| File | SHA-256 |
| --- | --- |
| `kernel/file/file.v`, `kernel-arm/kernel/file/file.v`, `kernel-x86/kernel/file/file.v` | `80479a301e9c072e08f0ab99ad50875b3d0b0d667a1e8778d7f277940d128eb2` |
| `kernel/proc/pidns.v`, `kernel-arm/kernel/proc/pidns.v`, `kernel-x86/kernel/proc/pidns.v` | `9e2b8f30e0da4c390145bd4afe9987b191b6437ea02380b26648dad1c0e66e07` |
| `kernel/syscall/table/linux_common.v`, `kernel-arm/kernel/syscall/table/linux_common.v`, `kernel-x86/kernel/syscall/table/linux_common.v` | `e02ca1595fcc117e237c44cfd5634218184c328592f9e4fcb82af3be15047f68` |
| `tests/linux-compat/ownerqueryfixture/core.v` | `cba64566fdb9dfbdcd93e22e7b9ae24245b7bfd29e4c6cdbf12479e6129fe64a` |
| `tests/linux-compat/ownerquery-reference.v` | `7ef90777d64db969571aef6bfd7b7ada0de2464a93a8b9a165af9d582b30fc21` |
| `tests/linux-compat/ownerqueryreferenceinit/core.v` | `10dc51b14d860049e3fae86ce5c88b2dcefa1c2b2a8ad1edf9842f9b6c7e2ad5` |
| `tests/linux-compat/run.v` | `b00110e9ca2f5c531c64d9e00d81ae65cd3c4bb24609b57be904675ee96282e8` |
| `allocs-before.log` | `d6743dae52e54766573a62069eade227794097f31f02807d2d02d16048d407c7` |
| `allocs-after.log` | `5276697186a422ef5368bb1e1f8d5840faaf4fe66c1efab871e39998616b38d6` |
| `host-tests.log` | `c9c412b947e20327b8c9eb537bb737ab64764e329a5b9d6912b60370f7c007aa` |
| `preview-arm.c`, `settled-before-arm/ownerquery/fixture.c`, `settled-after-arm/ownerquery/fixture.c` | `4c1ec2c6ed839c622178d7f3e7292920550eb688e7cdae3e44825410360f704a` |
| `preflight-settled-arm/fixture.c` | `8856f540d4ebcba44182d7f0b65b8b7bd73c8d61515c849904a04b2eea9c3293` |
| `preflight-settled-arm/init`, `settled-before-arm/ownerquery/init`, `settled-after-arm/ownerquery/init`, `settled-reference-arm/probe` | `1191aa709f4f35490a00fef24aed741f52f9f07a8e9383632c59e604f69d03b0` |
| `tests/linux-compat/ownerqueryfixture/core.v`, `settled-before-arm/sources/ownerqueryfixture/core.v`, `settled-after-arm/sources/ownerqueryfixture/core.v` | `cba64566fdb9dfbdcd93e22e7b9ae24245b7bfd29e4c6cdbf12479e6129fe64a` |
| `before-arm.c` | `d518624733f64f565255b87076b6d970e8cc83e2e351b305c5f152d2861f7127` |
| `kernel-arm/kernel/obj/blob.c` | `ccb2be1132cd7d5236cfebbbd8431e3cd9dc5d86964539c797c3ee96c3431d73` |
| `baseline-arm/kernel/bin/vinix`, `settled-before-arm/kernel/bin/vinix` | `39d2fad9396a856f9080e3c655271c1aeeacc8a5697363fdb2fffeb852b5d3c7` |
| `kernel-arm/kernel/bin/vinix`, `settled-after-arm/kernel/bin/vinix` | `7fc235f35ff23b615563e629f191dc52837304fafac5e39ff58294deaf2795cb` |
| `build-before-arm.log` | `47a3bb07dd8af8a8ddb24a991d46b387bd5abf476002b91b800fbf2db72fe383` |
| `build-after-arm.log` | `f725a183a86ec1ec452cb62183fbafb725dd9dcd77c808848f31265550b6e192` |
| `settled-before-arm/ownerquery/serial.log` | `0a51b91082f63587acd21c9ffafb5083654024d9c034c1e3e7348cf39d161656` |
| `settled-before-arm/receipt.json` | `65e004e43ec5298f5c33a537c99a5b39c7ac92e6d68120da45d3432752c5ca2e` |
| `settled-after-arm/ownerquery/serial.log` | `7c50999a6e32b961936dae7389fca2d3b280d71c9a9c8d28619ea4f52c88cd50` |
| `settled-after-arm/receipt.json` | `2954f8c9869ba7895b106cb132787437adb94d2986b451faec1369fb3df717f5` |
| `settled-reference-arm/fixture.c` | `53fab3dd5ab9e8e674e843c6435b06232f3022489febb1e80f475c8b4d3f35a5` |
| `settled-reference-arm/init` | `bf0316484b6541279636640a716fee784f1cd0aed5bb6d8aeb29c149b1d589a9` |
| `settled-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `settled-reference-arm/serial.log` | `de5b2f9578f3601c5240f290e681e293fee773f8c2f3878a50cb6a1480507c2d` |
| `settled-reference-arm/receipt.json` | `088c1ba6d41ea1ee58737f6589a7f4c467ccfa0623d3617cb1fe2ec1e8188f8a` |
| `settled-reference-arm/initramfs.cpio` | `52b85ac86baddcb26b8a8c1795a7af4ea041f58cf715d755bd55b1587486d553` |
| `settled-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `tests/linux-compat/ownerqueryreferenceinit/core.v`, `settled-reference-arm/source/ownerqueryreferenceinit/core.v` | `10dc51b14d860049e3fae86ce5c88b2dcefa1c2b2a8ad1edf9842f9b6c7e2ad5` |
| `preview-x86.c`, `settled-before-x86/ownerquery/fixture.c`, `settled-after-x86/ownerquery/fixture.c` | `4c1ec2c6ed839c622178d7f3e7292920550eb688e7cdae3e44825410360f704a` |
| `preflight-settled-x86/fixture.c` | `8856f540d4ebcba44182d7f0b65b8b7bd73c8d61515c849904a04b2eea9c3293` |
| `preflight-settled-x86/init`, `settled-before-x86/ownerquery/init`, `settled-after-x86/ownerquery/init`, `settled-reference-x86/probe` | `8cb5a77652258674a1eb8eab0fe10a68df2d3e84216841885746c17cf4d3d1b9` |
| `tests/linux-compat/ownerqueryfixture/core.v`, `settled-before-x86/sources/ownerqueryfixture/core.v`, `settled-after-x86/sources/ownerqueryfixture/core.v` | `cba64566fdb9dfbdcd93e22e7b9ae24245b7bfd29e4c6cdbf12479e6129fe64a` |
| `before-x86.c` | `129e9c9a2ee850d8d471737cfd36940b5d9cbfdfa90ea48b17962657e624dec2` |
| `kernel-x86/kernel/obj/blob.c` | `e5360e140bc3dba30f990e535c7fe9c5722d986ce508d62e1e75049728bd256b` |
| `baseline-x86/kernel/bin/vinix`, `settled-before-x86/kernel/bin/vinix` | `68d687a15529864ce93abde1ceadb0140e975f7a1ec38478baaed00b6e23095c` |
| `kernel-x86/kernel/bin/vinix`, `settled-after-x86/kernel/bin/vinix` | `b74d071578ec15e0deebf3dd8c27e14234db003810bed788048d8ef5ac309c43` |
| `build-before-x86.log` | `e4538e07d86f590824076affc042b45541dff229ed7131a15ce4e3a29ad07047` |
| `build-after-x86.log` | `cf185f289783e7c63ae1dd42c7f2d693e7ef45f4b9b0c27ccdc795e796dd73fa` |
| `settled-before-x86/ownerquery/serial.log` | `8b3453f413e1661cccd35f1c96f05b60a3247c0d9c45b16d868f8b681b29d374` |
| `settled-before-x86/receipt.json` | `f0f083f9525b5209d97339acf22050eef032aee6e3ad7aff5572ea503b6e6df1` |
| `settled-after-x86/ownerquery/serial.log` | `9c6c8b2c6a67f356f86cb6b7265bdfeea746bd6db7808bffcb2e9d4ccfc964d3` |
| `settled-after-x86/receipt.json` | `e0e75a18409ca4f3d7db443aab3b33c52253dddfa396854e73a4906066b49bcb` |
| `settled-reference-x86/fixture.c` | `53fab3dd5ab9e8e674e843c6435b06232f3022489febb1e80f475c8b4d3f35a5` |
| `settled-reference-x86/init` | `35e77cc044d13d4ce0cd42bad2c9bfbd4380b710e59cfdf2665d82b928afd2a9` |
| `settled-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `settled-reference-x86/serial.log` | `a1ca324fc8d62684f74fedfa66facde92e20818dd81365a38a0c64b713e3715b` |
| `settled-reference-x86/receipt.json` | `7e55f219d23f747ee62f4431ba91d9e1d008869babf6c0ac0d174899156b9193` |
| `settled-reference-x86/initramfs.cpio` | `dc987ba350528242b47cd67e15cad23beb3ee3331e5ca0bf975afc36c9bd45b0` |
| `settled-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `tests/linux-compat/ownerqueryreferenceinit/core.v`, `settled-reference-x86/source/ownerqueryreferenceinit/core.v` | `10dc51b14d860049e3fae86ce5c88b2dcefa1c2b2a8ad1edf9842f9b6c7e2ad5` |
| `qualified-reference-x86/probe` | `59bac5dad762df8d3011cee99edc3eac9e5b71bf90e40e610f20d960034468f2` |
| `qualified-reference-x86/serial.log` | `97da0dedcc4f20948407fbae85e11881379c1af4a26948ecc95107ef475c04ef` |
| `qualified-reference-x86/receipt.json` | `aa1c9ff077a0b9fedf494fc3353caadeba0101a9c4625cbaf95adc736cfa595c` |
| `qualified-reference-x86/initramfs.cpio` | `c0596aacaa92d6b50f022276d059db90d1a17650430a26760eac4fadcf11df06` |
