Independent procpid lifetime review: PASS

Reviewed the cached numeric procfs process-root invalidation in `kernel/fs/procfs.v`, unchanged scalar attachment/drop helpers, native V fixture and Linux reference wrapper/controller. Frozen baseline `a51d6a215d91fe47b84e1d544487f7e62ec1e759` reproduces 360 cache failures in 2,592 controls per architecture; both final native candidates and actual Linux 6.12.51 references pass. The independent V checker compiled without `-prod` and executed negative assertion and passing-reference-as-failing-baseline controls. Production C and runtime files were consumed only after their producers completed. Kernel/build paths below are relative to `/Users/alex/.cache/vinix-linux-compat/procpid-20261014`; profile/preflight paths were read from `/Users/alex/.cache/vinix-linux-compat/procpid-20261014/states`.

The new branch requires a PID-zero procfs root (registered initial root or namespace view), a nonempty digit-leading name already in its children map, and a real ProcFSResource directory child with a positive stored kernel PID and tid 0. Root PID names are generated from the view's visible numbers; the check uses the child's stored kernel number rather than parsing a namespace-local name as a global PID. Dot entries and static PID-zero resources do not drop. The child pointer is copied from map_get while procfs_lock protects map storage, and no map-value storage pointer escapes. Completed production C confirms the name-length test short-circuits before both string__at(name,0) calls. The inherited children map clones string keys separately, so map deletion frees its key copy while retaining VFSNode.name.

task_attached(pid,pid) takes pid_lock, tests Process-table presence and returns only bool, preserving process-main visibility while a zombie remains registered. It releases pid_lock before drop_procfs_directory deletes the child name and drops its resource reference. Existing procfs_lock → pid_lock order is unchanged; the directory-release callback reachable from free_pid only atomically updates a node timestamp. The unchanged drop helper clears magic_target, deletes the child name, adjusts parent/child link counts and unref(nil)s the resource once under procfs_lock. ProcFSResource.unref(nil) only decrements refcount; nodes/resources/subtrees remain physically retained for open descriptors, cwd/root users, mount routes and concurrent path walkers, even at zero refcount. No new process/thread borrow, pin, helper, field/layout, orphan/removed/retired flag or reclamation is introduced. Erasing exactly the changed lookup body and its prototype leaves byte-identical complete production C on both architectures; scalar/drop/unref helpers also remain byte-identical. No new allocation/free/pin call appears in the changed C body.

The fixture has nineteen explicit allocas and no hidden memdup, malloc, dynamic-array allocation or fixed-index helper in its preview C. Counts, Bank, Child, Slabs and path buffers have fixed storage. C borrows are synchronous; each fork has its own copied frame and child protocol branches terminate with _exit before returning it. Parent Child frames hold scalar PID/FD values and survive release, WNOWAIT zombie observation and reap. Fatal setup/protocol paths terminate the process; successful cohorts close both child-gate directions, wait for both children, transfer Counts by value to the top parent, and close all 9 root plus 18 held descriptor aliases after metadata checks. Query/special FDs close on success or mismatch; temporary cycle aliases close on failure and the slab observer closes through defer. Identity structs are initialized before form comparisons. Setup failures rely on process/guest teardown for residual FDs/mounts. The reference wrapper keeps its three-entry argv alive through synchronous execv.

Before declaring a retired PID absent, the fixture requires successful waitpid with exit status 0 and independently checks kill(PID,0) returns ESRCH. It does not use procfs to establish reaping. Each root/UID-GID-1000 × initial/one-level-PID-namespace cohort runs [135,45,90,180,90,108] controls (648 per cohort, 2,592 per architecture); baseline failures are [0,0,90,0,0,0] in every cohort (360 per architecture). Controls cover cached live/zombie/reaped PID roots and stat/status leaves, surviving processes, 0/INT_MAX missing numbers, dot/dotdot/self/thread-self/sys/version entries, three proc mounts, libc/raw high-word opens and all descriptor aliases. Preflight, preview, baseline and candidate probe C are byte-identical, as are preflight/baseline/candidate/actual-Linux native musl ELF bytes per architecture.

Native retention checks prime a finite live/retired process set, then run 32 warmups and 200 measured lookup/alias cycles per cohort with 13-second settling around snapshots. All 18 ARM and 14 x86 slab classes and measured large pages remain flat (arm [ordinary=0, namespace=0: 74/74; ordinary=1, namespace=0: 74/74; ordinary=0, namespace=1: 80/80; ordinary=1, namespace=1: 80/80]; x86 [ordinary=0, namespace=0: 188/188; ordinary=1, namespace=0: 188/188; ordinary=0, namespace=1: 199/199; ordinary=1, namespace=1: 199/199]). Existing retained procfs-node, namespace-view/mount and dynamic process/task-churn reclamation is not changed or qualified; retained allocations remain. Exact concurrent lookup/reap races, numeric PID reuse, arbitrary descriptor/mount mutation, deeper namespaces, GNU libc and foreign/translated/ELF32 paths remain unqualified. This qualifies fresh opens and retained descriptor inode/mode/FD flags, not stat/status contents, reads through retired files, link-count semantics or cwd conformance. Cwd lifetime safety is reviewed from unchanged retained nodes. Three broad roadmap gates remain open.

SHA-256 pins were computed independently after all producers completed; common rows require exact byte identity.

| File | SHA-256 |
| --- | --- |
| `kernel/fs/procfs.v`, `kernel-arm/kernel/fs/procfs.v`, `kernel-x86/kernel/fs/procfs.v` | `b924f6eee11e596e4abdeaf1816421ed0c2964956f9a75b1c34a3d60fe6ccb86` |
| `kernel/proc/pidns.v`, `kernel-arm/kernel/proc/pidns.v`, `kernel-x86/kernel/proc/pidns.v` | `45b6d1038abd9f0e7fd63690f4466e6329e4ead34d3172a4076e70494ed39870` |
| `kernel/syscall/table/linux_common.v`, `kernel-arm/kernel/syscall/table/linux_common.v`, `kernel-x86/kernel/syscall/table/linux_common.v` | `e02ca1595fcc117e237c44cfd5634218184c328592f9e4fcb82af3be15047f68` |
| `tests/linux-compat/procpidfixture/core.v` | `0a7d69aa79b28ff8e28dd7d5bdefcc52bba8d9e4aadb424bbd865fb3a347efba` |
| `tests/linux-compat/procpid-reference.v` | `845e7935999e1babd578957fdcf2294df9ef328e4486cefffe4af12c425ec476` |
| `tests/linux-compat/procpidreferenceinit/core.v` | `7cb75bcbd93cd6d0086211fa009f7c58bd713118f9704171550182fa7ba7c3db` |
| `tests/linux-compat/run.v` | `980bd0a0053589e47758a54c12710d88fe0a93f6fd31b3d858f22764c5eaa0f3` |
| `host-tests.log` | `35bd84dba468fed5159d4c3693af5e4554e1f31b0cf015313c4bb2e456e9b97b` |
| `allocs-before.log` | `8d960ff042a5f570100935179b42514f0d8bba87e9a6409ed71c50ba362cfe2d` |
| `allocs-after.log` | `cd2e17d150475087308ad061f57ebaa22e7d34cf177ee080578a28fcceef72b8` |
| `scope-check.log` | `904c6d2ee5f5128d2dc6aa2fa0935cac54bba4ef53f6762ac71e5e34b1cb61bc` |
| `independent-review.v` | `b77a7edde75ac1c8be2178b2c3c156d020d1e7bffd5309b0c297b785ab7c4f47` |
| `/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v` | `9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b` |
| `preview-arm.c`, `preflight-procpid-arm/fixture.c`, `final-procpid-before-arm/procpid/fixture.c`, `final-procpid-after-arm/procpid/fixture.c` | `e8bfab01df0eaaf6c753215a7ea651cdb6b3486f652a79cdc0b5f2ab91c271ec` |
| `preflight-procpid-arm/init`, `final-procpid-before-arm/procpid/init`, `final-procpid-after-arm/procpid/init`, `final-procpid-reference-arm/probe` | `5079f2675fd725c4ae05891dbdd42617fe534660a26ac87a6ca20179cd7c479a` |
| `tests/linux-compat/procpidfixture/core.v`, `final-procpid-before-arm/sources/procpidfixture/core.v`, `final-procpid-after-arm/sources/procpidfixture/core.v` | `0a7d69aa79b28ff8e28dd7d5bdefcc52bba8d9e4aadb424bbd865fb3a347efba` |
| `before-arm.c` | `1f11d280b81794322468e7b3f23f0da969becc1f41cc2884d1d70394fd507313` |
| `kernel-arm/kernel/obj/blob.c` | `0735d7ccaf97ca684c17b9f2c6ea2c8d2c793a969adea8769375974e4248af4a` |
| `baseline-arm/kernel/bin/vinix`, `final-procpid-before-arm/kernel/bin/vinix` | `c1d73c9b947825febef6c73605c1dd01b62f606d8ad00fdd4ca8aeb8d26cb10a` |
| `kernel-arm/kernel/bin/vinix`, `final-procpid-after-arm/kernel/bin/vinix` | `c5ad9b83cdbef4b4dca92b6c3ee35e219168a1c2cf15f2d7af6db49ee28b3620` |
| `build-before-arm.log` | `794bded55fe7e6540562864b85b15205ba54fb71b8f5d365109cb411d7f69b06` |
| `build-after-arm.log` | `b47fd17a84710dc7e6e77df8cfa3cfadb6fad8e94522bf437ce9ffb1610161f1` |
| `final-procpid-before-arm/procpid/serial.log` | `e1c61cc08e229d25dd8fd9e526788c603f3a27928a48bf16a605e90474332114` |
| `final-procpid-before-arm/receipt.json` | `a856a9561212a664439e9825d2870b822d429abdfbe334439e67fe908dbe398b` |
| `final-procpid-after-arm/procpid/serial.log` | `355eb70eafc5f112042e75de4b4a605006b4f9b372a8e1f50cf2e561539c95c7` |
| `final-procpid-after-arm/receipt.json` | `d59d0155bad3e1d95828436d44f7efcc1ae24c75b75dbe68a67f612ae5c8daee` |
| `final-procpid-reference-arm/fixture.c` | `7740abf79735240588185a33a03e96e8f9cb3a3d2a1984825f7bb833b019169a` |
| `final-procpid-reference-arm/init` | `6d6a52940e5ef64548fc48922061a34fc295ba0f09b1018352a945377a796149` |
| `final-procpid-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `final-procpid-reference-arm/serial.log` | `ab0bcf71505a051a505d6d74ac1463173c813ddad311428505ff5ad9e866a925` |
| `final-procpid-reference-arm/receipt.json` | `4c1f6caa0e5c5cd12c137d8fe7a0466b615f396ed1cb962d379a2b4f9ca67a09` |
| `final-procpid-reference-arm/initramfs.cpio` | `7d69d269e33425b528b1b6ffaa33e4366b7b6788a84cdf12728d12176728a41b` |
| `final-procpid-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `tests/linux-compat/procpidreferenceinit/core.v`, `final-procpid-reference-arm/source/procpidreferenceinit/core.v` | `7cb75bcbd93cd6d0086211fa009f7c58bd713118f9704171550182fa7ba7c3db` |
| `preview-x86.c`, `preflight-procpid-x86/fixture.c`, `final-procpid-before-x86/procpid/fixture.c`, `final-procpid-after-x86/procpid/fixture.c` | `e8bfab01df0eaaf6c753215a7ea651cdb6b3486f652a79cdc0b5f2ab91c271ec` |
| `preflight-procpid-x86/init`, `final-procpid-before-x86/procpid/init`, `final-procpid-after-x86/procpid/init`, `final-procpid-reference-x86/probe` | `35a1ef7e62fc82f259a0bf3d3e6dcee715de103223c74648714a01882cbccb6e` |
| `tests/linux-compat/procpidfixture/core.v`, `final-procpid-before-x86/sources/procpidfixture/core.v`, `final-procpid-after-x86/sources/procpidfixture/core.v` | `0a7d69aa79b28ff8e28dd7d5bdefcc52bba8d9e4aadb424bbd865fb3a347efba` |
| `before-x86.c` | `3ec9d14f94566e4732a03478261267299389c9fd0376b70fd36a1fdda8f2ed8c` |
| `kernel-x86/kernel/obj/blob.c` | `53c45c34b4706c7bd225131f8c55bb25417b687a20cb9827fd5d78fcc151754c` |
| `baseline-x86/kernel/bin/vinix`, `final-procpid-before-x86/kernel/bin/vinix` | `9ef6decfc2bb6c651033374b53046b4556c7f4f3b38f0c4671189c0e33b2b7d4` |
| `kernel-x86/kernel/bin/vinix`, `final-procpid-after-x86/kernel/bin/vinix` | `976924ddf0a094dc5e0e9276ac5a83cd99a141f0c5f47e157eafb9a551250cb1` |
| `build-before-x86.log` | `68b2a45633777e199b47a68c97ce56239b5c52299e604d03392d0b76081e0780` |
| `build-after-x86.log` | `e9d5d2a223fcc22cba181055a7f4b1dd77eb660883f9436ea7a25e7076482a60` |
| `final-procpid-before-x86/procpid/serial.log` | `49cc2818eaade7053365afc3df0f5993138ad9545be85c4103ed0c9511ecdcdd` |
| `final-procpid-before-x86/receipt.json` | `a721e122d7d65d4e23919e60d40ca7625d24304f5c70a3518ef9d35c9f6cfe54` |
| `final-procpid-after-x86/procpid/serial.log` | `c8154d6d9c983e770a3be21b97522573578d554b30005b43fbbb8d1fc712c836` |
| `final-procpid-after-x86/receipt.json` | `e99676a07a0c9808a3b1b13a2395760cabcde176d8f365fb2035a4a32eab649f` |
| `final-procpid-reference-x86/fixture.c` | `7740abf79735240588185a33a03e96e8f9cb3a3d2a1984825f7bb833b019169a` |
| `final-procpid-reference-x86/init` | `140b07a3981b0c8dd89f50f562e7c33ddc319edd3b9527b34a5a1214ef4fc1e3` |
| `final-procpid-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `final-procpid-reference-x86/serial.log` | `b10e805c9c64e1c83ec7992cff1644827ea4b95f897920e304e667f60684d4f2` |
| `final-procpid-reference-x86/receipt.json` | `6b5e76311268627c1a89da8e99f306860abb3f067dd5df7de2ae58a4bd44822e` |
| `final-procpid-reference-x86/initramfs.cpio` | `c8072f79a8fb0e91403055fdfca1fb0be211d2d02d62e4426dd78eae699c52b3` |
| `final-procpid-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `tests/linux-compat/procpidreferenceinit/core.v`, `final-procpid-reference-x86/source/procpidreferenceinit/core.v` | `7cb75bcbd93cd6d0086211fa009f7c58bd713118f9704171550182fa7ba7c3db` |
