module sys

import debug

const (
	// phys_base is the offset of kernel memory.
	phys_base = 0xFFFFFEFF00000000
	vma_base = 0xFFFFFFFF80000000
)

const (
	// bootloader_magic_mb2 is the magic number that get passed to the kernel
	// by MultiBoot2-compatible bootloaders.
	bootloader_magic_mb2 = u32(0x36D76289)
	// early_bootinfo_base is the offset of EarlyBootInfo passed to the kernel.
	early_bootinfo_base = u64(0xE00000)
)

pub struct EarlyBootInfo {
pub:
	magic u32
	boot_info u32
}

[inline]
fn banner() {
	build_date := v_build_date()
	compiler_version := v_version()
	printk('vOS/x86_64 [v${kernel_version} ${build_date}, V ${compiler_version}]')
}

fn (kernel &VKernel) init_platform() {
	debug.register_sink(new_debug_e9port())
	debug.register_sink(new_debug_dmesg_ring())

	fbcon_preinit()
}

fn (mut kernel VKernel) parse_bootinfo() {
	early_info := &EarlyBootInfo(phys_to_virtual(early_bootinfo_base))
	if early_info.magic == bootloader_magic_mb2 {
		init_multiboot2(mut kernel, early_info)
		return
	}

	printk('Unknown bootloader: ${&PtrHack(early_info.magic)}!')
	panic('cannot find any boot tags!')
}
