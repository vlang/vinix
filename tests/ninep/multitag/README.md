# Disposable multi-tag 9P qualification

These files are separate from the frozen Mission16-A / Path B harness.
Run the host proof with:

```sh
V=/home/agent/code/v/v /home/agent/code/v/v run tests/ninep/multitag/run.v
```

The runner copies the production facade, client, and transport into disposable
directories within this lane. Two independent wire fixtures exercise the real
facade and client; a separate DMA fixture exercises the real channel code.
Checks cover distinct mount adapters, per-tag clients/buffers/devices,
simultaneous independent reads/writes of the same filename, unknown-tag ENODEV,
same-tag remounts, detach isolation, independent close and quarantine, and
allocation-free generated C for seven read/write functions. Hardware discovery
is stubbed in the host tests; PCI/MMIO discovery requires a guest run.

Compile `guest.v` statically against the target userland libc and install it as
`/init` in a **private** boot image containing the changed production kernel.
Do not install it into the qualified single-tag image. Example host build:

```sh
/home/agent/code/v/v -cc clang -gc none -cflags -static \
  -o ../multitag-guest tests/ninep/multitag/guest.v
/home/agent/code/v/v -cc clang -o ../multitag-controller tests/ninep/multitag/host.v
../multitag-controller /absolute/path/to/private.iso /absolute/path/to/new-output
```

The controller boots x86 QEMU with TCG and two `-virtfs` exports, `tag-a` and
`tag-b`, each pointing at a new empty host directory. The ISO must support BIOS
boot, as the controller does not fetch firmware. The guest mounts both tags,
creates `value` independently on both, checks unknown-tag ENODEV before and
after mounting, unmounts A while retaining an open B descriptor, reads and
writes B, then remounts A and verifies its content. PID 1 parks after logging
its outcome. The controller has a 120-second deadline and stops only its own
QEMU process. It requires every stage marker and independently reads both
host files (`AAA\n` and `CCC\n`) before writing a PASS receipt.

The controller requires an existing boot image; compiling it or the guest is
not evidence of a successful kernel boot. See the lane report for actual run
status and environment limitations.
