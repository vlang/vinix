# Anonymous paging tests

Run production codec, crypto, backing-store and mapping functions with host
fixtures:

```sh
V=/path/to/v VINIX_HOST_SANITIZE=1 sh tests/paging/run-host.sh
```

The suite checks 4 KiB/16 KiB compression, malformed streams, RFC 8439 ChaCha20
and RFC 4231 HMAC-SHA256 vectors, encrypted disk contents, tampering, slot reuse,
short I/O, failed writes, allocation failure, swapoff rollback, pending refault
and unmap races, stale zero-page capture, shared alias revocation, locked/busy
aliases, fork backing lifetimes, pressure-cursor wrap with a 300-page target and
foreground reclaim past 600 locked mappings. It also runs the existing
private-file page suite. AddressSanitizer and UndefinedBehaviorSanitizer are
optional via the flag above.

The independent device-policy sanitizer fixture also checks swap claims against
active writes, pending mounts, mounted extents, overlapping aliases and disjoint
devices:

```sh
V=/path/to/v python3 tests/mounted-disk-policy/host.py
```

Build the kernels in isolated worktrees with their untracked dependencies linked,
then boot the guest on both architectures:

```sh
python3 tests/paging/run.py --arch aarch64 --kernel-dir /work/arm/kernel \
  --memory 256 --pressure --state-dir /tmp/paging-arm
python3 tests/paging/run.py --arch x86_64 --kernel-dir /work/x86/kernel \
  --memory 256 --pressure --state-dir /tmp/paging-x86
```

The runner creates its own 256 MiB raw swap image and static init, attaches the
device and requires both encrypted-disk/swapoff and final success verdicts.
The AArch64 build uses `VINIX_AARCH64_SYSROOT` (default
`build-aarch64-userland/sysroot`); x86-64 uses `CC_AMD64` (default
`x86_64-linux-musl-gcc`). QEMU and the existing boot-image tools are required.
Artifact paths must contain no spaces because the AArch64 launcher splits
`VINIX_QEMU_EXTRA` into arguments. The state directory and transcripts are kept
for inspection; only its dedicated `swap.img` is recreated on each run.

Guests check mincore residency, private fork isolation, protection changes,
discard, locked pages, shared fork aliases across remap, concurrent refault with
signals, private and shared encrypted disk faults, raw-write exclusion and
swapoff. `--pressure` touches anonymous memory equal to physical RAM without
explicit pageout, requires the pageout counter to increase and checks all data.
After warmup, 200 map/pageout/unmap cycles print per-class `PAGING SLAB` deltas;
compressed storage must return to its pre-churn baseline.

Broader validation uses `tests/desktop-perf/run.py` scenarios `ops,churn,cache`
and `idle,apps,drag`, together with `tests/kernel-allocs/run.sh`. The allocation
allowlist must be compared against the repository/compiler baseline rather than
accepting unrelated allocation warnings.

Validation on 2026-10-09: both kernel builds, host sanitizer suites, device-policy
sanitizers and 256 MiB pressure guests passed. Every reported slab class stayed
flat across 200 paging cycles on both architectures. The broader syscall,
process-churn, cache and desktop idle/apps/drag scenarios completed; they still
report existing retention outside the pager paths.

The allocation audit compiled both architectures successfully. Against an
unchanged checkout with the same compiler, allocation counts were identical:
432 AArch64 sites, 318 x86-64 sites and the same 179 allowlist failure groups.
Paging added no reported allocation categories; the allowlist was not changed.
