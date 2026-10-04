# Opt-in syscall instruction policy

Vinix's native Linux syscall entry paths can check an exact instruction address
for each syscall number. A cooperating runtime registers copied syscall veneers
once per image and chooses audit or enforcement. Ordinary Linux executables
start with the policy disabled; this does not yet load ELF pin tables or modify
musl, glibc, Go, or the foreign-architecture translators.

The design follows OpenBSD's per-number instruction checks in
[syscall_mi.h](https://github.com/openbsd/src/blob/3ce1f3f79392ae4d60ce67bea5835d517caaa2ca/sys/sys/syscall_mi.h)
and one-time registration in
[uvm_mmap.c](https://github.com/openbsd/src/blob/3ce1f3f79392ae4d60ce67bea5835d517caaa2ca/sys/uvm/uvm_mmap.c).
The Vinix extension uses Linux `prctl` and a restricted anonymous-text contract;
it does not accept OpenBSD's ABI, ELF segment, or wildcard offset encoding.

## ABI

Call `prctl(0x56490002, action, request, 0, 0)`. Actions are:

| Action | Result |
| --- | --- |
| 0 | Return mode: 0 disabled, 1 audit, 2 enforce. `request` must be zero. |
| 1 | Install the version 1 table in audit mode. |
| 2 | Install the version 1 table in enforce mode. |
| 3 | Return the violation count. `request` must be zero. |
| 4 | Strengthen an installed table to enforce mode. `request` must be zero. |

For installation, `request` points to this native little-endian layout:

```c
struct vinix_syscall_pin {
    uint32_t number;   /* Native Linux syscall number, less than 512. */
    uint32_t flags;    /* Must be zero. */
    uint64_t offset;   /* Offset of the SYSCALL/SVC instruction from base. */
};
struct vinix_syscall_pin_request {
    uint64_t version;  /* 1 */
    uint64_t base;
    uint64_t length;
    uint64_t entries;  /* Pointer to vinix_syscall_pin[count]. */
    uint64_t count;
    uint64_t reserved; /* Must be zero. */
};
```

The table has 1–512 entries, sorted strictly by number, with unique offsets.
Offset zero is valid. The base and length must be aligned to the kernel's
native page size; the nonempty span is limited to 64 MiB and must stay entirely
in userspace. Every instruction fits inside that span. Registration validates
the resident instruction bytes: AMD64 `0f 05`, or an aligned ARM64 `svc #0`
(`d4000001`). Malformed input returns `EINVAL`, inaccessible copies or absent
instruction pages `EFAULT`, and allocation failure `ENOMEM`.

## Runtime contract

Copy dedicated syscall veneers into private anonymous memory, synchronize
instruction caches where required, change the span to readable executable
memory, and seal it with Vinix's existing `mimmutable` syscall. Every mapping
in the registered span must be immutable, executable and nonwritable, with
neither `MADV_DONTFORK` nor `MADV_WIPEONFORK`. Holes, shared mappings and
file-backed mappings are rejected with `EPERM`. File-backed text could otherwise
change through its backing file after validation.

Install before publishing another thread. Registration holds the same
`threads_lock` as `CLONE_THREAD` attachment while checking the sole-thread
condition and publishing the table. Descriptor and record copies happen before
that lock, so they can page in safely. Non-thread `CLONE_VM` currently copies
the address space in Vinix; a future implementation of shared process address
spaces must preserve this policy and immutable-mapping contract.

Each number must use its own registered instruction. A runtime's generic
`syscall()` wrapper does not automatically satisfy this contract. Once
enforcement is enabled, all calls—including policy queries, exit, exec and a
signal handler's `rt_sigreturn`—must use their registered veneers. There is no
automatic exception for libc or the kernel-supplied signal restorer. Include a
registered `prctl` veneer to query or strengthen the policy.

Audit increments the counter and permits an invalid origin. A query from an
unregistered instruction itself counts as a violation; use the registered
query veneer when measuring. Enforcement ends the entire process with
uncatchable `SIGABRT` through the existing fatal-exit path. Origin checks run
before seccomp and pledge; passing the pin check grants no additional syscall
permission. The policy controls are allowed by pledge's `stdio` promise.

Successful installation is one-time until exec. It cannot be replaced or
weakened; failed installation leaves the process unconfigured. Fork inherits
the immutable table and mode, with a fresh violation count and an independent
mode that may be strengthened. Exec clears the table, mode and count after
stopping siblings and installing the replacement image. The table is kept
under a process lock during checks, reference-shared at fork, and freed after
its final exec/reclamation release. Entry checks use a bounded binary search
and allocate no memory.

## Verification and remaining work

See [the regression instructions](../tests/syscall-policy/README.md) for actual
guest and generated-production-code sanitizer tests. This implements the
runtime registration and native entry checks for SEC5. Automatic executable or
interpreter table loading, a toolchain/runtime contract for normal Linux text,
and default enforcement remain outstanding.
