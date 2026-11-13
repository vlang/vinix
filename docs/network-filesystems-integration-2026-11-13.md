# Network filesystem series: integration and regression verification

Date: 2026-11-13.

This integration carries the changes from #260, #262, #263, #264 and #265
onto master after #261, with the fixes described below. The original series
was cumulative; the implementation commits were applied once, in dependency
order. These remain experimental, bounded network filesystem clients.

## Fixes

| Area | Correction |
| --- | --- |
| 9P creation | `Tlcreate` requests `O_EXCL`, so a host-side creator winning the lookup/create race cannot have its existing file reopened and its identity changed. |
| 9P open descriptions | Server-opened FIDs remain live for open descriptions, including after unlink. Mode-specific FIDs are shared with counted ownership; every new open still checks server authorization. Final close and failed FD construction release the acquired ownership. |
| 9P qualification | Restored session-based facade assumptions and removed the nonexistent `network_mmap.v` dependency. Corrected fixture allocation, decrement, DMA-address and device-claim modeling while retaining the original assertions. |
| SMB rename | One bounded scratch buffer replaces per-descendant `alloca`. A directory with many cached descendants no longer grows the kernel stack by one KiB per child. |
| SMB metadata queries | `FILE_ALL_INFORMATION` reserves space for the supported UTF-16 pathname. A bounded overflow may truncate the unused name only; incomplete or malformed fixed metadata remains an error. |
| NFS metadata | An optional resource capability carries selected attributes and their values. Timestamp updates omit ownership and mode. Server-now and omitted timestamps remain distinct. Full metadata copy-up applies ownership before the final privileged mode. Legacy failure rollback restores only selected fields. |
| NFS mount options | The bounded client defaults to soft semantics and rejects explicit `hard` rather than promising indefinite retry/reconnection it does not implement. |
| Stat integration | `fstat`, `fstatat` and anonymous descriptor stats invoke an optional locked snapshot. Path queries pin only snapshot-capable resources before a blocking RPC; legacy device stats gain no close-callback side effects. |
| TCP connect | Preserves #265's distinction between a refused active open (`ECONNREFUSED`) and an established connection reset (`ECONNRESET`). |
| Current toolchain | Updated production machine-sized unsigned spellings and corrected two host fixture `alloca` prototypes to match `size_t`. |

New guest checks cover 9P open/dup/unlink/I/O/fsync, SMB long names and a
300-descendant rename, and retained-descriptor stat refresh. Their source was
compiled, but these new guest cases were not executed in this session.

## Verified source and tools

- Integration base: `a7e64839fee0dd5fb9e64c485cd30fc7995282b3` (master after #261).
- Final implementation snapshot: `0356eb03c5d164042a31fffcdb15c4bf83a6a994`.
- Implementation tree: `debc7320181c340d4bbdccba1a32a3afa7faa1cf`.
- Kernel tree: `3a4c28db352a57b2dd18ccf54563824b0d39ae6e`.
- V source: `9c42e542cd527ad71e4d95b367a1910a9164a025`, reporting `V 0.5.2 9c42e54`.
- VC bootstrap source: `3eda45e0e6d9ac3c0757dcde9ff19f3c33bd0ee6`.
- Clang, LLD and llvm-ar: LLVM 19.1.7.

The published integration also includes this report; no production changes
follow the recorded implementation tree. Isolated kernel builds used commit
`688afcb12254a882cb3a2307c9551ef811233450`, whose kernel tree exactly matches
the final implementation snapshot. Later changes affected two test prototypes
only. Local development commit IDs identify the retained audit source; the
tree hashes establish content identity independently of the publication commit.

## Results

| Check | Result |
| --- | --- |
| x86-64 kernel | Compiled and linked; verified static x86-64 ELF. |
| AArch64 kernel | Compiled and linked; verified static AArch64 ELF. |
| 9P protocol, queue, facade and transport | Passed, including creation races, retained FIDs, rollback and final reclamation. Generated-C audit passed for 22 functions. |
| 9P multiple tags | Passed facade and transport isolation; seven read/write bodies passed generated-C allocation checks. |
| SMB protocol | All 26 test functions passed. |
| SMB rename | Production helper passed with 509 cached descendants on a 64 KiB thread stack, including growing and shrinking prefixes. |
| SMB private mount options | Both privacy test functions passed on the final implementation tree. |
| NFS protocol and production facade | Passed wire, metadata, cleanup, rename-publication, statfs and snapshot regressions; host/Linux C generation passed. |
| NFS negative controls | All four compiled, then failed the intended assertions when old cleanup, publication, statfs or timestamp behavior was restored. |
| NFS allocations | Generated-C checks passed for 25 functions; populated failed-instance cleanup returned tracked host V heap objects and bytes to zero. |
| Shared stat snapshot | Passed live refresh, server errors, unchanged output on failure, path pin release on success/failure, and absence of legacy close side effects; generated-C allocation checks passed. |
| Mount-specifier dispatch | Passed opt-in, raw argument, error and allocation checks. |
| TCP reset callback | Passed active-open/established reset mapping and `SO_ERROR` read/clear behavior across all enumerated lwIP errors. |
| Git source policy | Passed; generated evidence and binaries are outside Git. |

The 9P and SMB protocol/rename runs used integrated revision `59a26ca7`.
Their tested production and fixture files were unchanged by the final five-file
compatibility patch. NFS and SMB privacy were rerun on a tree identical to the
final implementation snapshot. Both kernels are V3 outputs; no fallback
compiler result is counted. Initial compilation failures and their corrections
remain in the audit bundle. Host fixtures are not kernel runtime measurements.

Kernel SHA-256 values:

```text
abaeaa018125349741de4f0a5dc80066b6693bc3a94e58f8e627b3f95c4c4715  x86_64/vinix
c6ef97300f2927ba65fd4f9f6e844538dd5cd72bf48f2ce6cb62ad697e89ce3e  aarch64/vinix
```

## Evidence and boundaries

The audit bundle is outside Git at:

```text
/workspace/scratch/2e905bc07323/network-filesystems-validation-20261113.tar.zst
SHA256 f8d48b46f501ec7bcd0d617b18b097c4d89b75ccffa3d0a840080d11b4d622aa
```

It retains the implementation patch, test logs, assembled NFS fixtures,
generated C, binaries, mutant logs, both kernel ELFs and build receipts.
`validation/smb-nfs-receipt.txt` and `tmp/kernel-build-final/BUILD.md` record
exact invocations, tool/dependency pins, environment recovery and checksums.
Host helpers used `-gc none`; final reruns disabled compiler fallback and
automatic bug reporting. The isolated x86 build additionally used a scratch
linker-name symlink to the installed libarchive runtime, without source changes.

No new QEMU boot, real-server interoperability, hardware, stress or network
qualification is claimed. CI was not used as a gate. The per-filesystem docs
retain the session/node budgets, unsupported operations, dead-session behavior
and lack of reconnect/reclamation guarantees that still apply.
