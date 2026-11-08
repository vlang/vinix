// SPDX-License-Identifier: GPL-2.0-or-later
// The small GN host queries and file operations needed by CPU Skia.
module main

import os
import runtime

fn main() {
	if os.args.len < 2 { exit(2) }
	name := os.file_name(os.args[1])
	match name {
		'is_clang.py' { println('true') }
		'is_xcode.py' { println('false') }
		'num_cpus.py' { println(runtime.nr_cpus()) }
		'checkdir.py' { println(if os.is_dir(os.args[2]) { 'True' } else { 'False' }) }
		'rm.py' {
			for path in os.args[2..] {
				if os.is_dir(path) {
					os.rmdir_all(path) or { panic(err) }
				} else if os.exists(path) {
					os.rm(path) or { panic(err) }
				}
			}
		}
		'cp.py' { os.cp(os.args[2], os.args[3]) or { panic(err) } }
		else {
			eprintln('Unsupported GN operation: ${os.args[1..]}')
			exit(1)
		}
	}
}
