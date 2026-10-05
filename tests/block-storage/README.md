# Native block persistence and NVMe containment tests

Run `python3 tests/block-storage/run.py` with the host V compiler available
(or set `V=/path/to/v`). The runner compiles unchanged declarations and selected
functions from the native drivers with controlled clock, MMIO and allocator
substitutes. It checks:

- AHCI FLUSH CACHE/EXT FIS construction with zero PRDT entries, propagation of
  port errors, busy-port timeout, and refusal to reuse a failed port.
- NVMe namespace FLUSH, failed completion consumption, completion phase wrap,
  CID reuse, and correct completion doorbell updates.
- NVMe timeout containment: disabling a controller and observing RDY=0 permits
  freeing the submitted bounce/PRP buffers; a controller that stays ready keeps
  those buffers allocated. Later requests fail without submitting DMA, even if
  a late completion arrives.
- VirtIO FLUSH's header/status descriptor chain, unsupported-feature and device
  errors, and reclaiming a late completion before reusing shared buffers.

The AHCI RAM model cannot reproduce write-one-to-clear registers: its all-ones
PxIS clear write exercises the error path. Successful hardware completion needs
an emulator or real controller. The clock model advances while a kernel lock
would have interrupts disabled, matching the drivers' HPET/ARM timer deadlines.

`VINIX_KERNEL_DIR=/path/to/isolated/kernel VINIX_REBOOT_PERSISTENCE_NO_BUILD=1
 tests/reboot-persistence/run.sh` checks the real AArch64 VirtIO path across a
QEMU guest reboot. A passed reboot test verifies completion and restart
behavior; power-cut testing with a volatile device-cache model remains separate.

NVMe containment leaves the failed controller offline until reboot. Automatic
queue reconstruction, hot-unplug teardown, and proof of persistence on real
hardware remain follow-up work. The PCI NVMe driver retains its existing debug
build activation policy. Apple ANS's FUA/flush implementation is unchanged.
