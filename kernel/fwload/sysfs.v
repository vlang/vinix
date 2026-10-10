// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The firmware loader in /sys/firmware/loader:
//
//	loaded     one line per image held: name, bytes, checksum, holders, and
//	           "preloaded" for one kept by preload
//	stats      requests, shared, not_found, refused, bytes
//	preload    write a name to read the image now and keep it
//	drop       write a name to stop keeping it
module fwload

import errno
import fs
import lib

// Called once /sys is mounted.
pub fn publish() {
	fs.sysfs_attribute('firmware/loader/loaded', 0o444, show_loaded, unsafe { nil }, unsafe { nil })
	fs.sysfs_attribute('firmware/loader/stats', 0o444, show_stats, unsafe { nil }, unsafe { nil })
	fs.sysfs_attribute('firmware/loader/preload', 0o200, unsafe { nil }, store_preload, unsafe { nil })
	fs.sysfs_attribute('firmware/loader/drop', 0o200, unsafe { nil }, store_drop, unsafe { nil })
}

fn show_loaded(_ voidptr, mut text lib.Text) {
	enter()
	defer {
		leave()
	}
	for i in 0 .. max_images {
		image := fwload_images[i]
		if image == unsafe { nil } {
			continue
		}
		text.add(image.name)
		text.add_byte(` `)
		text.add_unsigned(image.size)
		text.add(' 0x')
		text.add_radix(u64(image.checksum), 16, 8)
		text.add_byte(` `)
		text.add_decimal(i64(image.holders))
		if image.preloaded {
			text.add(' preloaded')
		}
		text.add_byte(`\n`)
	}
}

fn show_stats(_ voidptr, mut text lib.Text) {
	text.add('requests: ')
	text.add_unsigned(fwload_stats.requests)
	text.add('\nshared: ')
	text.add_unsigned(fwload_stats.shared)
	text.add('\nnot_found: ')
	text.add_unsigned(fwload_stats.not_found)
	text.add('\nrefused: ')
	text.add_unsigned(fwload_stats.refused)
	text.add('\nbytes: ')
	text.add_unsigned(fwload_stats.bytes)
	text.add_byte(`\n`)
}

fn store_preload(_ voidptr, data &u8, length u64) u64 {
	name := fs.sysfs_word(data, length)
	if preload(name) {
		return 0
	}
	code := errno.get()
	return if code == 0 { u64(errno.eio) } else { u64(code) }
}

fn store_drop(_ voidptr, data &u8, length u64) u64 {
	name := fs.sysfs_word(data, length)
	return if drop(name) { u64(0) } else { u64(errno.enoent) }
}
