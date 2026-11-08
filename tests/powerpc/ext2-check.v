// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os

fn checked(args []string, log string) ! {
	mut p := os.new_process(args[0])
	p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
	output := p.stdout_slurp(); p.wait()
	code := p.code; p.close()
	os.write_file(log, args.join(' ') + '\n' + output)!
	print(output)
	if code != 0 { return error('Failed: ' + args.join(' ')) }
}

fn check(output string) ! {
	if os.exists(output) { return error('Use a fresh output directory') }
	os.mkdir_all(output)!
	root := os.getwd()
	v := os.find_abs_path_of_executable('v')!
	fsck := os.getenv_opt('VINIX_E2FSCK') or { '/opt/homebrew/opt/e2fsprogs/sbin/e2fsck' }
	os.write_file(output + '/revision.txt', os.execute('git rev-parse HEAD').output)!
	for dir in ['kernel/powerpc/ext2', 'tests/powerpc/ext2host', 'tools/powerpc-disk'] {
		os.mkdir_all(output + '/source/' + os.dir(dir))!
		os.cp_all(dir, output + '/source/' + dir, false)!
	}
	os.cp(@FILE, output + '/ext2-check.v')!
	checked([v, '-o', output + '/format', 'tools/powerpc-disk'], output + '/format-build.log')!
	checked([output + '/format', output + '/disk.raw'], output + '/format.log')!
	checked([v, '-enable-globals', '-path', '@vlib|' + root + '/kernel', '-o', output + '/probe',
		'tests/powerpc/ext2host'], output + '/probe-build.log')!
	checked([output + '/probe', output + '/disk.raw'], output + '/probe.log')!
	checked([fsck, '-fn', output + '/disk.raw'], output + '/fsck.log')!
	mut paths := os.walk_ext(output, '')
	paths.sort()
	mut sums := ''
	for path in paths {
		if os.is_file(path) { sums += sha256.hexhash(os.read_bytes(path)!.bytestr()) + '  ' + path.all_after(output + '/') + '\n' }
	}
	os.write_file(output + '/SHA256SUMS', sums)!
}

fn main() {
	if os.args.len != 2 { eprintln('Usage: v run tests/powerpc/ext2-check.v FRESH_OUTPUT'); exit(2) }
	check(os.abs_path(os.args[1])) or { eprintln(err); exit(1) }
}
