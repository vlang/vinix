// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

// Run the kernel's gzip decoder (kernel/initramfs/gzip.v) on the host against
// the system gzip's output. VINIX_GZIP_SAMPLE names an extra file to inflate,
// such as a release image, and reports the speed.
fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))
	work := os.join_path(os.temp_dir(), 'vinix-initramfs-gzip-${os.getpid()}')
	os.mkdir_all(work) or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/v.mod', "Module { name: 'initramfs' }\n") or { panic(err) }
	for pair in [
		['kernel/initramfs/gzip.v', 'gzip.v'],
		['tests/initramfs-gzip/fixture/gzip_test.v', 'gzip_test.v'],
	] {
		os.cp(root + '/' + pair[0], work + '/' + pair[1]) or { panic(err) }
	}
	mut compiler := os.getenv('V')
	if compiler == '' { compiler = @VEXE }
	mut process := os.new_process(compiler)
	process.set_args(['-cc', 'cc', '-prod', 'test', work])
	process.set_environment(os.environ())
	process.run()
	process.wait()
	code := process.code
	process.close()
	if code != 0 { exit(code) }
}
