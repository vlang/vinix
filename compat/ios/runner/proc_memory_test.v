// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_proc_memory_hierarchy_discovery() {
	mut output := [4096]u8{}
	for invalid in ['', '1:memory:/child\n', '1:cpu:/other\n0::/child\n', '0::/child\n1:memory:/other\n', '0::/a\ninjected\n', '0::relative\n', '0::/../child\n', '0::/a//b\n', '0::/a/.\n', '0::/a/\n', '0::/a\x00b\n'] {
		assert proc_memory_group(invalid.str, invalid.len, unsafe { &output[0] }, output.len) == -1
	}
	for valid in ['/', '/parent space/child\\name'] {
		text := '0::${valid}\n'
		assert proc_memory_group(text.str, text.len, unsafe { &output[0] }, output.len) == valid.len
		assert unsafe { cstring_to_vstring(&char(&output[0])) } == valid
	}
	view := '1 0 0:1 / /proc rw - proc proc rw\n2 0 0:2 /hidden /subtree rw - cgroup2 none rw\n3 0 0:2 / /cg\\040space\\134name rw shared:7 - cgroup2 none rw\n'
	assert proc_memory_mount(view.str, view.len, unsafe { &output[0] }, output.len) == 14
	assert unsafe { cstring_to_vstring(&char(&output[0])) } == '/cg space\\name'
	for invalid in ['1 0 0:2 /hidden /subtree rw - cgroup2 none rw\n', '1 0 0:2 / /bad\\000name rw - cgroup2 none rw\n', '1 0 0:2 / /../bad rw - cgroup2 none rw\n', '1 0 0:2 / /cg rw - tmpfs none rw\n'] {
		assert proc_memory_mount(invalid.str, invalid.len, unsafe { &output[0] }, output.len) == -1
	}
	assert proc_memory_mount(view.str, view.len, unsafe { &output[0] }, 8) == -1
	for invalid in ['', '\n', '-1\n', ' 1\n', '1x\n', '1\n2\n', '18446744073709551616\n'] {
		if _ := proc_memory_amount(invalid.str, invalid.len) { assert false }
	}
	for valid in ['0', '123456\n', '18446744073709551614\n'] {
		assert (proc_memory_amount(valid.str, valid.len) or { panic('invalid amount') }) == valid.u64()
	}
	assert (proc_memory_amount(c'max\n', 4) or { panic('invalid max') }) == ~u64(0)
}

fn test_proc_memory_macho() {
	path := os.getenv('VINIX_IOS_PROC_MEMORY_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.live == 0
	}
}
