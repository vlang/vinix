// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.boot

__global boot_info boot.Info

fn C.vinix_image_end()

fn image_end() u32 {
	return u32(voidptr(C.vinix_image_end))
}

fn hex(value u32) {
	mut buffer := [11]u8{}
	buffer[0] = `0`
	buffer[1] = `x`
	digits := unsafe { &char(c'0123456789abcdef') }
	for i in 0 .. 8 { buffer[i + 2] = unsafe { u8(digits[(value >> u32(28 - i * 4)) & 15]) } }
	puts(unsafe { &char(&buffer[0]) })
}

fn relation(service &char, node u32) u32 {
	mut call := Call{ service: service, nargs: 1, nret: 1 }
	call.cells[0] = node
	if firmware(unsafe { &call }) != 0 { return 0xffffffff }
	return call.cells[1]
}

fn claim(size u32) u32 {
	mut call := Call{ service: c'claim', nargs: 3, nret: 1 }
	call.cells[1] = size
	call.cells[2] = 4096
	if firmware(unsafe { &call }) != 0 { return 0xffffffff }
	return call.cells[3]
}

fn property_u32(node u32, name &char, fallback u32) u32 {
	mut value := u32(0)
	if get_property(node, name, unsafe { &value }, 4) != 4 { return fallback }
	return value
}

fn discover_memory() bool {
	root := find_device(c'/')
	address_cells := property_u32(root, c'#address-cells', 1)
	size_cells := property_u32(root, c'#size-cells', 1)
	if address_cells < 1 || address_cells > 2 || size_cells < 1 || size_cells > 2 { return false }
	memory := find_device(c'/memory')
	if memory == 0xffffffff { return false }
	mut cells := [256]u32{}
	length := get_property(memory, c'available', unsafe { &cells[0] }, sizeof(cells))
	stride := address_cells + size_cells
	if length <= 0 || length > int(sizeof(cells)) || u32(length) % (stride * 4) != 0 {
		return false
	}
	count := u32(length) / (stride * 4)
	if count > 64 { return false }
	boot_info.available_count = 0
	for i := u32(0); i < count; i++ {
		at := i * stride
		if address_cells == 2 && cells[at] != 0 { continue }
		if size_cells == 2 && cells[at + address_cells] != 0 { return false }
		base := cells[at + address_cells - 1]
		size := cells[at + stride - 1]
		if size == 0 { continue }
		if size > 0xffffffff - base { return false }
		// QEMU's -kernel path does not claim the loaded program in OF's
		// available map. Disk loaders may claim it; subtract it in either case.
		end := base + size
		if base < image_end() && end > 0x01000000 {
			if base < 0x01000000 && !add_memory(base, 0x01000000 - base) { return false }
			if end > image_end() && !add_memory(image_end(), end - image_end()) { return false }
		} else if !add_memory(base, size) {
			return false
		}
	}
	return boot_info.available_count > 0
}

fn add_memory(base u32, size u32) bool {
	if boot_info.available_count >= 64 { return false }
	boot_info.available[boot_info.available_count] = boot.MemoryRange{base, size}
	boot_info.available_count++
	puts(c'VINIX-PPC: available ')
	hex(base)
	puts(c' + ')
	hex(size)
	puts(c'\r\n')
	return true
}

fn discover_framebuffer() {
	screen := find_device(c'screen')
	if screen == 0xffffffff { return }
	address := property_u32(screen, c'address', 0)
	width := property_u32(screen, c'width', 0)
	height := property_u32(screen, c'height', 0)
	pitch := property_u32(screen, c'linebytes', 0)
	depth := property_u32(screen, c'depth', 0)
	if address == 0 || width == 0 || height == 0 || height > 16384 || width > 16384
		|| (depth != 8 && depth != 16 && depth != 24 && depth != 32)
		|| pitch < width * ((depth + 7) / 8) || pitch > (0xffffffff - address) / height {
		return
	}
	boot_info.framebuffer = address
	boot_info.width = width
	boot_info.height = height
	boot_info.pitch = pitch
	boot_info.depth = depth
	puts(c'VINIX-PPC: framebuffer ')
	hex(address)
	puts(c'\r\n')
}

fn discover() bool {
	boot_info = boot.Info{ magic: boot.magic, version: boot.version, bytes: sizeof(boot.Info) }
	if !copy_device_tree() { return false }
	discover_framebuffer()
	// Read available after claims: firmware-owned and loader-owned pages must
	// never become free pages in the kernel allocator.
	if !discover_memory() { return false }
	puts(c'VINIX-PPC: PASS firmware discovery\r\n')
	return true
}
