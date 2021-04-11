import lib
import memory
import stivale2
import x86

pub fn kmain(stivale2_struct &stivale2.Struct) {
	stivale2.terminal_init(stivale2_struct)

	// Hello world!
	stivale2.terminal_print('Hello world! From vOS')

	// Initialize the earliest arch structures.
	x86.gdt_init()
	x86.idt_init()

	// Fetch required tags.
	fb_tag := unsafe { &stivale2.FBTag(stivale2.get_tag(stivale2_struct, stivale2.framebuffer_id)) }
	memmap_tag := unsafe { &stivale2.MemmapTag(stivale2.get_tag(stivale2_struct, stivale2.memmap_id)) }
	if fb_tag == 0 || memmap_tag == 0 {
		lib.panic_kernel('Could not fetch all the required tags')
	}

	// Initialize the memory allocator.
	memory.physical_init(memmap_tag)

	// Test pmm
	mut ptr := memory.malloc(40000)
	ptr = memory.realloc(ptr, 80000)
	memory.free(ptr)

	for {
		asm amd64 {
			hlt 
		}
	}
}
