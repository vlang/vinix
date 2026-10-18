Run `v run tests/agx-g13-failure/run.v --sanitize` from the repository root.
Set `V` to select the compiler and `AGX_G13_TEST_BINARY` to retain the native
executable for running on the M1 Air.

The V runner copies the production channel implementation and extracts the
production compute/render publishers, event handler, health check, worker and
shutdown functions into a temporary host build. It uses the real firmware
layouts. The fixture replaces
privileged locks, atomics, MMIO and manager hardware services; it executes no
GPU commands. Address/undefined-behavior sanitizers check malformed indices
against small actual buffers. The fixture records shutdown service order and
rejects recursive lock acquisition.

The tests cover both supported firmware ABIs, corrupt and wrapped ring
pointers, sticky errors, firmware-control pointer placement, log subchannels,
fatal-event drain termination, halt without a notification, and stopping
firmware before failing pending work. Malformed inner/outer submission indices
must leave all command buffers untouched and release every reserved lock;
successful submissions require barriers at both publication stages. Success
paths still reap normally.

Source-bound Apple instruction checks live in `tools/agx-re/g13failure`;
`g13contract` independently checks the older FWStatus wire layout against
m1n1. A native test pass on macOS does not validate Vinix firmware execution.
