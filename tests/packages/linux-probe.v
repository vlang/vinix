// SPDX-License-Identifier: GPL-2.0-or-later
// This executable has a real PT_INTERP and an external shared-library import.
module main

import os

fn C.getuid() u32
fn C.geteuid() u32
fn C.getgroups(int, &u32) int

@[c_extern]
fn C.vinix_package_value() int

fn main() {
	assert C.getuid() == 1000 && C.geteuid() == 1000
	assert C.getgroups(0, unsafe { nil }) == 0
	assert C.vinix_package_value() == 23
	assert os.args[1..] == ['a space; $literal', '@unchanged']
	data := os.getenv('HOME')
	assert data == '/home/alex/.local/share/vinix-apps/linux-probe'
	assert !os.exists('/usr/bin/vinix-package')
	assert !os.exists('/home/alex/outside.txt')
	assert !os.exists('/lib/libc.so')
	os.write_file(data + '/result', 'packaged shared library: 23\n') or { panic(err) }
	println('PACKAGE LINUX uid=1000 groups=0 dynamic-library=23 literal-arguments private-data sandbox')
}
