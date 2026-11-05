// SPDX-License-Identifier: GPL-2.0-or-later
// Compile-only preparation; no root image, boot medium or guest is created.
module main

import os
import perfproducer

fn run() ! {
	if os.args.len != 5 { return error('usage: heap-producer-source COMPILER ROOT FRESH_STATE aarch64|x86_64') }
	state := os.abs_path(os.args[3])
	if os.exists(state) || os.is_link(state) { return error('producer state must be fresh') }
	if os.args[4] !in ['aarch64', 'x86_64'] { return error('unsupported producer architecture') }
	os.mkdir(state, mode: 0o700)!
	println(perfproducer.generate(os.args[1], os.args[2], state, os.args[4])!)
}

fn main() { run() or { eprintln(err); exit(1) } }
