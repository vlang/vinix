// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module sysdisk

import fs
import fs.ext2
import initramfs
import limine
import memory
import pagecache
import stat

// A machine booted from an installer image (the release ISOs pass
// vinix.disk=auto) keeps its system on a disk, as a QEMU machine started by
// scripts/run-desktop-aarch64.sh does: the whole filesystem survives a restart. Given a
// disk, the first boot installs the image onto it and runs from there; later
// boots find it and skip unpacking the image into memory; a newer image is
// unpacked over the old system, leaving /root as it is. Without a disk it runs
// from memory as before.
//
// Only a disk that is entirely blank at both ends is ever formatted. A disk
// with anything recognisable on it -- a partition table, a filesystem, data --
// is left alone unless it is an ext2 volume this installed.
pub enum Outcome {
	in_memory // no disk used: the image is still to be unpacked into RAM
	booted // an installed, up-to-date system is the root
	installed // the image was just unpacked onto a blank disk
	updated // the image was just unpacked over an older installed one
}

// Smaller than this and the system, with room for the apps pkg installs, does
// not fit.
const min_disk_bytes = u64(4) << 30

// The image's id, on the disk. It reads `pending` while an install or an
// update is being written, so a boot interrupted halfway is finished by the
// next one rather than trusted.
const id_file = '/.vinix-image-id'
const id_name = '.vinix-image-id'
const pending_id = 'pending'

pub fn requested() bool {
	kernel_file := limine.kernel_file()
	if kernel_file == unsafe { nil } || kernel_file.cmdline == unsafe { nil } {
		return false
	}
	return unsafe { cstring_to_vstring(kernel_file.cmdline) }.contains('vinix.disk=auto')
}

pub fn mount_or_install() Outcome {
	image := initramfs.image_id()
	if image.len == 0 {
		println('sysdisk: this image has no id; running from memory')
		return .in_memory
	}
	disks := whole_disks()
	defer {
		unsafe { disks.free() }
	}
	if disks.len == 0 {
		println('sysdisk: no disk; running from memory, and nothing will be kept')
		return .in_memory
	}
	// A disk this installed on before.
	for disk in disks {
		mut filesystem, ok := ext2.ext2_init(disk)
		if !ok {
			continue
		}
		mut root := ext2.ext2_root(mut filesystem) or { continue }
		installed := read_id(root)
		if installed.len == 0 {
			// Some other ext2 volume: not ours to take.
			continue
		}
		if installed == image {
			if fs.install_disk_root(mut root) {
				report('sysdisk: running from the system on', disk, '')
				return .booted
			}
			continue
		}
		if !fs.install_empty_disk_root(mut root) {
			continue
		}
		report('sysdisk: updating the system on', disk, ' (keeping /root)')
		mark(pending_id)
		initramfs.install('root')
		commit(image)
		return .updated
	}
	// A blank disk to install on.
	for disk in disks {
		if u64(disk.resource.stat.size) < min_disk_bytes || !blank(disk) {
			continue
		}
		report('sysdisk: installing onto', disk, '')
		if !ext2.format(disk, 'vinix') {
			report('sysdisk: could not format', disk, '')
			continue
		}
		mut filesystem, ok := ext2.ext2_init(disk)
		if !ok {
			continue
		}
		mut root := ext2.ext2_root(mut filesystem) or { continue }
		if !fs.install_empty_disk_root(mut root) {
			continue
		}
		mark(pending_id)
		initramfs.install('')
		commit(image)
		println('sysdisk: installed; later boots start from the disk')
		return .installed
	}
	println('sysdisk: no blank disk of 4 GiB or more; running from memory')
	return .in_memory
}

// Block devices in /dev that are whole disks: sd0, ata0, nvme0n1, vda. A
// partition's name has a dash (sd0-1), and a partition is never the target.
fn whole_disks() []&fs.VFSNode {
	mut disks := []&fs.VFSNode{}
	dev := fs.get_node(vfs_root, '/dev', true) or { return disks }
	for name, node in dev.children {
		// Not `name == '.'`: V3 compiles a string comparison in this loop to
		// a C == on the structs. No device name starts with a dot anyway.
		if name.contains('-') || name.starts_with('.') || node.resource == unsafe { nil } {
			continue
		}
		if stat.isblk(node.resource.stat.mode) {
			disks << node
		}
	}
	return disks
}

// Whether a disk reads as all zeroes over its first and last MiB: a disk
// image freshly made by QEMU or VirtualBox. Anything written by a partitioner,
// a filesystem or an OS shows up at one end or the other.
fn blank(disk &fs.VFSNode) bool {
	size := u64(disk.resource.stat.size)
	span := u64(1024 * 1024)
	if size < 2 * span {
		return false
	}
	buffer := memory.calloc(span, 1)
	if buffer == unsafe { nil } {
		return false
	}
	defer { memory.free(buffer) }
	for offset in [u64(0), size - span]! {
		mut res := unsafe { disk.resource }
		got := res.read(unsafe { nil }, buffer, offset, span) or { return false }
		if u64(got) != span {
			return false
		}
		words := unsafe { &u64(buffer) }
		for i in 0 .. span / 8 {
			if unsafe { words[i] } != 0 {
				return false
			}
		}
	}
	return true
}

// The id of the image installed on a volume, or '' when it has none.
fn read_id(root &fs.VFSNode) string {
	node := fs.get_node(root, id_name, true) or { return '' }
	if node.resource == unsafe { nil } || !stat.isreg(node.resource.stat.mode) {
		return ''
	}
	size := u64(node.resource.stat.size)
	if size == 0 || size > 256 {
		return ''
	}
	mut text := [256]u8{}
	mut res := unsafe { node.resource }
	got := res.read(unsafe { nil }, &text[0], 0, size) or { return '' }
	mut length := int(got)
	for length > 0 && text[length - 1] <= ` ` {
		length--
	}
	return unsafe { tos(&text[0], length) }.clone()
}

// Record `id` as the image the root holds. It is padded with spaces over a
// longer earlier id rather than truncated; readers trim them.
fn write_id(id string) {
	mut node := fs.get_node(vfs_root, id_file, true) or {
		fs.create(vfs_root, id_file, stat.ifreg | 0o644) or {
			println('sysdisk: could not record the image id')
			return
		}
	}
	mut res := node.resource
	old_size := u64(res.stat.size)
	mut text := [256]u8{}
	length := if u64(id.len) > old_size { u64(id.len) } else { old_size }
	if length > 256 {
		return
	}
	for i in 0 .. length {
		text[i] = if i < u64(id.len) { id[i] } else { ` ` }
	}
	res.write(unsafe { nil }, &text[0], 0, length) or {
		println('sysdisk: could not record the image id')
	}
}

// Mark the system on the disk as `image`, once all of it is there: the image
// is written out before the id that vouches for it, so a machine switched off
// at any point either has the whole image or a `pending` one to redo.
fn commit(image string) {
	pagecache.sync_all()
	mark(image)
}

// Record `id` and see that it reaches the disk.
fn mark(id string) {
	write_id(id)
	pagecache.sync_all()
}

fn report(what string, disk &fs.VFSNode, tail string) {
	size_gib := u64(disk.resource.stat.size) >> 30
	print(what)
	print(' /dev/')
	print(disk.name)
	print(' (')
	print(size_gib.str())
	print(' GiB)')
	println(tail)
}
