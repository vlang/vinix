# Process inspection regression

This static guest init validates Linux `PR_GET_DUMPABLE` / `PR_SET_DUMPABLE`
and `process_vm_readv` / `process_vm_writev` on both syscall tables. It checks
fork/exec and effective-credential transitions, scatter/gather copies,
self demand pages, COW restrictions, page protections, partial transfers, malformed
vectors, same-user authorization, `/proc` maps and executable-link access,
and concurrent inspection versus exec/exit and munmap/remap.

Remote inspection retains the selected address space until the copy finishes;
exec/exit may detach it but cannot destroy it while it is in use. Authorization
is checked once when acquiring that address space, using real credentials for
`process_vm_*` and effective credentials for `/proc`. Later operations observe
dumpability changes. Capabilities from a distinct noninitial user namespace do
not grant access to the initial namespace.

Cross-process copies currently require target pages to be resident. An absent
page returns `EFAULT`, or a byte count if an earlier part transferred. This
restriction avoids faulting through mapping ranges that another process can
unmap while the fault resolver is outside its page-map lock. Self inspection
uses ordinary demand faults and COW resolution.

All remote writes also require the page to be writable without COW. Rejecting
remote demand/COW allocation prevents an
inspection syscall from bypassing the target's `memory.max`. The regression
creates a limited target and checks resident access succeeds, missing-page and
fork-shared COW writes fail, and `memory.current` stays unchanged. Extending
these cases needs pinned mapping-range lifetimes and stable remote cgroup
charging during target exec/exit.

After building the kernel for the selected architecture, run:

```sh
python3 tests/kernel-gaps/run.py \
  --source tests/process-inspection/test.c --kernel-dir kernel \
  --arch aarch64 --expect 'VINIX PROCESS INSPECTION: PASS'
```

Repeat with `--arch x86_64` after an x86-64 build. The runner compiles the test
against the appropriate static musl sysroot, boots an isolated QEMU guest, and
rejects missing verdicts, `FAIL:` output, and kernel failures. `ptrace`, register
control, single stepping, and ELF core generation are separate work; these
tests do not claim to provide them.
