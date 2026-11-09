// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.rand
import crypto.sha256
import os

fn main() {
	if os.args.len != 2 { eprintln('Usage: v run tools/powerpc-disk NEW_DISK_IMAGE'); exit(2) }
	create(os.abs_path(os.args[1])) or { eprintln(err); exit(1) }
}

fn create(path string) ! {
	if os.exists(path) || os.is_link(path) { return error('Refusing to overwrite an existing disk') }
	tool := os.find_abs_path_of_executable(os.getenv_opt('VINIX_MKE2FS') or { '/opt/homebrew/opt/e2fsprogs/sbin/mke2fs' })!
	os.mkdir_all(os.dir(path))!
	seed := path + '.seed'
	if os.exists(seed) { return error('Seed staging directory already exists') }
	os.mkdir_all(seed)!
	defer { os.rmdir_all(seed) or {} }
	for dir in ['root', 'home', 'tmp', 'run'] { os.mkdir_all(seed + '/' + dir)! }
	os.chmod(seed + '/root', 0o700)!
	os.chmod(seed + '/tmp', 0o1777)!
	// Private host entropy seeds the guest DRBG; the guest rotates and flushes
	// this seed before exposing random bytes. It is never checked into Git.
	mut entropy := []u8{len: 32}
	rand.read(mut entropy)!
	os.write_file_array(seed + '/root/.vinix-rng-seed', entropy)!
	os.chmod(seed + '/root/.vinix-rng-seed', 0o600)!
	mut file := os.create(path)!
	file.seek(64 * 1024 * 1024 - 1, .start)!
	file.write([u8(0)])!
	file.close()
	os.chmod(path, 0o600)!
	args := ['-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-N', '2048', '-m', '0',
		'-O', 'none,filetype,sparse_super', '-E', 'lazy_itable_init=0', '-d', seed, path]
	mut child := os.new_process(tool)
	child.set_args(args); child.wait()
	code := child.code; child.close()
	if code != 0 { return error('mke2fs failed; incomplete disk remains at ' + path) }
	os.write_file(path + '.sha256', sha256.hexhash(os.read_bytes(path)!.bytestr()) + '  ' + os.file_name(path) + '\n')!
	println('Created persistent ext2 disk: ' + path)
}
