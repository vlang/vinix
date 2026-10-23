// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn checked(args []string) ! {
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
	p.run(); p.wait()
	code := p.code
	p.close()
	if code != 0 { return error('command failed (${code}): ${args}') }
}

fn main() {
	root := if os.args.len > 1 { os.abs_path(os.args[1]) } else { os.getwd() }
	scratch := os.getenv_opt('NFS_SCRATCH') or { os.temp_dir() }
	work := os.join_path(scratch, 'vinix-nfs-protocol-${os.getpid()}')
	os.mkdir_all(work + '/nfs')!
	defer { if '--keep' in os.args { println('Fixture artifacts: ' + work) } else { os.rmdir_all(work) or {} } }
	os.write_file(work + '/v.mod', "Module { name: 'nfs_protocol' }")!
	for name in ['xdr.v', 'rpc.v', 'operations.v', 'options.v'] {
		os.cp(root + '/kernel/fs/nfs/' + name, work + '/nfs/' + name)!
	}
	os.cp(root + '/tests/nfs/protocol/cases.vfixture', work + '/main.v')!
	v := os.getenv_opt('V') or { @VEXE }
	os.setenv('VEXE', v, true)
	flags := ['-nocache', '-cc', 'clang', '-gc', 'none', '-manualfree']
	mut args := [v]
	args << flags
	args << ['-o', work + '/protocol', work]
	checked(args)!
	checked([work + '/protocol'])!
	args = [v]
	args << flags
	args << ['-os', 'linux', '-o', work + '/protocol-linux.c', work]
	checked(args)!
	println('NFS production wire/XDR: host fixtures and Linux C generation passed')
	facade_check(root, work + '/contract', v)!
	if '--kernel' in os.args {
		assemble_kernel(root, work + '/kernel')!
		checked([v, '-os', 'linux', '-arch', 'amd64', '-enable-globals', '-gc', 'none', '-manualfree', '-no-closures', '-o', work + '/kernel.c', work + '/kernel'])!
		println('Production kernel including NFS: Linux C generation passed')
	}
}
