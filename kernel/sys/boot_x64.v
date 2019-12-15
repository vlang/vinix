module sys

pub const (
	// PHYS_BASE is the offset of kernel memory.
	PHYS_BASE = u64(0xFFFFFEFF00000000)
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
	vesa_bios_extension,
	framebuffer,
	elf_sections,
	adv_power_management,
	efi_32,
	efi_64
}

enum MultibootMmapType {
	unknown,
	available,
	reserved,
	acpi_reclaimable,
	nvs,
	badram
}

struct MultibootMmapEntry {
	addr u64
	len u64
	map_type MultibootMmapType
	zero u32
}

struct MultibootTagHeader {
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
	entry_size u32
	entry_version u32
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
	pointer voidptr
}

fn (entry &MultibootMmapEntry) type_str() string {
	return match entry.map_type {
		.unknown          { 'Unknown' }
		.available        { 'Available' }
		.acpi_reclaimable { 'ACPI Reclaimable' }
		.nvs              { 'NVS' }
		.badram           { 'Bad RAM' }
		else              { 'Reserved' }
	}

}

fn (tag &MultibootTagCmdline) command_line() string {
	return tos3(&tag._cmdline)
}

[inline]
fn (tag &MultibootTagEfi64) table() &EfiSystemTable {
	return &EfiSystemTable(phys_to_virtual(tag.pointer))
}

[inline]
fn banner() {
	build_date := v_build_date()
	compiler_version := v_version()
	printk('vOS/x86_64 [v${KERNEL_VERSION} ${build_date}, V ${compiler_version}]')
}

fn (kernel &VKernel) init_platform() {
	kernel.register_debug_sink(new_debug_e9port())
}

fn (kernel &VKernel) parse_bootinfo() {
	early_info := &EarlyBootInfo(phys_to_virtual(EARLY_BOOTINFO_BASE))
	if early_info.magic != BOOTLOADER_MAGIC_MB2 {
		printk('Unknown bootloader: ${&PtrHack(early_info.magic)}!')
		panic('cannot find any boot tags!')
	}

	printk('Booted using Multiboot2-compliant bootloader.')

	mut ptr := phys_to_virtual(early_info.boot_info)
	boot_info := &MultibootInfoHeader(ptr)
	printk('addr: $boot_info')
	printk('size: $boot_info.total_size')

	ptr = voidptr(u64(ptr) + u64(8))
	mut tag := &MultibootTagHeader(ptr)

	for {
		//printk('[tag] type=$tag._type size=$tag.size')

		match tag._type {
			.end {
				break
			}
			.command_line {
				cmdline_tag := &MultibootTagCmdline(tag)
				printk('Kernel command line: ${cmdline_tag.command_line()}')
			}
			.framebuffer {
				fb_tag := &MultibootTagFramebuffer(tag)
				//fb_test(phys_to_virtual(fb_tag.addr), fb_tag.width, fb_tag.height, fb_tag.pitch)
			}
			.efi_64 {
				efi_tag := &MultibootTagEfi64(tag)
				table := efi_tag.table()

				ven_bytes := [32]byte
				uni_to_ascii(phys_to_virtual(table.vendor), byteptr(&ven_bytes))
				vendor := tos3(voidptr(&ven_bytes))

				efi_major_revision := (table.header.revision >> 16) & 0xFF
				efi_minor_revision := (table.header.revision) & 0xFF

				printk('EFI Firmware revision: ${efi_major_revision}.${efi_minor_revision}')
				printk('EFI Firmware vendor: ${vendor}')
			}
			.memory_map {
				mmap_tag := &MultibootTagMemoryMap(tag)
				mut map_entry := &MultibootMmapEntry(u64(mmap_tag) + u64(16))
				mut done := false

				printk('+------------------------')
				printk('|   System memory map:')
				printk('+------------------------')

				for !done {
					base_addr := &PtrHack(map_entry.addr)
					end_addr := &PtrHack(map_entry.addr + map_entry.len)
					length := map_entry.len / 1024
					memory_type := map_entry.type_str()

					printk('| $base_addr - $end_addr ($length KiB) type = $memory_type')
					map_entry = &MultibootMmapEntry(u64(map_entry) + u64(mmap_tag.entry_size))

					if (u64(mmap_tag) + u64(mmap_tag.size)) < (u64(map_entry) + u64(mmap_tag.entry_size)) {
						done = true
					}
				}
				printk('+------------------------')
			}
			else {
				printk('[tag] Received tag type=${tag._type}')
			}
		}
		ptr = voidptr(u64(ptr) + u64(tag.size + u32(7) & u32(0xfffffff8)))
		tag = &MultibootTagHeader(ptr)
	}
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
