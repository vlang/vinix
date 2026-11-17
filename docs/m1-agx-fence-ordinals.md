# 32-bit G13 fence numbering

Both G13 submit ABIs number each batch's finished fence using its queue's
counter. The sequence starts at 1, crosses the signed boundary as an unsigned
value and wraps from `0xffffffff` to 0. The counter lives in the retained
queue record.
The owning file lock serializes assignment at the point where Vinix creates
its finished fence. A pre-fence failure leaves the counter alone. An error
after fence creation can consume a number, including when an output sync has
already received the fence. A recreated queue starts at 1 with a new context.

The change matches the numerical sequence of the packaged reference, where
entity creation initializes the count to zero and job arming puts an
incremented unsigned value in the finished fence. Tests used Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf` and an isolated Vinix checkout at
`e44893621` with this patch. [Asahi submission](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs) ·
[Packaged scheduler fence initialization](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/scheduler/sched_fence.c)

Vinix's native fences continue to complete independently. Consumers and
timeline transfers retain distinct fence instances across wrap, including when
they share the same queue context. Asahi's signed delta comparison for ordered
fences remains a separate scheduler difference.

The ASan/UBSan submission suite passed both ABIs at fresh, signed-boundary and
wrapping sequences. It checked reverse retirement across queues, numbering
after wrap, same-handle queue recreation, one number for a 64-command batch
and sequence consumption during fault injection. Restoring the clock-based
submit path failed the first ordinal assertion. File-close, G13 recovery and
DRM synchronization suites passed, as did 82 V test files and the five
protocol source gates.

AArch64 MP and x86_64 kernels both built. ARM DWARF confirms the counter fits
in the previous queue record padding and the record still occupies 0x3518
bytes. Generated C increments the unsigned field and widens it when creating
the fence. The compiler reported the same allocation counts by file and
kind as before, with 377 ARM and 289 x86 sites. Existing allowance failures
remain.

Validation injected completion events and excluded the concurrent event
edit. Hardware execution, deployment and reboot were outside this run.
Generic DRM timeline capability reporting and the matched Mesa image remain
open.

```sh
ASAN_OPTIONS=detect_stack_use_after_return=1 \
  v run tests/agx-async/run.v --audit-dependency-order
ASAN_OPTIONS=detect_stack_use_after_return=1 \
  v run tests/drm-syncobj-wait/run.v
```

Complete inputs, executables, logs and the verified archive restoration are
under `/Users/alex/.local/state/vinix/omarchy-m1-fence-ordinals-20261117/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `b7b83249dad98077ed27ae41627e59c3360ba6950753e0d40b3bbb0fee0cedba` |
| `bundle.tar.gz.inventory.txt` | `9fd7ef45f82dcb3563c388dd1996956069592c3bc70905ba8f914dfc1d06821f` |
