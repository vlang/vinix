# Native select ready-bit counts

select and pselect6 now count every returned bit across the read, write and
exception sets. A descriptor ready in both read and write sets contributes
two to the result. The shared implementation previously counted it once.
This change only adjusts the scalar counter; descriptor references, waits,
allocation and release paths retain their existing ownership.

The unchanged static musl probes run on Linux 6.12.51 and both original and
corrected production kernels. They exercise raw pselect6 and musl
pselect/select on both architectures, plus raw select on x86-64, as root and
UID1000/GID2000. Four descriptor layouts include an alias above descriptor
64 and three selected descriptors, all seven set combinations, zero/finite
timeouts and complete bitmap/canary checks.

UNIX stream, datagram and seqpacket socket cases qualify the count correction:
5,040 AArch64 and 6,720 x86-64 checks pass. Original kernels fail 288 and 384
socket count checks respectively. Linux passes every socket and regular-file
case, totaling 6,720 AArch64 and 8,960 x86-64 checks.

The same probe exposed a separate preexisting failure: ordinary tmpfs files
report no read/write readiness. The complete corrected-kernel runs retain
672 AArch64 and 896 x86-64 failures, all from regular-file cases. Complete
original-kernel runs retain 960 and 1,280 failures respectively. Those failures
remain visible and the full maintained selectready case remains failing.

Separate root and UID1000 storage cohorts warm 64 repeated calls, then measure
200 cycles across every available API using stable socket descriptions.
Every live slab class, large-page count and write-after-free counter stays
flat on original and corrected kernels. The reference boot explicitly skips
Vinix heap inspection. Generated-C comparisons allow only absolute-source-path
hashes in ignored-variable names and the do_select counter change; allocation,
release and ppoll call counts stay unchanged.

The isolated source base is `461e2ac18`. Its kernel source matches the prior
empty-wait candidate except for this count correction. Both architectures
build with V `b25b2d9`, `PROD=true`, `LIMINE_MP=1`, `ALLOC_TRACK=0` and link
seed 42. AArch64 uses 16 KiB native pages and four virtual CPUs; x86-64 uses
4 KiB pages and two virtual CPUs.

The retained bundle includes original/corrected kernels and generated C,
probe and reference-launcher ELFs, build/compile receipts, source snapshots,
images, raw logs and failed preparation attempts. Early compilation attempts
exposed V stack escapes; the final freestanding probes use explicit stack
storage. An initial reference boot exposed an initramfs /tmp permission
mistake, corrected before ordinary-user comparisons.

Closed-descriptor errors, regular-file readiness, timeout writeback, general
argument/error precedence, cancellation, races, GNU libc and foreign/32-bit
paths remain separate. Section 15's broader gates remain open.
