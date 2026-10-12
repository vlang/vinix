// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))
	work := os.join_path(os.temp_dir(), 'vinix-xhci-startup-${os.getpid()}')
	os.mkdir_all(work) or { panic(err) }
	defer {
		os.rmdir_all(work) or {}
	}
	for source in ['kernel/dev/xhci/startup.v', 'tests/xhci-startup/fixture/core_test.v'] {
		os.cp(os.join_path(root, source), os.join_path(work, os.file_name(source))) or {
			panic(err)
		}
	}
	mut compiler := os.getenv('V')
	if compiler == '' {
		compiler = @VEXE
	}
	mut process := os.new_process(compiler)
	process.set_args(['-enable-globals', '-cc', 'cc', 'test', work])
	process.set_redirect_stdio()
	process.run()
	process.wait()
	print(process.stdout_slurp())
	eprint(process.stderr_slurp())
	code := process.code
	process.close()
	if code != 0 {
		exit(code)
	}
}
