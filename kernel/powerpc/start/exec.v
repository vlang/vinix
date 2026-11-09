// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.cpu
import powerpc.elf32
import powerpc.exception
import powerpc.hash32
import powerpc.mmu
import powerpc.runtime
import powerpc.serial

__global exec_space mmu.Space
__global exec_strings [16384]u8
__global exec_words [320]u32

struct ExecArguments {
mut:
	strings u32
	count u32 = 1
}

fn exec_vector(address u32, mut args ExecArguments) int {
	if address == 0 { return -14 }
	for i := u32(0); i < 128; i++ {
		mut pointer := u32(0)
		if args.count >= 260 || !copy_from_user(unsafe { &u8(&pointer) }, address + i * 4, 4) { return -14 }
		if pointer == 0 { exec_words[args.count] = 0; args.count++; return 0 }
		exec_words[args.count] = 0x5fff0000 + args.strings
		args.count++
		mut ended := false
		for offset := u32(0); offset < 4096; offset++ {
			if args.strings >= 16384 { return -7 }
			if !copy_from_user(unsafe { &exec_strings[args.strings] }, pointer + offset, 1) { return -14 }
			args.strings++
			if exec_strings[args.strings - 1] == 0 { ended = true; break }
		}
		if !ended { return -7 }
	}
	return -7
}

fn load_exec_image(data &u8, image &elf32.Image, mut space mmu.Space) bool {
	table := physical_pages.take(hash32.bytes / 4096, hash32.bytes / 4096)
	if table == 0 || !space.init(table) { return false }
	for i := u32(0); i < image.count; i++ {
		segment := image.segments[i]
		end := segment.address + segment.memory_size
		if segment.address < 0x40000000 || end > 0x52000000
			|| (segment.flags & 1 != 0 && end > 0x50000000)
			|| (segment.flags & 2 != 0 && segment.address < 0x50000000) { return false }
		for address := segment.address & ~u32(4095); address < end; address += 4096 {
			physical := physical_pages.take(1, 1)
			if physical == 0 { return false }
			runtime.fill(voidptr(physical), 0, 4096)
			if !space.map(address, physical, segment.flags & 2 != 0) { physical_pages.give(physical, 1); return false }
		}
		mut copied := u32(0)
		for copied < segment.file_size {
			address := segment.address + copied
			mut count := 4096 - (address & 4095)
			if count > segment.file_size - copied { count = segment.file_size - copied }
			runtime.copy(voidptr(space.translate(address, false)), unsafe { &data[segment.offset + copied] }, count)
			copied += count
		}
	}
	for address := user_stack_start; address < 0x60000000; address += 4096 {
		physical := physical_pages.take(1, 1)
		if physical == 0 { return false }
		runtime.fill(voidptr(physical), 0, 4096)
		if !space.map(address, physical, true) { physical_pages.give(physical, 1); return false }
	}
	for i := u32(0); i < space.count; i++ {
		m := space.mappings[i]
		if m.virtual < 0x50000000 { cpu.publish_code(m.physical, 4096) }
	}
	return true
}

fn sys_exec(path u32, argv u32, envp u32, mut frame exception.Frame) int {
	length := user_path(path)
	if length < 0 { return length }
	if length == 0 || io_buffer[0] != `/` { return -2 }
	index := rootfs.find(unsafe { &io_buffer[1] }, u32(length - 1))
	if index < 0 { return -2 }
	file := rootfs.files[index]
	if file.directory { return -13 }
	mut image := elf32.Image{}
	if !elf32.parse_user(file.data, file.size, mut image) { return -8 }
	mut args := ExecArguments{}
	mut result := exec_vector(argv, mut args)
	if result < 0 { return result }
	exec_words[0] = args.count - 2
	result = exec_vector(envp, mut args)
	if result < 0 { return result }
	mut count := args.count
	for pair in [[u32(3), image.phdr]!, [u32(4), 32]!, [u32(5), image.phnum]!,
		[u32(6), 4096]!, [u32(7), 0]!, [u32(9), image.entry]!, [u32(11), 0]!,
		[u32(12), 0]!, [u32(13), 0]!, [u32(14), 0]!, [u32(16), 0x88000000]!,
		[u32(17), 100]!, [u32(23), 0]!, [u32(0), 0]!]! {
		exec_words[count] = pair[0]; exec_words[count + 1] = pair[1]; count += 2
	}
	if !load_exec_image(file.data, unsafe { &image }, mut exec_space) { release_space(mut exec_space); return -12 }
	// No failure after this point: arguments and replacement mappings are ready.
	if framebuffer_length != 0 { framebuffer_unmap(framebuffer_virtual, framebuffer_length) }
	for fd in 0 .. 64 { if descriptors[fd].used && close_on_exec[fd] { sys_close(u32(fd)) } }
	release_space(mut processes[current_process].space)
	processes[current_process].space = exec_space
	exec_space.table = 0; exec_space.count = 0
	user_space = unsafe { &processes[current_process].space }
	stack := (u32(0x5fff0000) - count * 4) & ~u32(15)
	if !copy_to_user(0x5fff0000, unsafe { &exec_strings[0] }, args.strings)
		|| !copy_to_user(stack, unsafe { &u8(&exec_words[0]) }, count * 4) { halt(c'exec argument mapping') }
	process_break_min = if image.end < 0x50000000 { u32(0x51000000) } else { image.end }
	process_break = process_break_min
	processes[current_process].wait_pc = 0
	frame = exception.Frame{pc: image.entry, msr: 0xe030}
	frame.gpr[1] = stack
	runtime.fill(unsafe { &processes[current_process].fpu[0] }, 0, 264)
	C.vinix_restore_fpu(unsafe { &processes[current_process].fpu[0] })
	user_space.activate()
	serial.text(c'VINIX-PPC: exec pid '); serial.hex(processes[current_process].pid)
	serial.text(c' /'); serial.text(unsafe { &char(&file.name[0]) }); serial.text(c'\n')
	return 0
}
