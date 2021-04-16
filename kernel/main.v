import lib
import memory
import stivale2
import x86

fn C._vinit(argc int, argv voidptr)

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
		lib.kpanic('Stivale2 memmap tag missing')
	}

	// Initialize the memory allocator.
	memory.physical_init(memmap_tag)

	// Call Vinit to initialise the runtime
	C._vinit(0, 0)

	// Test pmm
	mut ptr := memory.malloc(40)
	ptr = memory.realloc(ptr, 8000)
	memory.free(ptr)

	panic('End of kmain')
}
