# Native semaphore signed integer arguments

The corrected native ELF64 kernels pass 276 checks on both AArch64 and x86-64.
The identical static musl probe ELFs pass all 276 checks on Linux 6.12.51.
Each original Vinix kernel fails exactly 89 checks. The maintained runner passes
both `semword` (276 checks) and `semabi` (175 checks) on each candidate kernel.

The fix imports semaphore IDs, semget counts/flags and semctl indices/commands
as signed low 32-bit words. Upper register bits are ignored. Negative and
excessive semget counts return EINVAL before key lookup or exclusive-create
conflicts, matching the measured Linux error order. Existing-set, absent-key,
IPC_PRIVATE, removal and operation canaries exercise refusal and real mutation.
Vinix still limits a set to 32 semaphores and a vector to 32 operations.

Both production builds use isolated candidate
`955b4af34bd668722631cef7926be5a0a22cec1e`, based directly on
`51451adf1564de86e531b1de5a70f558d9bdb9b3`. The semaphore source SHA-256 is
`0e4a76e878aeb15a498e856dd8b8c7e32fa36fd35ff401a941f2152278270c9f`.
Before/after input maps are identical. Generated-C excerpts verify the integer
widths and validation order on both architectures. This change introduces no
allocation or lifetime changes; queue ownership and teardown are unchanged.

The portable `semword-evidence.v check` command rehashes the manifest artifacts
and binds compilation, matching-architecture ELFs, production builds, expected
baseline failures, Linux/native results and maintained-runner regressions.
Its controls reject six malformed result logs and a wrong ELF architecture.
The Linux controller separately passes two positive and nine negative parser
controls. Exploratory 240-check runs and unsuccessful compilation attempts are
retained separately; they are not final qualification results.

External toolchains and large boot media are recorded by content hash. This
bundle qualifies the isolated source change, not unrelated shared-checkout
changes or full reproducibility without the external dependencies. SEM_UNDO,
IPC permissions/namespaces, per-index GETPID, GNU libc and translated/32-bit
paths remain unqualified. The broader libc, installation/sandbox and foreign
application roadmap gates remain open.
