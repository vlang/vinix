// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))
	work := os.join_path(os.temp_dir(), 'vinix-initramfs-writes-${os.getpid()}')
	os.mkdir_all(work + '/resource') or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/v.mod', "Module { name: 'initramfs_write_fixture' }\n") or { panic(err) }
	for pair in [
		['kernel/initramfs/file_writer.v', 'file_writer.v'],
		['tests/initramfs-writes/fixture/file_writer_test.v', 'file_writer_test.v'],
		['tests/initramfs-writes/fixture/resource/core.v', 'resource/core.v'],
	] {
		os.cp(root + '/' + pair[0], work + '/' + pair[1]) or { panic(err) }
	}
	mut compiler := os.getenv('V')
	if compiler == '' { compiler = @VEXE }
	mut process := os.new_process(compiler)
	process.set_args(['-cc', 'cc', 'test', work])
	process.run()
	process.wait()
	code := process.code
	process.close()
	if code != 0 { exit(code) }
}
