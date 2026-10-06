# Large-allocation metadata checks

Run `tests/memory/run-big-metadata.sh` to compile the production metadata
implementation in optimized host tests with 4 KiB and 16 KiB pages. The cases
check valid geometry, each corrupted header word, address-bound cookies,
invalidated headers and coherently rewritten sizes that would overflow
ceiling arithmetic. The cookie detects accidental/incomplete corruption; it
is not a secret MAC and does not prevent a coherent attacker rewrite or a
stale pointer after address reuse.

For native validation, build an isolated kernel with
`VFLAGS='-d heap_selftest -d vmap_selftest'`. Ensure the generated V object is
rebuilt when changing test flags; they are not part of the ordinary make
configuration stamp. `heap_selftest` executes before V initializes derived
constants on amd64, so the size ceiling is evaluated from the current native
page size inside a function. Both tests use the actual production allocator,
and the vmap test exercises scattered-page realloc/free and PMM accounting.
The heap test runs during early boot before the ARM UART has initialized;
a complete boot with that define confirms completion even when its success
message is suppressed. Production builds also suppress its ordinary printf.

The syscall workload runs 300 large reads, writes and failed-copy reads/writes.
Every request obtains/releases a kernel bounce allocation, and the final
large-page accounting must match its warmed baseline after startup storage has
retired (three snapshots and a seven-second grace):

```sh
python3 tests/kernel-gaps/run.py --arch x86_64 --no-network \
  --kernel-dir /path/to/kernel --source tests/memory/bigio/core.v \
  --expect 'vmap: self-test passed' --expect 'BIG IO PASS:' --timeout 240
```

Repeat with `--arch aarch64` and its build. Build and run again with
`-d vmap_always` added to the flags to force scattered backing after the
kernel page map has initialized. This checks the direct and independently
tracked vmap allocation paths, including their header invalidation and
large-page accounting. A repeated free is rejected before dereferencing an
unmapped vmap header; ordinary PMM direct-map headers remain mapped and are
invalidated/poisoned before reuse.

The maintained guest is V. Its 17 original checks, 300 rounds, seven-second
grace and exact page equality remain unchanged. Compare it with an immutable
C reference on an actual host architecture using the shared V syscall model:

```sh
python3 tests/memory/test-big-io.py --host-arch arm64 \
  --state-dir /tmp/big-io-host --original-reference /path/to/original.c
```

Repeat with `--host-arch amd64` for the x86 host ABI. The 22 sanitizer cases
cover success, short reads/writes, malformed accounting, wrong EFAULT returns,
interrupted settling and close failures. Native validation uses `--arch`,
`--kernel-dir` and a fresh `--guest-state-dir`, preserving the original
240-second outer allowance. The optional `--original-reference` builds the
same immutable C control for comparison. Baseline kernel builds do not
establish the separate `vmap_always` self-test configuration described above.
