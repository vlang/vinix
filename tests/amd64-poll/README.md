# amd64 poll guest regression

The independent fixture is maintained in `pollfixture/core.v`. Build with an
x86_64 musl GCC toolchain and run against an isolated kernel:

```sh
CC_AMD64=x86_64-linux-musl-gcc python3 tests/amd64-poll/run.py \
  --kernel-dir /path/to/isolated/kernel \
  --state-dir /path/to/new/poll-build \
  --guest-state-dir /path/to/new/poll-guest
```

Build the amd64 kernel first (`./scripts/build-amd64.sh --no-userland --no-iso`). Boot the diagnostic ISO in an isolated QEMU/KVM x86_64 guest with UEFI, VGA, HPET, and COM1 serial capture. The init forks a test worker and prints `TEST RESULT: PASS` or `FAIL` on COM1. It then sleeps; terminate only the test VM from the host. Use a host-side timeout to detect a kernel crash or blocked syscall. Do not run these guest tests on the host.

The runner uses QEMU TCG with a 300-second outer boot allowance. All 29 original
checks remain, including 40-ms sleeping, both 50-ms child writes, duplicate FD
readiness, HUP, invalid syscall inputs and the original 32/33-event limits. Fixed
pipe/pollfd records remain on the stack through the original reap/close order;
the generated object has no allocator imports. `--build-only` emits the static
executable, and `--original-reference /path/to/frozen/test.c` builds an immutable
original control with the same SDK and warning policy. Both native C/V controls
passed. This fixture uses x86 `SYS_poll` and Vinix-specific event limits; it adds
no ARM, host sanitizer or new production-kernel claim.
