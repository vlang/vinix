@[has_globals]
module main

// Kernel entry point - shared definitions.
// Arch-specific kmain() and kmain_thread() are in main_amd64.v / main_arm64.v.

import lib.stubs
import limine

#include <symbols.h>

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile limine_base_revision = limine.LimineBaseRevision{
		revision: 2
	}
)

fn C._vinit(argc int, argv voidptr)

pub fn main() {
	kmain()
}
