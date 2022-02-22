// main.v: Main file of lscpu.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module main

import os
import cpu

fn main() {
	mut idx := 1
	for idx < os.args.len {
		match os.args[idx] {
			'--help' {
				println('Usage: ${os.args[0]}')
				println('')
				println('List CPU architecture information')
				println('')
				println('Options:')
				println('--help    display this help')
				println('--version display version information')
				exit(0)
			}
			'--version' {
				println('lscpu from util-vinix')
				exit(0)
			}
			else {
				println("Unexpected argument '${os.args[idx]}'")
				exit(1)
			}
		}
		idx++
	}

	info := cpu.get_cpu_info() or {
		println('Could not fetch CPU information')
		exit(1)
	}
	info.print()
}
