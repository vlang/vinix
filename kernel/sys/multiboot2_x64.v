module sys

import libtinyalloc

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
	acpi_nvs,
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

struct Multiboot2ParseResult {
mut:
	command_line string
	efi_system_table &EfiSystemTable
	framebuffer &MultibootTagFramebuffer
	mmap_tags_size u32
	mmap_tags [64]&sys.MultibootMmapEntry
}

fn (entry &MultibootMmapEntry) type_str() string {
	return match entry.map_type {
		.unknown          { 'Unknown' }
		.available        { 'Available' }
		.acpi_reclaimable { 'ACPI Reclaimable' }
		.acpi_nvs         { 'ACPI Non-volatile storage' }
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

fn init_multiboot2(kernel &VKernel, early_info &EarlyBootInfo) {
	printk('Booted using Multiboot2-compliant bootloader, attempting to parse boot tags...')
	result := parse_multiboot2(phys_to_virtual(early_info.boot_info))

	if result.mmap_tags_size == 0 {
		panic('No memory map was found, cannot initialize kernel memory manager!')
	}

	mut heap_addr := voidptr(0)
	mut heap_size := u64(8 * 1024 * 1024) // 8 MiB
	for i := 0; i < result.mmap_tags_size; i++ {
		tag := result.mmap_tags[i]
		if tag.map_type != .available {
			continue
		}

		if tag.len >= heap_size {
			heap_addr = phys_to_virtual(voidptr(tag.addr))
			printk('Found ${heap_size} bytes of space for kernel internal heap at ${&PtrHack(heap_addr)}')
			break
		}
	}

	if (heap_addr == nullptr) {
		panic('Cannot find enough memory space for kernel heap!')
	}

	printk('Initializing kernel internal heap allocator...')
	kernel.heap_init(heap_addr, heap_size)
	printk('Initializing kernel memory manager...')

	if result.framebuffer != nullptr {
		tag := result.framebuffer
		framebuffer := new_framebuffer(tag.addr, tag.width, tag.height, tag.pitch, .bgra8888)
		kernel.register_framebuffer(framebuffer)
	}
}

fn parse_multiboot2(boot_info_ptr voidptr) Multiboot2ParseResult {
	mut result := Multiboot2ParseResult{}

	boot_info := &MultibootInfoHeader(boot_info_ptr)
	printk('addr: $boot_info')
	printk('size: $boot_info.total_size')

	mut ptr := voidptr(u64(boot_info_ptr) + u64(8))
	mut tag := &MultibootTagHeader(ptr)

	for {
		//printk('[tag] type=$tag._type size=$tag.size')

		match tag._type {
			.command_line {
				cmdline_tag := &MultibootTagCmdline(tag)
				printk('Kernel command line: ${cmdline_tag.command_line()}')
			}
			.framebuffer {
				result.framebuffer = &MultibootTagFramebuffer(tag)
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

				for !done {
					base_addr := &PtrHack(map_entry.addr)
					end_addr := &PtrHack(map_entry.addr + map_entry.len)
					length := map_entry.len / 1024
					memory_type := map_entry.type_str()

					result.mmap_tags[result.mmap_tags_size++] = map_entry
					printk('PMA: ${base_addr}-${end_addr} (${length} KiB) type = $memory_type')
					map_entry = &MultibootMmapEntry(u64(map_entry) + u64(mmap_tag.entry_size))

					if (u64(mmap_tag) + u64(mmap_tag.size)) < (u64(map_entry) + u64(mmap_tag.entry_size)) {
						done = true
					}
				}
			}
			.end {
				break
			}
			else {}
		}
		ptr = voidptr(u64(ptr) + u64(tag.size + u32(7) & u32(0xfffffff8)))
		tag = &MultibootTagHeader(ptr)
	}

	return result
}

fn do_meme(entry &MultibootMmapEntry) {
	printk('Found a >16MiB memory block: ${&PtrHack(entry.addr)}')
	
	printk('allocating 1024 bytes')
	addr := alloc.alloc(1024)
	printk('freeing 1024 bytes')
	alloc.free(addr)

	printk('free blocks: ${alloc.free_blocks_count()}, used blocks: ${alloc.used_blocks_count()}, fresh blocks: ${alloc.fresh_blocks_count()}')
}
