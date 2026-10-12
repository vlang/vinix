// SPDX-License-Identifier: GPL-2.0-or-later
// Package this static runner inside the explicit Linux runtime.
module main

import os

#include <unistd.h>

fn C.execv(&char, &&char) int

fn run_linux() ! {
	if os.args.len < 3 {
		return error('usage: vinix-linux-runner ABSOLUTE_PACKAGED_LOADER ABSOLUTE_APPLICATION [ARGS...]')
	}
	loader := os.args[1]
	application := os.args[2]
	for path in [loader, application] {
		if !path.starts_with('/') || path.contains('\x00') || !os.is_file(path) || os.is_link(path)
			|| !os.is_executable(path) {
			return error('Linux launch needs ordinary executable packaged files: ${path}')
		}
	}
	// The service supplies this signed generation's library directories. Its
	// sandbox also hides host paths the musl loader might otherwise search.
	libraries := os.getenv('LD_LIBRARY_PATH')
	if libraries == '' || libraries.split(':').any(!it.starts_with('/') || it == '/') {
		return error('packaged Linux library path is unavailable')
	}
	mut args := [loader, '--library-path', libraries, application]
	args << os.args[3..]
	mut argv := []&char{cap: args.len + 1}
	for argument in args { argv << &char(argument.str) }
	argv << &char(unsafe { nil })
	C.execv(loader.str, &argv[0])
	return error('packaged Linux loader failed to execute: ${os.last_error().msg()}')
}

fn main() {
	run_linux() or {
		eprintln(err)
		exit(126)
	}
}
