The regression boots one explicitly selected Vinix ARM64 kernel and runs the
same x86-64 glibc fixture with explicit old and new native QEMU translators.
It does not launch Steam or modify an existing translation/runtime layer.

```
VINIX_PRUNE_BUILD=0 python3 tests/dota2/wake-op-run.py \
    --kernel-dir /path/to/isolated/kernel \
    --old-translator /path/to/unpatched/qemu-x86_64 \
    --new-translator /path/to/patched/qemu-x86_64 \
    --base-root build/dota2-vulkan/test/root \
    --work build/dota2-wake-op-contract --run --timeout 180
```

Omit `--run` to prepare and hash the fixture without starting a VM. Use a fresh
work directory for every attempt; `inputs.json`, `vinix.log` and `results.json`
preserve the selected kernel, translators, runtime, fixture source, linker
script and built program hashes. `--runtime-root` and `--boot-repo` support
separate runtime and repository locations. An optional `--signal-probe` selects
a diagnostic observer explicitly. The host needs Clang with Linux x86-64 and
LLD support; the supplied root provides native BusyBox/musl and private glibc.

`wake-op.ld` places code at `0x410000` and writable data at `0x412000`: separate
4 KiB guest pages sharing one 16 KiB native page. Translating that code protects
the native page. The old translator must reproduce `EFAULT` for a valid native
`FUTEX_WAKE_OP` write. The new translator must perform the write and retain
errors for read-only, `PROT_NONE`, unmapped and unaligned operands, while allowing
write-only secondary memory and a read-only primary wake address.

A second thread continuously executes the protected code. Each of 128 native
writes is followed by a published generation; the worker acknowledges it only
after executing the code. The parent waits outside the futex syscall with a
15-second monotonic deadline, and all 128 writes and acknowledgements must
succeed. This proves code execution between write steps; it does not trace
native page reprotection at every step. A 30-second process alarm and the host
timeout bound failure. The host reaps its VM after the result marker or timeout.

Older kernels may independently accept unaligned futex operands or return the
wrong error. The report records those old-translator alignment mismatches
separately from preserved permission behavior. All new-translator assertions
remain required. This focused regression does not certify the separate full
futex contract or resolve its intermittent misaligned-stack fault.
