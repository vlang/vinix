// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.packages.appsdk

#include <unistd.h>
fn C.geteuid() i32
fn C.getegid() i32
fn C.getgroups(int, voidptr) int

fn check() ! {
	mut context := appsdk.load()!
	defer { context.close() }
	assert C.geteuid() > 0 && C.getegid() > 0 && C.getgroups(0, unsafe { nil }) == 0
	assert context.id == 'launch-data-app' && context.data_directory == os.home_dir()
	assert os.getenv('TMPDIR') == context.data_directory + '/tmp'
	path := context.data_directory + '/kept'
	if os.exists(path) { assert os.read_file(path)! == 'retained application data' }
	else { os.write_file(path, 'retained application data')! }
	os.write_file(os.getenv('TMPDIR') + '/temporary', 'private temporary data')!
	println('PACKAGE LAUNCH DATA PROBE uid=${C.geteuid()} sdk=1 private-data-and-tmp')
}

fn main() { check() or { eprintln(err); exit(1) } }
