// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.ext2
import powerpc.runtime

fn sys_access(path u32, mode u32) int {
	if mode & ~u32(7) != 0 { return -22 }
	length := user_path(path)
	if length <= 0 { return if length < 0 { length } else { -2 } }
	if persistent_volume.mounted {
		id := persistent_volume.walk(unsafe { &io_buffer[0] }, u32(length), true)
		if id > 0 {
			mut n := ext2.Node{}
			if !persistent_volume.inode(u32(id), mut n) { return -5 }
			// The initial process runs as root. Linux still requires at least
			// one execute bit for X_OK on a regular file.
			if mode & 1 != 0 && n.mode() & 0xf000 == 0x8000 && n.mode() & 0o111 == 0 { return -13 }
			return 0
		}
		if id != -2 { return id }
	}
	if path_equal(c'/dev/urandom', length) || path_equal(c'/dev/random', length) {
		return if !persistent_random.ready { -19 } else if mode & 3 != 0 { -13 } else { 0 }
	}
	if length == 1 && io_buffer[0] == `/` { return if mode & 2 != 0 { -30 } else { 0 } }
	if io_buffer[0] != `/` { return -2 }
	id := rootfs.find(unsafe { &io_buffer[1] }, u32(length - 1))
	if id < 0 { return -2 }
	return if mode & 2 != 0 { -30 } else { 0 }
}

// Linux statx is a fixed-width structure on both endian variants of PPC32.
fn sys_statx(dirfd u32, path u32, flags u32, address u32) int {
	if flags & ~u32(0x7900) != 0 || flags & 0x6000 == 0x6000 { return -22 }
	if !user_space.accessible(address, 256, true) { return -14 }
	length := user_path(path)
	if length < 0 { return length }
	mut id := u32(0)
	mut archive := -1
	mut mode := u32(0)
	mut size := u32(0)
	if length == 0 && flags & 0x1000 != 0 {
		if dirfd >= 16 || (dirfd >= 3 && !descriptors[dirfd].used) { return -9 }
		if dirfd < 3 { mode = 0x2180 }
		else { id = descriptors[dirfd].inode; archive = descriptors[dirfd].file }
	} else {
		if length == 0 { return -2 }
		if io_buffer[0] != `/` && i32(dirfd) != -100 { return -95 }
		if persistent_volume.mounted {
			found := persistent_volume.walk(unsafe { &io_buffer[0] }, u32(length), flags & 0x100 == 0)
			if found > 0 { id = u32(found) } else if found != -2 { return found }
		}
		if id == 0 {
			if length == 1 && io_buffer[0] == `/` { archive = -2 }
			else if path_equal(c'/dev', length) { mode = 0x41ed }
			else if path_equal(c'/dev/urandom', length) || path_equal(c'/dev/random', length)
				|| path_equal(c'/dev/fb0', length) || path_equal(c'/dev/pointer', length)
				|| path_equal(c'/dev/audio', length) || path_equal(c'/dev/net0', length) { mode = 0x2180 }
			else if io_buffer[0] == `/` { archive = rootfs.find(unsafe { &io_buffer[1] }, u32(length - 1)) }
			if archive == -1 && mode == 0 { return -2 }
		}
	}
	mut n := ext2.Node{}
	if id != 0 {
		if !persistent_volume.inode(id, mut n) { return -5 }
		mode = n.mode(); size = n.size()
	} else if mode == 0 {
		if archive == -2 { mode = 0x41ed }
		else if archive < -2 { mode = 0x2180 }
		else if archive >= 0 { mode = if rootfs.files[archive].directory { u32(0x41ed) } else { u32(0x81a4) }; size = rootfs.files[archive].size }
		else { return -9 }
	}
	runtime.fill(unsafe { &io_buffer[0] }, 0, 256)
	buffer_word(0, 0x7ff); buffer_word(4, 4096)
	buffer_word(16, if id != 0 { n.links() } else { u32(1) })
	if id != 0 {
		buffer_word(20, ext2.le16(unsafe { &n.raw[0] }, 2))
		buffer_word(24, ext2.le16(unsafe { &n.raw[0] }, 24))
		buffer_word(52, n.blocks())
		buffer_word(68, ext2.le32(unsafe { &n.raw[0] }, 8))
		buffer_word(100, ext2.le32(unsafe { &n.raw[0] }, 12))
		buffer_word(116, ext2.le32(unsafe { &n.raw[0] }, 16))
	}
	io_buffer[28] = u8(mode >> 8); io_buffer[29] = u8(mode)
	buffer_word(36, if id != 0 { id } else { u32(archive + 16) })
	buffer_word(44, size)
	buffer_word(140, if id != 0 { u32(1) } else { u32(2) })
	return if copy_to_user(address, unsafe { &io_buffer[0] }, 256) { 0 } else { -14 }
}

fn storage_getdents(fd u32, address u32, requested u32, wide bool) int {
	if fd < 3 || fd >= 16 || !descriptors[fd].used { return -9 }
	if !disk_fd(fd) { return -20 }
	capacity := if requested > 4096 { u32(4096) } else { requested }
	if !user_space.accessible(address, capacity, true) { return -14 }
	mut used := u32(0)
	mut e := ext2.Entry{}
	for {
		result := persistent_volume.next(descriptors[fd].inode, descriptors[fd].offset, mut e)
		if result < 0 { return if used > 0 { int(used) } else { result } }
		if result == 0 { break }
		head := if wide { u32(19) } else { u32(10) }
		record := if wide { (head + e.length + 1 + 7) & ~u32(7) } else { (head + e.length + 2 + 3) & ~u32(3) }
		if record > capacity - used { if used == 0 { return -22 }; break }
		runtime.fill(unsafe { &io_buffer[used] }, 0, record)
		dtype := if e.kind == 2 { u8(4) } else if e.kind == 7 { u8(10) } else { u8(8) }
		if wide {
			buffer_word(used + 4, e.number); buffer_word(used + 12, e.next)
			io_buffer[used + 16] = u8(record >> 8); io_buffer[used + 17] = u8(record); io_buffer[used + 18] = dtype
		} else {
			buffer_word(used, e.number); buffer_word(used + 4, e.next)
			io_buffer[used + 8] = u8(record >> 8); io_buffer[used + 9] = u8(record); io_buffer[used + record - 1] = dtype
		}
		runtime.copy(unsafe { &io_buffer[used + head] }, unsafe { &e.name[0] }, e.length)
		used += record
		descriptors[fd].offset = e.next
	}
	return if copy_to_user(address, unsafe { &io_buffer[0] }, used) { int(used) } else { -14 }
}
