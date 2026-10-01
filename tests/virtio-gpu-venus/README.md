# Native Venus ABI and lifetime checks

`build-venus-aarch64.sh` builds both tests into `/opt/venus/bin`; the native
OpenGothic harness runs them before the desktop starts.

`venus-abi` creates a Venus context and submits 1,032 empty ring-zero fences.
Submissions alternate the default timeline and an explicit ring-zero index.
Each exported descriptor must immediately poll readable and close cleanly.
The last 1,024 submissions are bracketed by slab snapshots.

`venus-smoke` creates a Vulkan instance and device, fills a 64 KiB GPU buffer,
waits for its fence, maps the buffer and checks every word. It destroys all
objects and repeats four warmup and 32 measured cycles. A short grace period
on both sides excludes deferred reclamation from the slab snapshots. The
expected device is `Virtio-GPU Venus`, and every measured slab class should
stay flat.

With a kernel built using `ALLOC_TRACK=1`, set `VINIX_VENUS_ALLOC_TRACK=1`
inside the guest to print live allocation sites as `PERF-SITE` lines. Resolve
them using `tests/kernel-allocs/sites.py kernel/bin/vinix < run.log`.
Use the regular kernel for FPS measurements. See
[../opengothic/README.md](../opengothic/README.md) for the full gameplay test.
