Independent ofdlocks lifetime review: PASS

Reviewed the owned changes in `kernel/file/file.v` and `kernel/file/locks.v`, their identical isolated copies, both final generated kernel C files, the final probe/reference wrapper/controller, matching native previews and completed verified native/Linux-reference captures. This independent review changed only this report and found no blocking new lifetime or lock-order concern. Artifacts are in `/Users/alex/.cache/vinix-linux-compat/ofdlocks-20261013`; the recorded baseline is `8659d6717c12126a5fda37383e467d4bf9638058`.

OFD ranges now belong to the Handle address rather than a process PID. Generated C casts the retained Handle pointer directly to the owner integer, without copying or structurally comparing the Handle. Dup, CLOEXEC aliases and fork share that Handle; independent opens have different owners. POSIX ranges remain process-owned. Their conflict domain includes OFD ranges, even when the same process acquired both on one Handle, while flock keeps its separate domain. OFD conflict output reports PID -1. The own-range F_OFD_GETLK/F_UNLCK branch selects only matching resource/class/Handle owner and overlapping ranges, including readers; it returns a copied record and never removes it. Ordinary conflict queries exclude their own same-class owner. POSIX F_GETLK/F_UNLCK retains EINVAL. The own-range branch was independently checked against the pinned Linux 6.12.51 `posix_test_locks_conflict` source and the final actual Linux captures.

The existing descriptor lookup takes a paired FD/Handle hold while holding the descriptor-table lock, then releases that lock before fcntl work. That hold spans usercopy, query, mutation and blocking waits; the final caller release is after the lock helper returns. Thus an in-flight operation cannot access a freed Handle if another descriptor closes. Persistent lock entries store scalar resource identity, owner, class, bounds, kind and PID, with no new retained object or borrowed stack pointer. Final Handle release removes this owner's OFD and flock entries before resource unref, node release or Handle free. Nonfinal alias closes preserve OFD ranges; unrelated-description closes cannot remove them. POSIX close cleanup remains process/inode based. Flock conversion calls description cleanup with `only_flock=true`, so it preserves OFD entries.

All advisory-table readers and writers execute under the same lock. Conflict results are value copies made before release; no pointer into the old array survives reclamation. Range replacement preserves prefixes/suffixes, coalesces adjacent same-owner/class/kind ranges to a fixed point, then compacts in place with the write index never ahead of its read index. Its replacement array is sized up front and marked noslices; the old table is freed before the new owned header is installed. Cleanup either frees the old table and transfers its replacement, or frees the unused temporary. Generated push/compaction values remain on the stack, with no memdup, boxing or other hidden allocation. The added array trim helper adjusts length on this unsliced storage; it does not create a borrowed slice. Serialized readers and copied query results make immediate old-buffer reclamation safe without a new grace-period mechanism.

Usercopy occurs before acquiring the table lock or after releasing it; PID namespace translation also occurs after release. The conflict path samples the event generation while holding the table lock, releases the table lock before waiting, and retries after wakeup. Mutation and cleanup release the table lock before notifying waiters. The existing table-to-event generation lock order is unchanged; no new event-to-table nesting was found. The FD/Handle hold keeps the resource identity and Handle address valid throughout retries. Downgrade notifications let compatible readers proceed. Interrupted waits return EINTR and still release the paired syscall hold.

The complete generated-C scope proof was reviewed for both architectures. It removes only the reviewed lock conflict/range/query/cleanup, fcntl/flock and final Handle-release bodies/prototypes, their old/new names, the newly emitted array trim helper and the OFD class macro, and normalizes empty separator lines. The remaining complete C matches. This is a comparison after those explicitly disclosed removals and blank-line normalization, not raw C identity outside a single function. Both root owned sources match both isolated copies. The final before/after allocation scans are byte-identical: 659/655 source files and 400/292 allocation sites, with the same existing allowance failures.

Both regenerated native previews are byte-identical to the executed final C. Probe bodies contain 14 explicit allocas and no memdup, malloc, dynamic-array allocation or fixed-index call. Flock request/output buffers, counts, pipe descriptor arrays, Query transfers, poll scratch and slab snapshots have explicit stack storage. Fixed byte/path/parser arrays and wait statuses remain ordinary stack values. Synchronous fcntl borrows each flock only during its call; returned Query records contain scalars. The reference wrapper's three-element stack argv is borrowed only by synchronous execv.

The parent prepares both 0600 files before fork and gives the user file to UID/GID 1000, avoiding a dependency on UID 1000 creating files under /tmp. Each cohort exits through `_exit`, releasing its descriptor table on both passing and failing paths. Blocking controls use real pipes and independent child opens, observe the child sleeping in procfs and verify no completed result before intervention. The result buffer is read only after a full successful pipe read, including C short-circuit guarding of failed reads. Timeout failure kills the waiter and waits before closing the parent pipe ends and owner descriptor. Inheritance holds the child's alias until the parent has closed all its aliases, then commands child exit and waits before checking final-release behavior. No child reads a parent stack after that frame ends; fork provides separate address spaces and pipes copy the scalar results.

Retention cycles unconditionally close all three acquired descriptors even after an unexpected check, and partial-open failures close every successful acquisition. The same observer FD brackets before/after snapshots and closes on every returning path. Parent flow waits for both cohorts before unlinking both files; failed parent setup exits nonzero with process-exit cleanup. Fixture pointer lifetimes do not escape their synchronous calls or process frames. Unchecked teardown calls on some semantic-control failure paths do not turn a failed control into PASS; cohort exit remains the final cleanup boundary.

The final probes run libc and native upper-word descriptor/command forms, separately as root and UID/GID 1000 with supplementary groups cleared. Both candidate captures and actual Linux 6.12.51 references pass every final row. Each reference executes the byte-identical respective native probe ELF with `--reference` and skips Vinix allocator accounting.

| Probe kind | Candidate/reference calls per credential | Baseline calls per credential | Baseline failures per credential |
| --- | ---: | ---: | ---: |
| Description identity, aliases, cross-POSIX conflicts, own queries, close and flock preservation | 74 | 74 | 34 |
| Split, bridge/coalescing, conversion and normalized ranges | 44 | 44 | 18 |
| PID, pointer, descriptor, access-mode and range errors | 94 | 94 | 24 |
| Blocking release, signal interruption and downgrade | 12 | 0 | 0 |
| Fork inheritance and final inheritor exit | 8 | 0 | 0 |
| Total | 232 | 212 | 76 |

Candidates and references each pass 464 counted controls per architecture. Baselines run 424 controls and reproduce 152 failures each; the two later groups are deliberately skipped after earlier failures to avoid entering blocking tests with placeholder semantics. Qualified behavior includes nonzero OFD PID EINVAL, invalid-pointer EFAULT, invalid/O_PATH descriptor EBADF before user-pointer access, incompatible read/write access EBADF, conflict EAGAIN, overflow EOVERFLOW and signal EINTR. Own writer/reader queries preserve the range, reopened descriptions are excluded from own queries, ordinary OFD queries see conflicting descriptions, POSIX queries see OFD locks and OFD queries return the process PID for POSIX locks. Partial unlock, rebridging, read/write conversion, negative length, SEEK_CUR/END, 64-bit bounds and unbounded lengths return the expected ranges. File bytes remain intact. Nonfinal/unrelated closes preserve locks; final close and final inheritor exit release them. Flock acquire, conversion and unlock preserve OFD ranges.

After 32 warmup cycles and settling, each cohort runs 200 measured cycles that open two descriptions, duplicate one, acquire/split/rebridge through the alias, confirm real conflicts, close nonfinal/final aliases, then acquire on the other description and close it. All 18 AArch64 and 14 x86-64 slab rows remain flat in both credentials; large pages stay 63/63 and 160/160 respectively. This measures the exercised repeated open/alias/lock/close sequence. It does not qualify allocation behavior of an arbitrary population of persistent locks or every blocking workload.

This review pins the completed owned-case and Linux-reference artifacts. The separate five-case native regression controllers were still finishing related cases when this report was written, so this report makes no aggregate-completion claim or pin of their changing receipts. Earlier setup/credential failures, the rejected unlock-query expectation, intermediate kernels and ISO-writing failures are diagnostic evidence only and are excluded from this PASS verdict.

Remaining qualifications include concurrent POSIX close/set/fork/exec recovery, namespace/PID-reuse races, simultaneous cursor/size changes during range normalization, deadlock detection and fairness, terminal signed-offset boundaries beyond the tested overflow case, other filesystems and descriptor classes, GNU wrappers, translated/ELF32 paths, and broader mmap/epoll/SCM_RIGHTS retention interactions. The existing process-owned close/set race is not resolved by this OFD change. This approves the new ownership and reclamation paths and the exercised native musl ELF64 semantics, not complete Linux/POSIX lock conformance.

SHA-256 pins use repository-relative maintained-source paths and artifact-directory-relative build/capture paths. Shared rows were independently compared as identical.

| File | SHA-256 |
| --- | --- |
| `kernel/file/file.v`, both isolated `kernel-{arm,x86}/kernel/file/file.v` copies | `ded7a34cd242a6a862ac439511e49c3f4e042eb8b43494e709ad7dbbba99d14e` |
| `kernel/file/locks.v`, both isolated `kernel-{arm,x86}/kernel/file/locks.v` copies | `d4d518b42462c882b90678de2cc78f57c982aba7287f9e490a331827e1c6c34e` |
| `tests/linux-compat/ofdlocksfixture/core.v`, final frozen native sources | `2712479c6daf9277b38c34a4ee0153aa31f82884f7eadc80891e056a6954b177` |
| `tests/linux-compat/ofdlocksreferenceinit/core.v` | `144519e9b0a20e27be5947cc6dbe066c1fc005f12e4dc040ed6786cdaf228f73` |
| `tests/linux-compat/ofdlocks-reference.v` | `95c8cbea6ada20a54868c697b45f04db2226dc8323ea9af90a19a222b5cbbdac` |
| `before-arm.c` | `b2e5f0c4250ecbeef4b1a9eba6aace66d68a81628204d49cd22ada0755c13035` |
| `before-x86.c` | `cca2ecad3a6bfda4ffc356a11c0fac0c284a6a7511ef14417ec4a082687074ed` |
| `kernel-arm/kernel/obj/blob.c` | `6c5d64dd121a365a5e7c45c2cb0486a7c2e9bbe06c185c8782c23b05b2682b6e` |
| `kernel-x86/kernel/obj/blob.c` | `d0189f42260ae0a1a62279b651eff6471847b0b34b93160ab0f8c267b12fe96a` |
| `kernel-arm/kernel/bin/vinix`, `verified-after-arm/kernel/bin/vinix` | `58e0a1080bb4d349042a2b187b2c73b8f17d5e5b17b1a56c9f4738681650e1d7` |
| `kernel-x86/kernel/bin/vinix`, `verified-after-x86/kernel/bin/vinix` | `5579cc6d3b6220d9707561a76a052891fa163cfa94ba3fb358c77e9b47e10b3d` |
| `verified-before-arm/kernel/bin/vinix` | `59ca5505f55d93cf85d2012e7184bf71478504497ffac7f12feb59801f743dd1` |
| `verified-before-x86/kernel/bin/vinix` | `7671f070cde5a3970ab19f2fedf0061262728f77b67f72fc27e08f46cb971d65` |
| `preview-arm.c`, `preview-x86.c`, both verified native `ofdlocks/fixture.c` files | `7d80f30a2bf10edf8732dc54406d20bd0e2c9491250f47e89c43c2bc3d748900` |
| `verified-reference-arm/fixture.c`, `verified-reference-x86/fixture.c` | `95c9b97d5fc840376fb8bd68ffbf734c83bb8066f81125cb78b58f79c4a3dd84` |
| `verified-after-arm/ofdlocks/init`, `verified-reference-arm/probe` | `9459764e120b8213561413eaef14e8c629612bbb6045d3f722512853a0325b36` |
| `verified-after-x86/ofdlocks/init`, `verified-reference-x86/probe` | `00f6ec6e2346229e1b536999f0f7ee4efd1439d77fe7b00482f626aebb599140` |
| `verified-reference-arm/init` | `0f59429b335f808e308d09ebbefedf02d30fdfbc099d2f5c1b4477b9af3fdd4a` |
| `verified-reference-x86/init` | `9e525f50810445bec85c113c337694513d59f36ef57ceb9b79d2b0344fd0042e` |
| `verified-before-arm/ofdlocks/serial.log` | `204807e170bc0366f4aac653dfe37f236c1b4da4357ee4a6bcfc3685331fbfbe` |
| `verified-before-x86/ofdlocks/serial.log` | `dcd6bdb7154c2b52bad7dccf3550ac2d38bee01f17da4c8fd9e876a847c10ba0` |
| `verified-after-arm/ofdlocks/serial.log` | `e317e9032d88d8f7e96df1f12f49b4667b731d1d51b6cd377a4f3e3e09f930ce` |
| `verified-after-x86/ofdlocks/serial.log` | `0fd58ffbc73d791e44e86b2ac00dae0f9662e757bdfc4aa21d6bd7fe29f8bce7` |
| `verified-reference-arm/serial.log` | `a1fa6f49004a0bd2c2b04f2ec37b2ed73a1719f7525b4b8fe9003617a877fcbb` |
| `verified-reference-x86/serial.log` | `2b3458a18761e44a638b87ce0b34bd543b09afe34c8aaa95fa9b5a185d31f8f6` |
| `verified-before-arm/receipt.json` | `833ad59bd3054402b0211125d0f2bcbc866e27ddf67613c1610148deb251ef99` |
| `verified-before-x86/receipt.json` | `20b247dacb8f04ed138c15ca3000e82b1247b4ef51c8cbd0c79a67e8e87133f4` |
| `verified-reference-arm/receipt.json` | `dca8187035921b750f56bc0e0d3efdb369f28a45dd6ac81d70af86df5ceebda9` |
| `verified-reference-x86/receipt.json` | `801838fb92410e40c6e9f6491a986a76a0be7582529d85fc8149a8ce6ed4890d` |
| `scope.v` | `3fce6f1fec602e33168134755fd6687cf9ebb623922a7f3f3773abf40d9d3114` |
| `scope-check.log` | `06a661610932c800d298787bda2925440a51fb668257d2760b637a40d0f13b0f` |
| `linux-locks.c` | `1e3fb10f9d131dfefd39dd57d638786e94ed8d0773ac709d0011ec41af9c96f0` |
| Identical `allocs-before.log`, `allocs-after.log` | `8dbe80210d0568e5a6ba0c98756646d4b2c61fede1af3e4f04fa6b6fde96e6d5` |
