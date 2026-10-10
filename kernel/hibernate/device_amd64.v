// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The device an image is kept on.
//
// It is named on the kernel command line -- vinix.hibernate=sd1, or with
// /dev/ in front -- by the name it has in /dev: a whole disk or a partition.
// The kernel does not choose one. Whatever is named is found once, at boot,
// after the disk drivers have brought their disks up and before anything on a
// disk is mounted, and reached from then on through its node's resource: the
// same read and write a program's open of /dev/sd1 ends in, with no
// filesystem and no cache between. Every transfer is a call that returns when
// the driver has finished it, and the driver's own waits have ends.
//
// A device that is named is not thereby written to. The first image, and
// only the first, needs the device to be one of two things: blank at both
// ends, as a disk nobody has used is, or already carrying a header of this
// system's. A device with anything else on it -- somebody's filesystem,
// named by mistake -- is left exactly as it is, and hibernation is not
// offered.
//
// Its node is made readable and writable by root alone, and so is the disk a
// named partition is on: an image is a copy of memory, with every secret in
// it.
module hibernate

import block.fence
import devcore
import fs
import memory
import resource
import stat

// The least a device may be: room for the two megabytes looked at to see
// whether it is blank.
const least_device_bytes = u64(4) << 20
const blank_span = u64(1) << 20

__global (
	hib_option_read bool
	// As named, without /dev/; '' when no device was named.
	hib_device_name string
	hib_device      &fs.VFSNode
	// A whole number of blocks.
	hib_device_bytes u64
	// Why no image can be kept; '' when one can.
	hib_device_problem string
	// Whether the device has been seen to be this system's: carrying a
	// header, or blank.
	hib_device_ours bool
)

// The name on the command line, or ''.
pub fn device_name() string {
	if !hib_option_read {
		mut name := devcore.boot_option('vinix.hibernate=') or { '' }
		if name.starts_with('/dev/') {
			name = unsafe { tos(name.str + 5, name.len - 5) }
		}
		hib_device_name = name
		hib_option_read = true
	}
	return hib_device_name
}

// Whether `name`, as a node of /dev has it, is the device named for images
// or the disk a named partition is on. For whoever might otherwise take a
// blank disk for one that is free.
pub fn is_image_device(name string) bool {
	named := device_name()
	if named.len == 0 || name.len == 0 {
		return false
	}
	if named == name {
		return true
	}
	// sd0-2 is on sd0.
	return named.len > name.len && named.starts_with(name) && named[name.len] == `-`
}

fn restrict(mut node fs.VFSNode) {
	if node.resource != unsafe { nil } {
		node.resource.stat.mode = stat.ifblk | 0o600
	}
}

// Find the named device. False, with the reason kept, when there is none to
// use. Called once the disks are up; a device that appears later is not
// looked for.
fn open_device() bool {
	if hib_device != unsafe { nil } {
		return true
	}
	name := device_name()
	if name.len == 0 {
		hib_device_problem = 'no device was named for the image (vinix.hibernate=)'
		return false
	}
	path := '/dev/' + name
	defer {
		unsafe { path.free() }
	}
	mut node := fs.get_node(vfs_root, path, true) or {
		hib_device_problem = 'the device named for the image is not there'
		return false
	}
	if node.resource == unsafe { nil } || !stat.isblk(node.resource.stat.mode) {
		hib_device_problem = 'what was named for the image is not a block device'
		return false
	}
	bytes := u64(node.resource.stat.size) / block_bytes * block_bytes
	if bytes < least_device_bytes {
		hib_device_problem = 'the device named for the image is too small for any'
		return false
	}
	restrict(mut node)
	// And the disk a partition is on, whose node shows the same bytes.
	dash := name.index_u8(`-`)
	if dash > 0 {
		parent_path := '/dev/' + unsafe { tos(name.str, dash) }
		if mut parent := fs.get_node(vfs_root, parent_path, true) {
			if parent.resource != unsafe { nil } && stat.isblk(parent.resource.stat.mode) {
				restrict(mut parent)
			}
		}
		unsafe { parent_path.free() }
	}
	hib_device = node
	hib_device_bytes = bytes
	hib_device_problem = ''
	return true
}

fn device_read(offset u64, buffer voidptr, bytes u64) bool {
	if hib_device == unsafe { nil } || offset > hib_device_bytes || bytes > hib_device_bytes - offset {
		return false
	}
	mut res := unsafe { hib_device.resource }
	got := res.read(unsafe { nil }, buffer, offset, bytes) or { return false }
	return u64(got) == bytes
}

// The one way anything of this module's reaches a disk for writing: to the
// named device, inside it, and past the fence that holds every other write
// while an image is being written.
fn device_write(offset u64, buffer voidptr, bytes u64) bool {
	if hib_device == unsafe { nil } || offset > hib_device_bytes || bytes > hib_device_bytes - offset {
		return false
	}
	mut res := unsafe { hib_device.resource }
	fence.pass(true)
	got := res.write(unsafe { nil }, buffer, offset, bytes) or {
		fence.pass(false)
		return false
	}
	fence.pass(false)
	return u64(got) == bytes
}

// Have the device put what it was given where it stays.
fn device_flush() bool {
	if hib_device == unsafe { nil } {
		return false
	}
	mut res := unsafe { hib_device.resource }
	resource.sync_resource(mut res, unsafe { nil }) or { return false }
	return true
}

// A block of the device read into a page of its own. 0 when it cannot be.
fn read_block(offset u64) u64 {
	page := u64(memory.pmm_alloc_fallible(1))
	if page == 0 {
		return 0
	}
	if !device_read(offset, voidptr(page + higher_half), block_bytes) {
		memory.pmm_free(voidptr(page), 1)
		return 0
	}
	return page
}

fn all_zero(words &u64, count u64) bool {
	for index in u64(0) .. count {
		if unsafe { words[index] } != 0 {
			return false
		}
	}
	return true
}

// Whether the device reads as zeroes over its first and last megabyte.
fn device_blank() bool {
	buffer := u64(memory.pmm_alloc_fallible(blank_span / page_size))
	if buffer == 0 {
		return false
	}
	defer {
		memory.pmm_free(voidptr(buffer), blank_span / page_size)
	}
	for offset in [u64(0), hib_device_bytes - blank_span]! {
		if !device_read(offset, voidptr(buffer + higher_half), blank_span) {
			return false
		}
		if !all_zero(page_of(buffer), blank_span / 8) {
			return false
		}
	}
	return true
}

// Read the device's first block and say what it is. The header is copied
// out when there is one.
fn read_header(mut header Header) (Verdict, string) {
	page := read_block(0)
	if page == 0 {
		// Not known to be this system's: nothing is written to a device
		// that cannot be read.
		return Verdict.foreign, 'its first block cannot be read'
	}
	unsafe { C.memcpy(voidptr(header), voidptr(page + higher_half), sizeof(Header)) }
	memory.pmm_free(voidptr(page), 1)
	return judge_header(header, hib_device_bytes)
}

// Write `header` as the device's first block, have the device keep it, and
// read it back. True when what comes back is what was written.
fn write_header(header &Header) bool {
	// The two pages kept for this while an image is being written, or two
	// taken for the moment at any other time.
	borrowed := hib_scratch != 0
	page := if borrowed { hib_scratch } else { u64(memory.pmm_alloc_fallible(2)) }
	if page == 0 {
		return false
	}
	defer {
		if !borrowed {
			memory.pmm_free(voidptr(page), 2)
		}
	}
	unsafe { C.memset(voidptr(page + higher_half), 0, 2 * page_size) }
	block := voidptr(page + higher_half)
	back := voidptr(page + page_size + higher_half)
	unsafe { C.memcpy(block, voidptr(header), sizeof(Header)) }
	if !device_write(0, block, block_bytes) || !device_flush() {
		return false
	}
	if !device_read(0, back, block_bytes) {
		return false
	}
	return unsafe { C.memcmp(block, back, block_bytes) } == 0
}

// Replace whatever header the device has with one that describes no image.
// After this returns true nothing on the device can be entered.
fn write_empty_header(sequence u64) bool {
	mut header := new_header(0, sequence)
	seal(mut header)
	return write_header(header)
}

// Whether the device may be written to at all: it carries a header of this
// system's, or nothing. Looked at afresh each time it is asked, which is at
// boot and before every image: a device that has been given to something
// else since is not written over, and one that has been cleared is taken.
fn device_is_ours() bool {
	hib_device_ours = false
	if hib_device == unsafe { nil } {
		return false
	}
	mut header := Header{}
	verdict, _ := read_header(mut header)
	if verdict == .foreign && !device_blank() {
		hib_device_problem = 'the device named for the image holds something else; it is left alone (clear its first and last megabyte to give it to hibernation)'
		return false
	}
	hib_device_problem = ''
	hib_device_ours = true
	return true
}
