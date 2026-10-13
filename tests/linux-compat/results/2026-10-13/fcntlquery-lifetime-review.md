Independent fcntlquery lifetime review: PASS

Reviewed the F_DUPFD_QUERY case in `kernel/file/file.v`, native scalar adapter change in `linux_common.v`, final probe/reference wrapper/controller sources, both emitted kernel C files, matching module previews, and completed native/Linux-reference captures. This independent review changed only this report and found no remaining new lifetime or lock-order blocker. Artifacts are in `/Users/alex/.cache/vinix-linux-compat/fcntlquery-20261013`; the recorded baseline is `d3ed59c6e285d6cd90202fd373e6ed8b5f6562be`.

The primary lookup retains both FD and Handle under the descriptor-table lock and releases that lock before returning. The query keeps that paired hold while obtaining a second paired hold through the same lookup. Failed secondary lookup acquires no reference and releases the primary exactly once before returning scalar EBADF. Successful lookup compares the two Handle addresses, records scalar zero/one, then releases secondary and primary. The primary remains held during secondary release, including self-comparisons and aliases sharing one Handle; no FD/Handle is used after the final release. The emitted return defer reads current-process metadata only, and the executing thread keeps the process alive. No descriptor-table lock is held across either release, and no new allocation, retained pointer, ownership transfer or nested lock is introduced.

Independent generated-C inspection caught the initial typed-pointer equality expanding into structural Handle comparison, including mutable directory-array traversal. The final source explicitly casts both operands to voidptr. Both rebuilt kernels now emit exactly one direct void-pointer comparison, without Handle copies, resource equality, array traversal or hidden allocation in the query branch. The native adapter narrows the comparison descriptor to the lower 32 bits; the query lookup also uses that scalar width. Existing held descriptors above a lowered soft limit remain queryable because this operation does not allocate a descriptor.

The complete C scope proof was reviewed: removing the query branch and normalizing local temporary names restores the old fcntl body; removing only the query command from the adapter's scalar-command condition restores its old body. Restoring those two bodies restores the entire generated kernel C on both architectures, apart from normalized unused-loop names. Descriptor lookup/release, duplication/publication, O_PATH refusal and lock helpers remain unchanged. Both isolated kernel source copies match the reviewed root sources.

The probe's 34 State records, stat scratch, counts, rlimit, source/independent descriptor arrays and slab snapshots use stack storage. Both regenerated previews match the executed native C byte for byte. Probe bodies contain eight explicit allocas and no memdup, malloc, dynamic-array allocation or fixed-index calls. The pipe, byte and slab-parser buffers also remain ordinary stack arrays in emitted C. Synchronous fstat borrows an inline State metadata field or stack stat scratch; neither pointer escapes. Query results copy errno immediately before later state checks can change it. The reference wrapper's stack argv is borrowed only by synchronous execv.

The query itself creates no alias. Fixture replacement descriptor 66 closes after each sequence; the four temporary independent-directory aliases 68–71 close before replacement testing. Fatal setup/close/restoration failures exit the entire child. Zero/eight soft-limit controls restore limit 128 before subsequent calls. The regular-file cursor mutation restores source position three before the next fork. Children have their own stack/address-space copies, and normal parent flow waits for each child before checking bytes, queued pipe data and descriptor flags, then closing the 24 sources, eight independent descriptions and held 64/65. Initial main setup errors return nonzero and rely on process-exit descriptor cleanup. The same retention observer closes on every returning storage path.

Each row ran separately as root and UID/GID 1000 with supplementary groups cleared, on both architectures. Eight classes each have an original, dup and CLOEXEC alias: regular file, O_PATH private file/directory/FIFO/symlink, unlinked regular file, and the read/write ends of a pipe. Eight independent descriptions include separate opens of the same six filesystem objects and another pipe. Candidate and actual Linux 6.12.51 reference results have zero failures. The references use the respective byte-identical native probe ELF with `--reference` and skip Vinix allocator accounting.

| Probe kind | Calls per credential | Baseline failures per credential |
| --- | ---: | ---: |
| Native alias/independent-description identity and word controls | 3072 | 3072 |
| Invalid descriptors and lowered-limit held-descriptor controls | 512 | 424 |
| Libc, matched-directory aliases and close/replacement controls | 956 | 952 |
| Total | 4540 | 4448 |

Candidates and references each pass 9080 counted controls per architecture; baselines reproduce 8896 failures each. The actual Linux boots corroborate EBADF for invalid primary and comparison descriptors, including negative, large and high-word forms. Held 64/65 continue to produce real identity results with soft limits eight and zero. Temporary directory aliases equalize the inherited Handle-reference setup while a separately opened directory remains distinct; a true alias remains equal. Repeated closure/replacement of 66 changes its query result from EBADF to equal, distinct and EBADF. Selected metadata, flags and cursors remain intact, independent cursors stay independent, regular/unlinked bytes remain unchanged, and the parent receives the original AB/CD pipe queues.

After 32 warmup cycles and settling, each credential's 200 measured cycles performs four queries: equal held descriptor, distinct held descriptor, missing descriptor and negative descriptor, with high-word inputs. The same observer brackets both snapshots. All 18 AArch64 slab classes and 14 x86-64 classes stay flat; large pages remain 73/73 and 194/194 respectively, in both credentials. Both complete four-case aggregate logs and receipts pass `fcntlquery`, `fcntlpath`, `open` and `runtime`.

This approves the final query implementation and exercised native musl ELF64 behavior. Concurrent close/replacement, limit changes and exec, additional descriptor classes, GNU wrappers and translated/ELF32 paths remain separate qualifications. Flat retention applies to the four measured query outcomes, rather than the earlier alias/replacement setup. The structural-comparison draft kernels/C and fixed-index compile failures are retained as unqualified diagnostics and excluded from the approved final evidence below.

After qualification, the maintained fixture's extra trailing newline was removed to pass the commit whitespace check. Independently verified that `tested-source.v` and all four frozen native source copies equal the maintained source plus exactly one LF byte: their entire 15,424-byte prefix matches and the sole extra byte is 0x0a. Receipts continue to bind the exact 15,425-byte tested source. Both regenerated module previews from the normalized maintained source remain byte-identical to the executed C, and the native/reference probe ELF hashes remain unchanged. No function body, kernel source, lifetime or captured outcome changed. Maintained and tested source pins are distinguished below.

SHA-256 pins use repository-relative source paths and artifact-directory-relative build/capture paths. Shared rows were independently compared as identical.

| File | SHA-256 |
| --- | --- |
| `kernel/file/file.v` | `466f78e1e1731ad24dff58199f9cf565286c8b10697de6fa85445fd552a0da5d` |
| `kernel/syscall/table/linux_common.v` | `e02ca1595fcc117e237c44cfd5634218184c328592f9e4fcb82af3be15047f68` |
| Maintained `tests/linux-compat/fcntlqueryfixture/core.v` | `1033fc802ee503a9a14ae49cdcbca959066cfb8d7e1b2f6b8127755a5b2ed9a3` |
| Exact tested `tested-source.v`, all four frozen native `sources/fcntlqueryfixture/core.v` copies | `00b1a1cf512f07f7d4fc5e31961621dc4f58232c64cca6d31b684b999cb15bd9` |
| `tests/linux-compat/fcntlqueryreferenceinit/core.v` | `93b6f2788a21f7d3570e8fb29458a62e90d2302168157459514ad1e731c80a48` |
| `tests/linux-compat/fcntlquery-reference.v` | `c1f610f8ef44173b8a9556d5e92f348b5807c9d29178f8fb1b9b5e3ad27585db` |
| `before-arm.c` | `48c52b956c5a8cae6fa3048e58b02c380aef54f5e73bb27697e39acd825eb03c` |
| `before-x86.c` | `75218235851b368273ef21046a3f4747fec3d3ea9daaeaaf1860f81e759d7215` |
| `kernel-arm/kernel/obj/blob.c` | `5d41c2446672663cf359c96f3aac13b04ea7b279a59eb448305d400b5b4f2319` |
| `kernel-x86/kernel/obj/blob.c` | `e3d5c8f20223b47f1a3e9dc6ddb3481abf79062909c47eaac6274ac08caffa51` |
| `final-before-arm/kernel/bin/vinix` | `88dfbe3dd1e81db82212abffa739409d437abb068db2e72b38152b6095b07fcd` |
| `final-before-x86/kernel/bin/vinix` | `bd9a2a9fc7df7e7bc6a2b90d8ed5032ca9ffe5826aad31d7848c6fd9bbebeed2` |
| `kernel-arm/kernel/bin/vinix` | `f77832390b05a5c684cdfde69bddbcefb1988b4f65ba6412164ce683a2fbd021` |
| `kernel-x86/kernel/bin/vinix` | `5916b7965ce9a0be56d14d8a9274c92c8f2bfa8c92972367dfacf111766de5d4` |
| `preview-arm.c`, `preview-x86.c`, both final native `fcntlquery/fixture.c` files | `e82e0523e18133d3ca4d5b1e1f9ce38ff05edcc69e91346fe55283cdb90e9984` |
| `final-reference-arm/fixture.c`, `final-reference-x86/fixture.c` | `11fb053df14fa502873be42d6e2c7368e8332be743ea59780474a65d9fd66e07` |
| `final-after-arm/fcntlquery/init`, `final-reference-arm/probe` | `13f0bbe86c209e620ed074774bb255dcc894ead4b43ee1724ca11aabd4628ea2` |
| `final-after-x86/fcntlquery/init`, `final-reference-x86/probe` | `4e1e6186ab7364a3409bafbf39189f8c5909048d90c4abf0bbee863a270b0b18` |
| `final-reference-arm/init` | `4387a0123619e12251671086f4a439a0dc612435c4223f52c123a1eb80353b30` |
| `final-reference-x86/init` | `430f808d8907221981408d94dc5ecf042302f2096142e04117cff14514ad9293` |
| `final-before-arm/fcntlquery/serial.log` | `2adc6066e9efbef2a8e0e1bfde6c8963d5fe0a987b218768da6e4fa028eeb2ad` |
| `final-before-x86/fcntlquery/serial.log` | `c53b2b5bceed566cbd669c6019030f4d30589528a06eb165fa1ab39131374fc9` |
| `final-after-arm/fcntlquery/serial.log` | `2eba3aafb955958db30a9c3573efa4cc8d131a1bbbdbeef07aba16d14f9e828a` |
| `final-after-x86/fcntlquery/serial.log` | `390540604b6e2aa1a76586286f538cddb72564fc68ed8cff466813858daf6d87` |
| `final-reference-arm/serial.log` | `386024da896ff9280d53aecfeca93bd883780012fd858916eb5c89674078de29` |
| `final-reference-x86/serial.log` | `5f97130ba94750c0f23ffca0501fd91fb3d5d2b5540850f6bb84f08bba38f980` |
| `final-before-arm.log` | `6d90608641475933f03d49a7619b8923122e4166be8d4938a4cd5ad8c21f5604` |
| `final-before-x86.log` | `cef63ee43e59bf5b98484facdb1daa7c3101251834266400b582344bd1d66155` |
| `final-after-arm.log` | `74546f6a4fa92a8961375e492a2e74ce672874a7aaec20cacde3a0e26e9a2deb` |
| `final-after-x86.log` | `ff73586b86674dab15bfbfc289f3a5b07bee750ee3a1287bbb34e2171f29647f` |
| `final-reference-arm.log` | `b60803012830bf35e97917ce180fd2c033ff1c496df20838c897423ffbe2c7c0` |
| `final-reference-x86.log` | `f8027e1b62f7dbf446e74f2c36468263ac3178d8cc087a215ff9a6bb6c842ea9` |
| `final-before-arm/receipt.json` | `40b5bee0b50191c3931a570a755a29ea569a62a6ef571d2a76729a70af31e2a7` |
| `final-before-x86/receipt.json` | `1244a54474152901c1e605c7af39ab86fe1225e5ae4613138b8a68cafdb915dc` |
| `final-after-arm/receipt.json` | `f72ec56cc9e1eff782419b7c2797e4d5b6c2851ef2b5269e9483256f534dcf1b` |
| `final-after-x86/receipt.json` | `1d5245a2b56f166519a970b35e8ef788b5cd293dfa0cafc9adf1f41041668c0e` |
| `final-reference-arm/receipt.json` | `54cf8bad15c06df0f007c468d285f7671d58e7a6f1d2cab46ee3040e1f1fbf24` |
| `final-reference-x86/receipt.json` | `24c091025688c2cd09e15736d8258d51836b738865b088960edef45bf079247f` |
| `scope.v` | `ce6fe26a984181c1f546d633a34a99285140e671af7769f40adaa1ac07900b37` |
| `scope-check.log` | `56317dfcf0dece1a3c71e88f664e8a8005200e482d102aae60f2ae4ac9dd6f5d` |
