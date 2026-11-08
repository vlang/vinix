// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.boot
import powerpc.cpu
import powerpc.elf32

const image_limit = u32(16 * 1024 * 1024)

fn release(address u32, size u32) {
	mut call := Call{ service: c'release', nargs: 2 }
	call.cells[0] = address
	call.cells[1] = size
	firmware(unsafe { &call })
}

fn close_file(handle u32) {
	mut call := Call{ service: c'close', nargs: 1 }
	call.cells[0] = handle
	firmware(unsafe { &call })
}

// The current identity-linked kernel contract cannot use an OF virtual claim
// backed by a different physical page. Check every page through the MMU
// instance, rather than assuming that QEMU's mapping also holds on a Mac.
fn identity_mapping(address u32, size u32) bool {
	if size == 0 || size > 0xffffffff - address { return false }
	chosen := find_device(c'/chosen')
	mmu := property_u32(chosen, c'mmu', 0)
	if mmu == 0 { return false }
	for page := address & ~u32(4095); page < address + size; page += 4096 {
		mut call := Call{ service: c'call-method', nargs: 3, nret: 4 }
		call.cells[0] = u32(c'translate')
		call.cells[1] = mmu
		call.cells[2] = page
		// catch-result, valid?, mode, physical address (PPC32 MMU cells).
		if firmware(unsafe { &call }) != 0 || call.cells[3] != 0
			|| call.cells[4] == 0 || call.cells[6] != page {
			return false
		}
		if page > 0xffffefff { break }
	}
	return true
}

fn available_range(base u32, size u32) bool {
	if size == 0 || size > 0xffffffff - base { return false }
	for i := u32(0); i < boot_info.available_count; i++ {
		range := boot_info.available[i]
		if base >= range.base && size <= range.size && base - range.base <= range.size - size {
			return true
		}
	}
	return false
}

fn claim_exact(address u32, size u32) bool {
	mut call := Call{ service: c'claim', nargs: 3, nret: 1 }
	call.cells[0] = address
	call.cells[1] = size
	if firmware(unsafe { &call }) != 0 { return false }
	actual := call.cells[3]
	if actual == 0xffffffff || actual == 0 { return false }
	if actual != address || !identity_mapping(actual, size) {
		release(actual, size)
		return false
	}
	return true
}

// Load the single absolute OF file path supplied in /chosen/bootargs.
// An empty path leaves the firmware-only bring-up mode available.
fn load_image() bool {
	mut path := [512]u8{}
	length := get_property(find_device(c'/chosen'), c'bootargs', unsafe { &path[0] }, sizeof(path))
	if length <= 0 || path[0] == 0 { return true }
	if length >= int(sizeof(path)) { return false }
	path[length] = 0
	mut open := Call{ service: c'open', nargs: 1, nret: 1 }
	open.cells[0] = u32(unsafe { &path[0] })
	if firmware(unsafe { &open }) != 0 || open.cells[1] == 0 { return false }
	handle := open.cells[1]
	defer { close_file(handle) }
	source := claim(image_limit)
	if source == 0xffffffff || source == 0 { return false }
	defer { release(source, image_limit) }
	mut size := u32(0)
	for {
		if size == image_limit { return false }
		mut read := Call{ service: c'read', nargs: 3, nret: 1 }
		read.cells[0] = handle
		read.cells[1] = source + size
		read.cells[2] = image_limit - size
		if firmware(unsafe { &read }) != 0 { return false }
		actual := read.cells[3]
		if actual == 0 { break }
		if actual > image_limit - size { return false }
		size += actual
	}
	mut image := elf32.Image{}
	if !elf32.parse(unsafe { &u8(source) }, size, mut image) { return false }
	// Refresh after the source claim so destination claims cannot alias it.
	if !discover_memory() || !available_range(image.base, image.end - image.base)
		|| !claim_exact(image.base, image.end - image.base) {
		return false
	}
	defer { release(image.base, image.end - image.base) }
	stack := claim(64 * 1024)
	if stack == 0xffffffff || stack == 0 { return false }
	defer { release(stack, 64 * 1024) }
	if !identity_mapping(stack, 64 * 1024) || !identity_mapping(boot_info.tree, boot_info.tree_size)
		|| !identity_mapping(0x01000000, image_end() - 0x01000000) {
		return false
	}
	for i := u32(0); i < image.count; i++ {
		segment := image.segments[i]
		copy_bytes(voidptr(segment.address), voidptr(source + segment.offset), segment.file_size)
		fill_bytes(voidptr(segment.address + segment.file_size), 0, segment.memory_size - segment.file_size)
		if segment.flags & 1 != 0 { cpu.publish_code(segment.address, segment.file_size) }
	}
	boot_info.kernel = boot.MemoryRange{image.base, image.end - image.base}
	boot_info.stack = boot.MemoryRange{stack, 64 * 1024}
	if !discover_memory() { return false }
	puts(c'VINIX-PPC: entering ELF32 image ')
	hex(image.entry)
	puts(c'\r\n')
	result := C.vinix_ppc_call_image(image.entry, &boot_info, stack + 64 * 1024, firmware)
	puts(c'VINIX-PPC: image returned ')
	hex(result)
	puts(c'\r\n')
	// Returning is supported for the handoff probe. A running kernel does not
	// return; it must retain all reserved firmware/loader ranges until takeover.
	if result != 0x564f4b32 { return false }
	puts(c'VINIX-PPC: PASS ELF32 handoff probe\r\n')
	return true
}

// PPC32 SysV ABI: r3=Info*, r4=firmware client, r1=16-byte-aligned stack.
// Preserve the caller's stack and LR in callee-saved registers so a diagnostic
// image can return. Reserve its linkage/parameter area before calling it.
fn C.vinix_ppc_call_image(entry u32, info &boot.Info, top u32, client Client) u32

asm ppc raw {
	".pushsection .text.vinix_ppc_call_image,\"ax\"\n"
	".balign 4\n.globl vinix_ppc_call_image\nvinix_ppc_call_image:\n"
	"mflr 0\nstw 0,4(1)\nstwu 1,-32(1)\nstw 30,24(1)\nstw 31,28(1)\n"
	"mr 31,1\nmtctr 3\nmr 3,4\nmr 4,6\nrlwinm 1,5,0,0,27\n"
	"li 0,0\nstwu 0,-32(1)\nbctrl\n"
	"mr 1,31\nlwz 30,24(1)\nlwz 31,28(1)\naddi 1,1,32\nlwz 0,4(1)\nmtlr 0\nblr\n"
	".popsection\n"
}
