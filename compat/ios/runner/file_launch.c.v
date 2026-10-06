// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn ui_file_url(path string) u64 {
	if path.len == 0 || path.contains('\x00') { panic('iOS: invalid file URL path') }
	mut absolute := path
	if path[0] != `/` {
		working := os.getwd()
		defer { unsafe { working.free() } }
		if working.len == 0 { panic('iOS: cannot resolve a relative file URL') }
		absolute = '${working}/${path}'
	}
	defer { if path[0] != `/` { unsafe { absolute.free() } } }
	url := objc_allocate(ios_runtime.names['NSURL'])
	store_field(url, 0, make_string(unsafe { &char(absolute.str) }))
	return url
}

fn ui_file_url_string(url u64) u64 {
	mut header := obj_header(url)
	if header.fields[1] == 0 {
		mut bytes := []u8{cap: 16 + string_text(header.fields[0]).len * 3}
		bytes.flags |= .noslices
		defer { unsafe { bytes.free() } }
		unsafe { bytes.push_many(c'file://', 7) }
		for value in string_text(header.fields[0]) {
			if (value >= `a` && value <= `z`) || (value >= `A` && value <= `Z`) ||
				(value >= `0` && value <= `9`) || value in [`/`, `-`, `.`, `_`, `~`] {
				bytes << value
			} else {
				bytes << u8(`%`)
				bytes << '0123456789ABCDEF'[value >> 4]
				bytes << '0123456789ABCDEF'[value & 15]
			}
		}
		bytes << u8(0)
		store_field(url, 1, make_string(unsafe { &char(bytes.data) }))
	}
	return header.fields[1]
}

fn ui_launch_options() !u64 {
	path := os.getenv('VINIX_IOS_OPEN_FILE')
	defer { unsafe { path.free() } }
	if path.len == 0 { return 0 }
	if path.contains('\x00') || !os.is_file(path) { return error('iOS: launch file does not exist: ${path}') }
	url := ui_file_url(path)
	defer { objc_release(url) }
	options := objc_allocate(ios_runtime.names['NSDictionary'])
	mut header := obj_header(options)
	header.keys << objc_retain(make_string(c'UIApplicationLaunchOptionsURLKey'))
	array_append(mut header, url)
	return options
}
