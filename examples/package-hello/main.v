// SPDX-License-Identifier: MIT
module main

import os

fn main() {
	println('Hello from a signed Vinix application package.')
	println('Private application data: ' + os.getenv('HOME'))
	for path in os.args[1..] {
		text := os.read_file(path) or {
			eprintln('Cannot read supplied document: ${err}')
			exit(1)
		}
		println(text)
	}
}
