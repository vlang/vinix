// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// firmware: the kernel's firmware loader reads the image a driver names, and
// nothing else.
//
// No driver in a test machine wants firmware, so the loader is driven through
// its files in /sys/firmware/loader: `preload` reads an image and keeps it as
// a driver's request would, `loaded` says what is held, with a checksum this
// program can work out for itself. Checked here: an image is read whole and
// unchanged; a copy under updates/ wins; a name that is not a plain path
// below the firmware directories is refused, as are an image that is not
// there, one that is too big and one that is not a file; and reading and
// dropping an image fifty times leaves the kernel's heap as it was.
module main

import os

const loader = '/sys/firmware/loader/'

// The loader's checksum: rotate left by one, exclusive-or the byte.
fn firmware_checksum(data []u8) u32 {
	mut sum := u32(0)
	for b in data {
		sum = (sum << 1 | sum >> 31) ^ u32(b)
	}
	return sum
}

// The line of `loaded` for `name`, or ''.
fn loaded_line(name string) string {
	text := read_text(loader + 'loaded') or { return '' }
	for line in text.split_into_lines() {
		if line.starts_with(name + ' ') {
			return line
		}
	}
	return ''
}

fn refused(mut t Test, name string, why string) {
	write_text(loader + 'preload', name) or { return }
	t.check(false, 'preload accepted "${name}" (${why})')
	write_text(loader + 'drop', name) or {}
}

fn scenario_firmware(mut t Test) {
	os.mkdir_all('/lib/firmware/vendor') or {
		t.check(false, 'mkdir: ${err}')
		return
	}
	image := pattern_bytes(0x37, 100 * 1024)
	os.write_file_array('/lib/firmware/vendor/blob.bin', image) or {
		t.check(false, 'writing the image: ${err}')
		return
	}
	write_text(loader + 'preload', 'vendor/blob.bin') or {
		t.check(false, 'preload: ${err}')
		return
	}
	expected := 'vendor/blob.bin ${image.len} 0x${firmware_checksum(image):08x} 1 preloaded'
	t.check(loaded_line('vendor/blob.bin') == expected, 'loaded says "${loaded_line('vendor/blob.bin')}", not "${expected}"')
	// Keeping what is already kept changes nothing.
	write_text(loader + 'preload', 'vendor/blob.bin') or { t.check(false, 'second preload: ${err}') }
	t.check(loaded_line('vendor/blob.bin') == expected, 'a second preload changed the line to "${loaded_line('vendor/blob.bin')}"')
	write_text(loader + 'drop', 'vendor/blob.bin') or { t.check(false, 'drop: ${err}') }
	t.check(loaded_line('vendor/blob.bin') == '', 'the image is still held after drop')
	if _ := write_text(loader + 'drop', 'vendor/blob.bin') {
		t.check(false, 'dropping an image that is not held succeeded')
	}

	// A copy under updates/ is the one that is read.
	newer := pattern_bytes(0x91, 4096)
	os.mkdir_all('/lib/firmware/updates/vendor') or { t.check(false, 'mkdir: ${err}') }
	os.write_file_array('/lib/firmware/updates/vendor/blob.bin', newer) or {
		t.check(false, 'writing the update: ${err}')
	}
	write_text(loader + 'preload', 'vendor/blob.bin') or { t.check(false, 'preload of the update: ${err}') }
	updated := 'vendor/blob.bin ${newer.len} 0x${firmware_checksum(newer):08x} 1 preloaded'
	t.check(loaded_line('vendor/blob.bin') == updated, 'with an update, loaded says "${loaded_line('vendor/blob.bin')}", not "${updated}"')
	write_text(loader + 'drop', 'vendor/blob.bin') or { t.check(false, 'drop: ${err}') }
	os.rm('/lib/firmware/updates/vendor/blob.bin') or {}

	// What is not a firmware name, or not firmware.
	os.write_file('/etc/secret', 'not firmware') or {}
	refused(mut t, '../etc/secret', 'leaves the directory')
	refused(mut t, 'vendor/../../etc/secret', 'leaves the directory')
	refused(mut t, '/etc/secret', 'absolute')
	refused(mut t, 'vendor//blob.bin', 'empty component')
	refused(mut t, 'vendor/', 'trailing slash')
	refused(mut t, 'vendor/blob.bin;x', 'odd character')
	refused(mut t, 'vendor/absent.bin', 'not there')
	os.symlink('/dev/zero', '/lib/firmware/zero') or {}
	refused(mut t, 'zero', 'a device, not a file')
	mut big := os.create('/lib/firmware/big.bin') or {
		t.check(false, 'creating big.bin: ${err}')
		return
	}
	big.close()
	os.truncate('/lib/firmware/big.bin', u64(64) * 1024 * 1024 + 1) or { t.check(false, 'truncate: ${err}') }
	refused(mut t, 'big.bin', 'over the size limit')
	stats := read_text(loader + 'stats') or { '' }
	t.check(stats.contains('bytes: 0'), 'images are still held: ${stats.replace('\n', ' ')}')

	// Reading and dropping must not cost the kernel anything it keeps.
	for _ in 0 .. 10 {
		write_text(loader + 'preload', 'vendor/blob.bin') or {}
		write_text(loader + 'drop', 'vendor/blob.bin') or {}
	}
	before := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	for _ in 0 .. 50 {
		write_text(loader + 'preload', 'vendor/blob.bin') or {
			t.check(false, 'preload in the loop: ${err}')
			return
		}
		write_text(loader + 'drop', 'vendor/blob.bin') or {
			t.check(false, 'drop in the loop: ${err}')
			return
		}
	}
	after := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	t.info('50 load/drop cycles of ${image.len} bytes: live heap objects ${before.objects} -> ${after.objects}, large pages ${before.large_pages} -> ${after.large_pages}')
	t.check(after.objects - before.objects <= heap_noise_objects, '50 load/drop cycles left ${after.objects - before.objects} more heap objects allocated')
	t.check(after.large_pages <= before.large_pages, '50 load/drop cycles left ${after.large_pages - before.large_pages} more large-allocation pages')
}
