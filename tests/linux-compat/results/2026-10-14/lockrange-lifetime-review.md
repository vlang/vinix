Independent lockrange lifetime review: PASS

Reviewed the sole owned kernel source `kernel/file/locks.v`, its identical isolated copies, both final generated kernel C files, the final probe/reference wrapper/controller, exact native previews and completed verified native/Linux-reference captures. This independent review changed only this report and found no blocking new lifetime or lock-order concern. Artifacts are in `/Users/alex/.cache/vinix-linux-compat/lockrange-20261014`; the frozen baseline is `8682eac81b7e53ad8113513a883ac2ba750a8b9d`.

The positive-length normalizer now validates the inclusive last byte. `length - 1` is evaluated only for positive lengths, and the bound check precedes adding it to the nonnegative anchor. The addition therefore cannot overflow signed 64-bit arithmetic. An inclusive last byte of INT64_MAX maps to the existing zero-length sentinel; other endpoints use unsigned last-plus-one. Negative lengths retain the guard against starting below zero before addition. No arithmetic temporary owns memory or stores a pointer. The sentinel representation is consistent with Linux reporting l_len zero at OFFSET_MAX, including finite input extents reaching that byte. Partial removal of the last byte produces a finite prefix; conversion and coalescing preserve the endpoint representation.

The imported Flock remains a stack value. `fcntl_lock` obtains one optional normalized LockRange, copies its two scalar bounds into a stack value, then passes that value to get/set_record_lock. Both generated C prototypes and bodies pass the range by value; there is no address escape, boxing, allocation or stored reference to the caller's frame. Blocking setters keep their own copied bounds across retries. Usercopy still borrows the stack Flock synchronously, before table work or after a completed query. The retained FD/Handle remains alive through normalization, query, mutation, copyout and blocking waits, and is released by the unchanged caller after the helper returns.

POSIX F_GETLK validates its query kind before normalization. OFD GETLK and setters normalize before kind checks. OFD queries then validate PID; setters check access before OFD PID. This matches the reviewed pinned Linux 6.12.51 conversion/get/set order for the exercised regular files, and both actual Linux references agree on the combined-error cases. Refusals occur before table mutation or copyout, so rejected requests retain their original header and preexisting lock. Reading CUR/END earlier uses the same retained Handle/resource as before and introduces no new lifetime, though concurrent cursor/size changes remain a separate qualification.

Ownership, descriptor references, the advisory table, conflict selection, range replacement, coalescing, array allocation/freeing, final Handle cleanup and lock ordering are unchanged. The table still serializes readers/writers and copies conflict records before release. The refactor adds no lock acquisition, new ownership transfer, reclamation or grace-period requirement. Complete generated-C isolation was independently reviewed: removing exactly eight definitions/prototypes for normalize_lock, get_record_lock, set_record_lock and fcntl_lock restores the entire remaining C byte for byte on both architectures. No whitespace normalization, macro removal or newly emitted library helper is required. The root source matches both isolated copies. Before/after allocation scans are byte-identical, with 659/655 source files and 400/292 allocation sites and the same existing allowance failures.

Both module previews are byte-identical to each other and to executed before/after probe C. Probe bodies have ten explicit allocas and no memdup, malloc, dynamic-array allocation or fixed-index call. The Case tables, byte/parser buffers and wait statuses are ordinary stack values; flock request/saved-header buffers, metadata scratch, tally and slab snapshots use explicit stack storage. Case and Query values are copied, and synchronous fcntl/fstat/memcpy calls do not retain their borrowed pointers. Error/setter header checks compare a saved byte copy; valid getter outputs check the returned fields. Getter seeds use normalized zero lengths at maximum endpoints, allowing the baseline to run the actual failing query rather than fail in setup.

Each matrix case closes its alias, original and independent description before returning. POSIX close clears process-owned locks and final OFD alias close clears description-owned locks; later cases use fresh descriptions. Fatal setup/seed failures exit the whole cohort, so no caller continues using its stack storage. The retention cycle closes a/alias/b unconditionally after checks; partial-open failures close every successful acquisition. Its observer closes on every returning storage path and brackets snapshots using the same FD. Parent flow prepares both 0600 files before forking, gives the user file to UID/GID 1000, waits for both cohorts before unlinking, and exits nonzero on setup failures with process-exit descriptor cleanup. Cohorts exit through `_exit`. No thread or asynchronous user of fixture stack storage is introduced. The reference wrapper's stack argv is borrowed only by synchronous execv.

Six commands run through libc and native upper-word descriptor/command forms in both credentials: F_GETLK, F_SETLK, F_SETLKW and their three OFD variants. Each command sees sixteen valid and ten invalid cases. The probe also checks combined kind/range/access/PID errors, exact unchanged rejected headers, independently observed accepted/preserved ranges, metadata/mode/owner, file bytes, descriptor/status flags and shared versus independent cursors. Actual Linux 6.12.51 references use the byte-identical respective native probe ELF with `--reference` and skip Vinix allocator accounting. Both native captures and both completed reference receipts pass all final rows.

| Probe kind | Calls per credential | Baseline failures per credential |
| --- | ---: | ---: |
| Accepted setter headers and endpoints | 128 | 48 |
| Getter conflict headers and normalized extents | 64 | 24 |
| Invalid ranges and combined-error precedence | 204 | 34 |
| Accepted/preserved locks and maximum-byte split/conversion/alias controls | 340 | 70 |
| Metadata, bytes, flags and cursor preservation | 312 | 0 |
| Total | 1048 | 176 |

Candidates and references each pass 2096 counted controls per architecture; each baseline reproduces 352 failures in the same 2096 controls. Maximum-byte positive and zero lengths return the expected zero-length extent. Finite extents below that byte and negative lengths retain their finite output. SET/CUR/END bases, large forward/backward ranges and arithmetic overflow/negative-start errors match the oracle. Error precedence retains real EINVAL, EOVERFLOW and EBADF. Splitting, rebridging, removing the last byte, converting its suffix, nonfinal close and final alias release preserve the exact expected ranges.

After 32 warmups and settling, each cohort runs 200 measured cycles that acquire/query/unlock the final byte, acquire/query a POSIX extent reaching the final byte, verify POSIX any-alias close cleanup, then acquire an OFD final-byte extent and verify final alias release. All 18 AArch64 and 14 x86-64 slab rows stay flat in both credentials; large pages remain 63/63 and 160/160 respectively. This qualifies the measured open/alias/range/query/close sequence, not arbitrary persistent-lock populations or all blocking workloads.

This report pins only the completed owned-case and reference evidence. Related five-case native controllers were still finishing separately, so their changing aggregate receipts are not pinned and no aggregate-completion claim is made. Remaining limits include concurrent CUR/END updates, POSIX close/set/fork/exec recovery, namespace/PID-reuse races, nonregular and additional filesystem behavior, deadlock detection/fairness, GNU wrappers, foreign/translated/ELF32 paths and broader mmap/epoll/SCM_RIGHTS retention interactions. Ownership and lock-table correctness outside the exercised paths remain as qualified by the preceding OFD review.

SHA-256 pins use repository-relative maintained-source paths and artifact-directory-relative build/capture paths. Shared rows were independently compared as identical.

| File | SHA-256 |
| --- | --- |
| `kernel/file/locks.v`, both isolated `kernel-{arm,x86}/kernel/file/locks.v` copies | `81996f537c478a119e006dc29491cfa08274b147fe6d35cb2bdce5c13ef8c2e7` |
| `tests/linux-compat/lockrangefixture/core.v`, final frozen native sources | `1d07e75cda68db7f74b981be2ed2a086b65958efa5a40da8b9b49280b6b9dcc2` |
| `tests/linux-compat/lockrangereferenceinit/core.v` | `d4b597300e40a5602d20ed818e93318263da0756b838e41b785ac6fac45d37a7` |
| `tests/linux-compat/lockrange-reference.v` | `f9fb1a932b55a631ec2f6cff96072eb5cb90d80f50ef764fa6a8945c5ce0a943` |
| `before-arm.c` | `6c5d64dd121a365a5e7c45c2cb0486a7c2e9bbe06c185c8782c23b05b2682b6e` |
| `before-x86.c` | `d0189f42260ae0a1a62279b651eff6471847b0b34b93160ab0f8c267b12fe96a` |
| `kernel-arm/kernel/obj/blob.c` | `a7f8b143d7fbc016aaceb8ff1993b01ac70dbee95fbf46106d6cc82c2fbd49ad` |
| `kernel-x86/kernel/obj/blob.c` | `b9a86f07bdaf39f1a22ad47748eb86c97f9bbe17b91fee8884c8386a7728c391` |
| `kernel-arm/kernel/bin/vinix`, `verified-after-arm/kernel/bin/vinix` | `d8bf8ba78d24863a014a7dd1554f27655376aa83968bccada510e4b2ac8eb2fd` |
| `kernel-x86/kernel/bin/vinix`, `verified-after-x86/kernel/bin/vinix` | `02fb738d237405f32a8704167624c59f4ac6282e0559282518ad6599dc6f5d00` |
| `verified-before-arm/kernel/bin/vinix` | `58e0a1080bb4d349042a2b187b2c73b8f17d5e5b17b1a56c9f4738681650e1d7` |
| `verified-before-x86/kernel/bin/vinix` | `5579cc6d3b6220d9707561a76a052891fa163cfa94ba3fb358c77e9b47e10b3d` |
| `preview-arm.c`, `preview-x86.c`, all verified native `lockrange/fixture.c` files | `646183e81b91ad73a523b7d99d38634f37b6f96830ad711d3c023251699de0df` |
| `verified-reference-arm/fixture.c`, `verified-reference-x86/fixture.c` | `83636ca1e2fd78ebddd9835b85a0fc22cc1f108efab858771141ead54d30d5a7` |
| Both verified AArch64 `lockrange/init` files, `verified-reference-arm/probe` | `05f805f200ec14fdefdf15cac5e2a92e4682793b373213186b72f179b7f2fcb7` |
| Both verified x86-64 `lockrange/init` files, `verified-reference-x86/probe` | `ef4e92abd270f6923b393b29518551d4374e53a6eb44bd4b9a1ef528f5ed781c` |
| `verified-reference-arm/init` | `29cb484b4820a3f1004cb86180bd3193dd2b380716e634416ee73da138b191af` |
| `verified-reference-x86/init` | `79e97fa4f3ea0356da80c501afccac1fdaf48c0d7e8c788c9944f7675712a4c7` |
| `verified-before-arm/lockrange/serial.log` | `74961e534bd53dc4291a16bc1a73b0c09b8e7e31734c3b5808e9f769d847562a` |
| `verified-before-x86/lockrange/serial.log` | `240d4386792276c6d31f30d44d2138e14fe499200738fb5579b3b38aa1b438d5` |
| `verified-after-arm/lockrange/serial.log` | `8bb73ecc18431c4419f97a65431b3536b8366d6b51a7584a09c758fbcf1bab6a` |
| `verified-after-x86/lockrange/serial.log` | `5ddee8d86cd7b58ed812a7b66869cc2153c1aba4379e066aa5cbe526af497b0e` |
| `verified-reference-arm/serial.log` | `27a8bdb390d182196fe35ccf4d17bf07035a607cc27b77c0e8eba5814fcc400c` |
| `verified-reference-x86/serial.log` | `a8492309d6bc43f4633ac06cfab605ca34d9504d9f7de82e02660d5afb7897af` |
| `verified-before-arm/receipt.json` | `7ef5c6e6c5ea52a18ed5c81a760fa0fc6b480361099f2a30cbde74291e238203` |
| `verified-before-x86/receipt.json` | `57b1ca8216058daed24e0ed738ce027d2c22eef2198ed5a5de6e567e273be3f2` |
| `verified-reference-arm/receipt.json` | `b654eea9cf57e2e12a178a46af2839e75b0091ec0474141b9ce1ae0b7e0ec2a6` |
| `verified-reference-x86/receipt.json` | `9f3de2ebb914ee212a96a961fced0f8f46e294d911ac9d7234a7a75ea4b37573` |
| `scope.v` | `2c0ada934143c38e9f5d4d64b188ae2d9a91fb0fdb46415204664896c8e43aed` |
| `scope-check.log` | `0df2a0b8aa272c9be7d6b11f0ee817a59fe4729a3a89cfd77bf6811f2a4b9b17` |
| Identical `allocs-before.log`, `allocs-after.log` | `8dbe80210d0568e5a6ba0c98756646d4b2c61fede1af3e4f04fa6b6fde96e6d5` |
| Reviewed pinned primary source `../ofdlocks-20261013/linux-locks.c` | `1e3fb10f9d131dfefd39dd57d638786e94ed8d0773ac709d0011ec41af9c96f0` |
