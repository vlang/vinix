# PCI configuration transactions

`./run.sh` compiles the production V transaction core and the independent V
oracle in `configfixture/`, using the preserved native C ABI. GNU99 and GNU11
run with AddressSanitizer and UndefinedBehaviorSanitizer. All 71 original
assertion sites, device vectors, 10,000,000-spin progress bound and atomic memory
orders remain. The model checks register widths and bounds, unchanged outputs
on error, serialized CF8 access, atomic COMMAND updates, preserved per-thread
interrupt/pin state, and the adjacent write-one-to-clear STATUS register.
Allocator imports are replaced with traps in the production core only; the
oracle's pthread/libc backing retains its normal ownership.

Pass `--source /immutable/config_test.c` to run a frozen original C control, and
`--keep-dir /new/evidence-directory` to retain compiler inputs, both dialect
objects, binaries, logs and input hashes. Select V with `V` or
`VINIX_V_COMPILER`; the selected compiler also supplies `VEXE`. Default Darwin
runs disable LeakSanitizer and make no LeakSanitizer claim. Only generated V
objects receive unused-helper/parameter warning exceptions. Five byte-identical
repeated V forward typedefs are normalized for strict GNU99, with raw bytes and
a normalization receipt retained; no generated function body is changed.

The private native header contains declarations, native constants and layout
checks. Its five bool/unsigned thread-local words retain the original true/zero
initializers because the Vinix V backend cannot emit general TLS. Those two
original storage declaration lines receive no V algorithm credit. V owns all
transport/oracle algorithms and permanent device banks. Actor records and byte
snapshots stay on the stack; the actual exported C callback wrapper is passed
to pthread, and both actors are joined before their records disappear.

The frozen original control is available at
`1696dbaf6be3d2379c420288abde4268d0455a77:tests/pci-config/config_test.c`.
Its C/V GNU99/GNU11 host sanitizer controls pass, and both complete C/V native
model controls pass on ARM and x86 with the recorded default kernels. These
fixture-only controls reuse those kernels; they add no fresh kernel build claim.
Both dialects have identical loaded instructions/data/TLS within each native
C/V build (apart from build IDs); GNU11 runs each full native control. Actual
FAT/ISO kernel and init payloads match the separately built SDK artifacts.
Native mutex/actor/observation layouts match the original on both SDKs, and a
supplementary V observer verifies initial TLS values and independent addresses
across three live host threads. These native runs retain the 180-second harness
deadline and 1024 MiB guest memory. Retained evidence is in the local
`pci-config-fixture/native-validation.json` migration cache. Two earlier ARM
runs also passed, but the helper removed their temporary boot images; the final
pair repeats the unchanged workload with boot-image retention enabled.

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
