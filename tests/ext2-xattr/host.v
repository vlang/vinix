// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import hostfixture
import os
import sourcecommand

fn run() !int {
	argv := os.args[1..]
	separator := argv.index('--')
	flags := if separator >= 0 { argv[separator + 1..] } else { []string{} }
	options := if separator >= 0 { argv[..separator] } else { argv }
	args := cachecli.arguments(options, ['--compiler', '--state-dir'], [], ['--keep'], 0, 0,
		'Exercise the production ext2 EA codec, persistence, copy and ACL tests.\nUsage: host [--compiler V] [--state-dir NEW_DIR] [--keep] -- [V compiler flags]') or { return error_with_code(err.msg(), 2) }
	root := os.real_path(os.dir(@FILE) + '/../..')
	compiler := args.value('--compiler', os.getenv_opt('V') or { 'v' })
	mut parent := ''
	mut work := args.value('--state-dir', '')
	if work == '' {
		parent = sourcecommand.temporary('vinix-xattr-codec')!
		work = parent + '/fixture'
	}
	defer { if parent != '' && '--keep' !in args.options { os.rmdir_all(parent) or {} } }
	hostfixture.prepare(root, work)!
	mut env := os.environ()
	env['VEXE'] = compiler
	os.mkdir(work + '/bin')!
	mut transcript := ''
	for index, suite in ['ext2/codec_test.v', 'ext2/persistence_test.v', 'fs/copy_test.v', 'posix_acl/acl_test.v'] {
		cachecli.checkpoint()!
		binary := os.real_path(work) + '/bin/test-' + index.str()
		for command in [[compiler, '-enable-globals', '-gc', 'none', ...flags, '-o', binary, suite], [binary]] {
			result := sourcecommand.capture_in(command, env, work, true, cachecli.cancelled, '')!
			text := result.stdout + result.stderr
			print(text)
			transcript += text
			if result.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:', 'ERROR: AddressSanitizer', 'FAIL'].any(text.contains(it)) {
				os.write_file(work + '/host-test.log', transcript)!
				return error('ext2 native host suite failed: ' + suite)
			}
		}
		text := 'PASS ' + suite + '\n'
		print(text)
		transcript += text
	}
	transcript += '4 passed, 4 total\n'
	println('4 passed, 4 total')
	if args.value('--state-dir', '') != '' || '--keep' in args.options { os.write_file(work + '/host-test.log', transcript)! }
	return 0
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	status := run() or { eprintln(err); exit(if cachecli.cancelled() { cachecli.interrupt_status() } else if err.code() == 2 { 2 } else { 1 }) }
	exit(status)
}
