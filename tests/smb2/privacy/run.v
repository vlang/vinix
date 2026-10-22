// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..', '..'))
	work := os.join_path(os.getenv_opt('TMPDIR') or { os.temp_dir() }, 'm17a-privacy-${os.getpid()}')
	os.mkdir_all(work + '/fs')!
	os.mkdir_all(work + '/krandom')!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/v.mod', "Module { name: 'mount_privacy_checks' }")!
	os.cp(root + '/kernel/fs/mount_private.v', work + '/fs/mount_private.v')!
	os.cp(root + '/tests/smb2/privacy/privacy_test.fixture', work + '/fs/privacy_test.v')!
	os.cp(root + '/tests/smb2/protocol/sha256.fixture', work + '/krandom/sha256.v')!
	mut child := os.new_process(os.getenv_opt('V') or { @VEXE })
	child.set_args(['-nocache', '-cc', 'clang', 'test', work + '/fs'])
	child.run()
	child.wait()
	result := child.code
	child.close()
	if result != 0 { exit(result) }
	println('M17A:mount option privacy production helper PASS')
}
