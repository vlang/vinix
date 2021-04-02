module main

import lib
import memory
import stivale2
import x86
import drawing

const (
	boxcolor   = 0xff77ff
	vcolor     = 0x536b8a // from V logo
	vthickness = 10
	vwidth     = 500
	vy         = 100
	vx         = 100
)

fn C._vcleanup()
fn C._vinit(___argc int, ___argv voidptr)

pub fn kmain(stivale2_struct &stivale2.Struct) {
	memmap_tag := unsafe { &stivale2.MemmapTag(stivale2.get_tag(stivale2_struct, stivale2.memmap_id)) }
	if memmap_tag == 0 {
		lib.panic_kernel('Could not fetch all the required tags')
	}

	// Initialize the memory allocator.
	memory.physical_init(memmap_tag)

	stivale2.terminal_init(stivale2_struct)

	lol := u64(1234567890)

	// Hello world!
	stivale2.terminal_print('Hello world! $lol From vOS')

	// Initialize the earliest arch structures.
	x86.gdt_init()
	x86.idt_init()
	// C._vinit(0, 0) // makes array initializations and other unsupported stuff

	// Test pmm
	mut ptr := memory.malloc(40)
	ptr = memory.realloc(ptr, 8000)
	memory.free(ptr)
	// Fetch required tags.
	fb_tag := unsafe { &stivale2.FBTag(stivale2.get_tag(stivale2_struct, stivale2.framebuffer_id)) }
	memmap_tag := unsafe { &stivale2.MemmapTag(stivale2.get_tag(stivale2_struct, stivale2.memmap_id)) }
	if fb_tag == 0 || memmap_tag == 0 {
		lib.panic_kernel('Could not fetch all the required tags')
	}

	// Initialize the memory allocator.
	memory.physical_init(memmap_tag)
	mut fb := drawing.new_fb(fb_tag)

	fb.rect(800, 100, 100, 100, boxcolor)

	// big V
	for x in 0 .. vwidth / 2 {
		for i in 0 .. vthickness + 1 {
			fb.set(x + vx + i, x * 2 + vy, vcolor)
			fb.set(x + vx + i, x * 2 + vy - 1, vcolor)
			fb.set(500 - x + vx + i, x * 2 + vy, vcolor)
			fb.set(500 - x + vx + i, x * 2 + vy - 1, vcolor)
		}
	}
	for {
		asm volatile amd64 {
			hlt
			; ; a (ptr)
		}
	}
}
