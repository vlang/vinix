// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.exception
import powerpc.runtime
import powerpc.serial

struct Descriptor {
mut:
	used   bool
	file   int
	offset u32
}

__global descriptors [16]Descriptor
__global io_buffer [4096]u8

fn copy_to_user(address u32, source &u8, size u32) bool {
	if !user_space.accessible(address, size, true) { return false }
	mut done := u32(0)
	for done < size {
		mut count := 4096 - ((address + done) & 4095)
		if count > size - done { count = size - done }
		runtime.copy(voidptr(user_space.translate(address + done, true)), unsafe { &source[done] }, count)
		done += count
	}
	return true
}

fn user_path(address u32) int {
	for i := u32(0); i < 128; i++ {
		if i > 0xffffffff - address { return -14 }
		physical := user_space.translate(address + i, false)
		if physical == 0 { return -14 }
		byte := unsafe { *(&u8(physical)) }
		io_buffer[i] = byte
		if byte == 0 { return int(i) }
	}
	return -36
}

fn sys_open(path u32, flags u32) int {
	if flags != 0 { return -30 }
	length := user_path(path)
	if length < 0 { return length }
	if length == 0 || io_buffer[0] != `/` { return -2 }
	mut end := length
	for end > 1 && io_buffer[end - 1] == `/` { end-- }
	node := if end == 1 { -2 } else { rootfs.find(unsafe { &io_buffer[1] }, u32(end - 1)) }
	if node == -1 { return -2 }
	for fd in 3 .. 16 {
		if !descriptors[fd].used {
			descriptors[fd] = Descriptor{ used: true, file: node }
			return fd
		}
	}
	return -24
}

fn sys_read(fd u32, address u32, requested u32) int {
	count := if requested > 4096 { u32(4096) } else { requested }
	if fd != 0 && (fd < 3 || fd >= 16 || !descriptors[fd].used) { return -9 }
	if !user_space.accessible(address, count, true) { return -14 }
	if count == 0 { return 0 }
	if fd == 0 {
		byte := serial.get()
		if byte < 0 { return -11 }
		io_buffer[0] = u8(byte)
		if !copy_to_user(address, unsafe { &io_buffer[0] }, 1) { return -14 }
		return 1
	}
	node := descriptors[fd].file
	if node == -2 || rootfs.files[node].directory { return -21 }
	file := rootfs.files[node]
	offset := descriptors[fd].offset
	if offset >= file.size { return 0 }
	actual := if count > file.size - offset { file.size - offset } else { count }
	if !copy_to_user(address, unsafe { &file.data[offset] }, actual) { return -14 }
	descriptors[fd].offset += actual
	return int(actual)
}

fn sys_write(fd u32, address u32, requested u32) int {
	if fd != 1 && fd != 2 { return -9 }
	count := if requested > 4096 { u32(4096) } else { requested }
	if !user_space.accessible(address, count, false) { return -14 }
	for i := u32(0); i < count; i++ {
		byte := unsafe { *(&u8(user_space.translate(address + i, false))) }
		if byte == `\n` { serial.put(`\r`) }
		serial.put(byte)
	}
	return int(count)
}

fn buffer_word(at u32, value u32) {
	for i := u32(0); i < 4; i++ { io_buffer[at + i] = u8(value >> (24 - i * 8)) }
}

fn sys_getdents(fd u32, address u32, requested u32) int {
	if fd < 3 || fd >= 16 || !descriptors[fd].used { return -9 }
	parent := descriptors[fd].file
	if parent >= 0 && !rootfs.files[parent].directory { return -20 }
	capacity := if requested > 4096 { u32(4096) } else { requested }
	if !user_space.accessible(address, capacity, true) { return -14 }
	mut used := u32(0)
	for descriptors[fd].offset < rootfs.count {
		index := descriptors[fd].offset
		file := rootfs.files[index]
		mut name_start := u32(0)
		mut child := true
		if parent >= 0 {
			prefix := rootfs.files[parent].name_size
			if file.name_size <= prefix || file.name[prefix] != `/` { child = false }
			for i := u32(0); child && i < prefix; i++ {
				if file.name[i] != rootfs.files[parent].name[i] { child = false }
			}
			name_start = prefix + 1
		}
		for i := name_start; child && i < file.name_size; i++ {
			if file.name[i] == `/` { child = false }
		}
		if !child {
			descriptors[fd].offset++
			continue
		}
		namesize := file.name_size - name_start
		record := (10 + namesize + 2 + 3) & ~u32(3)
		if record > capacity - used {
			if used == 0 { return -22 }
			break
		}
		runtime.fill(unsafe { &io_buffer[used] }, 0, record)
		buffer_word(used, index + 1)
		buffer_word(used + 4, index + 1)
		io_buffer[used + 8] = u8(record >> 8)
		io_buffer[used + 9] = u8(record)
		for i := u32(0); i < namesize; i++ { io_buffer[used + 10 + i] = file.name[name_start + i] }
		io_buffer[used + record - 1] = if file.directory { u8(4) } else { u8(8) }
		used += record
		descriptors[fd].offset++
	}
	if !copy_to_user(address, unsafe { &io_buffer[0] }, used) { return -14 }
	return int(used)
}

fn buffer_text(at u32, text &char) {
	unsafe { for i := u32(0); text[i] != 0 && i < 64; i++ { io_buffer[at + i] = u8(text[i]) }
	 }
}

fn sys_uname(address u32) int {
	runtime.fill(unsafe { &io_buffer[0] }, 0, 390)
	buffer_text(0, c'Vinix')
	buffer_text(65, c'powerpc')
	buffer_text(130, c'0.1-ppc-dev')
	buffer_text(195, c'PPC32 bring-up')
	buffer_text(260, c'powerpc')
	if !copy_to_user(address, unsafe { &io_buffer[0] }, 390) { return -14 }
	return 0
}

fn sys_info(address u32) int {
	runtime.fill(unsafe { &io_buffer[0] }, 0, 64)
	buffer_word(0, ticks / 100)
	buffer_word(16, managed_pages * 4096)
	buffer_word(20, physical_pages.count * 4096)
	io_buffer[41] = 1 // one live userspace process
	buffer_word(52, 1)
	if !copy_to_user(address, unsafe { &io_buffer[0] }, 64) { return -14 }
	return 0
}

fn syscall(mut frame exception.Frame) {
	mut result := -38
	match frame.gpr[0] {
		1 {
			serial.text(c'\nVinix: init exited, status ')
			serial.hex(frame.gpr[3])
			serial.text(c'\n')
			for {}
		}
		3 { result = sys_read(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		4 { result = sys_write(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		5 { result = sys_open(frame.gpr[3], frame.gpr[4]) }
		6 {
			fd := frame.gpr[3]
			result = -9
			if fd >= 3 && fd < 16 && descriptors[fd].used {
				descriptors[fd].used = false
				result = 0
			}
		}
		20 { result = 1 }
		116 { result = sys_info(frame.gpr[3]) }
		122 { result = sys_uname(frame.gpr[3]) }
		141 { result = sys_getdents(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		else {}
	}
	frame.cr &= ~u32(0x10000000)
	if result < 0 {
		frame.cr |= 0x10000000
		frame.gpr[3] = u32(-result)
	} else {
		frame.gpr[3] = u32(result)
	}
}
