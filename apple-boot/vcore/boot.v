// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module applecore

fn C.apple_mmio_write32(u64, u32)

__global loader_main_reserved Reserved_set
__global loader_main_memmap Memmap

// --- iBoot boot arguments (xnu pexpert/arm64/boot.h) --------------------

pub struct Boot_video {
pub mut:
	base    u64
	display u64
	stride  u64
	width   u64
	height  u64
	depth   u64
}

pub struct Boot_info {
pub mut:
	revision           u16
	version            u16
	virt_base          u64
	phys_base          u64
	mem_size           u64
	top_of_kernel_data u64
	video              Boot_video
	machine_type       u32
	devtree            u64
	// physical
	devtree_size u32
	cmdline      &char
	// NUL-terminated inside boot_args
	boot_flags      u64
	mem_size_actual u64
}

// --- Payload appended to the loader image ---------------------------------

// QEMU harness: HHDM-map 0-4 GiB like Limine rev 2

pub struct Payload_header {
pub mut:
	magic            [8]char
	header_bytes     u32
	flags            u32
	kernel_offset    u64
	kernel_bytes     u64
	initramfs_offset u64
	initramfs_bytes  u64
	cmdline_offset   u64
	cmdline_bytes    u64
	build_time       u64
	// seconds since the epoch; Limine boot time
	total_bytes u64
}

// --- On-screen diagnostics --------------------------------------------------

// A coloured square per stage along the top of the screen.

// Stops with a red band carrying the failing stage, a code and a value.

// Draws a labelled hex value on the diagnostic rows below the stage squares.

// --- Physical memory ------------------------------------------------------

pub struct Allocator {
pub mut:
	start u64
	next  u64
	end   u64
}

// --- Page tables (4 KiB granule, 48-bit VA, as Limine hands over) ----------

pub struct Pagemap {
pub mut:
	root      u64
	allocator &Allocator
}

// --- Kernel image -----------------------------------------------------------

pub struct Loaded_kernel_segments {
pub mut:
	virt  u64
	bytes u64
	flags u32
}

pub struct Loaded_kernel {
pub mut:
	entry     u64
	phys_base u64
	virt_base u64
	bytes     u64
	// span from virt_base, page-rounded
	segments      [16]Loaded_kernel_segments
	segment_count u32
}

// --- Limine protocol --------------------------------------------------------

pub struct Memmap_entry {
pub mut:
	base   u64
	length u64
	type_  u64
}

pub struct Memmap {
pub mut:
	entries [64]Memmap_entry
	count   u32
}

// Firmware-owned spans inside RAM, page-aligned, sorted and merged.

pub struct Reserved_range {
pub mut:
	base u64
	end  u64
}

pub struct Reserved_set {
pub mut:
	ranges [48]Reserved_range
	count  u32
}

// The first aligned address at or above from where bytes fit clear of every
// *reserved range.

// Add [base, end) as type, minus the reserved ranges.

pub struct Limine_inputs {
pub mut:
	kernel            &Loaded_kernel
	kernel_file_phys  u64
	kernel_file_bytes u64
	initramfs_phys    u64
	initramfs_bytes   u64
	cmdline           &char
	dtb_phys          u64
	video             &Boot_video
	memmap            &Memmap_entry
	memmap_count      u32
	boot_time         u64
}

// Fills every request the loaded kernel carries; returns how many.

// --- Assembly ---------------------------------------------------------------

fn C.enter_kernel(entry u64, stack u64, sctlr u64, mair u64, tcr u64, ttbr0 u64, ttbr1 u64)

fn C.cache_invalidate_range(start u64, end u64)

fn C.quiesce_fiq_sources()

fn C.read_id_aa64mmfr0() u64

fn C.read_current_el() u64

fn C.read_midr() u64

fn C.halt_forever()

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// iBoot's boot arguments, as xnu's pexpert/arm64/boot.h and m1n1's
// *xnuboot.h describe them. Revisions 1-3 differ only in the length of the
// *command line, which moves the two trailing fields; like m1n1, a later
// *revision is read as revision 3.
// * *  0x00 u16 revision, u16 version       0x28 video {base, display, stride,
// *  0x08 virt_base                                     width, height, depth}
// *  0x10 phys_base                       0x58 u32 machine_type
// *  0x18 mem_size                        0x60 device tree (iBoot virtual)
// *  0x20 top_of_kernel_data              0x68 u32 device tree size
// *                                       0x6c command line, then
// *                                            boot_flags, mem_size_actual
//

const cmdline_bytes = [u32(0), u32(256), u32(608), u32(1024)]!

@[export: 'parse_boot_args']
pub fn parse_boot_args(address u64, out &Boot_info) i32 {
	unsafe {
		args := &u8(usize(address))
		out.revision = u16((i32(args[0]) | i32(args[1]) << 8))
		out.version = u16((i32(args[2]) | i32(args[3]) << 8))
		if i32(out.revision) < 1 {
			return -1
		}
		out.virt_base = load_le64(voidptr(args + 8))
		out.phys_base = load_le64(voidptr(args + 16))
		out.mem_size = load_le64(voidptr(args + 24))
		out.top_of_kernel_data = load_le64(voidptr(args + 32))
		out.video.base = load_le64(voidptr(args + 40))
		out.video.display = load_le64(voidptr(args + 48))
		out.video.stride = load_le64(voidptr(args + 56))
		out.video.width = load_le64(voidptr(args + 64))
		out.video.height = load_le64(voidptr(args + 72))
		out.video.depth = load_le64(voidptr(args + 80))
		out.machine_type = load_le32(voidptr(args + 88))
		devtree_virtual := load_le64(voidptr(args + 96))
		out.devtree_size = load_le32(voidptr(args + 104))
		out.cmdline = &char(voidptr(args)) + 108
		tail := align_up(u64(u32(108) + cmdline_bytes[if i32(out.revision) < 3 {
			i32(out.revision)
		} else {
			3
		}]), u64(8))
		out.boot_flags = load_le64(voidptr(args + tail))
		out.mem_size_actual = load_le64(voidptr(args + tail + 8))
		// iBoot passes the tree at its virtual address for the kernel it thinks
		//     *it is starting; the phys/virt pair converts it.

		if devtree_virtual < out.virt_base {
			return -1
		}
		out.devtree = devtree_virtual - out.virt_base + out.phys_base
		if !out.mem_size || !out.devtree_size || out.top_of_kernel_data <= out.phys_base || out.top_of_kernel_data >= out.phys_base + out.mem_size {
			return -1
		}
		return 0
	}
}

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// Diagnostics on iBoot's framebuffer. A MacBook has no serial port, so a
// *photo of the screen is the only report from a failed boot: stage squares
// *along the top edge, and on failure a red band with hex values drawn in a
// *5x7 digit font. All writes are aligned 32-bit stores, which is all the
// *MMU-off Device mapping allows.

pub struct FramebufferState {
pub mut:
	pixels &u32
	stride u64
	// in pixels
	width      u64
	height     u64
	thirty_bit i32
	scale      u32
	last_stage u32
}

__global fb FramebufferState

// HD44780-style 5x7 glyphs for 0-9 and A-F, one row per byte, bit 4 left.

const hex_glyphs = [[u8(14), u8(17), u8(19), u8(21), u8(25), u8(17), u8(14)]!,
	[u8(4), u8(12), u8(4), u8(4), u8(4), u8(4), u8(14)]!,
	[u8(14), u8(17), u8(1), u8(2), u8(4), u8(8), u8(31)]!,
	[u8(31), u8(2), u8(4), u8(2), u8(1), u8(17), u8(14)]!,
	[u8(2), u8(6), u8(10), u8(18), u8(31), u8(2), u8(2)]!,
	[u8(31), u8(16), u8(30), u8(1), u8(1), u8(17), u8(14)]!,
	[u8(6), u8(8), u8(16), u8(30), u8(17), u8(17), u8(14)]!,
	[u8(31), u8(1), u8(2), u8(4), u8(8), u8(8), u8(8)]!,
	[u8(14), u8(17), u8(17), u8(14), u8(17), u8(17), u8(14)]!,
	[u8(14), u8(17), u8(17), u8(15), u8(1), u8(2), u8(12)]!,
	[u8(14), u8(17), u8(17), u8(31), u8(17), u8(17), u8(17)]!,
	[u8(30), u8(17), u8(17), u8(30), u8(17), u8(17), u8(30)]!,
	[u8(14), u8(17), u8(16), u8(16), u8(16), u8(17), u8(14)]!,
	[u8(28), u8(18), u8(17), u8(17), u8(17), u8(18), u8(28)]!,
	[u8(31), u8(16), u8(16), u8(30), u8(16), u8(16), u8(31)]!,
	[u8(31), u8(16), u8(16), u8(30), u8(16), u8(16), u8(16)]!]!

const stage_colours = [[u8(32), u8(192), u8(32)]!, [u8(32), u8(96), u8(255)]!,
	[u8(255), u8(208), u8(32)]!, [u8(32), u8(208), u8(208)]!, [u8(208), u8(48), u8(208)]!,
	[u8(255), u8(255), u8(255)]!, [u8(255), u8(128), u8(32)]!, [u8(128), u8(128), u8(128)]!]!

pub fn colour(red u32, green u32, blue u32) u32 {
	unsafe {
		if fb.thirty_bit {
			return u32(red) << 22 | u32(green) << 12 | u32(blue) << 2
		}
		return u32(red) << 16 | u32(green) << 8 | u32(blue)
	}
}

pub fn fill(x u64, y u64, width u64, height u64, value u32) {
	unsafe {
		if (usize(fb.pixels) == 0) || x >= fb.width || y >= fb.height {
			return
		}
		if x + width > fb.width {
			width = fb.width - x
		}
		if y + height > fb.height {
			height = fb.height - y
		}
		for row := u64(0); row < height; row++ {
			line := fb.pixels + ((y + row) * fb.stride) + x
			for column := u64(0); column < width; column++ {
				C.apple_mmio_write32(u64(usize(line + column)), value)
			}
		}
	}
}

@[export: 'console_init']
pub fn console_init(video &Boot_video) {
	unsafe {
		depth := u32((video.depth & u64(255)))
		fb.pixels = nil
		if !video.base || !video.width || !video.height || video.stride < video.width * u64(4) {
			return
		}
		if depth != u32(32) && depth != u32(30) {
			return
		}
		fb.pixels = &u32(usize(video.base))
		fb.stride = video.stride / u64(4)
		fb.width = video.width
		fb.height = video.height
		fb.thirty_bit = depth == u32(30)
		fb.scale = u32(if video.width >= u64(2000) { 6 } else { 3 })
	}
}

@[export: 'console_stage']
pub fn console_stage(stage u32) {
	unsafe {
		size := u64(8) * u64(fb.scale)
		rgb := &u8(&stage_colours[stage % u32(8)][0])
		fb.last_stage = stage
		fill(size + u64(stage) * size * u64(3) / u64(2), size, size, size, colour(u32(rgb[0]), u32(rgb[1]), u32(rgb[2])))
	}
}

pub fn draw_digit(x u64, y u64, digit u32, value u32) {
	unsafe {
		for row := u32(0); row < u32(7); row++ {
			for column := u32(0); column < u32(5); column++ {
				if i32(hex_glyphs[digit & u32(15)][row]) & (16 >> column) {
					fill(x + u64(column * fb.scale), y + u64(row * fb.scale), u64(fb.scale), u64(fb.scale), value)
				}
			}
		}
	}
}

pub fn draw_hex(x u64, y u64, number u64, digits u32, value u32) {
	unsafe {
		for index := u32(0); index < digits; index++ {
			digit := u32((number >> (u32(4) * (digits - u32(1) - index)))) & u32(15)
			draw_digit(x + u64(index * u32(6) * fb.scale), y, digit, value)
		}
	}
}

@[export: 'console_hex']
pub fn console_hex(row u32, label u32, value u64) {
	unsafe {
		line := u64(u32(8) * fb.scale * (u32(3) + row))
		x := u64(u32(8) * fb.scale)
		white := colour(u32(255), u32(255), u32(255))
		fill(x, line, u64(u32(30 * 6) * fb.scale), u64(u32(8) * fb.scale), colour(u32(0), u32(0), u32(0)))
		draw_hex(x, line, u64(label), u32(2), colour(u32(255), u32(208), u32(32)))
		draw_hex(x + u64(u32(4 * 6) * fb.scale), line, value, u32(16), white)
	}
}

@[export: 'loader_fail']
pub fn loader_fail(code u32, value u64) {
	unsafe {
		band := u64(u32(8) * fb.scale * u32(12))
		red := colour(u32(208), u32(16), u32(16))
		white := colour(u32(255), u32(255), u32(255))
		fill(u64(0), band, fb.width, u64(u32(10) * fb.scale), red)
		draw_hex(u64(u32(8) * fb.scale), band + u64(fb.scale), u64(fb.last_stage), u32(2), white)
		draw_hex(u64(u32(8) * fb.scale + u32(4 * 6) * fb.scale), band + u64(fb.scale), u64(code), u32(4), white)
		draw_hex(u64(u32(8) * fb.scale + u32(10 * 6) * fb.scale), band + u64(fb.scale), value, u32(16), white)
		C.halt_forever()
	}
}

// Called from the vector table with the vector index and syndrome.

@[export: 'loader_exception']
pub fn loader_exception(vector u64, esr u64, elr u64, far u64) {
	unsafe {
		console_hex(u32(6), u32(225), esr)
		console_hex(u32(7), u32(226), elr)
		console_hex(u32(8), u32(227), far)
		loader_fail(u32(57344) | u32(vector), esr)
	}
}

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// Physical allocation and the page tables the kernel is entered with: 4 KiB
// *granule, four levels, 48-bit virtual addresses, as Limine builds them.

@[export: 'alloc_pages']
pub fn alloc_pages(allocator &Allocator, bytes u64, alignment u64) u64 {
	unsafe {
		if alignment < 16384 {
			alignment = 16384
		}
		start := align_up(allocator.next, alignment)
		length := align_up(bytes, 16384)
		if start < allocator.next || start > allocator.end || allocator.end - start < length {
			loader_fail(u32(2561), bytes)
		}
		allocator.next = start + length
		return start
	}
}

@[export: 'alloc_zeroed']
pub fn alloc_zeroed(allocator &Allocator, bytes u64, alignment u64) u64 {
	unsafe {
		start := alloc_pages(allocator, bytes, alignment)
		memset(voidptr(usize(start)), 0, usize(align_up(bytes, 16384)))
		return start
	}
}

// table at levels 0-2, page at level 3

__global apple_table_chunk u64
__global apple_table_chunk_used = u64(16384)

pub fn new_table(map_ &Pagemap) u64 {
	unsafe {
		// Tables are 4 KiB but the allocator hands out Apple pages; pack them.

		if apple_table_chunk_used + 4096 > 16384 {
			apple_table_chunk = alloc_zeroed(map_.allocator, 16384, 16384)
			apple_table_chunk_used = u64(0)
		}
		table := apple_table_chunk + apple_table_chunk_used
		apple_table_chunk_used += 4096
		return table
	}
}

@[export: 'pagemap_init']
pub fn pagemap_init(map_ &Pagemap, allocator &Allocator) {
	unsafe {
		map_.allocator = allocator
		map_.root = new_table(map_)
	}
}

pub fn leaf_bits(attribute u32, flags u32) u64 {
	unsafe {
		bits := (1 << 0) | (u64(attribute) << 2) | (1 << 10) | (u64(1) << 54)
		if attribute != 2 {
			bits |= (3 << 8)
		}
		if !(flags & 1) {
			bits |= (1 << 7)
		}
		if !(flags & 2) {
			bits |= (u64(1) << 53)
		}
		return bits
	}
}

pub fn next_level(map_ &Pagemap, entry &u64) &u64 {
	unsafe {
		if !((*entry) & (1 << 0)) {
			*entry = new_table(map_) | (1 << 0) | (1 << 1)
		} else if !((*entry) & (1 << 1)) {
			// A block already covers this range; refuse to split it.

			loader_fail(u32(2817), (*entry))
		}
		return &u64(usize(((*entry) & u64(281474976706560))))
	}
}

@[export: 'map_range']
pub fn map_range(map_ &Pagemap, virt u64, phys u64, bytes u64, attribute u32, flags u32) {
	unsafe {
		end := virt + align_up(bytes, u64(4096))
		bits := leaf_bits(attribute, flags)
		if (virt | phys) & u64(4095) {
			loader_fail(u32(2818), virt | phys)
		}
		for virt < end {
			level0 := &u64(usize(map_.root))
			level1 := next_level(map_, level0 + ((virt >> 39) & u64(511)))
			slot1 := level1 + ((virt >> 30) & u64(511))
			if !((virt | phys) & u64(1073741823)) && end - virt >= u64(1073741824) && !((*slot1) & (1 << 0)) {
				*slot1 = phys | bits
				// 1 GiB block

				virt += u64(1073741824)
				phys += u64(1073741824)
				continue
			}
			level2 := next_level(map_, slot1)
			slot2 := level2 + ((virt >> 21) & u64(511))
			if !((virt | phys) & u64(2097151)) && end - virt >= u64(2097152) && !((*slot2) & (1 << 0)) {
				*slot2 = phys | bits
				// 2 MiB block

				virt += u64(2097152)
				phys += u64(2097152)
				continue
			}
			level3 := next_level(map_, slot2)
			level3[(virt >> 12) & u64(511)] = phys | bits | (1 << 1)
			virt += u64(4096)
			phys += u64(4096)
		}
	}
}

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// Loads the kernel ELF physically contiguous with one uniform virtual offset,
// *which is what the Limine protocol promises.

pub fn le16(bytes &u8) u16 {
	unsafe {
		return u16((i32(bytes[0]) | i32(bytes[1]) << 8))
	}
}

@[export: 'load_elf']
pub fn load_elf(image &u8, size u64, allocator &Allocator, out &Loaded_kernel) i32 {
	unsafe {
		if size < u64(64) || memcmp(voidptr(image), voidptr(c'\177ELF'), u64(4)) || i32(image[4]) != 2 || i32(image[5]) != 1 || i32(le16(image + 18)) != 183 {
			return -1
		}
		entry := load_le64(voidptr(image + 24))
		phoff := load_le64(voidptr(image + 32))
		phentsize := le16(image + 54)
		phnum := le16(image + 56)
		if i32(phentsize) < 56 || phoff > size || u64(phnum) * u64(phentsize) > size - phoff {
			return -1
		}
		low := u64(0xffffffffffffffff)
		high := u64(0)

		for index := u16(0); i32(index) < i32(phnum); index++ {
			header := image + phoff + (u64(index) * u64(phentsize))
			if load_le32(voidptr(header)) != u32(1) {
				continue
			}
			vaddr := load_le64(voidptr(header + 16))
			memsz := load_le64(voidptr(header + 40))
			if vaddr < low {
				low = vaddr
			}
			if vaddr + memsz > high {
				high = vaddr + memsz
			}
		}
		if low == u64(0xffffffffffffffff) || low < u64(0xffffffff80000000) {
			return -1
		}
		low &= ~4095
		high = align_up(high, 16384)
		phys := alloc_zeroed(allocator, high - low, u64(2097152))
		out.entry = entry
		out.phys_base = phys
		out.virt_base = low
		out.bytes = high - low
		out.segment_count = u32(0)
		for index := u16(0); i32(index) < i32(phnum); index++ {
			header := image + phoff + (u64(index) * u64(phentsize))
			if load_le32(voidptr(header)) != u32(1) {
				continue
			}
			flags := load_le32(voidptr(header + 4))
			offset := load_le64(voidptr(header + 8))
			vaddr := load_le64(voidptr(header + 16))
			filesz := load_le64(voidptr(header + 32))
			memsz := load_le64(voidptr(header + 40))
			if filesz > memsz || offset > size || filesz > size - offset {
				return -1
			}
			memcpy(voidptr(usize((phys + vaddr - low))), voidptr(image + offset), filesz)
			if out.segment_count == u32(16) {
				return -1
			}
			out.segments[out.segment_count].virt = vaddr
			out.segments[out.segment_count].bytes = memsz
			out.segments[out.segment_count].flags = (if flags & u32(2) { 1 } else { u32(0) }) | (if flags & u32(1) {
				2
			} else {
				u32(0)
			})
			out.segment_count++
		}
		if entry < low || entry >= high {
			return -1
		}
		return 0
	}
}

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// The memory map handed to the kernel.
// * *iBoot's usable range is [phys_base, phys_base + mem_size). Coprocessor
// *firmware it has already loaded -- the "segment-ranges" of the ASC nodes
// *(SIO, DCP, ANS, ISP, ...) -- is live and must never be handed out, and
// *m1n1 reserves the same segments for Linux. The rest of the carveouts in
// */chosen/carveout-memory-map lie outside the usable range (one of them is
// *the usable range itself), so they need nothing.

// u64 phys, iova, remap; u32 size, flags

pub fn add_reserved(set &Reserved_set, base u64, end u64, ram_base u64, ram_end u64) {
	unsafe {
		base &= ~(16384 - u64(1))
		end = align_up(end, 16384)
		if base < ram_base {
			base = ram_base
		}
		if end > ram_end {
			end = ram_end
		}
		if end <= base {
			return
		}
		if set.count == u32(48) {
			loader_fail(u32(1283), base)
		}
		// Kept sorted and merged, so the map built from it stays ordered.

		index := set.count
		for index > u32(0) && set.ranges[index - u32(1)].base > base {
			set.ranges[index] = set.ranges[index - u32(1)]
			index--
		}
		set.ranges[index].base = base
		set.ranges[index].end = end
		set.count++
		out := u32(0)
		for in_ := u32(0); in_ < set.count; in_++ {
			if out > u32(0) && set.ranges[in_].base <= set.ranges[out - u32(1)].end {
				if set.ranges[in_].end > set.ranges[out - u32(1)].end {
					set.ranges[out - u32(1)].end = set.ranges[in_].end
				}
				continue
			}
			set.ranges[out++] = set.ranges[in_]
		}
		set.count = out
	}
}

pub fn collect_node(adt &Adt, node usize, depth u32, set &Reserved_set, ram_base u64, ram_end u64) {
	unsafe {
		segments := Adt_property{}
		if !adt_get(adt, node, c'segment-ranges', &segments) {
			for at := u32(0); at + u32(32) <= segments.length; at += u32(32) {
				phys := load_le64(voidptr(segments.value + at))
				size := u64(load_le32(voidptr(segments.value + at + 24)))
				if size {
					add_reserved(set, phys, phys + size, ram_base, ram_end)
				}
			}
		}
		if depth == u32(64) {
			return
		}
		child := adt_first_child(adt, node)
		for index := u32(0); index < adt_child_count(adt, node); index++ {
			collect_node(adt, child, depth + u32(1), set, ram_base, ram_end)
			child = adt_next_sibling(adt, child)
		}
	}
}

@[export: 'reserved_collect']
pub fn reserved_collect(adt &Adt, ram_base u64, ram_end u64, set &Reserved_set) {
	unsafe {
		set.count = u32(0)
		collect_node(adt, usize(0), u32(0), set, ram_base, ram_end)
	}
}

@[export: 'reserved_window']
pub fn reserved_window(set &Reserved_set, from u64, end u64, bytes u64, alignment u64) u64 {
	unsafe {
		base := align_up(from, alignment)
		for index := u32(0); index < set.count; index++ {
			if set.ranges[index].end <= base {
				continue
			}
			if base + bytes <= set.ranges[index].base {
				break
			}
			base = align_up(set.ranges[index].end, alignment)
		}
		if base + bytes > end || base + bytes < base {
			loader_fail(u32(1284), bytes)
		}
		return base
	}
}

pub fn insert(map_ &Memmap, base u64, end u64, type_ u64) {
	unsafe {
		if end <= base {
			return
		}
		if map_.count == u32(64) {
			loader_fail(u32(1281), base)
		}
		// Sorted by base, as Limine's map is.

		index := map_.count
		for index > u32(0) && map_.entries[index - u32(1)].base > base {
			map_.entries[index] = map_.entries[index - u32(1)]
			index--
		}
		map_.entries[index].base = base
		map_.entries[index].length = end - base
		map_.entries[index].type_ = type_
		map_.count++
	}
}

@[export: 'memmap_add']
pub fn memmap_add(map_ &Memmap, base u64, end u64, type_ u64, reserved &Reserved_set) {
	unsafe {
		for index := u32(0); index < reserved.count && base < end; index++ {
			range := &reserved.ranges[0] + index
			if range.end <= base {
				continue
			}
			if range.base >= end {
				break
			}
			insert(map_, base, range.base, type_)
			base = range.end
		}
		if base < end {
			insert(map_, base, end, type_)
		}
	}
}

@[export: 'memmap_add_reserved']
pub fn memmap_add_reserved(map_ &Memmap, reserved &Reserved_set) {
	unsafe {
		for index := u32(0); index < reserved.count; index++ {
			insert(map_, reserved.ranges[index].base, reserved.ranges[index].end, u64(1))
		}
	}
}

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// iBoot leaves the SoC watchdog armed for the OS it started; nothing in Vinix
// *services it, so disarm it before the kernel runs, as m1n1's wdt_disable
// *does: clear the control register at reg[0] + 0x1c, and on watchdog
// *versions 2 and 3 also the secondary control word at reg[2].

pub fn write32(address u64, value u32) {
	unsafe {
		C.apple_mmio_write32(address, value)
	}
}

@[export: 'disable_watchdog']
pub fn disable_watchdog(adt &Adt) {
	unsafe {
		node := usize(0)
		chain := [8]usize{}

		base := u64(0)
		size := u64(0)
		version := u64(0)

		if adt_find_path(adt, c'/arm-io/wdt', &node, &chain[0], usize(8)) || adt_get_reg(adt, &chain[0], usize(0), &base, &size) {
			console_hex(u32(1), u32(209), u64(0))
			return
		}
		write32(base + u64(28), u32(0))
		if adt_get_u64(adt, node, c'wdt-version', &version) {
			version = u64(0)
		}
		if u32(version) == u32(2) || u32(version) == u32(3) {
			secondary := u64(0)
			if !adt_get_reg(adt, &chain[0], usize(2), &secondary, &size) {
				write32(secondary, u32(0))
			}
		}
		console_hex(u32(1), u32(209), base)
	}
}

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// The part of the Limine boot protocol the Vinix kernel uses, answered the
// *way Limine 12.8 answers it at base revision 2: every pointer in a response
// *is a higher-half direct-map address, responses live in bootloader-
// *reclaimable memory, and a request the loader cannot honour keeps a NULL
// *response (the kernel checks). Requests are found by scanning the loaded
// *image for the protocol's common identifier words, as Limine does.

// id[4], revision, then the response pointer

pub struct Limine_file {
pub mut:
	revision        u64
	address         u64
	size            u64
	path            u64
	cmdline         u64
	media_type      u32
	unused          u32
	tftp_ip         u32
	tftp_port       u32
	partition_index u32
	mbr_disk_id     u32
	gpt_disk_uuid   [16]u8
	gpt_part_uuid   [16]u8
	part_uuid       [16]u8
}

pub struct Limine_framebuffer {
pub mut:
	address          u64
	width            u64
	height           u64
	pitch            u64
	bpp              u16
	memory_model     u8
	red_mask_size    u8
	red_mask_shift   u8
	green_mask_size  u8
	green_mask_shift u8
	blue_mask_size   u8
	blue_mask_shift  u8
	unused           [7]u8
	edid_size        u64
	edid             u64
}

// One reclaimable arena holds every response; carved sequentially.

pub struct Arena {
pub mut:
	base u64
	used u64
	size u64
}

pub fn arena_take(arena &Arena, bytes u64) voidptr {
	unsafe {
		start := align_up(arena.used, u64(16))
		if start + bytes > arena.size {
			loader_fail(u32(3073), bytes)
		}
		arena.used = start + bytes
		return voidptr(usize((arena.base + start)))
	}
}

pub fn hhdm(physical voidptr) u64 {
	unsafe {
		return u64(usize(physical)) + u64(0xffff000000000000)
	}
}

pub fn copy_string(arena &Arena, text &char) &char {
	unsafe {
		length := strlen(text)
		copy := &char(arena_take(arena, u64(length + usize(1))))
		memcpy(voidptr(copy), voidptr(text), length + usize(1))
		return copy
	}
}

pub fn set_response(request &u8, response voidptr) {
	unsafe {
		value := hhdm(voidptr(response))
		memcpy(voidptr(request + 40), voidptr(&value), u64(8))
	}
}

pub fn answer(inputs &Limine_inputs, arena &Arena, request &u8, id u64) {
	unsafe {
		match id {
			u64(0xf55038d8e2a1202f) {
				response := &u64(arena_take(arena, u64(24)))
				response[0] = u64(0)
				response[1] = hhdm(voidptr(copy_string(arena, c'Vinix Apple loader')))
				response[2] = hhdm(voidptr(copy_string(arena, c'1')))
				set_response(request, voidptr(response))
			}
			u64(5250337122116876370) {
				response := &u64(arena_take(arena, u64(16)))
				response[0] = u64(0)
				response[1] = u64(0xffff000000000000)
				set_response(request, voidptr(response))
			}
			u64(0x95c1a0edab0944cb) {
				response := &u64(arena_take(arena, u64(16)))
				response[0] = u64(0)
				response[1] = u64(0)
				// four levels, 48-bit

				set_response(request, voidptr(response))
			}
			u64(8194992790871301987) {
				response := &u64(arena_take(arena, u64(24)))
				response[0] = u64(0)
				response[1] = inputs.kernel.phys_base
				response[2] = inputs.kernel.virt_base
				set_response(request, voidptr(response))
			}
			u64(0xb40ddb48fb54bac7) {
				response := &u64(arena_take(arena, u64(16)))
				response[0] = u64(0)
				response[1] = inputs.dtb_phys + u64(0xffff000000000000)
				set_response(request, voidptr(response))
			}
			u64(5775662981534746794) {
				response := &u64(arena_take(arena, u64(16)))
				response[0] = u64(0)
				response[1] = inputs.boot_time
				set_response(request, voidptr(response))
			}
			u64(7480265251536666735) {
				response := &u64(arena_take(arena, u64(24)))
				entries := &Memmap_entry(arena_take(arena, sizeof(Memmap_entry) * u64(inputs.memmap_count)))
				pointers := &u64(arena_take(arena, 8 * u64(inputs.memmap_count)))
				for index := u32(0); index < inputs.memmap_count; index++ {
					entries[index] = inputs.memmap[index]
					pointers[index] = hhdm(voidptr(entries + index))
				}
				response[0] = u64(0)
				response[1] = u64(inputs.memmap_count)
				response[2] = hhdm(voidptr(pointers))
				set_response(request, voidptr(response))
			}
			u64(0x9d5827dcd881dd75) {
				video := inputs.video
				depth := u32((video.depth & u64(255)))
				if !video.base || (depth != u32(30) && depth != u32(32)) {
					return
				}
				framebuffer := &Limine_framebuffer(arena_take(arena, sizeof(Limine_framebuffer)))
				memset(voidptr(framebuffer), 0, sizeof(Limine_framebuffer))
				framebuffer.address = video.base + u64(0xffff000000000000)
				framebuffer.width = video.width
				framebuffer.height = video.height
				framebuffer.pitch = video.stride
				framebuffer.bpp = u16(32)
				framebuffer.memory_model = u8(1)
				// RGB

				channel := u32(if depth == u32(30) { 10 } else { 8 })
				framebuffer.red_mask_size = u8(channel)
				framebuffer.red_mask_shift = u8((u32(2) * channel))
				framebuffer.green_mask_size = u8(channel)
				framebuffer.green_mask_shift = u8(channel)
				framebuffer.blue_mask_size = u8(channel)
				framebuffer.blue_mask_shift = u8(0)
				pointers := &u64(arena_take(arena, u64(8)))
				pointers[0] = hhdm(voidptr(framebuffer))
				response := &u64(arena_take(arena, u64(24)))
				response[0] = u64(0)
				response[1] = u64(1)
				response[2] = hhdm(voidptr(pointers))
				set_response(request, voidptr(response))
			}
			u64(0xad97e90e83f1ed67) {
				file := &Limine_file(arena_take(arena, sizeof(Limine_file)))
				memset(voidptr(file), 0, sizeof(Limine_file))
				file.address = inputs.kernel_file_phys + u64(0xffff000000000000)
				file.size = inputs.kernel_file_bytes
				file.path = hhdm(voidptr(copy_string(arena, c'/boot/vinix')))
				file.cmdline = hhdm(voidptr(copy_string(arena, inputs.cmdline)))
				response := &u64(arena_take(arena, u64(16)))
				response[0] = u64(0)
				response[1] = hhdm(voidptr(file))
				set_response(request, voidptr(response))
			}
			u64(4503080206956638895) {
				if !inputs.initramfs_bytes {
					return
				}
				file := &Limine_file(arena_take(arena, sizeof(Limine_file)))
				memset(voidptr(file), 0, sizeof(Limine_file))
				file.address = inputs.initramfs_phys + u64(0xffff000000000000)
				file.size = inputs.initramfs_bytes
				file.path = hhdm(voidptr(copy_string(arena, c'/boot/initramfs.tar')))
				file.cmdline = hhdm(voidptr(copy_string(arena, c'initramfs')))
				pointers := &u64(arena_take(arena, u64(8)))
				pointers[0] = hhdm(voidptr(file))
				response := &u64(arena_take(arena, u64(24)))
				response[0] = u64(0)
				response[1] = u64(1)
				response[2] = hhdm(voidptr(pointers))
				set_response(request, voidptr(response))
			}
			else {
				// MP, RSDP, SMBIOS, EFI, stack size, ...: not offered on Apple
				//         *hardware; the kernel falls back when the response is NULL.
			}
		}
	}
}

@[export: 'limine_answer']
pub fn limine_answer(inputs &Limine_inputs, allocator &Allocator) u32 {
	unsafe {
		kernel := inputs.kernel
		image := &u8(usize(kernel.phys_base))
		arena := Arena{
			base: alloc_zeroed(allocator, u64(65536), 16384)
			used: u64(0)
			size: u64(65536)
		}

		answered := u32(0)
		for offset := u64(0); offset + u64(32) <= kernel.bytes; offset += u64(8) {
			first := (*&u64(voidptr((image + offset))))
			if first == u64(0xf9562b2d5c95a6c8) {
				if (*&u64(voidptr((image + offset + 8)))) == u64(7672788277485857756) {
					revision := &u64(voidptr((image + offset + 16)))
					// Zero acknowledges a revision this loader implements.

					if (*revision) <= u64(2) {
						*revision = u64(0)
					}
				}
				continue
			}
			if first != u64(0xc7b1dd30df4c8b88) || (*&u64(voidptr((image + offset + 8)))) != u64(757423339400917115) {
				continue
			}
			id := (*&u64(voidptr((image + offset + 16))))
			answer(inputs, &arena, image + offset, id)
			answered++
			offset += u64(40)
		}
		return answered
	}
}

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// Boot Vinix directly from iBoot on Apple silicon.
// * *iBoot starts this image as a custom kernel with the Apple DeviceTree and a
// *framebuffer already set up. The loader converts the tree to an FDT, loads
// *the kernel ELF appended to it, answers the kernel's Limine requests and
// *enters it exactly as Limine 12.8 would on the same CPU, so the kernel runs
// *unchanged. Stages, in the order their squares appear on screen:
// * *  0 boot arguments parsed       4 ADT converted to an FDT
// *  1 ADT validated               5 memory map built
// *  2 watchdog disarmed           6 page tables built
// *  3 kernel loaded               7 Limine requests answered, entering
//

@[c_extern]
__global C.loader_end [1]char

fn tcr_value() u64 {
	pa_range := C.read_id_aa64mmfr0() & u64(15)
	if pa_range > u64(5) {
		pa_range = u64(5)
	}
	// 48 bits: the most a 4 KiB, four-level map expresses

	return pa_range << 32 | u64(2) << 30 | u64(3) << 28 | u64(1) << 26 | u64(1) << 24 | u64(16) << 16 | u64(3) << 12 | u64(1) << 10 | u64(1) << 8 | u64(16)
}

// Map [0, 4 GiB) into the direct map around the RAM entries, as Limine does
// *below base revision 3. Only the QEMU harness asks for it; on Apple hardware
// *that window holds nothing the early kernel touches.

pub fn map_low_4g(map_ &Pagemap, memmap &Memmap) {
	unsafe {
		entries := &Memmap_entry(&memmap.entries[0])
		count := memmap.count
		cursor := u64(0)
		limit := u64(4294967296)

		for index := u32(0); index <= count && cursor < limit; index++ {
			next := if index < count { entries[index].base } else { limit }
			if next > limit {
				next = limit
			}
			if next > cursor {
				map_range(map_, u64(0xffff000000000000) + cursor, cursor, next - cursor, 2, 1)
			}
			if index < count && entries[index].base + entries[index].length > cursor {
				cursor = entries[index].base + entries[index].length
			}
		}
	}
}

@[export: 'loader_main']
pub fn loader_main(boot_args u64, image_base u64) {
	unsafe {
		info := Boot_info{}
		arguments_valid := parse_boot_args(boot_args, &info)
		console_init(&info.video)
		console_stage(u32(0))
		console_hex(u32(0), u32(176), u64(info.revision) | u64(C.read_current_el()) << 32)
		if arguments_valid {
			loader_fail(u32(1), boot_args)
		}
		adt := Adt{
			base: &u8(usize(info.devtree))
			size: usize(info.devtree_size)
		}

		if adt_validate(&adt) {
			loader_fail(u32(257), info.devtree)
		}
		console_stage(u32(1))
		disable_watchdog(&adt)
		console_stage(u32(2))
		payload := &Payload_header(&C.loader_end[0])
		payload_base := u64(usize(voidptr(payload)))
		if memcmp(&payload.magic[0], c'VNXAPPL1', 8) != 0 || u64(payload.header_bytes) < sizeof(Payload_header)
			|| payload.kernel_offset + payload.kernel_bytes > payload.total_bytes
			|| payload.initramfs_offset + payload.initramfs_bytes > payload.total_bytes
			|| payload.cmdline_offset + payload.cmdline_bytes > payload.total_bytes
			|| image_base < info.phys_base || payload_base < image_base
			|| payload_base + payload.total_bytes > info.top_of_kernel_data {
			loader_fail(769, payload_base)
		}
		cmdline := if payload.cmdline_bytes {
			&char(voidptr(payload)) + payload.cmdline_offset
		} else {
			c''
		}
		// The loader's own allocations start above iBoot's data, in the first
		//     *window no coprocessor firmware lies in.

		ram_end := info.phys_base + info.mem_size

		reserved_collect(&adt, info.phys_base, ram_end, &loader_main_reserved)
		window := reserved_window(&loader_main_reserved, info.top_of_kernel_data, ram_end, 268435456, u64(2097152))
		allocator := Allocator{
			start: window
			next:  window
			end:   window + 268435456
		}

		// Everything below is written with the MMU off, straight to DRAM. A
		//     *dirty line iBoot left over the window could be evicted on top of it
		//     *later, so drop them all first; the same range is invalidated again
		//     *before the kernel reads it cacheably.

		C.cache_invalidate_range(window, window + 268435456)
		kernel := Loaded_kernel{}
		kernel_file := &u8(voidptr(payload)) + payload.kernel_offset
		if load_elf(kernel_file, payload.kernel_bytes, &allocator, &kernel) {
			loader_fail(u32(770), payload.kernel_bytes)
		}
		console_hex(u32(2), u32(224), kernel.entry)
		console_stage(u32(3))
		fdt_capacity := u64(info.devtree_size) + 1048576
		fdt := alloc_pages(&allocator, fdt_capacity, 16384)
		strings := &char(usize(alloc_pages(&allocator, 1048576, 16384)))
		hash := &u32(usize(alloc_pages(&allocator, u64(4) * 65536, 16384)))
		builder := Fdt_builder{}
		fdt_begin(&builder, voidptr(usize(fdt)), usize(fdt_capacity), strings, usize(1048576), hash, usize(65536))
		extras := Adt_fdt_extras{
			bootargs: cmdline
		}

		if adt_to_fdt(&adt, &builder, &extras) || !fdt_finish(&builder) {
			loader_fail(u32(1025), u64(builder.length))
		}
		console_stage(u32(4))
		// Everything the kernel still reads after hand-off -- tables, responses,
		//     *its stack -- comes from one window fixed now, so the memory map it is
		//     *described by can be final before any of it is built.

		late_start := align_up(allocator.next, u64(2097152))
		late_end := late_start + 16777216
		if late_end > allocator.end {
			loader_fail(u32(1282), late_end)
		}

		kernel_end := kernel.phys_base + kernel.bytes
		payload_start := payload_base & ~4095
		payload_end := align_up(payload_base + payload.total_bytes, u64(4096))
		// Below the kernel: iBoot's data, the loader and the ADT, which the
		//     *kernel may reclaim, and the payload, which it keeps: the initramfs
		//     *module and its own file live there.

		memmap_add(&loader_main_memmap, info.phys_base, payload_start, u64(5), &loader_main_reserved)
		memmap_add(&loader_main_memmap, payload_start, payload_end, u64(6), &loader_main_reserved)
		memmap_add(&loader_main_memmap, payload_end, kernel.phys_base, u64(5), &loader_main_reserved)
		memmap_add(&loader_main_memmap, kernel.phys_base, kernel_end, u64(6), &loader_main_reserved)
		memmap_add(&loader_main_memmap, kernel_end, late_end, u64(5), &loader_main_reserved)
		memmap_add(&loader_main_memmap, late_end, ram_end, u64(0), &loader_main_reserved)
		memmap_add_reserved(&loader_main_memmap, &loader_main_reserved)
		fb_base := info.video.base & ~(16384 - u64(1))
		fb_end := align_up(info.video.base + info.video.stride * info.video.height, 16384)
		if info.video.base {
			memmap_add(&loader_main_memmap, fb_base, fb_end, u64(7), &loader_main_reserved)
		}
		allocator.next = late_start
		allocator.end = late_end
		console_hex(u32(3), u32(160), info.phys_base)
		console_hex(u32(4), u32(161), info.mem_size | u64(loader_main_reserved.count) << 56)
		console_stage(u32(5))
		kernel_map := Pagemap{}
		identity_map := Pagemap{}

		pagemap_init(&kernel_map, &allocator)
		pagemap_init(&identity_map, &allocator)
		for index := u32(0); index < loader_main_memmap.count; index++ {
			entry := &loader_main_memmap.entries[0] + index
			if entry.type_ == u64(1) {
				continue
			}
			attribute := u32(if entry.type_ == u64(7) { 1 } else { 0 })
			map_range(&kernel_map, u64(0xffff000000000000) + entry.base, entry.base, entry.length, attribute, 1)
		}
		if payload.flags & 1 {
			map_low_4g(&kernel_map, &loader_main_memmap)
		}
		for index := u32(0); index < kernel.segment_count; index++ {
			virt := kernel.segments[index].virt & ~4095
			end := align_up(kernel.segments[index].virt + kernel.segments[index].bytes, u64(4096))
			map_range(&kernel_map, virt, kernel.phys_base + (virt - kernel.virt_base), end - virt, 0, kernel.segments[index].flags)
		}
		// The loader keeps running from physical addresses as the MMU comes on;
		//     *only its own image needs to be reachable there.

		image_start := image_base & ~4095
		map_range(&identity_map, image_start, image_start, payload_base - image_start, 0, 1 | 2)
		console_stage(u32(6))
		stack := alloc_zeroed(&allocator, 262144, 16384)
		inputs := Limine_inputs{
			kernel:            &kernel
			kernel_file_phys:  u64(usize(voidptr(kernel_file)))
			kernel_file_bytes: payload.kernel_bytes
			initramfs_phys:    u64(usize(voidptr(payload))) + payload.initramfs_offset
			initramfs_bytes:   payload.initramfs_bytes
			cmdline:           cmdline
			dtb_phys:          fdt
			video:             &info.video
			memmap:            &loader_main_memmap.entries[0]
			memmap_count:      loader_main_memmap.count
			boot_time:         payload.build_time
		}

		answered := limine_answer(&inputs, &allocator)
		console_hex(u32(5), u32(192), u64(answered))
		console_stage(u32(7))
		C.quiesce_fiq_sources()
		// Written with the caches off: drop whatever the firmware still holds
		//     *for these lines before the kernel reads them cacheably. The window
		//     *holds the kernel, the FDT, the tables, the responses and the stack.

		C.cache_invalidate_range(allocator.start, late_end)
		C.enter_kernel(kernel.entry, stack + 262144 + u64(0xffff000000000000), ((1 << 29) | (1 << 28) | (1 << 23) | (1 << 22) | (1 << 20) | (1 << 12) | (1 << 11) | (1 << 8) | (1 << 7) | (1 << 4) | (1 << 3) | (1 << 2) | (1 << 0)), 255 | 68 << 8 | 4 << 16, tcr_value(), identity_map.root, kernel_map.root)
	}
}
