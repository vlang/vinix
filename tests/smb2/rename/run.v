// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the production cache update on an ARM64-sized kernel stack.
module main

import os

fn checked(args []string) ! {
	mut child := os.new_process(args[0])
	child.set_args(args[1..])
	child.run()
	child.wait()
	code := child.code
	child.close()
	if code != 0 { return error('command failed with status ${code}: ${args[0]}') }
}

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..', '..'))
	scratch := os.getenv_opt('TMPDIR') or { os.temp_dir() }
	work := os.join_path(scratch, 'vinix-smb2-rename-${os.getpid()}')
	os.mkdir_all(work + '/fs/smb2')!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/v.mod', "Module { name: 'smb2_rename_stack_checks' }")!
	os.cp(root + '/kernel/fs/smb2/wire.v', work + '/fs/smb2/wire.v')!
	os.cp(root + '/tests/smb2/rename/rename.fixture', work + '/main.v')!
	source := os.read_file(root + '/kernel/fs/smb2.v')!
	start := source.index('fn (mut b SMB2FS) rebase_cached_paths(') or {
		panic('missing production cached-path update')
	}
	rest := source[start..]
	end := rest.index('\n}\n') or { panic('unterminated production cached-path update') }
	os.write_file(work + '/paths.v', 'module main\nimport fs.smb2\n' + rest[..end + 3])!
	compiler := os.getenv_opt('V') or { @VEXE }
	cc := os.getenv_opt('CC') or { 'clang' }
	os.setenv('VEXE', compiler, true)
	checked([compiler, '-nocache', '-cc', cc, '-gc', 'none', '-manualfree', '-o', work + '/rename', work])!
	checked([work + '/rename'])!
}
