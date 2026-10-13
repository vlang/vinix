Independent statabi lifetime review: PASS

Reviewed the native `fstat`/`newfstatat` changes in `linux_common.v`, `linux_table_amd64.v` and `syscall_table_arm64.v`, the probe and reference wrapper sources, both generated kernel C files, final emitted fixture C, and completed native/Linux reference captures. This independent review changed only this report and found no blocking lifetime or lock-order concern.

The isolated artifact directory is `/Users/alex/.cache/vinix-linux-compat/statabi-20261013`. Its recorded baseline is `8fc078a86a6cd540c80ef667d9335afaf7c0230e`. Root kernel sources match their isolated candidate copies. The final scope proof restores the complete baseline generated C on both architectures by replacing only the two native stat adapter bodies and removing the shared helper declaration/body, after normalizing unused-loop symbol offsets. Existing stat layouts, converters, `statx` and VFS implementations remain identical in that comparison.

The adapters narrow descriptor arguments to the lower 32 bits. The shared helper validates the lower 32 flag bits before path lookup or output copying, accepts the native `fstatat` sync bits including their combination, and routes a NULL path through `fstat` only for a nonnegative lower-word descriptor and exactly `AT_EMPTY_PATH`. Other valid spellings use the existing `fstatat` path. The helper introduces no allocation, ownership transfer, retained pointer or lock acquisition.

Each adapter's existing `vinix_stack_alloc` stat scratch remains alive through synchronous filesystem filling and checked conversion/copy. The scratch contains a value copy, not a retained resource pointer. `fd_from_fdnum` takes paired FD/Handle references under the descriptor-table lock; the existing `fstat` defer releases them after copying metadata, including its MAC-error return. The existing empty-path `fstatat` branch likewise releases its retained descriptor on both success and MAC failure. Neither converter keeps the scratch pointer or copies output after a metadata error. This fix adds no nested locking or new reclamation.

The probe uses the actual C `struct stat` size and stack guards around each ordinary output. Successful probes compare selected metadata fields; failed probes require untouched output and guard bytes. Explicit stack buffers and counters are borrowed only by synchronous calls. Both final preview C files match the actual native fixture C byte for byte and have no heap promotion or dynamic-array allocation sites. The reference wrapper's three-pointer argv is explicit stack storage borrowed by synchronous `execv`.

Successful descriptor opens have cleanup on returning paths, the slab observer closes on every storage return, and successful fork controls wait for each child before checking the shared cursor/data. A wait failure marks the run failed. Child process exit releases inherited descriptors. A successful parent deliberately pauses with its stable test descriptors until the controller stops the guest; the PASS marker does not claim those parent descriptors have already closed. The same native probe ELF, verified byte for byte, runs on actual Linux 6.12.51 with `--reference`; that mode skips Vinix slab accounting.

Every row below ran separately as root and as UID/GID 1000 with supplementary groups cleared. All candidate and Linux-reference calls passed.

| Probe kind | AArch64 calls per credential | x86-64 calls per credential | Baseline failures per credential, each architecture |
| --- | ---: | ---: | ---: |
| Raw fstat | 54 | 54 | 24 |
| Valid fstatat | 348 | 348 | 140 |
| Flag validation and NULL mixtures | 1152 | 1152 | 972 |
| Error precedence and legacy controls | 96 | 132 | 9 |
| Musl wrappers | 12 | 12 | 1 |
| Total | 1662 | 1698 | 1146 |

The final native and reference totals are 3324 AArch64 calls and 3396 x86-64 calls, each with zero failures. Both baseline captures reproduce 2292 failures. Native retention checks use 32 warmup cycles, settling, then 200 cycles of 21 stat/error operations each and another settling interval, with the same observer FD before and after. All 18 AArch64 slab classes and all 14 x86-64 classes are flat in both credential groups; large-allocation pages remain 63/63 and 160/160 respectively. Both completed candidate aggregates and receipts report PASS for `statabi`, `statx`, `open` and `runtime`.

Qualification is limited to the exercised native musl ELF64 paths and metadata/error/output controls. It does not qualify translated or 32-bit ABIs, all glibc behavior, every filesystem or concurrent MAC/metadata mutation, or partial user-copy fault behavior across page boundaries. The flat-retention result applies to the measured operation set, not every kernel workload.

SHA-256 pins below use repository-relative source paths and artifact-directory-relative build/capture paths. Shared rows list files independently compared as identical.

| File | SHA-256 |
| --- | --- |
| `kernel/syscall/table/linux_common.v` | `b7d14581ccff941615521e56210e17b9f80b0c04fc22c505ee626e0c389a4cc4` |
| `kernel/syscall/table/linux_table_amd64.v` | `74f93df973a7346ddccf9ce191c7848621efc8f39de6c390af0cef6569702b35` |
| `kernel/syscall/table/syscall_table_arm64.v` | `3effd471be9ebcc88ca7b2e312e3d12c086be5841f4fc305a9ed753b252c8476` |
| `tests/linux-compat/statabifixture/core.v` | `467c23ba0f1b1a4f6e36c88aec01834e17785a703df9682b44cae8270dc6bdd5` |
| `tests/linux-compat/statabireferenceinit/core.v` | `75dbfb4f06779923066fa2286022eb91e3fd3554fdcd93f1e7e4c7ca99cad193` |
| `before-arm.c` | `85e918ba071b9a68140b540722e94af8a9554fd516bd07c1bb3693399f251b57` |
| `before-x86.c` | `f0fe4029d0b09a5d3988cf2c1aa030cf33ac1bd93eecce41805d763cf7d1f574` |
| `kernel-arm/kernel/obj/blob.c` | `7e4aad677947b8360541d0dbbd606e3c8695d1cc2f7a7e9388f373571f705832` |
| `kernel-x86/kernel/obj/blob.c` | `2cbf9a09674893cc5d2c5f01fc10264a79d3dedeb9df049f691fd634fa62efe9` |
| `final-preview-arm.c`, `final-after-arm/statabi/fixture.c` | `064711d8fe9fa1ad155d634034375e40b89c5b1cd0efce08dd0373abcdec712a` |
| `final-preview-x86.c`, `final-after-x86/statabi/fixture.c` | `d5788af51c2c8890e7b61076418ff3c1cbef7c8b0460beecb9523b68d1c28f47` |
| `final-reference-arm/fixture.c`, `final-reference-x86/fixture.c` | `74ae3fe6e24f44197eb6c68ce8f6d0b079d22f1ca107c87a1d5fc1b83e0eb555` |
| `final-before-arm/statabi/serial.log` | `508aa487e43fa370069906c43629ef9be63435e714ffef196dcd728b34913fcc` |
| `final-before-x86/statabi/serial.log` | `2a41eeefd7200fde7246e9efc5851a0f614305c59bebc9848682cc900139ba70` |
| `final-after-arm/statabi/serial.log` | `cfa6c9675be914ebb1df1faf629cd18d0963c38a4f3ef40fb3cc4cd2d64ed41c` |
| `final-after-x86/statabi/serial.log` | `8c0ed243a5d17c46187b1c7745a5d4afe2e1b89a1311b088a9db85670f6f63d6` |
| `final-reference-arm/serial.log` | `f7beddfcd289c903a6642c0546b74d553048cf212ff22c1659208a4a82da60b6` |
| `final-reference-x86/serial.log` | `86acc33dbfcee63c9461444001366a368ba3ec97a86aee8732e350d350c3d427` |
| `final-after-arm/statabi/init`, `final-reference-arm/probe` | `66163106c2ecf5288de964899b3272f9046dc4c57cba948d3ba510fa5bb11233` |
| `final-after-x86/statabi/init`, `final-reference-x86/probe` | `105a50fb5d8c04f3e26e87b86c0864e7d1910dc1bd2917b9d28541dfa73b5bd3` |
| `final-after-arm.log` | `0b67b20370c21178cf7da76c173f93bc0bd482107efef0788fa05e2760049206` |
| `final-after-x86.log` | `0b93da3459b92829fc32d8fe453591cae811bad4ca1e219ffeaa2d25f2e86ea2` |
| `final-after-arm/receipt.json` | `521fc62183eb51dc277a25690b56e6552f9b9f4a7e4b3127a3a4ba79e0d03ea0` |
| `final-after-x86/receipt.json` | `9efb72b06d39944bbe92da709adab333271a7a7bc79e169ea2b7e183c594f27b` |
| `scope-check.log` | `f7ec630efa2d7b4903b87ceda2006fae1c31e7d0181b3eccdaef41da44b9a7ad` |
| `scope.v` | `dcd3fd74bd7135b581659f5d9052b94652cd2a34c035d967fd647cd76e05b851` |
