import lib
import memory
import stivale2
import acpi
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

	// Initialize the memory allocator.
	memmap_tag := unsafe { &stivale2.MemmapTag(stivale2.get_tag(stivale2_struct, stivale2.memmap_id)) }
	if memmap_tag == 0 {
		lib.kpanic('Stivale2 memmap tag missing')
	}

	memory.physical_init(memmap_tag)

	// Call Vinit to initialise the runtime
	C._vinit(0, 0)

	// ACPI init
	rsdp_tag := unsafe { &stivale2.RSDPTag(stivale2.get_tag(stivale2_struct, stivale2.rsdp_id)) }
	if rsdp_tag == 0 {
		panic('Stivale2 RSDP tag missing')
	}

	acpi.init(&acpi.RSDP(rsdp_tag.rsdp))

	// Test vmm
	pagemap := memory.new_pagemap_from_current()
	pagemap.map_page(0xcafebabe000, 0xbabecafe000, 1)
	pagemap.switch_to()

	panic('End of kmain')
}
