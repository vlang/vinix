import lib
import memory
import stivale2
import x86
import drawing

const (
	start_max_step = 2
	stop_max_step  = 1
)

pub fn kmain(stivale2_struct &stivale2.Struct) {
	// Initialize the earliest arch structures.
	x86.gdt_init()
	x86.idt_init()

	// Init terminal
	stivale2.terminal_init(stivale2_struct)

	memmap_tag := unsafe {
		&stivale2.MemmapTag(stivale2.get_tag(stivale2_struct, stivale2.memmap_id))
	}
	if memmap_tag == 0 {
		lib.kpanic('Could not fetch all the required tags')
	}

	// Initialize the memory allocator.
	memory.physical_init(memmap_tag)

	mut ptr := memory.malloc(40)
	ptr = memory.realloc(ptr, 8000)
	memory.free(ptr)

	mut step := 0
	step++
	lib.kprint('[$step/$start_max_step] Initializing framebuffer\n') // Cannot do these messages before because int.str() requires malloc
	mut fb := drawing.new_fb(unsafe {
		&stivale2.FBTag(stivale2.get_tag(stivale2_struct, stivale2.framebuffer_id))
	})
	step++
	lib.kprint('[$step/$start_max_step] Drawing test circle and lines\n')
	fb.circle(800, 450, 75, 0x536b8a)
	fb.line_thick(850, 300, 900, 400, 4, 0x536b8a)
	fb.line_thick(950, 300, 900, 400, 4, 0x536b8a)

	// We're alive
	lib.kprint('Welcome to vOS\n\n')

	step = 0
	step++
	lib.kprint('[$step/$stop_max_step] Shutting Down Kernel\n')
	for {
		asm volatile amd64 {
			hlt
			; ; a (ptr)
		}
	}
}
