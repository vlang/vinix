// SPDX-License-Identifier: MIT
module main

import os
import tools.packages.appsdk

fn main() {
	mut context := appsdk.load() or { eprintln(err); exit(1) }
	defer { context.close() }
	println('Hello from a signed Vinix application package.')
	println('Application: ' + context.id + ' ' + context.version)
	println('Private application data: ' + context.data_directory)
	for path in os.args[1..] {
		text := os.read_file(path) or {
			eprintln('Cannot read supplied document: ${err}')
			exit(1)
		}
		println(text)
		unsafe { text.free() }
	}
}
