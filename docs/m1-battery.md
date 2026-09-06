# M1 SMC battery percentage (experimental)

Enable the read-only battery driver on an M1 with the exact kernel command-line
option `vinix.apple_battery=1`. It is off by default; `vinix.apple_battery=0`
disables it, and the last battery option wins. Keep a known-good boot entry.
This is independent of the GPU/DCP options. Rebuild using the existing working
ARM64/M1 build procedure; the kernel makefile discovers the new C source.

## Userspace ABI

After a successful probe, `cat /dev/battery` returns a decimal integer in 0..100
followed by a newline. Each open-file description captures one snapshot on its
first nonempty read, supports short reads, then returns EOF. Reopen for a fresh
sample. `dup()`/`fork()` share that snapshot. A panel should reopen every few
seconds and treat missing devices, read errors and invalid text as unavailable,
never as 0%.

The node is mode 0444. Writes and resizing are refused; mmap and control ioctls
are unsupported. A missing device/initially absent BRSC leaves the node absent.
Registered devices return EIO on failed or stale samples, ENODEV on a later
missing key, and EFAULT for invalid output pointers through checked usercopy.
Console diagnostics start with `apple-smc:`.

## Implementation and limits

`kernel/modules/apple/smc/smc.v` discovers an enabled `apple,t8103-smc`, its
translated named SRAM resource, and its zero-argument `mboxes` provider. The
provider must be an enabled `apple,asc-mailbox-v4` with a valid translated MMIO
range. No physical register addresses are guessed. The existing Apple mailbox
implementation provides Device mappings and ordering barriers.

The freestanding C core negotiates RTKit 11/12, completes IOP/AP power-state and
endpoint negotiation, starts endpoint 32, and requests the SMC SRAM address.
Firmware-owned system buffers must fit the DT SRAM region. They are not mapped
or read; log and IOReport notifications are acknowledged. Host DMA allocations
are unsupported. This separate SMC client does not change the GPU-oriented
shared RTKit implementation. It must be the sole owner of its mailbox.

Only SMC GET_SRAM_ADDR (0x17) and READ_KEY (0x10) are sent. BRSC is read as an
inline, little-endian ui16, with checked status, message ID, size and 0..100
range. There is no B0RM fallback. SRAM-address replies are raw addresses rather
than ordinary tagged command completions.

A worker drains messages approximately every 100 ms and samples at most once
per second. It owns the protocol state, waits outside the Resource spinlock,
and publishes a result plus the original sample timestamp under a short lock.
A new handle rejects samples at least two seconds old. Existing open handles
retain their snapshot. Cache hits never renew the sample age.

Boot negotiation has a two-second counter deadline; commands have 100 ms
deadlines. Receive loops also have iteration caps and do not use WFE to wait
for an uninstalled mailbox interrupt. These are protocol-loop bounds, not a
promise about scheduler delays or MMIO faults. In-flight timeouts, malformed
transport replies, resets/crashes and invalid firmware buffers disable the
instance until reboot: retrying after four-bit message-ID wrap could confuse a
late reply with a later request. Completed key errors and invalid percentages
can be retried after the cache interval.

There are no charging, GPIO, notification-enable, shutdown or reboot key writes.
RTKit negotiation/acknowledgments still send mailbox messages; read-only refers
to the battery/control-key interface. Suspend/resume recovery, interrupt-driven
service, host-allocated firmware buffers and other SoCs are not implemented.

## Validation

Run from the repository root:

```sh
./tests/apple_smc/run.sh
CC=clang SANITIZE=1 ./tests/apple_smc/run.sh
```

The 24 host test groups exercise the real C core against a simulated peer:
negotiation, buffers, SRAM bounds, all percentages, formatting, byte order,
malformed replies, IDs, notifications, cache age, timeout poisoning, late
responses, stopped clocks, floods, transport failures and counter/ID wrap.
Every outgoing SMC application request is checked to be read-only. With Clang,
the runner also cross-compiles the core and counter accessor for AArch64.

These tests and sanitizer checks passed during development. The V wrapper,
complete kernel build and real M1 hardware have NOT been validated here. For
hardware testing retain a known-good kernel, test with the option absent and
present, inspect diagnostics, exercise one-byte and concurrent reads, and verify
that a freshly opened device tracks charge changes. A full V build and hardware
validation must precede enabling this driver by default.

## Primary protocol references

- SMC key descriptions: https://asahilinux.org/docs/hw/soc/smc/
- SMC transport: https://github.com/openbsd/src/blob/master/sys/arch/arm64/dev/aplsmc.c
- RTKit and firmware buffers: https://github.com/openbsd/src/blob/master/sys/arch/arm64/dev/rtkit.c
- SMC binding: https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/mfd/apple,smc.yaml
- Mailbox binding: https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/mailbox/apple,mailbox.yaml

Originally prepared against cf9d952376ca96af721a182b3604a07742717050 and integrated
on top of the subsequent Settings/Display changes without altering them.
