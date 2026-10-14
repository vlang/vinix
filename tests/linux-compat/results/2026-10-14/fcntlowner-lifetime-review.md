Independent fcntlowner lifetime review: PASS

Reviewed the owner command mapping and refusal branches in `kernel/file/file.v`, scalar locked PID-number helper in `kernel/proc/pidns.v`, native fixture and Linux reference wrapper/controller. Frozen baseline revision `6182c530e5bbb6fe7b1cca7db9e4b1c73cbd3106` reproduces the failures on both architectures; both final native candidates and both Linux 6.12.51 references pass. No blocking new lifetime concern was found. The private independent V checker ran without `-prod`, with assertions active and an executed negative assertion control. Paths below are relative to `/Users/alex/.cache/vinix-linux-compat/fcntlowner-20261014`; maintained paths are repository relative.

Correct Linux command numbers select `F_SETOWN=8` and `F_GETOWN=9`. Existing native dispatch imports fd/cmd low words and the F_SETOWN low argument word; pointer arguments remain whole. The new scalar helper acquires pid_lock once and releases it through defer on every return. PID-namespace mapping, process/thread tables and fallback live group/session numbers are read while locked. Process/thread teardown clears those tables under the same lock. No borrowed process or thread leaves the lookup, and no target or namespace reference is acquired, released, retained or transferred. The current running process keeps its numbered_in namespace live. FD lookup drops fds_lock before entering the helper and retains FD/Handle/resource; added EINVAL/ESRCH branches release that FD once. Zero clears without lookup, INT_MIN is refused before negation, and complete extended copy/type/target validation precedes owner-state mutation. No newly allocated object or reclamation path exists. Independently erasing exactly the fcntl/helper prototypes and bodies plus the two changed command defines leaves byte-identical generated C on each architecture; the helper is absent in baseline.

Both executed fixture previews contain sixteen explicit allocas and no memdup, malloc, dynamic-array allocation or fixed-index helper. Descriptor storage has 27 slots, State 28 slots including the reused FD 66 scratch snapshot, Counts five fixed categories; the slab parser bounds 32 rows and a 4 KiB explicitly terminated buffer. Query values, wait status, data buffers and fixed literals are stack values. All C pointer borrows are synchronous. Fork gives each credential cohort its own frame/address space; the parent waits before checking queued bytes/content and closing all 27 descriptors, then removes the regular file/directory. Setup failures return and fatal matrix failures _exit, relying on process teardown for acquired FDs and guest tmpfs teardown for paths. Successful retention cycles close temporary aliases; a final reset failure can short-circuit close and relies on child teardown. The slab observer defer closes on every storage return. The reference wrapper keeps its three-entry argv live until synchronous execv replaces the process or fails.

Each credential cohort executes [630, 315, 189, 2106, 355] counted controls: 3,595 per cohort and 7,190 per architecture. Baseline failure categories are [630, 0, 126, 486, 126], totaling 2,736 per architecture. Direct raw F_GETOWN controls check positive PID results and ignored/upper-word arguments; native libc getters also check zero and negative group values after scalar setter/error controls. Both final native candidates and both actual Linux references pass the same native ELF bytes. Native retention checks run 32 warmups and 200 measured cycles per credential with 13-second settling on each side; all 18 ARM and 14 x86 slab classes stay flat, as do observed large pages (arm: root 70/70, UID/GID 1000 70/70; x86: root 181/181, UID/GID 1000 181/181). These observations qualify the exercised sequence.

Qualification covers bounded native ELF64 musl/raw owner-target refusal and preserved scalar owner state. Actual SIGIO delivery, retained target identity across exit/recycling, owner credentials/security policy, arbitrary concurrent mutation, namespace-aware getters, non-main-thread PID-kind attachment, GNU libc wrappers and foreign/translated/ELF32 paths remain unqualified. Three broad roadmap gates remain open.

SHA-256 pins were computed independently after all producers completed; common rows require exact byte identity.

| File | SHA-256 |
| --- | --- |
| `kernel/file/file.v`, `kernel-arm/kernel/file/file.v`, `kernel-x86/kernel/file/file.v` | `dda05ff0363c72198b61589140074d2d2bbe33b350192c7f851e6a884fd4c192` |
| `kernel/proc/pidns.v`, `kernel-arm/kernel/proc/pidns.v`, `kernel-x86/kernel/proc/pidns.v` | `7915d7739f045406b3fc9e0e09ab722584f72da2ec6ba3c68a3d7c2b60676649` |
| `kernel/syscall/table/linux_common.v`, `kernel-arm/kernel/syscall/table/linux_common.v`, `kernel-x86/kernel/syscall/table/linux_common.v` | `e02ca1595fcc117e237c44cfd5634218184c328592f9e4fcb82af3be15047f68` |
| `tests/linux-compat/fcntlownerfixture/core.v` | `18bc551207da34489364967399e71ba01e45a9b10dc1151c5ea9ee1cb08d83fe` |
| `tests/linux-compat/fcntlowner-reference.v` | `3f68b33ccdfd80c8744568511958f177c9dcf7cc31dfa36e2fc2c212780d6257` |
| `tests/linux-compat/fcntlownerreferenceinit/core.v` | `dc49e080234c6cc09e6d57e1b413a78a4f90fa13e7f59abcb6678badea09199b` |
| `tests/linux-compat/run.v` | `ff854a2f445f9872697fde15abca3056c2ab28d54a3b4733ea62503a0466b1dc` |
| `allocs-before.log` | `d6743dae52e54766573a62069eade227794097f31f02807d2d02d16048d407c7` |
| `allocs-after.log` | `d6743dae52e54766573a62069eade227794097f31f02807d2d02d16048d407c7` |
| `host-tests.log` | `875707ce213a1d55387267a3e5be1ae341bc4f4af55791a842290021bc68fb5f` |
| `preview-arm.c`, `qualified-preflight-arm/fixture.c`, `qualified-before-arm/fcntlowner/fixture.c`, `qualified-after-arm/fcntlowner/fixture.c` | `76725cb508aebf2c38fd47aa8e5a0b024c4e216a86255f4d7ddef71323ccef6c` |
| `qualified-preflight-arm/init`, `qualified-before-arm/fcntlowner/init`, `qualified-after-arm/fcntlowner/init`, `qualified-reference-arm/probe` | `d09524562fef0930eccfac43488c414092aa48b2524f73a99e4500c4dbad72e0` |
| `tests/linux-compat/fcntlownerfixture/core.v`, `qualified-before-arm/sources/fcntlownerfixture/core.v`, `qualified-after-arm/sources/fcntlownerfixture/core.v` | `18bc551207da34489364967399e71ba01e45a9b10dc1151c5ea9ee1cb08d83fe` |
| `before-arm.c` | `484a7e23eb2e5f95f8dc35f88e480d5bdaca9743d048b888521e5831cf274cba` |
| `kernel-arm/kernel/obj/blob.c` | `d518624733f64f565255b87076b6d970e8cc83e2e351b305c5f152d2861f7127` |
| `baseline-arm/kernel/bin/vinix`, `qualified-before-arm/kernel/bin/vinix` | `88a480222c6472ab602ed835c2775ceeb984094f05beabd1afba789f10de1825` |
| `kernel-arm/kernel/bin/vinix`, `qualified-after-arm/kernel/bin/vinix` | `ff1526d99edd1002b7d8cafdc93f52ec66a6929e75ea2aa2c32ca3c7593950ed` |
| `build-before-arm.log` | `0506d8a615adda5c8146bb0b56927d657ce14bd51e3c629ae1885a466fd13cbb` |
| `build-after-arm.log` | `08856565eef566e0293ca3e1b17f2bfe8b262c0a6d1088c9bbf316c501d9fbfc` |
| `qualified-before-arm/fcntlowner/serial.log` | `935a674fc5ec6803dd34288cf0ffe697f6c3395c3a858faea6b0523ba4e2d164` |
| `qualified-before-arm/receipt.json` | `db4ab2ae0051dd91c1963dbf7e1e62846dd2c11eb66228351712d9422fc9a418` |
| `qualified-after-arm/fcntlowner/serial.log` | `c281ab8cabffa926e19576c90f03adc0b7fdce5483ea8f3ec893330ce58141bc` |
| `qualified-after-arm/receipt.json` | `3cd9d480adb8aba1032d70908634925a8d390ea8aadc456d41d135c3f5aae731` |
| `qualified-reference-arm/fixture.c` | `bdf235f183b884402320e74434b4539fe79e62250fd432474128f746ade3311c` |
| `qualified-reference-arm/init` | `712ccacdbe19a3a0dd14ea0111ca9c516aaa6e343e900645f13f6aebfa6a330d` |
| `qualified-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `qualified-reference-arm/serial.log` | `c85c90b8931c2bf9298056545387b1c2996f02fa14e0da745afc76971056bf91` |
| `qualified-reference-arm/receipt.json` | `627a92eca169a2dc955ac7e2f031819a8326e04675225ad2ba28d9a3c415e564` |
| `qualified-reference-arm/initramfs.cpio` | `7b7ccd3ae08ff0d0931873e96b31f525fb82c07790ad932927cf19f0f2e0f4b8` |
| `qualified-reference-arm/serial.c` | `c49ac2e66ea0cd147fbe54a25564b5af26363f8905a8217ad65303d563093cd2` |
| `tests/linux-compat/fcntlownerreferenceinit/core.v`, `qualified-reference-arm/source/fcntlownerreferenceinit/core.v` | `dc49e080234c6cc09e6d57e1b413a78a4f90fa13e7f59abcb6678badea09199b` |
| `preview-x86.c`, `qualified-preflight-x86/fixture.c`, `qualified-before-x86/fcntlowner/fixture.c`, `qualified-after-x86/fcntlowner/fixture.c` | `76725cb508aebf2c38fd47aa8e5a0b024c4e216a86255f4d7ddef71323ccef6c` |
| `qualified-preflight-x86/init`, `qualified-before-x86/fcntlowner/init`, `qualified-after-x86/fcntlowner/init`, `qualified-reference-x86/probe` | `e964db49e5478bafa3001dfb4002633a606bae63abcd167f95ee2c24f324ec07` |
| `tests/linux-compat/fcntlownerfixture/core.v`, `qualified-before-x86/sources/fcntlownerfixture/core.v`, `qualified-after-x86/sources/fcntlownerfixture/core.v` | `18bc551207da34489364967399e71ba01e45a9b10dc1151c5ea9ee1cb08d83fe` |
| `before-x86.c` | `7cbf29482d6566e75d62ce68908032f577c75ca261542a5905e5db005599ab51` |
| `kernel-x86/kernel/obj/blob.c` | `129e9c9a2ee850d8d471737cfd36940b5d9cbfdfa90ea48b17962657e624dec2` |
| `baseline-x86/kernel/bin/vinix`, `qualified-before-x86/kernel/bin/vinix` | `e835fa2e07928ee916b66870af5458cf870e71241b9f5df203f4355704a955c9` |
| `kernel-x86/kernel/bin/vinix`, `qualified-after-x86/kernel/bin/vinix` | `499ff2cb97e2d1acd0c7be757a6d0a49391381717eeca1b3a9d18bbd06f83701` |
| `build-before-x86.log` | `872cc1ed409bed03fce4a921104cf0245e731014b318cd2546a10c8c57dcdec8` |
| `build-after-x86.log` | `740af20b6236655e0781125aaeeaa4c4f4e316c18f641ae3f63a6ffd40cc8aa1` |
| `qualified-before-x86/fcntlowner/serial.log` | `1f221136b795de0fb36b0e9341acbf14e5dfbbd7be1758b12fe079dc688b0b9b` |
| `qualified-before-x86/receipt.json` | `61646c872301cf01e24cc41211ef3e51eff10deaaaa7726d5f59c4db90080dc6` |
| `qualified-after-x86/fcntlowner/serial.log` | `ae0d8c52da56405e97f015fd8840c7831e18ee721a514426eca994941ef7a4da` |
| `qualified-after-x86/receipt.json` | `a8befcc09e3990fdcd097b0ba4b1a89649430e79d330f9c293840fdee942436e` |
| `qualified-reference-x86/fixture.c` | `bdf235f183b884402320e74434b4539fe79e62250fd432474128f746ade3311c` |
| `qualified-reference-x86/init` | `0d348772a1928825b3643dfd50872efbc51753b1061b8f262927976bfc9eb15d` |
| `qualified-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `qualified-reference-x86/serial.log` | `67e7ca630b19ba22cf71e55eff439ca3295a08b9b171c6854e7c2a56e81755c6` |
| `qualified-reference-x86/receipt.json` | `25fc7900ba5fffb5ab1c46e4747f5e6f10698cd6587e81aabb09d754aef30dbd` |
| `qualified-reference-x86/initramfs.cpio` | `9f2f0613e4a7b9dc1b739afbd4f451353966019c6153039446eaa4783d2340c6` |
| `qualified-reference-x86/serial.c` | `f32deebe2af4585e8ba8b413f3623c0e7627bf67412e081c533d8bdc18e2bd16` |
| `tests/linux-compat/fcntlownerreferenceinit/core.v`, `qualified-reference-x86/source/fcntlownerreferenceinit/core.v` | `dc49e080234c6cc09e6d57e1b413a78a4f90fa13e7f59abcb6678badea09199b` |
