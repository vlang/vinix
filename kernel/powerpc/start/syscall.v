// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.exception
import powerpc.runtime
import powerpc.serial
import powerpc.ohci
import powerpc.gem
import powerpc.cpu

struct Descriptor {
mut:
	refs u32
	pipe int
	pty int
	used   bool
	writable bool
	file   int
	offset u32
	inode u32
	flags u32
}

__global descriptors [64]&Descriptor
__global io_buffer [4096]u8
__global syscall_trace_count u32

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

fn copy_from_user(destination &u8, address u32, size u32) bool {
	if !user_space.accessible(address, size, false) { return false }
	mut done := u32(0)
	for done < size {
		mut count := 4096 - ((address + done) & 4095)
		if count > size - done { count = size - done }
		runtime.copy(unsafe { &destination[done] }, voidptr(user_space.translate(address + done, false)), count)
		done += count
	}
	return true
}

fn sys_writev(fd u32, vectors u32, count u32) int {
	if count > 1024 { return -22 }
	if !user_space.accessible(vectors, count * 8, false) { return -14 }
	mut total := 0
	for i := u32(0); i < count; i++ {
		mut pair := [2]u32{}
		if !copy_from_user(unsafe { &u8(&pair[0]) }, vectors + i * 8, 8) { return -14 }
		if pair[1] > u32(0x7fffffff - total) { return if total > 0 { total } else { -22 } }
		mut sent := u32(0)
		for sent < pair[1] {
			result := sys_write(fd, pair[0] + sent, pair[1] - sent)
			if result < 0 { return if total > 0 { total } else { result } }
			if result == 0 { return total }
			sent += u32(result)
			total += result
		}
	}
	return total
}

fn sys_readv(fd u32, vectors u32, count u32) int {
	if count > 1024 { return -22 }
	if !user_space.accessible(vectors, count * 8, false) { return -14 }
	mut total := 0
	for i := u32(0); i < count; i++ {
		mut pair := [2]u32{}
		if !copy_from_user(unsafe { &u8(&pair[0]) }, vectors + i * 8, 8) { return if total > 0 { total } else { -14 } }
		if pair[1] > u32(0x7fffffff - total) { return if total > 0 { total } else { -22 } }
		mut done := u32(0)
		for done < pair[1] {
			request := if pair[1] - done > 4096 { u32(4096) } else { pair[1] - done }
			result := sys_read(fd, pair[0] + done, request)
			if result < 0 { return if total > 0 { total } else { result } }
			total += result
			if result < int(request) { return total }
			done += u32(result)
		}
	}
	return total
}

fn sys_clock64(clock_id u32, address u32) int {
	if clock_id != 0 && clock_id != 1 && clock_id != 4 { return -22 }
	elapsed := cpu.timebase() - boot_clock
	mut seconds := runtime.divide_u64(elapsed, startup_info.timebase_hz)
	nanos := runtime.divide_u64((elapsed - seconds * startup_info.timebase_hz) * 1000000000, startup_info.timebase_hz)
	if clock_id == 0 { seconds += persistent_volume.epoch } // initial wall-clock estimate from disk
	buffer_word(0, u32(seconds >> 32)); buffer_word(4, u32(seconds))
	buffer_word(8, 0); buffer_word(12, u32(nanos))
	if !copy_to_user(address, unsafe { &io_buffer[0] }, 16) { return -14 }
	return 0
}

fn user_path(address u32) int {
	for i := u32(0); i < 512; i++ {
		if i > 0xffffffff - address { return -14 }
		physical := user_space.translate(address + i, false)
		if physical == 0 { return -14 }
		byte := unsafe { *(&u8(physical)) }
		io_buffer[i] = byte
		if byte == 0 { return int(i) }
	}
	return -36
}

fn sys_open(path u32, requested_flags u32, mode u32) int {
	// Strip lookup/descriptor flags before validating archive device access.
	flags := requested_flags & ~u32(0x9c100)
	length := user_path(path)
	if length < 0 { return length }
	if length == 0 || io_buffer[0] != `/` { return -2 }
	terminal := pty_open(length, requested_flags)
	if terminal != -2 { return terminal }
	device := device_node(length)
	if device != -1 && !device_present(device) { return -19 }
	if device == -7 {
		if requested_flags & 3 != 0 { return -13 }
		for fd in 3 .. 64 {
			if !descriptors[fd].used {
				if !install_fd(fd, Descriptor{used: true, file: -7, flags: requested_flags}) { return -24 }
				return fd
			}
		}
		return -24
	}
	if length < 5 || !(io_buffer[1] == `d` && io_buffer[2] == `e` && io_buffer[3] == `v` && io_buffer[4] == `/`) {
		opened := storage_open(length, requested_flags, mode)
		if opened != -2 { return opened }
	}
	mut end := length
	for end > 1 && io_buffer[end - 1] == `/` { end-- }
	packet_device := device == -3
	audio_device := device == -4
	framebuffer_device := device == -5
	pointer_device := device == -6
	node := if pointer_device { -6 } else if framebuffer_device { -5 } else if audio_device { -4 } else if packet_device { -3 } else if end == 1 { -2 } else { rootfs.find(unsafe { &io_buffer[1] }, u32(end - 1)) }
	if node == -1 { return -2 }
	if flags != 0 && !(pointer_device && flags == 0x800) && !((packet_device || framebuffer_device) && flags == 2) && !(audio_device && (flags == 1 || flags == 2)) { return -30 }
	if requested_flags & 0x4000 != 0 && node != -2 && (node < 0 || !rootfs.files[node].directory) { return -20 }
	for fd in 3 .. 64 {
		if !descriptors[fd].used {
			if !install_fd(fd, Descriptor{ used: true, writable: flags == 1 || flags == 2, file: node, flags: requested_flags }) { return -24 }
			return fd
		}
	}
	return -24
}

fn sys_read(fd u32, address u32, requested u32) int {
	count := if requested > 4096 { u32(4096) } else { requested }
	if fd >= 64 || !descriptors[fd].used { return -9 }
	if descriptors[fd].pipe != 0 { return pipe_read(fd, address, count) }
	if descriptors[fd].pty != 0 { return pty_read(fd, address, requested) }
	if !user_space.accessible(address, count, true) { return -14 }
	if count == 0 { return 0 }
	if disk_fd(fd) { return storage_read(fd, address, count) }
	if descriptors[fd].file == -8 {
		if descriptors[fd].writable { return -9 }
		mut byte := serial.get()
		if byte < 0 { byte = ohci.get() }
		if byte < 0 { return -11 }
		io_buffer[0] = u8(byte)
		if !copy_to_user(address, unsafe { &io_buffer[0] }, 1) { return -14 }
		return 1
	}
	node := descriptors[fd].file
	if node == -7 { return sys_random(address, count, 0) }
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
	if fd >= 64 || !descriptors[fd].used { return -9 }
	if descriptors[fd].pipe != 0 { return pipe_write(fd, address, requested) }
	if descriptors[fd].pty != 0 { return pty_write(fd, address, requested) }
	if disk_fd(fd) { return storage_write(fd, address, if requested > 4096 { u32(4096) } else { requested }) }
	if descriptors[fd].file == -4 {
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
	if descriptors[fd].file == -3 {
		if !descriptors[fd].writable { return -9 }
		if requested < 14 || requested > 1514 { return -90 }
		if !user_space.accessible(address, requested, false) { return -14 }
		for i := u32(0); i < requested; i++ { io_buffer[i] = unsafe { *(&u8(user_space.translate(address + i, false))) } }
		return gem.send(unsafe { &io_buffer[0] }, requested)
	}
	if descriptors[fd].file != -8 || !descriptors[fd].writable { return -9 }
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

fn sys_getdents(fd u32, address u32, requested u32, wide bool) int {
	if fd >= 64 || !descriptors[fd].used { return -9 }
	if disk_fd(fd) { return storage_getdents(fd, address, requested, wide) }
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
		head := if wide { u32(19) } else { u32(10) }
		record := if wide { (head + namesize + 1 + 7) & ~u32(7) } else { (head + namesize + 2 + 3) & ~u32(3) }
		if record > capacity - used {
			if used == 0 { return -22 }
			break
		}
		runtime.fill(unsafe { &io_buffer[used] }, 0, record)
		dtype := if file.directory { u8(4) } else { u8(8) }
		if wide {
			buffer_word(used + 4, index + 1); buffer_word(used + 12, index + 1)
			io_buffer[used + 16] = u8(record >> 8); io_buffer[used + 17] = u8(record); io_buffer[used + 18] = dtype
		} else {
			buffer_word(used, index + 1); buffer_word(used + 4, index + 1)
			io_buffer[used + 8] = u8(record >> 8); io_buffer[used + 9] = u8(record); io_buffer[used + record - 1] = dtype
		}
		for i := u32(0); i < namesize; i++ { io_buffer[used + head + i] = file.name[name_start + i] }
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
	for i in 0 .. 8 { if processes[i].state != 0 { io_buffer[41]++ } }
	buffer_word(52, 1)
	if !copy_to_user(address, unsafe { &io_buffer[0] }, 64) { return -14 }
	return 0
}

// Development packet device ABI: MAC[6], reserved[2], BE link and MTU words.
// It is deliberately not advertised as a POSIX socket interface.
fn sys_ioctl(fd u32, request u32, address u32) int {
	if fd >= 64 || !descriptors[fd].used { return -9 }
	if descriptors[fd].pty != 0 { return pty_ioctl(fd, request, address) }
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
	if processes[current_process].sandbox && !sandbox_allows(frame.gpr[0]) {
		frame.gpr[3] = 1
		frame.cr |= 0x10000000
		switch_process(mut frame)
		return
	}
	mut result := -38
	match frame.gpr[0] {
		1, 234 {
			finish_process((frame.gpr[3] & 255) << 8)
			switch_process(mut frame)
			return
		}
		2 { result = sys_fork(&frame) }
		7, 114 { result = sys_waitpid(i32(frame.gpr[3]), frame.gpr[4], frame.gpr[5]) }
		11 {
			result = sys_exec(frame.gpr[3], frame.gpr[4], frame.gpr[5], mut frame)
			if result == 0 { switch_process(mut frame); return }
		}
		3 { result = sys_read(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		4 { result = sys_write(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		5 { result = sys_open(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		6 { result = sys_close(frame.gpr[3]) }
		10, 15, 39, 40 { result = sys_path_change(frame.gpr[3], frame.gpr[4], frame.gpr[0]) }
		19 { result = sys_seek(frame.gpr[3], i64(i32(frame.gpr[4])), frame.gpr[5], 0) }
		36 { result = if !persistent_volume.mounted || persistent_volume.sync() { 0 } else { -5 } }
		38 { result = sys_rename(frame.gpr[3], frame.gpr[4]) }
		20, 207 { result = int(processes[current_process].pid) }
		64 { result = int(processes[current_process].parent) }
		66 { result = int(processes[current_process].pid) } // single-process terminal sessions
		41 { result = sys_dup_min(frame.gpr[3], 0, 0) }
		63 { result = sys_dup(frame.gpr[3], frame.gpr[4], 0) }
		42 { result = sys_pipe(frame.gpr[3], 0) }
		317 { result = sys_pipe(frame.gpr[3], frame.gpr[4]) }
		316 { result = if frame.gpr[3] == frame.gpr[4] { -22 } else { sys_dup(frame.gpr[3], frame.gpr[4], frame.gpr[5]) } }
		158 { result = 0 }
		175 {
			// Signal delivery is limited to process termination for now. Musl
			// blocks signals around fork; always return a defined old mask.
			result = if frame.gpr[6] != 8 || frame.gpr[3] > 2 { -22 } else { 0 }
			if result == 0 && frame.gpr[5] != 0 {
				runtime.fill(unsafe { &io_buffer[0] }, 0, 8)
				if !copy_to_user(frame.gpr[5], unsafe { &io_buffer[0] }, 8) { result = -14 }
			}
		}
		33 { result = sys_access(frame.gpr[3], frame.gpr[4]) }
		37 { result = sys_kill(i32(frame.gpr[3]), frame.gpr[4]) }
		24, 47, 49, 50 { result = if processes[current_process].sandbox { 65534 } else { 0 } }
		45 { result = sys_brk(frame.gpr[3]) }
		54 { result = sys_ioctl(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		55, 204 { result = sys_fcntl(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		60 { result = int(process_umask); process_umask = frame.gpr[3] & 0x1ff }
		83 { result = sys_symlink(frame.gpr[3], frame.gpr[4]) }
		85 { result = sys_readlink(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		94 { result = if disk_fd(frame.gpr[3]) { persistent_volume.chmod(descriptors[frame.gpr[3]].inode, frame.gpr[4]) } else { -9 } }
		91 {
			result = if frame.gpr[3] == framebuffer_virtual { framebuffer_unmap(frame.gpr[3], frame.gpr[4]) }
				else { anonymous_unmap(frame.gpr[3], frame.gpr[4]) }
		}
		116 { result = sys_info(frame.gpr[3]) }
		118, 148 { result = sys_fsync(frame.gpr[3]) }
		122 { result = sys_uname(frame.gpr[3]) }
		141 { result = sys_getdents(frame.gpr[3], frame.gpr[4], frame.gpr[5], false) }
		140 { result = if frame.gpr[6] == 0 { -14 } else { sys_seek(frame.gpr[3], i64(u64(frame.gpr[4]) << 32 | frame.gpr[5]), frame.gpr[7], frame.gpr[6]) } }
		202 { result = sys_getdents(frame.gpr[3], frame.gpr[4], frame.gpr[5], true) }
		146 { result = sys_writev(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		145 { result = sys_readv(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		162 { result = sys_nanosleep(frame.gpr[3], frame.pc) }
		167 { result = sys_poll(frame.gpr[3], frame.gpr[4], i32(frame.gpr[5]), frame.pc) }
		182 {
			result = if frame.gpr[4] < 2 { -34 }
				else if copy_to_user(frame.gpr[3], unsafe { &u8(c'/') }, 2) { 2 } else { -14 }
		}
		192 {
			result = if frame.gpr[6] & 0x20 != 0 { anonymous_map(frame.gpr[3], frame.gpr[4], frame.gpr[5], frame.gpr[6], frame.gpr[8]) }
				else { framebuffer_map(frame.gpr[3], frame.gpr[4], frame.gpr[5], frame.gpr[6], frame.gpr[7], frame.gpr[8]) }
		}
		232 { result = if frame.gpr[3] == 0 || user_space.accessible(frame.gpr[3], 4, true) { int(processes[current_process].pid) } else { -14 } }
		223 {
			buffer_word(0, 1)
			result = if frame.gpr[3] != 0 && frame.gpr[3] != 1 { -3 }
				else if frame.gpr[4] < 4 { -22 }
				else if copy_to_user(frame.gpr[5], unsafe { &io_buffer[0] }, 4) { 4 } else { -14 }
		}
		403 { result = sys_clock64(frame.gpr[3], frame.gpr[4]) }
		359 { result = sys_random(frame.gpr[3], frame.gpr[4], frame.gpr[5]) }
		436 {
			result = if frame.gpr[3] > frame.gpr[4] || frame.gpr[5] != 0 { -22 } else { 0 }
			if result == 0 { for fd := frame.gpr[3]; fd < 64 && fd <= frame.gpr[4]; fd++ { if descriptors[fd].used { sys_close(fd) } } }
		}
		383 { result = sys_statx(frame.gpr[3], frame.gpr[4], frame.gpr[5], frame.gpr[7]) }
		0x7f10 { result = sys_app_sandbox(frame.gpr[3], frame.gpr[4]) }
		else {}
	}
	if result == restart_call {
		frame.pc -= 4
		switch_process(mut frame)
		return
	}
	processes[current_process].wait_pc = 0
	frame.cr &= ~u32(0x10000000)
	if result < 0 {
		$if ppc_trace_syscalls ? {
			if result != -11 && syscall_trace_count < 128 {
				syscall_trace_count++
				serial.text(c'syscall '); serial.hex(frame.gpr[0])
				serial.text(c' errno '); serial.hex(u32(-result))
				serial.text(c' pc '); serial.hex(frame.pc); serial.text(c'\n')
			}
		}
		frame.cr |= 0x10000000
		frame.gpr[3] = u32(-result)
	} else {
		frame.gpr[3] = u32(result)
	}
	switch_process(mut frame)
}
