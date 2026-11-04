// SPDX-License-Identifier: GPL-2.0-or-later
// AArch64 musl compile adapter for the retained compatibility SDK.
module main

import json2
import os

fn main() {
	sdk := os.getenv('VINIX_AARCH64_SYSROOT')
	uapi := os.getenv('VINIX_UAPI_HEADERS')
	state := os.getenv('VINIX_COMPAT_STATE')
	if sdk == '' || uapi == '' || state == '' || '--target=aarch64-linux-musl' !in os.args { panic('SDK, UAPI, state and AArch64 target required') }
	mut args := ['-idirafter', uapi, '--gcc-install-dir=' + sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0']
	for arg in os.args[1..] {
		if '-c' !in os.args && arg == '-pthread' { continue }
		args << arg
	}
	index := os.args.index('-o')
	if index <= 0 || index + 1 >= os.args.len { panic('Output required') }
	destination := os.args[index + 1]
	if !destination.starts_with(state + '/') { panic('Output outside fresh state') }
	compiler := os.find_abs_path_of_executable('clang')!
	mut p := os.new_process(compiler); p.set_args(args); p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	os.write_file(destination + '.compiler.json', json2.encode({'compiler': compiler, 'arguments': args.join('\n'), 'status': code.str(), 'output': out}, prettify: true) + '\n')!
	print(out); exit(code)
}
