// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.ata
import powerpc.ext2
import powerpc.entropy
import powerpc.runtime
import powerpc.serial

__global persistent_volume ext2.Volume
__global persistent_random entropy.Generator
__global process_umask u32 = 0o022

fn storage_init() {
	if ata.capacity() == 0 { return }
	if !persistent_volume.mount(ext2.Device{read: ata.read, write: ata.write, flush: ata.flush, sectors: ata.capacity()}) {
		serial.text(c'Vinix: disk has no supported ext2 volume; leaving it untouched\n')
		return
	}
	serial.text(c'VINIX-PPC: PASS writable ext2 mounted\n')
	if storage_seed() { serial.text(c'VINIX-PPC: PASS private random seed rotated and flushed\n') }
	else { serial.text(c'Vinix: random device unavailable: seed missing or flush failed\n') }
}

fn storage_seed() bool {
	id := persistent_volume.walk(unsafe { &u8(c'/root/.vinix-rng-seed') }, 21, false)
	mut n := ext2.Node{}
	if id < 0 || !persistent_volume.inode(u32(id), mut n) || n.mode() != 0x8180 || n.size() != 32 { return false }
	mut old := [32]u8{}
	mut key := [32]u8{}
	mut next := [32]u8{}
	defer {
		entropy.explicit_bzero(&old[0], sizeof(old)); entropy.explicit_bzero(&key[0], sizeof(key))
		entropy.explicit_bzero(&next[0], sizeof(next))
	}
	if persistent_volume.read(u32(id), 0, unsafe { &old[0] }, 32) != 32 { return false }
	entropy.derive(unsafe { &old[0] }, unsafe { &key }, unsafe { &next })
	if persistent_volume.write(u32(id), 0, unsafe { &next[0] }, 32) != 32 || !persistent_volume.sync() { return false }
	persistent_random.seed(unsafe { &key[0] })
	return true
}

fn disk_fd(fd u32) bool { return fd >= 3 && fd < 16 && descriptors[fd].used && descriptors[fd].inode != 0 }
fn inode_open(id u32) bool {
	for fd in 3 .. 16 { if descriptors[fd].used && descriptors[fd].inode == id { return true } }
	return false
}

fn sys_close(fd u32) int {
	if fd < 3 || fd >= 16 || !descriptors[fd].used { return -9 }
	id := descriptors[fd].inode
	descriptors[fd] = Descriptor{}
	if id != 0 && !inode_open(id) {
		mut n := ext2.Node{}
		if !persistent_volume.inode(id, mut n) { return -5 }
		if n.links() == 0 && !persistent_volume.reap(id) { return -5 }
	}
	return 0
}

fn path_equal(name &char, length int) bool {
	unsafe {
		for i in 0 .. length { if name[i] == 0 || io_buffer[i] != u8(name[i]) { return false } }
		return name[length] == 0
	}
}

fn storage_open(length int, flags u32, mode u32) int {
	if !persistent_volume.mounted { return -2 }
	mut available := -1
	for fd in 3 .. 16 { if !descriptors[fd].used { available = fd; break } }
	if available < 0 { return -24 }
	if flags & ~u32(0x1ddfc3) != 0 || flags & 3 == 3 { return -22 }
	mut id := persistent_volume.walk(unsafe { &io_buffer[0] }, u32(length), flags & 0x8000 == 0 && flags & 0xc0 != 0xc0)
	if id > 0 && flags & 0xc0 == 0xc0 { return -17 }
	if id == -2 && flags & 0x40 != 0 {
		mut name := ext2.Entry{}
		parent := persistent_volume.parent(unsafe { &io_buffer[0] }, u32(length), mut name)
		if parent < 0 { return parent }
		id = persistent_volume.create(u32(parent), unsafe { &name.name[0] }, name.length, 0x8000 | (mode & 0xfff & ~process_umask))
	}
	if id < 0 { return id }
	mut n := ext2.Node{}
	if !persistent_volume.inode(u32(id), mut n) { return -5 }
	if n.mode() & 0xf000 == 0xa000 { return -40 }
	if flags & 0x4000 != 0 && n.mode() & 0xf000 != 0x4000 { return -20 }
	if (flags & 3 != 0 || flags & 0x200 != 0) && n.mode() & 0xf000 == 0x4000 { return -21 }
	if flags & 0x200 != 0 {
		if flags & 3 == 0 { return -22 }
		result := persistent_volume.truncate(u32(id))
		if result < 0 { return result }
	}
	descriptors[available] = Descriptor{used: true, writable: flags & 3 != 0, inode: u32(id), flags: flags}
	return available
}

fn storage_read(fd u32, address u32, count u32) int {
	if descriptors[fd].flags & 3 == 1 { return -9 }
	result := persistent_volume.read(descriptors[fd].inode, descriptors[fd].offset, unsafe { &io_buffer[0] }, count)
	if result <= 0 { return result }
	if !copy_to_user(address, unsafe { &io_buffer[0] }, u32(result)) { return -14 }
	descriptors[fd].offset += u32(result)
	return result
}

fn storage_write(fd u32, address u32, count u32) int {
	if !descriptors[fd].writable { return -9 }
	if !copy_from_user(unsafe { &io_buffer[0] }, address, count) { return -14 }
	if descriptors[fd].flags & 0x400 != 0 {
		mut n := ext2.Node{}
		if !persistent_volume.inode(descriptors[fd].inode, mut n) { return -5 }
		descriptors[fd].offset = n.size()
	}
	result := persistent_volume.write(descriptors[fd].inode, descriptors[fd].offset, unsafe { &io_buffer[0] }, count)
	if result > 0 { descriptors[fd].offset += u32(result) }
	if result >= 0 && descriptors[fd].flags & 0x1000 != 0 && !persistent_volume.sync() { return -5 }
	return result
}

fn sys_random(address u32, requested u32, flags u32) int {
	if flags & ~u32(3) != 0 { return -22 }
	count := if requested > 4096 { u32(4096) } else { requested }
	if !user_space.accessible(address, count, true) { return -14 }
	if !persistent_random.fill(unsafe { &io_buffer[0] }, count) { return -11 }
	result := if copy_to_user(address, unsafe { &io_buffer[0] }, count) { int(count) } else { -14 }
	entropy.explicit_bzero(&io_buffer[0], count)
	return result
}

fn sys_fsync(fd u32) int {
	if fd < 3 || fd >= 16 || !descriptors[fd].used { return -9 }
	if !disk_fd(fd) { return if descriptors[fd].file >= -2 { 0 } else { -22 } }
	return if persistent_volume.sync() { 0 } else { -5 }
}

fn sys_fcntl(fd u32, command u32, arg u32) int {
	if fd >= 16 || (fd >= 3 && !descriptors[fd].used) { return -9 }
	match command {
		1 { return int((descriptors[fd].flags >> 19) & 1) }
		2 { descriptors[fd].flags = (descriptors[fd].flags & ~u32(0x80000)) | ((arg & 1) << 19); return 0 }
		3 { return int(descriptors[fd].flags & ~u32(0x80000)) }
		4 { descriptors[fd].flags = (descriptors[fd].flags & ~u32(0xc00)) | (arg & 0xc00); return 0 }
		else { return -22 }
	}
}

fn sys_seek(fd u32, delta i64, whence u32, result_address u32) int {
	if fd < 3 || fd >= 16 || !descriptors[fd].used { return -9 }
	if result_address != 0 && !user_space.accessible(result_address, 8, true) { return -14 }
	mut size := u32(0)
	if disk_fd(fd) {
		mut n := ext2.Node{}
		if !persistent_volume.inode(descriptors[fd].inode, mut n) { return -5 }
		size = n.size()
	} else if descriptors[fd].file >= 0 { size = rootfs.files[descriptors[fd].file].size }
	else if descriptors[fd].file != -2 { return -29 }
	if whence > 2 { return -22 }
	base := if whence == 1 { descriptors[fd].offset } else if whence == 2 { size } else { u32(0) }
	if delta < -i64(base) || delta > 0x7fffffff - i64(base) { return -22 }
	position := u32(i64(base) + delta)
	descriptors[fd].offset = position
	if result_address == 0 { return int(position) }
	buffer_word(0, 0); buffer_word(4, position)
	return if copy_to_user(result_address, unsafe { &io_buffer[0] }, 8) { 0 } else { -14 }
}

fn sys_path_change(path u32, arg u32, operation u32) int {
	length := user_path(path)
	if length < 0 { return length }
	if !persistent_volume.mounted { return -30 }
	if operation == 15 {
		id := persistent_volume.walk(unsafe { &io_buffer[0] }, u32(length), true)
		return if id < 0 { id } else { persistent_volume.chmod(u32(id), arg) }
	}
	mut name := ext2.Entry{}
	parent := persistent_volume.parent(unsafe { &io_buffer[0] }, u32(length), mut name)
	if parent < 0 { return parent }
	if operation == 39 {
		id := persistent_volume.create(u32(parent), unsafe { &name.name[0] }, name.length, 0x4000 | (arg & 0xfff & ~process_umask))
		return if id < 0 { id } else { 0 }
	}
	id := persistent_volume.lookup(u32(parent), unsafe { &name.name[0] }, name.length)
	if id < 0 { return id }
	return persistent_volume.unlink(u32(parent), unsafe { &name.name[0] }, name.length, operation == 40, inode_open(u32(id)))
}

fn sys_rename(old_path u32, new_path u32) int {
	length := user_path(old_path)
	if length < 0 { return length }
	if !persistent_volume.mounted { return -30 }
	mut old_name := ext2.Entry{}
	old_parent := persistent_volume.parent(unsafe { &io_buffer[0] }, u32(length), mut old_name)
	if old_parent < 0 { return old_parent }
	new_length := user_path(new_path)
	if new_length < 0 { return new_length }
	mut new_name := ext2.Entry{}
	new_parent := persistent_volume.parent(unsafe { &io_buffer[0] }, u32(new_length), mut new_name)
	if new_parent < 0 { return new_parent }
	replaced := persistent_volume.lookup(u32(new_parent), unsafe { &new_name.name[0] }, new_name.length)
	return persistent_volume.rename(u32(old_parent), unsafe { &old_name.name[0] }, old_name.length,
		u32(new_parent), unsafe { &new_name.name[0] }, new_name.length, replaced > 0 && inode_open(u32(replaced)))
}

fn sys_symlink(target u32, path u32) int {
	length := user_path(target)
	if length < 0 { return length }
	if length > 60 { return -36 }
	mut saved := [60]u8{}
	runtime.copy(unsafe { &saved[0] }, unsafe { &io_buffer[0] }, u32(length))
	size := user_path(path)
	if size < 0 { return size }
	if !persistent_volume.mounted { return -30 }
	mut name := ext2.Entry{}
	parent := persistent_volume.parent(unsafe { &io_buffer[0] }, u32(size), mut name)
	if parent < 0 { return parent }
	return persistent_volume.symlink(u32(parent), unsafe { &name.name[0] }, name.length, unsafe { &saved[0] }, u32(length))
}

fn sys_readlink(path u32, address u32, size u32) int {
	length := user_path(path)
	if length < 0 { return length }
	if !persistent_volume.mounted { return -2 }
	id := persistent_volume.walk(unsafe { &io_buffer[0] }, u32(length), false)
	if id < 0 { return id }
	capacity := if size > 4096 { u32(4096) } else { size }
	result := persistent_volume.readlink(u32(id), unsafe { &io_buffer[0] }, capacity)
	if result < 0 { return result }
	return if copy_to_user(address, unsafe { &io_buffer[0] }, u32(result)) { result } else { -14 }
}
