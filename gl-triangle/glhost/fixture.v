// SPDX-License-Identifier: GPL-2.0-or-later
module glhost

import os

fn fixture() ! {
	work := private_directory('vinix-triangle-')!
	defer { os.rmdir_all(work) or {} }
	cc := os.getenv_opt('CC') or { 'clang' }
	flags := ['-std=gnu11', '-O2', '-g', '-fwrapv', '-fno-strict-aliasing',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-Wall', '-Wextra', '-Werror',
		'-DVINIX_TRIANGLE_HOST_TEST', '-I' + root() + '/gl-triangle',
		'-I' + root() + '/tests/gl-triangle', '-I/opt/homebrew/include']
	for kind in ['egl', 'glut', 'legacy'] {
		source, obj, executable := work + '/' + kind + '.c', work + '/' + kind + '.o', work + '/' + kind
		generate(source, kind, 'arm64', '')!
		mut compile := [cc, ...flags, '-Dmain=test_program_main']
		for hook in ['open', 'close', 'ioctl', 'mmap', 'munmap', 'malloc', 'free'] {
			compile << '-D' + hook + '=test_' + hook
		}
		run([...compile, '-c', source, '-o', obj])!
		for line in output(['nm', '-u', obj])!.split_into_lines() {
			name := line.trim_space().all_after_last(' ').trim_left('_')
			if name in ['calloc', 'realloc', 'memdup'] || name.starts_with('new_array') {
				return error('unexpected native allocation: ' + line)
			}
		}
		mut link := [cc, ...flags]
		if kind != 'egl' { link << '-DVINIX_GLUT_TRIANGLE' }
		if kind == 'legacy' { link << '-DVINIX_LEGACY_TRIANGLE' }
		run([...link, root() + '/tests/gl-triangle/native_fixture.c', obj, '-o', executable])!
		scenarios := if kind != 'egl' {
			[[]string{}]
		} else {
			[[]string{}, ['--submit-only'], ['--submit-only', '--depth'],
				['--submit-only', '--stencil'], ['--submit-only', '--depth-stencil'], ['--depth'],
				['--stencil'], ['--depth-stencil']]
		}
		for args in scenarios {
			text := output([executable, ...args])!
			if !text.contains('Triangle native fixture: PASS') || text.contains('VINIX M1 AGX RENDER TEST: PASS') {
				return error(text)
			}
			println(kind + ' ' + args.join(' ') + ': PASS')
		}
		if kind == 'egl' {
			for bpp in ['16', '24', '32'] {
				environment_fixture(executable, {
					'TRIANGLE_FB_BPP': bpp
				}, false)!
			}
			for setting in ['TRIANGLE_SOFTWARE', 'TRIANGLE_APPLE'] {
				environment_fixture(executable, {
					setting: '1'
				}, setting == 'TRIANGLE_APPLE')!
			}
		}
	}
	println('Triangle sanitizer API/lifetime fixtures: PASS')
}

fn environment_fixture(executable string, settings map[string]string, apple bool) ! {
	mut env := os.environ()
	for key, value in settings { env[key] = value }
	// The process owns its complete environment; no global env mutation survives a fixture.
	text := capture_environment([executable], env)!
	if !text.contains('Triangle native fixture: PASS') || text.contains('VINIX M1 AGX RENDER TEST: PASS') != apple {
		return error(text)
	}
}
