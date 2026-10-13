Independent fcntlcreated lifetime review: PASS

Reviewed the F_CREATED_QUERY Handle bit and fcntl case in `kernel/file/file.v`, the isolated VFS creation-result transport, final probe/reference wrapper/controller sources, both emitted kernel C files, matching module previews, and completed native/Linux-reference captures. This independent review changed only this report and found no blocking new lifetime or lock-order concern. Artifacts are in `/Users/alex/.cache/vinix-linux-compat/fcntlcreated-20261013`; the recorded baseline is `cfc19a5471894cc0891257c62aa368f3e6da34bb`. The qualified VFS source is the identical frozen source in the two isolated kernels; unrelated edits in the root VFS file are outside this review and evidence.

Generic Handle construction and standard-stream aggregate constructors zero the new created bit. Path opens pass the existing local creation result into descriptor construction. The only assignment to Handle.created occurs on the newly constructed private Handle before `fdnum_create_from_fd` publishes its descriptor. The existing creation and EEXIST-fallback logic is unchanged. The scalar addition does not alter the origin-resource or VFS-node ownership transfers, mount-context borrow, publication-failure unref, or existing rollback defers. Duplication and fork retain the same Handle, so the creation result belongs to that open description and stays with its aliases. No post-publication writer of the bit was found.

The query uses the existing lookup, which retains both FD and Handle under the descriptor-table lock and releases that lock before returning. It reads the retained immutable bit into scalar zero/one and releases the paired temporary hold exactly once. Invalid lookup acquires no hold and returns EBADF. No FD/Handle is accessed after the final unref; the emitted return defer reads current-process metadata only, and the executing thread keeps the process alive. No new allocation, stored pointer, ownership transfer or nested lock is introduced by the query. Its third argument is ignored without user-pointer access.

The complete generated-C scope proof was reviewed. Removing the query branch and normalizing local temporaries restores the old fcntl body. Removing the scalar parameter, assignment and call argument restores both old VFS helper bodies. Restoring those bodies, their prototype and the single bool field restores the complete old kernel C on both architectures, apart from normalized unused-loop names. Generic construction, descriptor lookup/release, duplication/publication, native adapters, O_PATH refusal and the existing identity query remain unchanged. Both emitted query bodies contain one paired release and no allocation; both emitted path helpers set created before publication.

The probe's 50 State records, stat scratch, counts, rlimit, descriptor list and slab snapshots use explicit stack storage. The inherited descriptor pair, pipe pair, byte buffers and slab-parser buffer remain ordinary stack arrays in generated C. Both regenerated architecture previews match the executed native C byte for byte; probe bodies contain seven explicit allocas and no memdup, malloc, dynamic-array allocation or fixed-index calls. Synchronous fstat borrows an inline State metadata field or stack scratch without retaining its pointer. Query results copy errno immediately. The reference wrapper's stack argv is borrowed only by synchronous execv.

Each child enters its own prepared directory after any credential drop, so its pathname setup remains separate from the parent's inherited open descriptions. Replacement 66 closes after each sequence. Zero/eight soft-limit controls restore limit 128 before later calls. Passing cursor controls restore the newly created file's position three before retention. Normal child flow checks closure of all 48 source descriptors and held 64/65; setup failures return to the child's immediate `_exit`, and fatal replacement/limit failures exit directly. Unexpected successful refusal controls disqualify the run and rely on child-exit cleanup. The retention observer closes on every returning storage path. Normal parent flow waits for both children, checks its inherited descriptor flags and closes those descriptors before PASS; initial parent setup failures rely on process-exit cleanup. No fixture pointer is used after its stack frame ends.

Each row ran separately as root and UID/GID 1000 with supplementary groups cleared, on both architectures. Sixteen description classes each have an original, dup and CLOEXEC alias. Cases cover inherited creator/reopen descriptions, a new file and separate existing opens, truncation of an existing file, O_PATH creation flags, followed and unfollowed symlinks, creation through a dangling symlink, directory opens, an unlinked creator and a new inode at its old name, and both pipe ends. Candidate and actual Linux 6.12.51 reference results have zero failures. The references use the respective byte-identical native probe ELF with `--reference` and skip Vinix allocator accounting.

| Probe kind | Calls per credential | Baseline failures per credential |
| --- | ---: | ---: |
| Native created/reopened descriptions, aliases and ignored arguments | 1152 | 1152 |
| Invalid descriptors and lowered-limit held descriptions | 240 | 96 |
| Libc creation/error controls | 416 | 384 |
| Closed/replaced description 66 | 96 | 48 |
| Total | 1904 | 1680 |

Candidates and references each pass 3808 counted controls per architecture; baselines reproduce 3360 failures each. Creation results differ for separate opens of the same inode, remain true on the unlinked creator, and remain false for reopens, O_PATH and pipe descriptions. Duplicates and inherited descriptions preserve their result. Held 64/65 still report true/false with soft limits eight and zero. Negative, large and high-word descriptor forms retain real EBADF, and all eight third-argument values are ignored. Exclusive-create and missing-O_PATH setup controls retain EEXIST/ENOENT. Metadata, descriptor/status flags, separate and shared cursors, file bytes and the original AB pipe queue remain intact.

After 32 warmup cycles and settling, each credential's 200 measured cycles performs three queries: created held description, existing held description and missing descriptor, with high-word inputs and an all-ones ignored argument. The same observer brackets the snapshots. All 18 AArch64 slab classes and 14 x86-64 classes stay flat; large pages remain 68/68 and 177/177 respectively, in both credentials. Both complete five-case aggregate logs and receipts pass `fcntlcreated`, `fcntlquery`, `fcntlpath`, `open` and `runtime`.

This approves the isolated creation-query transport and exercised native musl ELF64 behavior. Concurrent creators, close/replacement/table changes and exec, GNU wrappers, O_TMPFILE, overlay/disk filesystems, additional descriptor classes and translated/ELF32 paths remain separate qualifications. Flat retention applies to the three measured query outcomes. No broad allocation-flat claim is made for the earlier creation, alias or replacement setup.

SHA-256 pins use repository-relative maintained-source paths and artifact-directory-relative frozen-source/build/capture paths. Shared rows were independently compared as identical.

| File | SHA-256 |
| --- | --- |
| `kernel/file/file.v`, both isolated `kernel-{arm,x86}/kernel/file/file.v` copies | `976a8bf417aa259b1afbbf9526d9bf99ec69fac21ec78a75d4d28d9a0473787b` |
| Qualified frozen `kernel-arm/kernel/fs/vfs.v`, `kernel-x86/kernel/fs/vfs.v` | `70738f9b1de00216f51185139fdcd245eb23c8286c1f7c70f2105541ab42970e` |
| `tests/linux-compat/fcntlcreatedfixture/core.v` | `ebdff7f3e7d90dc5e753b1c691679a5de55917b09e042116f84b117da01963b9` |
| `tests/linux-compat/fcntlcreatedreferenceinit/core.v` | `e8f4d5a203978fc2c0a91356e4b5a3d18167bec8b632834e84f2929812c841cf` |
| `tests/linux-compat/fcntlcreated-reference.v` | `e9edabcbcabcf43bbc69f455ad64238acca7ab46545847f20adc9712391167c4` |
| `before-arm.c` | `5d41c2446672663cf359c96f3aac13b04ea7b279a59eb448305d400b5b4f2319` |
| `before-x86.c` | `e3d5c8f20223b47f1a3e9dc6ddb3481abf79062909c47eaac6274ac08caffa51` |
| `kernel-arm/kernel/obj/blob.c` | `e3f93ea7078ab351b0ae29c1c810ac0e56258d4ee2c323e98d63425893fc6733` |
| `kernel-x86/kernel/obj/blob.c` | `6acd1ed199163a245366e306165f189b66830a464b8c9a9a2668ecb5a89b9f80` |
| `final-before-arm/kernel/bin/vinix` | `f77832390b05a5c684cdfde69bddbcefb1988b4f65ba6412164ce683a2fbd021` |
| `final-before-x86/kernel/bin/vinix` | `5916b7965ce9a0be56d14d8a9274c92c8f2bfa8c92972367dfacf111766de5d4` |
| `kernel-arm/kernel/bin/vinix` | `ddc79e74900a643feba7c918bbad5bbde3798a432188bac80857a218dc38d74f` |
| `kernel-x86/kernel/bin/vinix` | `fd6c9fb1e7e0b3c7c4d7506394798c77b186b390c90e55c51fcb348e6a3d87e3` |
| `preview-arm.c`, `preview-x86.c`, both final native `fcntlcreated/fixture.c` files | `36b344c6b96e3332bc088556c33e3eece88230c32eaf975826ba161495f0cc52` |
| `final-reference-arm/fixture.c`, `final-reference-x86/fixture.c` | `c16e98ea3366b9798da298a8794b39d689d64dc053570441910f37f2b7ce524d` |
| `final-after-arm/fcntlcreated/init`, `final-reference-arm/probe` | `cdba0dd5c7d69a293df03f6d652625df98a24162fb7c9114054087f4e49ce29b` |
| `final-after-x86/fcntlcreated/init`, `final-reference-x86/probe` | `45de3f3e4f5337a8b1ebf4113eaf44954bb18fd3626f6335807240e9d5ea6664` |
| `final-reference-arm/init` | `cd76056a5ec9eb90675447bd6105fccbe0dab95792420b091ba304be96b075fb` |
| `final-reference-x86/init` | `4eb063f52307376af4a21e58ba9f6cc75573f96883694244facc1140bc528542` |
| `final-before-arm/fcntlcreated/serial.log` | `1f330578af3c7475d9d71ef06facb5f0db5b3e4d3525e6828fe3f3648907c6b9` |
| `final-before-x86/fcntlcreated/serial.log` | `4ed6d0039166e7dcb6cb27f870057648645217141f215d326795078097d5ecc1` |
| `final-after-arm/fcntlcreated/serial.log` | `5c9fac024af81133ad0b616b1181c60454ea6a231d1c0c38d35d31481ab0df22` |
| `final-after-x86/fcntlcreated/serial.log` | `32b821fff847ccc9e22d794dad21a53b286b40adb27b4cfadb45e5fc3d371a0a` |
| `final-reference-arm/serial.log` | `ad3ce1438a94736bcd49c8930756d076b174bd7287aa17279303de8239bb8ce5` |
| `final-reference-x86/serial.log` | `8edd6a1fa88ded97a7ff7ac8e52cacd664b0eb72f91cfa3487de8d69399d4828` |
| `final-before-arm.log` | `424f398c987f9668703082f801b64d1e5a3c73ed34acc19eaaef53232c5b7fe7` |
| `final-before-x86.log` | `0725b6a6073d9e2d00c9ae015240b690d7581ab69418760c99f7a101edcef2a8` |
| `final-after-arm.log` | `a02304b93185b54dbbfcc2fba4b61f041333a70be02794f3d40ec313334bb603` |
| `final-after-x86.log` | `61c0de0c6a2026d1cbc680b4047fd08e0d3eefdffaf2e75124b6ffcefb1757c8` |
| `final-reference-arm.log` | `35b6a390393c7d5d40ce98e3d5d7c064454128003cdc9c4f9be84d212815183a` |
| `final-reference-x86.log` | `c6611d2b1eb9b2e4c99d6ac270927dc6ec45bdca668285ee4d4049078fb56eff` |
| `final-before-arm/receipt.json` | `dfdcbb0ce69d18fc2e96c0cb6e17931d3619eee526b6f3b0a3b45def6ac374a9` |
| `final-before-x86/receipt.json` | `3804c2f1485a310d3004c9c053a9cea48e2084a53155fbc2bfffe1114c4d2dec` |
| `final-after-arm/receipt.json` | `764758b5ed2e746089a3f0937b62ec754f3def984ce6e46f781a55cd62ab9682` |
| `final-after-x86/receipt.json` | `e6ac875ad76aa45f74155929c9dfe6b53f2a299c27f15bf1dd18f1c40708f5cc` |
| `final-reference-arm/receipt.json` | `32b688ba89365c57b264a4f7b932312c31a7aa06cff273092d028fcad64d7e9e` |
| `final-reference-x86/receipt.json` | `c0ab856118217c15c8c3daa1a8a1de5395cce0a714c55aee1269544bb2349884` |
| `scope.v` | `7df7e3e16254d8346ee5ac5e274ec5c358822bdf59c4ea3d5a9a1b5a79ec3e21` |
| `scope-check.log` | `93e3c7391f46e66f597a8431e337a339c3b606372b84cb9b40c2f5c9c1fd2eeb` |
