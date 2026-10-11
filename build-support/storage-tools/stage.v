// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn C.execvp(&char, &&char) i32

// Keep the existing V entry point on the same qualified staging implementation.
fn main() {
	root := os.dir(os.dir(os.dir(@FILE)))
	arguments := ['sh', root + '/build-support/run-v-tool.sh',
		root + '/build-support/native-compat-tools/main.v', 'volume-stage', ...os.args[1..]]
	mut native := []&char{}
	for argument in arguments { native << &char(argument.str) }
	native << &char(unsafe { nil })
	unsafe { C.execvp(c'sh', native.data) }
	eprintln('Cannot launch the native volume staging controller')
	exit(1)
}
