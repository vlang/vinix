// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module verity

import errno
import event.eventstruct
import fs
import fs.ext2
import klock
import lib
import limine
import memory
import resource
import stat

#include <verity.h>

struct C.vinix_verity {
mut:
	data_blocks u64
	total_blocks u64
	level_start [8]u64
	levels u32
	root_hash [32]u8
}

fn C.vinix_verity_parse(cmdline &char, geometry &C.vinix_verity, device &char, capacity usize) int
fn C.vinix_verity_check(geometry &C.vinix_verity, block u64, data voidptr,
	reader voidptr, context voidptr, scratch voidptr) int

__global (
	boot_geometry C.vinix_verity
	boot_device [128]u8
	boot_selection int
	boot_parsed bool
)

// A requested profile either becomes the root or stops boot. It never selects
// an installer, a mutable disk root, or an initramfs fallback after an error.
pub fn requested() bool {
	if !boot_parsed {
		boot_parsed = true
		kernel := limine.kernel_file()
		if kernel != unsafe { nil } {
			boot_selection = C.vinix_verity_parse(kernel.cmdline, &boot_geometry,
				unsafe { &char(&boot_device[0]) }, sizeof(boot_device))
		}
	}
	if boot_selection < 0 {
		lib.kpanic(unsafe { nil }, c'verity: invalid, duplicate or conflicting root policy')
	}
	return boot_selection == 1
}

struct VerifiedDevice {
pub mut:
	stat stat.Stat
	refcount int = 1
	l klock.Lock
	event eventstruct.Event
	status int
	can_mmap bool
	backing &resource.Resource = unsafe { nil }
	geometry C.vinix_verity
	data_physical voidptr
	hash_physical voidptr
	data voidptr
	hashes voidptr
	box &resource.Resource = unsafe { nil }
}

// This callback only borrows the wrapper and its scratch while read() holds
// the wrapper lock. The backing read finishes its DMA before returning.
fn read_hash_block(context voidptr, block u64, output voidptr) i32 {
	mut device := unsafe { &VerifiedDevice(context) }
	read := device.backing.read(unsafe { nil }, output, block * 4096, 4096) or { return -1 }
	return if read == 4096 { 0 } else { -1 }
}

fn (mut device VerifiedDevice) read(_handle voidptr, output voidptr, offset u64, count u64) ?i64 {
	device.l.acquire()
	defer { device.l.release() }
	size := device.geometry.data_blocks * 4096
	if offset >= size || count == 0 { return 0 }
	actual := if count < size - offset { count } else { size - offset }
	mut done := u64(0)
	for done < actual {
		position := offset + done
		block := position / 4096
		read := device.backing.read(unsafe { nil }, device.data, block * 4096, 4096) or {
			errno.set(errno.eio)
			return none
		}
		if read != 4096 || C.vinix_verity_check(&device.geometry, block, device.data,
			voidptr(read_hash_block), voidptr(device), device.hashes) != 0 {
			errno.set(errno.eio)
			return none
		}
		in_block := position % 4096
		part := if actual - done < 4096 - in_block { actual - done } else { 4096 - in_block }
		// Only the verified, still-owned data buffer reaches the caller. Reading
		// the backing device again here would introduce a tampering race.
		unsafe { C.memcpy(voidptr(u64(output) + done), voidptr(u64(device.data) + in_block), part) }
		done += part
	}
	return i64(done)
}

fn (mut device VerifiedDevice) write(_handle voidptr, _buffer voidptr, _offset u64, _count u64) ?i64 {
	errno.set(errno.erofs)
	return none
}

fn (mut device VerifiedDevice) grow(_handle voidptr, _size u64) ? {
	errno.set(errno.erofs)
	return none
}

fn (mut device VerifiedDevice) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut device VerifiedDevice) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	errno.set(errno.enodev)
	return unsafe { nil }
}

fn (device &VerifiedDevice) read_only_backend() bool { return true }

// /dev and the ext2 filesystem pin this single boot-created device until
// shutdown. Descriptor closes cannot release its geometry or DMA scratch.
fn (mut device VerifiedDevice) unref(_handle voidptr) ? {}
fn (mut device VerifiedDevice) link(_handle voidptr) ? {}
fn (mut device VerifiedDevice) unlink(_handle voidptr) ? {}

pub fn mount_root() {
	if !requested() { return }
	path := unsafe { cstring_to_vstring(&boot_device[0]) }
	backing := fs.get_node(vfs_root, path, true) or {
		lib.kpanic(unsafe { nil }, c'verity: requested block device is missing')
		return
	}
	if backing.resource == unsafe { nil } || !stat.isblk(backing.resource.stat.mode)
		|| backing.resource.stat.size < i64(boot_geometry.total_blocks * 4096)
		|| backing.resource.stat.blksize <= 0 || backing.resource.stat.blksize > 4096
		|| 4096 % backing.resource.stat.blksize != 0 {
		lib.kpanic(unsafe { nil }, c'verity: incompatible or truncated backing device')
		return
	}
	data_physical := memory.pmm_alloc_fallible(1)
	if data_physical == unsafe { nil } {
		lib.kpanic(unsafe { nil }, c'verity: no data scratch page')
		return
	}
	hash_physical := memory.pmm_alloc_fallible(1)
	if hash_physical == unsafe { nil } {
		memory.pmm_free(data_physical, 1)
		lib.kpanic(unsafe { nil }, c'verity: no hash scratch page')
		return
	}
	mut device := &VerifiedDevice{
		backing: backing.resource
		geometry: boot_geometry
		data_physical: data_physical
		hash_physical: hash_physical
		data: voidptr(u64(data_physical) + higher_half)
		hashes: voidptr(u64(hash_physical) + higher_half)
	}
	device.stat.mode = stat.ifblk | 0o400
	device.stat.size = i64(boot_geometry.data_blocks * 4096)
	device.stat.blksize = backing.resource.stat.blksize
	device.stat.blocks = device.stat.size / device.stat.blksize
	device.stat.rdev = resource.create_dev_id()
	device.box = &resource.Resource(device)
	fs.devtmpfs_add_device(device.box, 'verity-root')
	node := fs.get_node(vfs_root, '/dev/verity-root', true) or {
		lib.kpanic(unsafe { nil }, c'verity: could not publish verified device')
		return
	}
	mut filesystem, ok := ext2.ext2_init(node)
	if !ok {
		lib.kpanic(unsafe { nil }, c'verity: root integrity or filesystem check failed')
		return
	}
	mut root := ext2.ext2_root(mut filesystem) or {
		lib.kpanic(unsafe { nil }, c'verity: verified root could not be read')
		return
	}
	if !fs.install_verified_root(mut root) {
		lib.kpanic(unsafe { nil }, c'verity: verified root is not a bootable system')
		return
	}
	// Reuse the already-boxed authenticated filesystem for explicit aliases.
	// Its immutable mount backend refuses any different source device.
	fs.add_filesystem(root.filesystem, 'ext2')
	C.kprintf(c'verity: mounted read-only authenticated-block view (%llu blocks)\n', boot_geometry.data_blocks)
}
