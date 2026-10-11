// SPDX-License-Identifier: MIT
module compathost

import fixturehost
import hosttest
import os
import policyhost

fn n64_bridge(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{name: '--build-dir', value: true},
		hosttest.Option{name: '--archive', value: true}, hosttest.Option{name: '--rom', value: true},
		hosttest.Option{name: '--llvm-bin', value: true}], 0,
		'Usage: test-bridge [--build-dir DIR] [--archive FILE] [--rom FILE] [--llvm-bin DIR]', 'Run the native V boundary fixture against an independently built N64 archive.') or { return error_with_code(err.msg(), 2) }
	build := resolve(if '--build-dir' in parsed.options { parsed.options['--build-dir'] } else { root() + '/build/n64-host' })!
	archive := resolve(if '--archive' in parsed.options { parsed.options['--archive'] } else { build + '/libvinix_n64.a' })!
	if !os.is_file(archive) { return error('Missing N64 archive: ' + archive) }
	llvm := resolve(if '--llvm-bin' in parsed.options { parsed.options['--llvm-bin'] } else { os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' } })!
	support := root() + '/build-support/n64'
	mut flags := ['-O2', '-fPIC', '-D_GNU_SOURCE', '-DNO_ASM', '-DHAVE_LLE', '-DHAVE_THR_AL',
		'-DM64P_PLUGIN_API', '-DM64P_CORE_PROTOTYPES', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter', '-I' + support + '/bridgefixture']
	for relative in ['mupen64plus-core/src', 'mupen64plus-core/src/api', 'mupen64plus-core/custom', 'include', 'libretro-common/include', 'libretro'] {
		flags << '-I' + build + '/source/' + relative
	}
	work := hosttest.work_dir('', 'vinix-n64-bridge-')!
	defer { retire(work) }
	generate(support + '/bridgefixture', work + '/fixture.c', policyhost.caller_arch(), []string{}, '')!
	run([llvm + '/clang', ...flags, '-c', work + '/fixture.c', '-o', work + '/fixture.o'])!
	run([llvm + '/clang++', work + '/fixture.o', archive, '-lpthread', '-lz', '-o', work + '/fixture'])!
	mut env := policyhost.environment()
	if '--rom' in parsed.options {
		rom := resolve(parsed.options['--rom'])!
		if !os.is_file(rom) { return error('Missing N64 ROM: ' + rom) }
		env['VINIX_N64_BRIDGE_ROM'] = rom
		env['VINIX_N64_BRIDGE_SAVE'] = work + '/cartridge.sav'
	}
	fixturehost.inherited_command_environment_preferred([work + '/fixture'], env, policyhost.caller_arch())!
	return 0
}
