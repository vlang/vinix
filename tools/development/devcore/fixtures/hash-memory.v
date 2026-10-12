// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.development.devcore

#include <sys/resource.h>
struct C.rusage {
	ru_maxrss i64
}
fn C.getrusage(int, &C.rusage) int

fn peak_bytes() i64 {
	mut usage := C.rusage{}
	if C.getrusage(0, unsafe { &usage }) != 0 { panic('getrusage failed') }
	$if macos { return usage.ru_maxrss }
	return usage.ru_maxrss * 1024
}

fn main() {
	if os.args.len != 2 { exit(2) }
	for _ in 0 .. 10 { devcore.file_hash(os.args[1])! }
	start := peak_bytes()
	for _ in 0 .. 1000 { devcore.file_hash(os.args[1])! }
	growth := peak_bytes() - start
	println('HASH-MEMORY: growth=${growth} iterations=1000')
	if start <= 0 || growth > 16 * 1024 * 1024 { exit(1) }
}
