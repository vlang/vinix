Build `run.v` with V into an external executable, then run it. Set
`AGX_VM_ALLOCATOR_BINARY` to retain the ASan/UBSan binary outside Git.

The runner extracts the production MMU context constructor/destructor, driver
buffer allocator/release and immutable identity allocation. It uses the real
pure VM geometry module. Locks, VA heaps, physical memory and UAT mapping are
injected services. Two hundred contexts and 1200 shared/private allocations
check normalized 32 KiB reservation boundaries and midpoint, minimum/stronger
alignment, 16 KiB dummy mapping, permissions, overflow refusal, inactive VMs,
physical/VA/map failure unwind and final release. Successful context metadata
is explicitly freed only by fixture cleanup after destruction; the kernel's
existing metadata retention is unchanged. No firmware/TLB execution or
whole-kernel heap measurements are claimed.
