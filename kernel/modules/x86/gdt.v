module x86

#include "modules/x86/gdt.h"

pub const kernel_code_seg = u16(0x08)

pub const kernel_data_seg = u16(0x10)

fn C.gdt_reload()

pub fn gdt_init() {
	C.gdt_reload()
}
