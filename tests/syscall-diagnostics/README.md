# Checked syscall diagnostics

Build each architecture with `PROD=false` and select strict SMAP/PAN with
`vinix.user_access=strict`. The independent V guest invokes every VFS pathname diagnostic with address
1 and requires EFAULT, then checks valid stat/statx/getcwd and a failed wait
status copy followed by a successful retry. The debug formatter must not
dereference a user path before checked pathname copying runs.

```sh
VINIX_CMDLINE=vinix.user_access=strict \
python3 tests/kernel-gaps/run.py --arch x86_64 --no-network \
  --kernel-dir /path/to/debug-amd64-kernel \
  --source tests/syscall-diagnostics/guestfixture/core.v \
  --expect 'SYSCALL DIAGNOSTICS PASS' --timeout 180
```

Run the same command with `--arch aarch64` and the ARM debug kernel. Set
`VINIX_AARCH64_SYSROOT` when the userland sysroot is outside this checkout.
The original 46-line C oracle is recoverable at
`15048510:tests/syscall-diagnostics/guest.c`. Both native ABIs retain all
original checks and their diagnostic line numbers, including the child's
exit code 37. The fixture introduces no allocation and uses the SDK's native
`stat` layout; `--source` also accepts a materialized immutable C reference.
