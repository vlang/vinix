// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.exception
import powerpc.runtime
import powerpc.serial
import powerpc.ohci
import powerpc.gem
import powerpc.cpu
import powerpc.video

struct Descriptor {
mut:
	used   bool
	writable bool
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
	length := user_path(path)
	if length < 0 { return length }
	if length == 0 || io_buffer[0] != `/` { return -2 }
	mut end := length
	for end > 1 && io_buffer[end - 1] == `/` { end-- }
	mut packet_device := end == 9
	name := c'/dev/net0'
	unsafe { for i := 0; packet_device && i < end; i++ { if io_buffer[i] != u8(name[i]) { packet_device = false } } }
	mut audio_device := end == 10
	audio_name := c'/dev/audio'
	unsafe { for i := 0; audio_device && i < end; i++ { if io_buffer[i] != u8(audio_name[i]) { audio_device = false } } }
	mut framebuffer_device := end == 8
	fb_name := c'/dev/fb0'
	unsafe { for i := 0; framebuffer_device && i < end; i++ { if io_buffer[i] != u8(fb_name[i]) { framebuffer_device = false } } }
	mut pointer_device := end == 12
	pointer_name := c'/dev/pointer'
	unsafe { for i := 0; pointer_device && i < end; i++ { if io_buffer[i] != u8(pointer_name[i]) { pointer_device = false } } }
	if packet_device && !gem.present() { return -19 }
	if audio_device && !ohci.sound_present() { return -19 }
	if framebuffer_device && video.info().base == 0 { return -19 }
	if flags != 0 && !(pointer_device && flags == 0x800) && !((packet_device || framebuffer_device) && flags == 2) && !(audio_device && (flags == 1 || flags == 2)) { return -30 }
	node := if pointer_device { -6 } else if framebuffer_device { -5 } else if audio_device { -4 } else if packet_device { -3 } else if end == 1 { -2 } else { rootfs.find(unsafe { &io_buffer[1] }, u32(end - 1)) }
	if node == -1 { return -2 }
	for fd in 3 .. 16 {
		if !descriptors[fd].used {
			descriptors[fd] = Descriptor{ used: true, writable: flags == 1 || flags == 2, file: node }
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
		mut byte := serial.get()
		if byte < 0 { byte = ohci.get() }
		if byte < 0 { return -11 }
		io_buffer[0] = u8(byte)
		if !copy_to_user(address, unsafe { &io_buffer[0] }, 1) { return -14 }
		return 1
	}
	node := descriptors[fd].file
	if node == -6 {
		if count < 32 { return -22 }
		packet := ohci.pointer_snapshot()
		buffer_word(0, u32(packet.x)); buffer_word(4, u32(packet.y))
		buffer_word(8, u32(packet.max_x)); buffer_word(12, u32(packet.max_y))
		buffer_word(16, packet.buttons); buffer_word(20, packet.pressed); buffer_word(24, packet.released)
		buffer_word(28, u32(packet.scroll)); buffer_word(32, u32(packet.scroll_x))
		actual := if count >= 36 { u32(36) } else { u32(32) }
		if !copy_to_user(address, unsafe { &io_buffer[0] }, actual) { return -14 }
		return int(actual)
	}
	if node == -5 { return -22 } // fbdev currently exposes ioctl and mmap only
	if node == -4 { return -9 }
	if node == -3 {
		actual := gem.receive(unsafe { &io_buffer[0] }, count)
		if actual <= 0 { return actual }
		if !copy_to_user(address, unsafe { &io_buffer[0] }, u32(actual)) { return -14 }
		return actual
	}
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
	if fd >= 3 && fd < 16 && descriptors[fd].used && descriptors[fd].file == -4 {
		if !descriptors[fd].writable { return -9 }
		if requested == 0 || requested > 192000 || requested % 192 != 0 { return -22 }
		if !user_space.accessible(address, requested, false) { return -14 }
		destination := ohci.sound_buffer()
		if destination == 0 { return -19 }
		mut done := u32(0)
		for done < requested {
			mut size := 4096 - ((address + done) & 4095)
			if size > requested - done { size = requested - done }
			runtime.copy(voidptr(destination + done), voidptr(user_space.translate(address + done, false)), size)
			done += size
		}
		return ohci.sound_play(requested)
	}
	if fd >= 3 && fd < 16 && descriptors[fd].used && descriptors[fd].file == -3 {
		if !descriptors[fd].writable { return -9 }
		if requested < 14 || requested > 1514 { return -90 }
		if !user_space.accessible(address, requested, false) { return -14 }
		for i := u32(0); i < requested; i++ { io_buffer[i] = unsafe { *(&u8(user_space.translate(address + i, false))) } }
		return gem.send(unsafe { &io_buffer[0] }, requested)
	}
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
	if parent < -2 { return -20 }
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
	buffer_word(0, u32(runtime.divide_u64(cpu.timebase() - boot_clock, startup_info.timebase_hz)))
	buffer_word(16, managed_pages * 4096)
	buffer_word(20, physical_pages.count * 4096)
	io_buffer[41] = 1 // one live userspace process
	buffer_word(52, 1)
	if !copy_to_user(address, unsafe { &io_buffer[0] }, 64) { return -14 }
	return 0
}

// Development packet device ABI: MAC[6], reserved[2], BE link and MTU words.
// It is deliberately not advertised as a POSIX socket interface.
fn sys_ioctl(fd u32, request u32, address u32) int {
	if fd < 3 || fd >= 16 || !descriptors[fd].used { return -9 }
	if descriptors[fd].file == -5 { return framebuffer_ioctl(request, address) }
	if descriptors[fd].file != -3 || request != 0x564e0001 { return -25 }
	runtime.fill(unsafe { &io_buffer[0] }, 0, 16)
	gem.mac(unsafe { &io_buffer[0] })
	buffer_word(8, if gem.link() { u32(1) } else { u32(0) })
	buffer_word(12, 1500)
	if !copy_to_user(address, unsafe { &io_buffer[0] }, 16) { return -14 }
	return 0
}

fn syscall(mut frame exception.Frame) {
	mut result := -38
	match frame.gpr[0] {
		1 {
			if framebuffer_length != 0 { framebuffer_unmap(framebuffer_virtual, framebuffer_length) }
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
		54 { result = sys_ioctl(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		91 { result = framebuffer_unmap(frame.gpr[3], frame.gpr[4]) }
		116 { result = sys_info(frame.gpr[3]) }
		122 { result = sys_uname(frame.gpr[3]) }
		141 { result = sys_getdents(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		192 { result = framebuffer_map(frame.gpr[3], frame.gpr[4], frame.gpr[5], frame.gpr[6], frame.gpr[7], frame.gpr[8]) }
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
