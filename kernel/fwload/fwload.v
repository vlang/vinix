// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Firmware for devices: the images a driver has to give its hardware before
// the hardware does anything, read from the filesystem by name.
//
// A wireless card, a GPU's display controller, a storage adapter's microcode:
// the driver knows the name of the image -- brcm/brcmfmac4378b1-pcie.bin --
// and nothing about where it is kept. request() looks for it where Linux
// keeps firmware, so that the linux-firmware tree can be dropped into a Vinix
// image as it is:
//
//	/lib/firmware/updates/<name>     a newer copy, put there by hand
//	/lib/firmware/<name>
//	/usr/lib/firmware/<name>
//
// The image is read whole into kernel memory and handed back with a count of
// who holds it. Asking again for a name that is still held gives the same
// memory, which matters more than the saving: a driver that keeps hold of its
// image can load it into its device again after a sleep or a reset without
// the disk the image came from, which may itself be asleep at that moment.
// For the same reason an image can be loaded ahead of its driver and kept
// (preload()); release() and drop() let go, and the memory goes with the
// last holder.
//
// A name is a path below the firmware directories and nothing else: no
// leading slash, no "..", and no bytes a shell or a log would trip over. An
// image larger than size_limit is refused: what a driver is handed here it
// will copy into a device, and nothing legitimate is that big.
@[has_globals]
module fwload

import acpisync
import errno
import fs
import memory
import resource

pub const size_limit = u64(64) << 20
pub const name_limit = 128
const max_images = 32

@[heap]
pub struct Image {
pub mut:
	// Owned: the name it was asked for by.
	name string
	data &u8 = unsafe { nil }
	size u64
	// A sum of the bytes, to tell one revision of an image from another in a
	// report. It protects nothing.
	checksum u32
	// Who holds it: drivers that asked, plus one if it was preloaded.
	holders   int
	preloaded bool
}

pub struct Stats {
pub mut:
	requests u64
	// Requests answered from memory.
	shared    u64
	not_found u64
	refused   u64
	// Bytes of images held now.
	bytes u64
}

__global (
	fwload_images [max_images]&Image
	fwload_stats  Stats
	// Serializes the table and the reading of images, which waits for a disk.
	fwload_gate voidptr
)

const directories = ['/lib/firmware/updates/', '/lib/firmware/', '/usr/lib/firmware/']!

fn enter() {
	if fwload_gate == unsafe { nil } {
		fwload_gate = acpisync.create(true)
	}
	// acquire(), not wait(), which gives up for a caller with a signal coming
	// and would let it in without the gate.
	acpisync.acquire(fwload_gate, 0xffff)
}

fn leave() {
	acpisync.signal(fwload_gate)
}

// Whether `name` is something this will look for at all: one or more
// components separated by single slashes, none of them empty or made only of
// dots, in letters, digits and the punctuation firmware names use.
pub fn valid_name(name string) bool {
	if name.len == 0 || name.len > name_limit {
		return false
	}
	mut start := 0
	for end := 0; end <= name.len; end++ {
		if end < name.len && name[end] != `/` {
			c := name[end]
			ordinary := (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`)
				|| c == `.` || c == `-` || c == `_` || c == `+` || c == `,`
			if !ordinary {
				return false
			}
			continue
		}
		// A component ends here. An empty one is a leading, trailing or
		// doubled slash; one made of dots is the way out of the directory.
		if end == start {
			return false
		}
		mut dots := true
		for i in start .. end {
			if name[i] != `.` {
				dots = false
				break
			}
		}
		if dots {
			return false
		}
		start = end + 1
	}
	return true
}

fn find_held(name string) &Image {
	for i in 0 .. max_images {
		if fwload_images[i] != unsafe { nil } && fwload_images[i].name == name {
			return fwload_images[i]
		}
	}
	return unsafe { nil }
}

// Read the image called `name` from the first directory that has it. The
// errno says why not: ENOENT, EFBIG, ENOMEM, EIO.
fn read_image(name string) ?&Image {
	mut path := [name_limit + 32]u8{}
	for directory in directories {
		mut length := 0
		for i in 0 .. directory.len {
			path[length] = directory[i]
			length++
		}
		for i in 0 .. name.len {
			path[length] = name[i]
			length++
		}
		path[length] = 0
		node := fs.get_node(vfs_root, unsafe { tos(&path[0], length) }, true) or { continue }
		if node.resource == unsafe { nil } {
			continue
		}
		mut res := node.resource
		// Regular files only: a firmware name must not read a device.
		if res.stat.mode & 0o170000 != 0o100000 {
			continue
		}
		size := u64(res.stat.size)
		if size == 0 || size > size_limit {
			errno.set(errno.efbig)
			return none
		}
		data := unsafe { &u8(memory.malloc_packed_fallible(size)) }
		if data == unsafe { nil } {
			errno.set(errno.enomem)
			return none
		}
		resource.retain_resource(mut res)
		mut done := u64(0)
		mut failed := false
		for done < size {
			count := res.read(unsafe { nil }, unsafe { voidptr(data + done) }, done, size - done) or {
				failed = true
				break
			}
			if count <= 0 {
				failed = true
				break
			}
			done += u64(count)
		}
		resource.release_resource(mut res)
		if failed {
			memory.free(voidptr(data))
			errno.set(errno.eio)
			return none
		}
		mut sum := u32(0)
		for i in u64(0) .. size {
			sum = (sum << 1 | sum >> 31) ^ u32(unsafe { data[i] })
		}
		// Freed by let_go(), with its name and its data.
		mut image := &Image{} @[freed]
		image.name = name.clone()
		image.data = data
		image.size = size
		image.checksum = sum
		return image
	}
	errno.set(errno.enoent)
	return none
}

fn hold(name string, preload bool) ?&Image {
	if !valid_name(name) {
		fwload_stats.refused++
		errno.set(errno.einval)
		return none
	}
	enter()
	defer {
		leave()
	}
	fwload_stats.requests++
	mut image := find_held(name)
	if image != unsafe { nil } {
		if preload {
			if image.preloaded {
				return image
			}
			image.preloaded = true
		}
		image.holders++
		fwload_stats.shared++
		return image
	}
	mut slot := -1
	for i in 0 .. max_images {
		if fwload_images[i] == unsafe { nil } {
			slot = i
			break
		}
	}
	if slot < 0 {
		fwload_stats.refused++
		errno.set(errno.enfile)
		return none
	}
	image = read_image(name) or {
		if errno.get() == errno.enoent {
			fwload_stats.not_found++
		} else {
			fwload_stats.refused++
		}
		return none
	}
	image.holders = 1
	image.preloaded = preload
	fwload_images[slot] = image
	fwload_stats.bytes += image.size
	return image
}

// One holder fewer; the image goes with the last. The gate is held.
fn let_go(mut image Image) {
	image.holders--
	if image.holders > 0 {
		return
	}
	for i in 0 .. max_images {
		if voidptr(fwload_images[i]) == voidptr(image) {
			fwload_images[i] = unsafe { nil }
			break
		}
	}
	fwload_stats.bytes -= image.size
	memory.free(voidptr(image.data))
	unsafe {
		image.name.free()
		free(image)
	}
}

// The firmware image called `name`, read if nobody holds it yet. The caller
// holds it until it calls release(), and must not write to it. None, with
// errno saying why, when there is no such image or it may not be used.
pub fn request(name string) ?&Image {
	return hold(name, false)
}

// Let go of an image request() gave.
pub fn release(image &Image) {
	if image == unsafe { nil } {
		return
	}
	enter()
	mut held := unsafe { image }
	let_go(mut held)
	leave()
}

// Read `name` now and keep it until drop(): for an image whose driver will
// want it when the filesystem cannot be read -- on the way back from a sleep,
// or for a device that is plugged in later.
pub fn preload(name string) bool {
	hold(name, true) or { return false }
	return true
}

// Stop keeping a preloaded image. Drivers that hold it keep it.
pub fn drop(name string) bool {
	enter()
	defer {
		leave()
	}
	mut image := find_held(name)
	if image == unsafe { nil } || !image.preloaded {
		return false
	}
	image.preloaded = false
	let_go(mut image)
	return true
}

pub fn stats() Stats {
	return fwload_stats
}
