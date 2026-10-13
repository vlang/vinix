Independent dupabi lifetime review: PASS

Reviewed the native duplication adapters in `linux_common.v`, `linux_table_amd64.v` and `syscall_table_arm64.v`, the probe/reference wrapper sources, both emitted kernel C files and fixture previews, and the completed native and Linux-reference captures. This review changed only this report. There is no blocking new lifetime or lock-order concern in the scoped fix.

Artifacts are in `/Users/alex/.cache/vinix-linux-compat/dupabi-20261013`, with recorded baseline `35f1a52fac949a772a5e331b6f3b8cd0b59376ee`. The reviewed root kernel sources match the isolated candidates. The whole-C scope proof restores the baseline by replacing the native duplication adapter bodies, removing the new dup3 adapter declaration/body and restoring one dup3 dispatch entry per architecture, with only unused-loop symbol offsets normalized. Generic descriptor duplication, ownership/publication, fcntl and native stat bodies remain identical in that comparison.

The dup and x86-64 dup2 adapters use the lower 32 descriptor words. Dup2 compares those words before its same-descriptor shortcut; that shortcut takes and releases the existing paired FD/Handle lookup references before returning, without changing flags or cursor. The new dup3 adapter validates lower-word flags against `O_CLOEXEC` before descriptor lookup, retention or target replacement, and then forwards narrowed scalar arguments. It adds no allocation, stored pointer, reclamation or lock acquisition.

The existing `fdnum_dup` retains the source FD and Handle under the table lock, releases that lookup through defer on reservation failure, publication failure and success, and takes a separate Handle reference for the new descriptor. Failed publication releases the new descriptor/reference; successful publication transfers them to the descriptor table. The outer F_DUPFD lookup used by dup is separately released on success and failure. These paired releases are present in both generated kernel C files. The adapter changes introduce no additional nested lock ordering.

The probe's three C stat records are explicit alloca storage borrowed synchronously by fstat and metadata comparisons. Counts and retention snapshots also use explicit stack storage; descriptor arrays, data buffers and snapshot parser scalars remain ordinary stack values in both final previews. There are no memdup, heap promotion or dynamic-array allocation sites in the emitted probe C. The native generated fixture C matches its preview byte for byte. The wrapper borrows an explicit stack argv only through synchronous execv, and its two generated C files are identical.

After successful target seeding, every probe return closes descriptor 63; every nonnegative automatic dup result is closed. Successful cursor mutation is followed by an unconditional restoration attempt before returning. The storage observer closes on each returning path, and temporary storage aliases are closed on successful paths and checked failure paths. The parent cleans up every successfully installed source/seed descriptor on return; fork controls wait for each child, and any failed wait prevents PASS. Child exit releases inherited descriptors. A successful parent pauses with stable test descriptors until the controller stops the VM, so the PASS marker does not imply those parent descriptors have already closed.

Each row below ran separately as root and UID/GID 1000 with supplementary groups cleared. Final native and actual Linux 6.12.51 reference results have zero failures. The reference runs use byte-identical native probe ELFs with `--reference` and omit Vinix retention checks. Final runs include 35 libc controls per credential; retained draft runs with 33 controls are not the qualification evidence.

| Probe kind | AArch64 calls per credential | x86-64 calls per credential | AArch64 baseline failures | x86-64 baseline failures |
| --- | ---: | ---: | ---: | ---: |
| Raw dup | 24 | 24 | 12 | 12 |
| Valid dup3 word combinations | 324 | 324 | 288 | 288 |
| Invalid flags and precedence | 372 | 372 | 279 | 279 |
| Descriptor errors and dup3 equality | 84 | 84 | 30 | 30 |
| Raw dup2 | 0 | 138 | 0 | 96 |
| Libc controls | 35 | 35 | 3 | 3 |
| Total per credential | 839 | 977 | 612 | 708 |

Across both credentials, candidates and Linux references each pass 1678 AArch64 requests and 1954 x86-64 requests. Baselines reproduce 1224 and 1416 failures respectively. Checks cover selected metadata, source/target preservation on refusal, CLOEXEC and status flags, shared cursor mutations/restoration, source/seed bytes and queued pipe bytes. After 32 warmup cycles and settling, 200 measured cycles keep all 18 AArch64 slab classes and all 14 x86-64 classes flat in both credential groups; large pages remain 68/68 and 177/177 respectively. Both four-case aggregate logs finish with `Linux compatibility guest suite: PASS`; complete receipts show zero-status `dupabi`, `statabi`, `open` and `runtime` results.

A preexisting publication hazard remains outside this fix: `fdnum_create_from_fd` publishes the new descriptor and releases the table lock before `fdnum_dup` writes its final flags, without retaining an extra reference to that published descriptor. A concurrent close can race that later pointer write; concurrent fork can observe the copied source flags before the requested flags are finalized. Concurrent dup/close/fork/exec publication is therefore explicitly unqualified. The generated-C scope proof confirms this generic path is unchanged. The approval covers the new adapters and exercised single-thread native musl ELF64 behavior, not translated/32-bit ABIs, all glibc behavior, atomic fork snapshots or every resource/error condition.

SHA-256 pins use repository-relative source paths and artifact-directory-relative build/capture paths. Shared rows were independently compared as identical.

| File | SHA-256 |
| --- | --- |
| `kernel/syscall/table/linux_common.v` | `f835aa0fcc89fa8fe67c3b39a22e412944978a28509e328b566d180eb0d753ed` |
| `kernel/syscall/table/linux_table_amd64.v` | `f2bdc6c68a73e588e4549fa3c04bb81eeb90ce6177954888b1f6b30b17feda7f` |
| `kernel/syscall/table/syscall_table_arm64.v` | `ad9afab1533b8eee415a02c1a54627ba1b78d4d2cab3771f02f35d034249f76f` |
| `tests/linux-compat/dupabifixture/core.v` | `1dde787ee13101903dee2c0ce31c985ca27de9f6ff1c8545587e7d5d39f6cd3d` |
| `tests/linux-compat/dupabireferenceinit/core.v` | `f77eb1d02e6c3c131b1e152a98b30fc59913c20b0fd5bc8d39d9f068da5a5c80` |
| `before-arm.c` | `0b1373eba10691be7b7fac3815487c8049fd66ec2e089bd44974a5a31b190ebe` |
| `before-x86.c` | `8880a5d2ca8afa9a9237bec52241dad4972691d7991ae3896fa92516baea744d` |
| `kernel-arm/kernel/obj/blob.c` | `f7a9cd1a5e91a36ebd55fd4c37d807d5f77e6e174f2c2fb13e82347edd18c202` |
| `kernel-x86/kernel/obj/blob.c` | `fed3796e8fbaeffdd093e69fb6cbdf9627c4d61eecb539f82e2819bf8b5e4e15` |
| `kernel-arm/kernel/bin/vinix` | `40f7dea903998593b0e007604476c0b644acdff939436fd88a49e93310a589f2` |
| `kernel-x86/kernel/bin/vinix` | `814d6c8e89268714237681debdd24b032643606e418f29282d001b8e40aa6fb2` |
| `preview-arm.c`, `final-after-arm/dupabi/fixture.c` | `fab67acc42c3ce87c589b03ec6c536c8120edba15393c6234b922a4afa65d05a` |
| `preview-x86.c`, `final-after-x86/dupabi/fixture.c` | `5bff87060bf70feb90efc5f5fefef2c7f4f6057533ac9ceffeb8633492447f49` |
| `final-reference-arm/fixture.c`, `final-reference-x86/fixture.c` | `bd4fe5e1784f4152f87b0c265fec4b943f684cf32b8fd36c43d93f69cbc1f0c2` |
| `final-reference-arm/init` | `91a1b30b95ff31fdeaab452ad7e2134fe017ef41f00b6ced0cd0797f610e2ca9` |
| `final-reference-x86/init` | `aa1fde943a5e458aa970643fa1a8fc7751ff9ebb1f888a5b255a38df7354fa6a` |
| `final-before-arm/dupabi/serial.log` | `3adaa841d52689bb1bb81e2b26742cd95f31c017f7efb056b78335340686f66a` |
| `final-before-x86/dupabi/serial.log` | `23af74f935d2ab7d8936600058de4604b1f0d61e3643b4096d6016295835bad9` |
| `final-after-arm/dupabi/serial.log` | `0d23674948b1943b4b3a12baac6ee3fdf2d4cd3c8740e60e759946b4a03f81e9` |
| `final-after-x86/dupabi/serial.log` | `049725555a4c21fe65e534ebda598f95e077b728c32bc96da4373ed7b21ae963` |
| `final-reference-arm/serial.log` | `947fb349e9f89b7354d576eb62cc6fd310b5c3e035d8c78d77288b63630ae95e` |
| `final-reference-x86/serial.log` | `deaad4aaa4c2ee90201beb5a8e2549aa89612d86a2ce2ddb3776bd5c9a12e823` |
| `final-after-arm/dupabi/init`, `final-reference-arm/probe` | `d2c8310f9aa8f35fd1cd81f1c17251b406399fb6e5a08883314974e58c73c2f4` |
| `final-after-x86/dupabi/init`, `final-reference-x86/probe` | `9717907cce9e0e7b59e65ba89468a50b3ad9fab51ec9c9c068d0d8e4ae5ac6f4` |
| `final-after-arm.log` | `21267bba6403cb6da7ad640a35d5cddd4063dbb441b674df1a42ce579d1f2fda` |
| `final-after-x86.log` | `59c4ef766f1fb782ddb83cf51da13c429dc5f468f3dea6d6cb4779e017747d93` |
| `final-after-arm/receipt.json` | `403fb5afe98fa7ee634c37cb3b5993598b1a2c2e3dc2a7522cbbb5c6b241142d` |
| `final-after-x86/receipt.json` | `23e347e1225479f2e4957aa16b8b067a0779bc38a77c76182c6b5b6b6fc9a28e` |
| `final-reference-arm/receipt.json` | `48db9d6bb8377731dfd37aa42337b498851ff930a318cd350d718dc4f9c15740` |
| `final-reference-x86/receipt.json` | `7f7bd0df36e32f28e14ebcd6bbc5f7a0c7aa64b9e3f1cdf20faf44c9e091bd43` |
