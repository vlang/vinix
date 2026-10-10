// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hosttest
import os

fn run() ! {
	work := hosttest.work_dir('', 'vinix-ans-suite-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	mut env := os.environ()
	selected := hosttest.capture(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
		'find-v', hosttest.root()], '', 30, env)!
	if selected.code != 0 { return error(selected.stderr) }
	flags := [selected.stdout, '-nocache', '-cc', 'cc', '-arch',
		if os.uname().machine in ['arm64', 'aarch64'] { 'arm64' } else { 'amd64' }]
	tool := os.join_path(work, 'verify-reads')
	built := hosttest.capture([...flags, '-o', tool,
		os.join_path(hosttest.root(), 'tools/apple-ans/verify-reads.v')], '', 120, env)!
	if built.code != 0 { return error(built.stdout + built.stderr) }
	env['VINIX_ANS_READS_TOOL'] = tool
	tested := hosttest.capture([...flags, 'test',
		os.join_path(hosttest.root(), 'tools/apple-ans/ansreads')], '', 120, env)!
	print(tested.stdout)
	eprint(tested.stderr)
	if tested.code != 0 { return error('ANS read verifier tests failed') }
}

fn main() {
	if os.args[1..] in [['--help'], ['-h']] {
		println('Usage: tools/apple-ans/test-verify-reads\nBuild and test the native verifier with synthetic regular files only.')
		return
	}
	if os.args.len != 1 {
		eprintln('Usage: tools/apple-ans/test-verify-reads')
		exit(2)
	}
	run() or {
		eprintln(err.msg())
		exit(1)
	}
}
