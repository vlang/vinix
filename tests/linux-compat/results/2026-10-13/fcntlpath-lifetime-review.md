Independent fcntlpath lifetime review: PASS

Reviewed the O_PATH fcntl refusal in `kernel/file/file.v`, final probe/reference wrapper/controller sources, both emitted kernel C files, matching module previews, and completed native/Linux-reference captures. This independent review changed only this report and found no blocking new lifetime or lock-order concern. Artifacts are in `/Users/alex/.cache/vinix-linux-compat/fcntlpath-20261013`; the recorded baseline is `6f0ea0e0a69883abd9a61b1f7b2b82902be26207`.

The descriptor lookup retains both FD and Handle under the descriptor-table lock and releases that lock before returning. The new guard reads the retained Handle's O_PATH flag and allows the listed descriptor commands. Every rejected command releases that paired temporary hold exactly once, then returns scalar EBADF before MAC checks, resource operations or user-pointer access. There is no FD/Handle dereference after that unref. The emitted return defer reads current-process metadata only; the executing thread keeps the process alive. Allowed commands retain the existing cleanup, including the separate outer fcntl and inner duplication holds. No new allocation, stored pointer, ownership transfer or nested lock is introduced.

The sole kernel source change is the guard and two reserved command constants. Independently inspected complete generated-C diffs contain those two defines, the guard, and local return-temporary renumbering inside fcntl. The rest of fcntl remains identical after removal of the guard and normalization of those temporary names; whole C outside that function and the two defines is unchanged. The native width/minimum adapter, descriptor lookup, duplication/publication and lock helpers remain unchanged. Both isolated kernel source copies match the reviewed root file.

The probe uses explicit stack storage for stat records, the canary-wrapped flock Packet and its saved copy, counts, rlimit, source-descriptor array and slab snapshots. Both regenerated architecture previews match the executed native C byte for byte. Probe bodies contain exactly 10 explicit allocas and no memdup, malloc, dynamic-array allocation or fixed-array promotion. Synchronous fstat and fcntl calls do not retain fixture pointers. Query results copy errno immediately; refusal checks compare the entire packet and selected metadata, descriptor flags and status flags afterward. NULL, valid stack and address-one arguments exercise refusal before pointer access.

Every nonnegative tested duplicate is closed even if its validation fails. SETFD controls restore saved descriptor flags, and the ordinary-file SETFL control restores its saved status. The baseline refusal helper also restores status when a wrongly accepted command changes it, so later cases retain their original setup. Source arrays and snapshots stay alive throughout synchronous calls; fork children have their own address-space copies, and normal parent flow waits for each child before final source-byte/flag checks and closing all sources. Initial main setup errors return nonzero and rely on process-exit descriptor cleanup; fatal child setup/restoration errors use `_exit`. The retention observer closes on every returning storage path. The reference wrapper's stack argv is borrowed only by synchronous execv.

Each row ran separately as root and UID/GID 1000 with supplementary groups cleared, on both architectures. Six object types each have an O_PATH source, dup alias and CLOEXEC alias: ordinary file, private file, directory, FIFO, symlink opened without following it, and unlinked file. Candidate and actual Linux 6.12.51 reference results have zero failures; the reference uses the byte-identical respective native probe ELF with `--reference` and skips Vinix allocator accounting.

| Probe kind | Calls per credential | Baseline failures per credential |
| --- | ---: | ---: |
| Refused commands, pointers and selected state | 3888 | 3726 |
| Allowed getters, descriptor flags and duplication | 648 | 0 |
| Invalid descriptors, libc refusals and ordinary-file controls | 870 | 432 |
| Total | 5406 | 4158 |

Candidates and references each pass 10,812 counted controls per architecture; baselines reproduce 8316 failures each. Allowed controls retain selected metadata, O_PATH/status flags and expected alias CLOEXEC while preserving the source. The ordinary descriptor still accepts/restores NONBLOCK, returns EFAULT for invalid pointer commands and EINVAL for an unknown command, and retains its bytes. The private-file open control preserves real EACCES for the ordinary credential.

After 32 warmup cycles and settling, each credential's 200 measured cycles performs two O_PATH alias duplications/closes and four refused commands, without descriptor-pressure setup. The same observer brackets the snapshots. All 18 AArch64 slab classes and 14 x86-64 classes stay flat; large pages remain 63/63 and 160/160 respectively, in both credentials. Both complete four-case aggregate logs and receipts pass `fcntlpath`, `fcntlabi`, `open` and `runtime`.

This approves the new refusal path and exercised native musl ELF64 behavior. The reserved F_DUPFD_QUERY/F_CREATED_QUERY constants preserve an allowlist exception but do not implement those query semantics; they remain separate qualifications. Full ownership/sealing/status-flag semantics, dynamic pipe resizing, full lock semantics/concurrency, concurrent close/limit changes, GNU wrappers and translated/ELF32 paths also remain separate qualifications. Flat retention applies to the measured duplication/refusal operation set. The original host-generated `preview.c` and the initial coverage-directory failure are diagnostic artifacts; the approved previews below are the regenerated matching module C.

SHA-256 pins use repository-relative source paths and artifact-directory-relative build/capture paths. Shared rows were independently compared as identical.

| File | SHA-256 |
| --- | --- |
| `kernel/file/file.v` | `c2dd466b3a90121005d13069584f437555a47a5766a861916544d8c42683a6b2` |
| `tests/linux-compat/fcntlpathfixture/core.v` | `314b2cefc9567f5c6552d8b0534cd9e6039cd71c0d80689360ac7b1966dbea3e` |
| `tests/linux-compat/fcntlpathreferenceinit/core.v` | `9df9223b1033e63e7c423b86c9ba10ff1397b3af44599ef0ad6c10223aa19267` |
| `tests/linux-compat/fcntlpath-reference.v` | `598bee6fa7f5d1e10c728dc40745aa06da9c4878251185e03c57d65d14eb4997` |
| `before-arm.c` | `05df84d3139c82b60cbece759c7a00be346cdcd86997f11af5d3b7c71c484883` |
| `before-x86.c` | `04d2e8012287ba1ff1630af718e9a06bf68d5d109c84c7b3f02183ae74c8cec7` |
| `kernel-arm/kernel/obj/blob.c` | `48c52b956c5a8cae6fa3048e58b02c380aef54f5e73bb27697e39acd825eb03c` |
| `kernel-x86/kernel/obj/blob.c` | `75218235851b368273ef21046a3f4747fec3d3ea9daaeaaf1860f81e759d7215` |
| `final-before-arm/kernel/bin/vinix` | `df54779d899c0293cd51829026201b3eb9b64bf34dc3e35b4049c783e8e45e9c` |
| `final-before-x86/kernel/bin/vinix` | `fbb9971a378e69382e4981f0efc7c124384c36444c991398eac83fc4afad54bf` |
| `kernel-arm/kernel/bin/vinix` | `88dfbe3dd1e81db82212abffa739409d437abb068db2e72b38152b6095b07fcd` |
| `kernel-x86/kernel/bin/vinix` | `bd9a2a9fc7df7e7bc6a2b90d8ed5032ca9ffe5826aad31d7848c6fd9bbebeed2` |
| `preview-arm.c`, `preview-x86.c`, both final native `fcntlpath/fixture.c` files | `957fa07d680e3f01976bbb2b7a737cfdfb91019874dd8bcf45781101a30744c5` |
| `final-reference-arm/fixture.c`, `final-reference-x86/fixture.c` | `0c45c5adefdc10045d5c6e7612fbe110e1ad012020f5e9cb6329c265cbfeccdb` |
| `final-after-arm/fcntlpath/init`, `final-reference-arm/probe` | `11b8c3ffb5a640d607c362244b6b3816acb3b7315c83b9f6c0d6ba8add464510` |
| `final-after-x86/fcntlpath/init`, `final-reference-x86/probe` | `b0c820d141e0b7e7af9801761069655abf591d2e6e114c54cbcaba61b9555126` |
| `final-reference-arm/init` | `b9b14548f35e8c76ae136ef84538f8661fd68b525378264318bcc37ff04c2b8f` |
| `final-reference-x86/init` | `ec8ceb3fb2f9857c06c293e8b16b63411201b6099e17206e20c3ec6d282f894a` |
| `final-before-arm/fcntlpath/serial.log` | `8c5b0f68f06a283c4bab573faab01cff15ca5fbba57b6ce10c190fe2477f6874` |
| `final-before-x86/fcntlpath/serial.log` | `b4991c7556ef816b11bca5581d90377b30a9a1ae82a961deb973375e47344239` |
| `final-after-arm/fcntlpath/serial.log` | `6f679ad075b810a75660405bd7165a06fed930423410abd4839ac41e5869a24c` |
| `final-after-x86/fcntlpath/serial.log` | `cbc44ecfb2c6ef2b25177db4ffc30a3e578dbf2105697119a367b032aec81b0f` |
| `final-reference-arm/serial.log` | `0ef5c49aa2dd51c880551fff3a7ed542724c9ce1238504b6478ae2caef398137` |
| `final-reference-x86/serial.log` | `48fe1515bd005c8dbbee2690ee02123c92288993730e295c461b254f5c946e16` |
| `final-before-arm.log` | `ee53fe01587e9da7f0b208e1f7256b92c879f0684e997170bbfa8f12c438c7cc` |
| `final-before-x86.log` | `ceb5f3b678f91b630bce62be9e52de74c55b1db1ea10033e837aef6c80901ef9` |
| `final-after-arm.log` | `69be3563d1b3ad6aaa13981a0dada63851a0328266cea8a0c18886acda769ca7` |
| `final-after-x86.log` | `b057f042c1f0cdb4847286c9db214019b51efa491d362de64746e07e685d2862` |
| `final-reference-arm.log` | `30d0f4ad2e5ac999f77cacf5fed41d9fea694ed17445904062779993d699287e` |
| `final-reference-x86.log` | `9422c9f2a5fb7960a5b3db28ba64b51cbffdf425433351b9e16d692378541b68` |
| `final-before-arm/receipt.json` | `22216af9e677c1e4aeca2fa0bc89639d6b5cb8bfe2c88ad6357078f801f3ada2` |
| `final-before-x86/receipt.json` | `7ac5cb400bfbdb0983e964511f138424ef8003775a8bac9ddb12b131a1b69d8b` |
| `final-after-arm/receipt.json` | `eb3d8db8468fafc42003fd037da0024121aa82b587fbe76f91d49965a548d82b` |
| `final-after-x86/receipt.json` | `9ca4f412faff221261e6fb32fddcbaa1d1079ced4b5d1a51097963e19f75e257` |
| `final-reference-arm/receipt.json` | `8d6bd47307c51ad1874a9b7ba891c35e988949afd0c364ec85f2342840629361` |
| `final-reference-x86/receipt.json` | `b3803cd2ce5200e9a313d21e66c9ad808ce50513b08c2564ff486d47bc6eaf54` |
| `scope.v` | `305ceb36926fa16556c3865368b5b641ec77c46838693f5f4ae0cac471362c8f` |
| `scope-check.log` | `1c81c22c6bbb19d1b533f1c989440ed3b6170247de534c1ffbe20edb8315c3aa` |
