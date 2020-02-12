module sys

const (
	// PHYS_BASE is the offset of kernel memory.
	PHYS_BASE = u64(0xFFFFFEFF00000000)
	VMA_BASE = u64(0xFFFFFFFF80000000)
)

const (
	// BOOTLOADER_MAGIC_MB2 is the magic number that get passed to the kernel
	// by MultiBoot2-compatible bootloaders.
	BOOTLOADER_MAGIC_MB2 = u32(0x36D76289)
	// EARLY_BOOTINFO_BASE is the offset of EarlyBootInfo passed to the kernel.
	EARLY_BOOTINFO_BASE = u64(0xE00000)
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
	printk('vOS/x86_64 [v${KERNEL_VERSION} ${build_date}, V ${compiler_version}]')
}

fn (kernel &VKernel) init_platform() {
	kernel.register_debug_sink(new_debug_e9port())
	kernel.register_debug_sink(new_debug_dmesg_ring())

	fbcon_preinit()
}

fn (kernel &VKernel) parse_bootinfo() {
	early_info := &EarlyBootInfo(phys_to_virtual(EARLY_BOOTINFO_BASE))
	if early_info.magic == BOOTLOADER_MAGIC_MB2 {
		kernel.parse_multiboot2(phys_to_virtual(early_info.boot_info))
		return
	}
	printk('Unknown bootloader: ${&PtrHack(early_info.magic)}!')
	panic('cannot find any boot tags!')

}

fn fb_test(framebuf voidptr, width u32, height u32, pitch u32) {
	onefifth := int(height) / 5

	for y := 0; y < int(height); y++ {
		for x := 0; x < int(width); x++ {
			if y < (onefifth * 3) && y > (onefifth * 2) {
				memputd(framebuf, y * int(pitch) / 4 + x, 0xFFFFFF)
			} else if y < onefifth || y >= (4 * onefifth) {
				memputd(framebuf, y * int(pitch) / 4 + x, 0x55CDFC)
			} else if y < (onefifth * 2) || y < (onefifth * 4) {
				memputd(framebuf, y * int(pitch) / 4 + x, 0xF7A8B8)
			}
		}
	}
}
