module sys

pub const (
	PHYS_BASE = u64(0xFFFFFEFF00000000)
)

const (
	BOOTLOADER_MAGIC_MB2 = u32(0x36D76289)
	EARLY_BOOTINFO_BASE = u64(0xE00000)
)

pub struct EarlyBootInfo {
pub:
	magic u32
	boot_info u32
}

struct MultibootInfoHeader {
	total_size u32
	reserved u32
}

enum MultibootTagType {
	end,
	command_line,
	bootloader_name, 
	boot_module, 
	basic_meminfo,
	boot_device,
	memory_map,
	vbe,
	framebuffer,
	elf_sections,
	apm,
	efi_32,
	efi_64
}

struct MultibootTag {
	_type MultibootTagType
	size u32
}

struct MultibootTagCmdline {
	_type u32
	size u32
	_cmdline [0]byte
}

struct MultibootTagMemoryMap {
	_type u32
	size u32	
}

struct MultibootTagFramebuffer {
	_type u32
	size u32
	addr voidptr
	pitch u32
	width u32
	height u32
	depth byte
	fb_type byte
}

struct MultibootTagEfi64 {
	_type u32
	size u32
	pointer u64
}

fn (tag &MultibootTagCmdline) command_line() string {
	return tos3(&tag._cmdline)
}

[inline]
fn (tag &MultibootTagEfi64) table() &EfiSystemTable {
	return &EfiSystemTable(voidptr(PHYS_BASE + tag.pointer))
}

fn (tag &MultibootTagEfi64) firmware_vendor() string {
	return tos3(voidptr(PHYS_BASE + u64(tag.table().vendor)))
}

pub fn banner() {
	build_date := v_build_date()
	v_ver := v_version()
	printk('vOS/x86_64 [v${KERNEL_VERSION} ${build_date}, V ${v_ver}]')
}

pub fn (kernel &VKernel) parse_bootinfo() {
	early_info := &EarlyBootInfo(voidptr(PHYS_BASE + EARLY_BOOTINFO_BASE))

	if early_info.magic == BOOTLOADER_MAGIC_MB2 {
		printk('Booted using Multiboot2-compliant bootloader.')
		
		mut ptr := voidptr(PHYS_BASE + u64(early_info.boot_info))
		boot_info := &MultibootInfoHeader(ptr)
		printk('addr: $boot_info')
		printk('size: $boot_info.total_size')

		ptr = voidptr(u64(ptr) + u64(8))
		mut tag := &MultibootTag(ptr)
		mut end := false

		for !end {
			//printk('[tag] type=$tag._type size=$tag.size')

			match tag._type {
				.end {
					end = true
				}
				.command_line {
					cmdline_tag := &MultibootTagCmdline(tag)
					printk('Kernel command line: ${cmdline_tag.command_line()}')
				}
				.framebuffer {
					fb_tag := &MultibootTagFramebuffer(tag)
					printk('Framebuffer @ ${fb_tag.addr}: ${fb_tag.width}x${fb_tag.height} ${fb_tag.depth}bpp pitch: ${fb_tag.pitch}')

					/*for i := 0; i < 255; i++ {
						memset(voidptr(PHYS_BASE + u64(fb_tag.addr) + u64(u32(i) * fb_tag.pitch)), byte(i), int(1024 * 4))
					}*/

					onefifth := int(fb_tag.height) / 5

					for x := 0; x < int(fb_tag.width); x++ {
						for y := 0; y < int(fb_tag.height); y++ {
							if y < (onefifth * 3) && y > (onefifth * 2) {
								memputd(voidptr(PHYS_BASE + u64(fb_tag.addr)), y * int(fb_tag.pitch) / 4 + x, 0xFFFFFF)
							} else if y < onefifth || y >= (4 * onefifth) {
								memputd(voidptr(PHYS_BASE + u64(fb_tag.addr)), y * int(fb_tag.pitch) / 4 + x, 0x55CDFC)
							} else if y < (onefifth * 2) || y < (onefifth * 4) {
								memputd(voidptr(PHYS_BASE + u64(fb_tag.addr)), y * int(fb_tag.pitch) / 4 + x, 0xF7A8B8)
							}
						}
					}
				}
				.efi_64 {
					efi_tag := &MultibootTagEfi64(tag)
					table := efi_tag.table()
					
					ven_bytes := [32]byte
					uni_to_ascii(voidptr(PHYS_BASE + u64(table.vendor)), byteptr(&ven_bytes))
					vendor := tos3(voidptr(&ven_bytes))

					printk('EFI Firmware revision: ${(table.header.revision >> 16) & u32(0xff)}.${(table.header.revision) & u32(0xff)}')
					printk('EFI Firmware vendor: ${vendor}')
				}
				.memory_map {
					printk('Kernel memory map:')
				}
			}
			ptr = voidptr(u64(ptr) + u64(tag.size + u32(7) & u32(0xfffffff8)))
			tag = &MultibootTag(ptr)
		}
	} else {
		panic('Unknown bootloader version!')
	}
}