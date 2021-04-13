import lib
import memory
import stivale2
import x86

pub fn kmain(stivale2_struct &stivale2.Struct) {
	// Initialize the earliest arch structures.
	x86.gdt_init()
	x86.idt_init()

	// Init terminal
	stivale2.terminal_init(stivale2_struct)

	// We're alive
	lib.kprint('Welcome to vOS\n\n')

	memmap_tag := unsafe { &stivale2.MemmapTag(stivale2.get_tag(stivale2_struct, stivale2.memmap_id)) }
	if memmap_tag == 0 {
		lib.kpanic('Could not fetch all the required tags')
	}

	// Initialize the memory allocator.
	memory.physical_init(memmap_tag)

	// Test pmm
	mut ptr := memory.malloc(40)
	ptr = memory.realloc(ptr, 8000)
	memory.free(ptr)

	for {
		asm volatile amd64 {
			hlt
			; ; a (ptr)
		}
	}
}
