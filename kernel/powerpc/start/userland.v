// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.cpu
import powerpc.elf32
import powerpc.exception
import powerpc.ramfs
import powerpc.runtime
import powerpc.serial

__global rootfs ramfs.Image
const user_stack_start = u32(0x5f800000)

fn launch_init() {
	archive := startup_info.initramfs
	if archive.base == 0 {
		for {}
	}
	if !ramfs.parse(unsafe { &u8(archive.base) }, archive.size, mut rootfs) {
		halt(c'initramfs validation')
	}
	index := rootfs.find(unsafe { &u8(c'bin/init') }, 8)
	if index < 0 { halt(c'missing /bin/init') }
	file := rootfs.files[index]
	mut image := elf32.Image{}
	if !elf32.parse_user(file.data, file.size, mut image) { halt(c'init ELF32 validation') }
	for i := u32(0); i < image.count; i++ {
		segment := image.segments[i]
		end := segment.address + segment.memory_size
		if segment.address < 0x40000000 || end > 0x5fe00000
			|| (segment.flags & 1 != 0 && end > 0x50000000)
			|| (segment.flags & 2 != 0 && segment.address < 0x50000000) {
			halt(c'init segment permissions')
		}
		for address := segment.address & ~u32(4095); address < end; address += 4096 {
			physical := physical_pages.take(1, 1)
			if physical == 0 { halt(c'init memory exhausted') }
			runtime.fill(voidptr(physical), 0, 4096)
			if !user_space.map(address, physical, segment.flags & 2 != 0) { halt(c'init mapping') }
		}
		mut copied := u32(0)
		for copied < segment.file_size {
			address := segment.address + copied
			mut count := 4096 - (address & 4095)
			if count > segment.file_size - copied { count = segment.file_size - copied }
			physical := user_space.translate(address, false)
			if physical == 0 { halt(c'init segment copy') }
			runtime.copy(voidptr(physical), unsafe { &file.data[segment.offset + copied] }, count)
			copied += count
		}
	}
	for i := u32(0); i < 2048; i++ {
		physical := physical_pages.take(1, 1)
		if physical == 0 { halt(c'user stack allocation') }
		runtime.fill(voidptr(physical), 0, 4096)
		if !user_space.map(user_stack_start + i * 4096, physical, true) { halt(c'user stack mapping') }
	}
	for i := u32(0); i < user_space.count; i++ {
		mapping := user_space.mappings[i]
		if mapping.virtual < 0x50000000 { cpu.publish_code(mapping.physical, 4096) }
	}
	user_space.activate()
	process_break_min = if image.end < 0x50000000 { u32(0x51000000) } else { image.end }
	process_break = process_break_min
	if process_break_min >= 0x52000000 { halt(c'init data exceeds heap boundary') }
	stack := prepare_user_stack(image)
	initialize_processes()
	serial.text(c'Vinix: starting /bin/init in protected userspace\n')
	exception.enter_user(image.entry, stack)
	halt(c'init returned')
}

fn prepare_user_stack(image elf32.Image) u32 {
	// SysV PPC32 stack: argc, argv, envp, then Elf32 auxiliary vector pairs.
	// Keep strings above the vector and align the stack to 16 bytes.
	name := u32(0x5fffff00)
	path := u32(0x5fffff20)
	if !copy_to_user(name, unsafe { &u8(c'/bin/init') }, 10)
		|| !copy_to_user(path, unsafe { &u8(c'PATH=/bin:/usr/bin') }, 19) { halt(c'initial stack strings') }
	mut words := [64]u32{}
	words[0] = 1
	words[1] = name
	words[3] = path
	mut at := 5
	for pair in [[u32(3), image.phdr]!, [u32(4), 32]!, [u32(5), image.phnum]!,
		[u32(6), 4096]!, [u32(7), 0]!, [u32(9), image.entry]!,
		[u32(11), 0]!, [u32(12), 0]!, [u32(13), 0]!, [u32(14), 0]!,
		[u32(16), 0x88000000]!, [u32(17), 100]!, [u32(23), 0]!, [u32(31), name]!]! {
		words[at] = pair[0]
		words[at + 1] = pair[1]
		at += 2
	}
	stack := (name - u32((at + 2) * 4)) & ~u32(15)
	if !copy_to_user(stack, unsafe { &u8(&words[0]) }, u32((at + 2) * 4)) { halt(c'initial stack vector') }
	return stack
}
