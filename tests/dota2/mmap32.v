// SPDX-License-Identifier: GPL-2.0-or-later
// Sanitize the V parser/mapping fixture, optionally against frozen original C.
module main

import hosttest
import os

fn run(baseline string, has_baseline bool) ! {
	root := hosttest.root()
	arch := if os.uname().machine in ['arm64', 'aarch64'] { 'arm64' } else { 'amd64' }
	work := hosttest.work_dir('', 'vinix-dota-mmap32-')!
	defer { os.rmdir_all(work) or { eprintln(err) } }
	flags := [hosttest.env_default('CC', 'clang'), '-O1', '-g', '-std=gnu11', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	aliases := ['-Dopen=fixture_open', '-Dread=fixture_read', '-Dclose=fixture_close',
		'-D__errno_location=fixture_errno', '-Ddlsym=fixture_dlsym', '-Dmunmap=fixture_munmap',
		'-Dmmap=fixture_mmap', '-Dmmap64=fixture_mmap64']
	hosttest.generate_module(root + '/tests/dota2/mmapfixture', work + '/fixture.c', arch, ['nofloat'])!
	hosttest.generate_module(root + '/build-support/dota2/mmapcore', work + '/production.c', arch, ['nofloat'])!
	mut sources := [work + '/production.c']
	if has_baseline { sources << hosttest.module_resolve(baseline)! }
	mut outputs := []hosttest.Result{}
	for index, source in sources {
		production := work + '/production-' + index.str() + '.o'
		fixture := work + '/fixture-' + index.str() + '.o'
		mut command := [...flags, ...aliases]
		if index != 0 { command << '-Dstatic=' }
		command << ['-I', root + '/build-support/dota2', '-c', source, '-o', production]
		hosttest.command(command, '', -1, os.environ())!
		imports := hosttest.command(['nm', '-u', production], '', -1, os.environ())!.stdout
		if hosttest.allocation_symbols(imports) { return error(imports) }
		mut fixture_command := flags.clone()
		if index != 0 { fixture_command << '-Dvinix_dota_next_gap=next_gap' }
		fixture_command << ['-I', root + '/tests/dota2', '-c', work + '/fixture.c', '-o', fixture]
		hosttest.command(fixture_command, '', -1, os.environ())!
		executable := work + '/test-' + index.str()
		hosttest.command([...flags, production, fixture, '-o', executable], '', -1, os.environ())!
		result := hosttest.capture([executable], '', -1, os.environ())!
		if result.code != 0 { return error('${index}: ${result.code}\n${result.stdout}${result.stderr}') }
		outputs << result
	}
	if outputs.len == 2 && outputs[0] != outputs[1] { return error('Frozen C and production V fixture results differ') }
	print(outputs[0].stdout)
}

fn main() {
	args := hosttest.parse_arguments(os.args[1..], [hosttest.Option{'--baseline', true, []string{}}],
		0, 'Usage: mmap32.v [--baseline SOURCE]',
		'Sanitize the V parser/mapping fixture, optionally against frozen original C.') or { eprintln(err); exit(2) }
	run(args.options['--baseline'] or { '' }, '--baseline' in args.options) or { eprintln(err); exit(1) }
}
