# PCI configuration transactions

`./run.sh` compiles the production V transaction core and links independent C
callers against its preserved ABI. Both GNU C dialects run with AddressSanitizer
and UndefinedBehaviorSanitizer. The transport model checks register widths and
bounds, unchanged outputs on error, serialized CF8 access, atomic COMMAND
updates, preserved interrupt state, and the adjacent write-one-to-clear STATUS
register. Allocator calls are replaced with traps.

The host transport model cannot validate real interrupt masking or ECAM access.
Build an ARM kernel with `PCI_CONFIG_TEST=1` and run `arm_vm.py --kernel <image>`
to exercise the actual platform transport and every DAIF mask combination.

`python3 topology_test.py` compiles the actual production V topology, capability
parser and checked transport core, then runs GNU99/GNU11 ASan/UBSan tests. Supply
`V=/path/to/v` when needed and `--keep-dir /tmp/new-directory` to retain compiler
inputs, logs and provenance. Only private allocation and synchronous transport
observers replace native services. The tests check explicit root borrowing,
bridge parents, all eight functions, malformed windows/chains, every private
OOM/transaction error and destruction after reader quiescence.

Build either architecture with `PCI_TOPOLOGY_TEST=1` for the read-only native
boot fixture, then pass `--pci-topology-test` to `arm_vm.py` or
`tests/linuxkpi/run_vm.py`. It reads actual root-zero configuration, compares the
private snapshot with permanent boot records, rejects every graph allocation
index and measures physical pages plus all live heap classes after three
warmups. The flag defaults to zero; harnesses reject an unexpected fixture.

The boot scanner supports domain-zero root zero and configured descendants;
firmware discovery of other roots remains pending. Published native device
pointers have boot lifetime. These tests supply no Linux PCI/device/devres
registration, hotplug, BAR sizing, DMA or GPU validation. The private graph has
recoverable OOM rollback; permanent vector/bitmap allocators retain existing
fatal-OOM behavior.
