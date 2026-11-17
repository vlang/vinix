Build `run.v` with V into an external executable, then run it. Set
`AGX_VM_ALLOCATOR_BINARY` to retain the ASan/UBSan binary outside Git.
`AGX_VM_ALLOCATOR_MMU_SOURCE` selects an alternate MMU source for a negative
control.

The runner extracts the production MMU context constructor/destructor, driver
buffer allocator/release and immutable identity allocation. It uses the real
pure VM geometry module. Locks, VA heaps, physical memory and UAT mapping are
injected services. The 16 KiB and 4 KiB PMM models each exercise 200 contexts
and 1200 shared/private allocations. They check that the dummy mapping owns
one zeroed 16 KiB allocation, as well as normalized reservation boundaries
and midpoint, minimum/stronger alignment, permissions, overflow refusal,
inactive VMs, physical/VA/map failure unwind and final release. Fixture cleanup
frees the retained context metadata after destruction.
