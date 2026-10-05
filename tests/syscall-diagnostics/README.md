# Checked syscall diagnostics

Build each architecture with `PROD=false` and select strict SMAP/PAN with
`vinix.user_access=strict`. This guest invokes every VFS pathname diagnostic with address
1 and requires EFAULT, then checks valid stat/statx/getcwd and a failed wait
status copy followed by a successful retry. The debug formatter must not
dereference a user path before checked pathname copying runs.

```sh
VINIX_CMDLINE=vinix.user_access=strict \
python3 tests/kernel-gaps/run.py --arch x86_64 --no-network \
  --kernel-dir /path/to/debug-amd64-kernel \
  --source tests/syscall-diagnostics/guest.c \
  --expect 'SYSCALL DIAGNOSTICS PASS' --timeout 180
```

Run the same command with `--arch aarch64` and the ARM debug kernel. Set
`VINIX_AARCH64_SYSROOT` when the userland sysroot is outside this checkout.
