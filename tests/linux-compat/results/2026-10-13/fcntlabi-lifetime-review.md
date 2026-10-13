Independent fcntlabi lifetime review: PASS

Reviewed the native fcntl adapter and both dispatch changes in the three kernel table sources, final probe/reference wrapper sources, both emitted kernel C files, fixture previews, and complete native/Linux-reference captures. This independent review changed only this report and found no blocking new lifetime or lock-order concern. Artifacts are in `/Users/alex/.cache/vinix-linux-compat/fcntlabi-20261013`; the recorded baseline is `e85df8e5f8086a8d048669e420196bae9b206a72`.

The adapter narrows descriptor and command words to unsigned 32 bits, sign-extends signed 32-bit duplication minima, and narrows the listed int-valued setter arguments. Pointer and unknown arguments remain full width. Invalid F_DUPFD/F_DUPFD_CLOEXEC minima validate the narrowed source through `fd_from_fdnum`; that lookup retains both FD and Handle under the descriptor-table lock. The adapter releases that paired hold before returning scalar EINVAL, with no later pointer use. Failed lookup returns EBADF without acquiring a reference. The executing thread keeps the current process alive during the scalar limit read. The adapter adds no allocation, stored pointer, ownership transfer or nested lock.

Forwarded calls keep the existing generic fcntl and duplication cleanup, including both the outer fcntl lookup and inner duplication source hold. Native dup bypasses the new minimum precheck and retains EMFILE for full/zero limits. Complete generated-C diffs contain only the new adapter declaration/body and one dispatch assignment per architecture. Generic fcntl, descriptor lookup/duplication, publication, native dup/dup3 and lock helper bodies are unchanged. Source and generated C both show exactly one unref on the new successful temporary lookup path.

The probe's State/stat records, canary-wrapped flock Packet, rlimit, descriptor array and retention snapshots use explicit stack storage. Both architecture previews are identical and match the executed native C byte for byte; all 16 allocas are explicit, with no memdup, heap promotion or dynamic-array allocation sites. Synchronous fstat and fcntl pointer calls do not keep fixture pointers. The F_GETLK transport control uses an actual stack address above 4 GiB and checks packet canaries. Query results copy errno immediately before later state checks can change it.

Every nonnegative duplicate result is closed; successful regular-file cursor mutation is followed by an unconditional restoration attempt. Flag/status/signal setters restore saved state, and pressure controls track and close only the slots they temporarily filled after restoring soft limit 128. The same observer FD brackets retention and closes on every storage return. Fork controls wait for each child before final shared cursor/byte checks; failed fork/wait/status prevents PASS. Fatal child setup/restoration errors use `_exit`. Initial main setup errors return nonzero and rely on process-exit descriptor cleanup; normal main flow explicitly closes all test descriptors before its PASS marker. The reference wrapper's stack argv is borrowed only by synchronous execv.

Each row below ran separately as root and UID/GID 1000 with supplementary groups cleared, on both architectures. Candidate and actual Linux 6.12.51 reference results have zero failures. The reference runs use byte-identical native probe ELFs with `--reference` and skip Vinix allocator accounting.

| Probe kind | Calls per credential | Baseline failures per credential |
| --- | ---: | ---: |
| Getters | 324 | 288 |
| Duplication minima and aliases | 2592 | 2136 |
| Descriptor/status/signal/pipe scalar controls | 1350 | 1180 |
| Full-width flock pointer transport | 36 | 32 |
| Descriptor/command/limit errors and libc controls | 162 | 38 |
| Total | 4464 | 3674 |

Candidates and references each pass 8928 calls per architecture; baselines reproduce 7348 failures each. Checks cover selected metadata, alias CLOEXEC and shared cursor behavior, distinct seed 64 preservation, setter refusal state, pointer canaries, source/seed bytes and queued pipe data. Fixed-full-64 and soft-zero controls distinguish native dup EMFILE from fcntl invalid-minimum EINVAL. After 32 warmup cycles and settling, each credential's 200 measured cycles performs two high-word duplicates and four invalid-minimum calls. All 18 AArch64 slab classes and 14 x86-64 classes remain flat; large pages remain 68/68 and 177/177 respectively. Both complete five-case aggregate logs and receipts pass `fcntlabi`, `dupabi`, `duppublish`, `open` and `runtime`.

This approves the new adapter and exercised native musl ELF64 behavior. O_PATH-disallowed commands, complete ownership/sealing/status-flag semantics, dynamic pipe resizing, full lock semantics/concurrency, concurrent RLIMIT changes, GNU wrappers and translated/ELF32 paths remain separate qualifications. Flat retention applies to the measured duplication/error operation set. Failed disk-space builds and earlier setup attempts are diagnostic artifacts, not the qualified final receipts.

SHA-256 pins use repository-relative source paths and artifact-directory-relative build/capture paths. Shared rows were independently compared as identical.

| File | SHA-256 |
| --- | --- |
| `kernel/syscall/table/linux_common.v` | `718a1fd9630e902000792eb110d8a80ca8e2289983764353d2ad248c942ae277` |
| `kernel/syscall/table/linux_table_amd64.v` | `f7e48c44a6152339e2ecb7a668102546a85cff540120109809ce3bd79c3a1bb7` |
| `kernel/syscall/table/syscall_table_arm64.v` | `9e27de44d482ba0581c023f2486b295f16a2f5f8b4d02f7d42d6d9940d637747` |
| `tests/linux-compat/fcntlabifixture/core.v` | `6f70bc290dff8671cbde66025806b7b5d99d82468dc6e7098ec86a27cc43c3ac` |
| `tests/linux-compat/fcntlabireferenceinit/core.v` | `cc780acbbe0eabad41f02bbe093d110c218a7d10c154b85491aad3971d885c5c` |
| `tests/linux-compat/fcntlabi-reference.v` | `3c18092c8025b0f7c60270569338a86aca5945b28f74ac1dd04d175a0501fec7` |
| `before-arm.c` | `7d6bf90617ae3b955c1e16a8a73f8709df9b52a9772f95013e8f20909ac2bcd3` |
| `before-x86.c` | `a9ea5aa549b835d1a0feba747f8cc9104103dfe073708d5b7dbaf151c4f8cb49` |
| `kernel-arm/kernel/obj/blob.c` | `05df84d3139c82b60cbece759c7a00be346cdcd86997f11af5d3b7c71c484883` |
| `kernel-x86/kernel/obj/blob.c` | `04d2e8012287ba1ff1630af718e9a06bf68d5d109c84c7b3f02183ae74c8cec7` |
| `before-arm.kernel` | `5ec94d5b84d064a2580d87213ef68f8211d06c7a78dd7e729cb57fefebe27fd3` |
| `before-x86.kernel` | `f13b02f27a3003a3105b73ad5f35c59c47143e45462b0bf9de9ea4df8a1357c8` |
| `kernel-arm/kernel/bin/vinix` | `df54779d899c0293cd51829026201b3eb9b64bf34dc3e35b4049c783e8e45e9c` |
| `kernel-x86/kernel/bin/vinix` | `fbb9971a378e69382e4981f0efc7c124384c36444c991398eac83fc4afad54bf` |
| `preview-arm.c`, `preview-x86.c`, both final native `fcntlabi/fixture.c` files | `214391504c640d251498205116f3dd9473925931e8a068e6a15ffb349965fb09` |
| `final-reference-arm/fixture.c`, `final-reference-x86/fixture.c` | `ee31b77e9c9162482f3fe7d575ec716b06efd455de3f5f91c45c2233a3c3c364` |
| `final-after-arm/fcntlabi/init`, `final-reference-arm/probe` | `b92892f1860ff4aae349f27924922645aed79becbcff2dd00a0a18fc797fd3fd` |
| `final-after-x86/fcntlabi/init`, `final-reference-x86/probe` | `d627872a0a61cbe541ae88541b21efe49f0ae214e13801f1828a0cd19cb8dc16` |
| `final-reference-arm/init` | `0dc6a76cbfeb9307b2114f1ff5ac43ff3c8ed02aff65caf99d916ffd2d541bf5` |
| `final-reference-x86/init` | `33522d6f73890152c3015e2ea45c891b0d272c8447a043cee24778f73e984f02` |
| `final-before-arm/fcntlabi/serial.log` | `6a9374f6a06b0c75ef02dd7877a245843331a580617b85985af90868e66b0149` |
| `final-before-x86/fcntlabi/serial.log` | `50f818d075c3c8de2dc38042dac6153c88f6942bee9d7efb80e4347516809a26` |
| `final-after-arm/fcntlabi/serial.log` | `5eb24544e2ddada1a8f555c9b934109ce66b616f1bdc33da447f6336224a1af0` |
| `final-after-x86/fcntlabi/serial.log` | `58525bd9931706f50deb94e5bdd4c712495764862facb95c674c24c8c3fbcfc5` |
| `final-reference-arm/serial.log` | `e151ddf8b7b91cd58a709515f65efc3ab53a8acf10ec14c2424697c0848234e7` |
| `final-reference-x86/serial.log` | `c01ad965f244dceefc0693e45bff3c7c2224f29e24d302fe918737551a8389ba` |
| `final-before-arm.log` | `129a066c6510ce1fa8ad28f39f3e0c7b64bfc281d6ddeec19988ec48b266e1f8` |
| `final-before-x86.log` | `fa8212d8a6021fcdba06547957daa5ac8d9c0ff4e84b5f870c390e192ecde26b` |
| `final-after-arm.log` | `104e0e75783827c9099eb04eaf92ef8a02895358bcba1c4590ea585b327698c0` |
| `final-after-x86.log` | `4cecc0fa0c8f73ef50846442f9a4dbc1fcc94260086cab124882528928f3a85c` |
| `final-reference-arm.log` | `d143036fe6903c3e1ec3ce42c5e05f164dfd682babe6e38c0e874c246b43f931` |
| `final-reference-x86.log` | `9a4943802796efa615294cdfb9ea83ac1c65e453ef2a640b5fbc072080732b0e` |
| `final-before-arm/receipt.json` | `3c5e9a523cabf096b40ad5ed39d597c53bee853651cb45cdbd0177684d0fc45e` |
| `final-before-x86/receipt.json` | `21d6ab28bc579cc2d183a72eb4ae5c7f75979e893dfe49e28b73f62e26a9123b` |
| `final-after-arm/receipt.json` | `d4dbed1c81451a8a0a186b04b99f9c7187741e06baf5e1b77ddbd642227769d8` |
| `final-after-x86/receipt.json` | `0dfad6a68b0d3a0ef73a0f1937d50a497210c10c0b95fbf0e286bd58d8d2cd87` |
| `final-reference-arm/receipt.json` | `52f840229b94ed30d10f3f7ed93a94c353e6150f741d5421d29bd5c4cef575b6` |
| `final-reference-x86/receipt.json` | `ea7e1e57a8837e7993b241aa72f98d4e959e86d965753e4f0749791fdd072ad5` |
