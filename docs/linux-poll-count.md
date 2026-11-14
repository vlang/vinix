# Native poll count register width

Raw x86-64 poll now decodes `nfds` as unsigned32 before checking the existing
4096-entry limit. High register bits no longer turn a low count of zero or one
into EINVAL. Counts with low UINT32_MAX still fail. This follows the unsigned
int argument in [Linux v6.12's poll entrypoint](https://github.com/torvalds/linux/blob/v6.12/fs/select.c).
Timeout decoding, poll-array import/output, scratch reservation and cleanup
remain unchanged. AArch64 has no native poll syscall; its musl path uses ppoll.

The same newly compiled static musl ELF runs 350 checks on original/fixed
Vinix and Linux 6.12.51. Original Vinix fails 84 checks; fixed Vinix and Linux
pass all checks. Root and UID1000/GID2000 exercise seven count-register profiles
and ignored-negative, queued-socket, closed-slot, inaccessible and read-only
poll arrays. Each call checks exact return/errno, the complete guarded array,
unchanged signal mask and queued socket data. Zero-count calls ignore invalid
poll pointers. The parser passes three positive and 244 negative controls.

Both native kernels retain flat live slab classes, large pages at 222/222 and
allocator taint at 0/0 in each credential cohort after 64 warmup and 200 measured
matrix cycles. Linux explicitly skips Vinix allocator measurements. Independent
lifetime/arithmetic review passes, including generated fixture and kernel C.
The kernel adds one scalar conversion; its allocation and cleanup calls are
unchanged. After canonicalizing absolute-path hashes in ignored loop-variable
names, full generated C differs only in the poll entrypoint/declaration.

Both production architectures build in isolated worktrees from
`867f43bbbfbafffb44e5cad935ada4be9a3adad5` plus the retained file.v patch,
with V 0.5.2 `7d74206`, PROD=true, LIMINE_MP=1, ALLOC_TRACK=0 and link seed 42.
The baseline reuses the retained ppoll qualification's fixed x86-64 kernel;
its kernel sources match the new base before this patch. Its complete build
receipts and generated C are retained in this bundle. Fresh registered
pollcount, ppollargs and selecttimeout cases pass on the corrected x86-64 kernel.

Run `run.v --arch x86_64 --cases pollcount` with an isolated kernel and a fresh
external state directory. This explicitly selected case freezes both fixture
sources and has a 300-second default budget; AArch64 requests are refused.
`pollcount-reference.v` runs the identical native ELF on Linux and offers
`--self-test` for the strict parser. Build `pollcount-evidence.v` without `-prod`
and pass the complete bundle. It audits inventory, original failures, same-ELF
Linux/native receipts, flat storage, generated-C scope, reviewed identities,
registered regressions and both architecture builds.

Evidence is retained at `/Users/alex/.cache/vx-pc-1114/bundle`.
Its 256-file manifest has SHA-256
`18f354f03205e866f146daf5efd0c8353327e2f686d693492929f6f5070e927d`.

This qualifies native x86-64 count-register decoding at zero timeout. The
4096-entry cap, resource limits, timeout writeback/interruption, partial copies,
aliases and concurrent mutation, GNU/foreign/32-bit paths remain separate.
Broader §15 semantics, installation/integration and translated-runtime gates
remain open.
