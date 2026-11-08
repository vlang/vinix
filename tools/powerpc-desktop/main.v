// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os

fn run(args []string, output string, name string) ! {
	println('Desktop: ' + name)
	mut child := os.new_process(args[0])
	child.set_args(args[1..])
	child.set_redirect_stdio_merged()
	child.run()
	log := child.stdout_slurp()
	child.wait()
	defer { child.close() }
	os.write_file(output + '/' + name + '.log', args.join('\n') + '\n\n' + log)!
	if child.code != 0 { return error(name + ' failed; see ' + output + '/' + name + '.log') }
}

fn executable(variable string, fallback string) !string {
	return os.find_abs_path_of_executable(os.getenv_opt(variable) or { fallback })
}

fn main() {
	if os.args.len != 2 {
		eprintln('Usage: VINIX_UI2_SOURCE=... VINIX_PPC_DESKTOP_V=... v run tools/powerpc-desktop OUTPUT_DIRECTORY')
		exit(2)
	}
	build(os.abs_path(os.args[1])) or {
		eprintln(err)
		exit(1)
	}
}

fn build(output string) ! {
	root := os.real_path(@VMODROOT + '/../..')
	ui := os.real_path(os.getenv('VINIX_UI2_SOURCE'))
	if !os.is_file(ui + '/examples/calculator/calculator.vml') {
		return error('VINIX_UI2_SOURCE must name a ui2 checkout with compiled VML support')
	}
	host := executable('VINIX_V_COMPILER', 'v')!
	v := executable('VINIX_PPC_DESKTOP_V', 'v')!
	zig := executable('VINIX_PPC_ZIG', 'zig')!
	vroot := os.dir(os.real_path(v))
	os.mkdir_all(output + '/vmodules')!
	app := output + '/app-src'
	// The host entrypoints are V programs. An explicit -o prevents V from
	// overwriting the same-named checked-in stage_app/stage_ui2 launchers.
	run([host, '-o', output + '/stage-ui2', 'run', root + '/desktop/tools/stage_ui2.v',
		output + '/vmodules/ui2', ui, root + '/desktop/tools/ui2_headless_bounds.v'], output, 'stage-ui2')!
	run([host, '-o', output + '/stage-app', 'run', root + '/desktop/tools/stage_app.v', app,
		root + '/desktop', ui + '/examples/calculator'], output, 'stage-app')!
	os.setenv('V', v, true)
	for item in [['execinfocore', 'execinfo.c', output + '/execinfo_compat.h'],
		['gpucore', 'gpu-present-soft.c', app + '/gpu_present.h']] {
		// stage_app may have linked the checked-in declaration header.
		if os.is_link(item[2]) { os.rm(item[2])! }
		mut generate := [host, '-o', output + '/generate-module', 'run',
			root + '/tests/linuxkpi/generate_module.v', root + '/desktop/' + item[0],
			output + '/' + item[1], '--arch', 'ppc', '--header', item[2]]
		if os.getenv('VINIX_PPC_TRACE') == '1' { generate << ['-d', 'desktop_startup_trace'] }
		run(generate, output, 'generate-' + item[0])!
	}
	run([v, '-gc', 'none', '-o', output + '/stage-runtime', 'run',
		root + '/build-support/stage-v-runtime.v', output + '/v-runtime'], output, 'stage-runtime')!
	run([v, '-new-compiler', '-no-memory-limit', '-os', 'linux', '-arch', 'ppc', '-gc', 'none',
		'-manualfree', '-enable-globals', '-prod', '-d', 'glibc', '-d', 'ui2_headless', '-path',
		'@vlib|' + output + '/vmodules|@vmodules|' + root + '|' + root + '/third_party|' + root + '/tools/accounts',
		'-o', output + '/desktop.c', app], output, 'generate-desktop')!
	run([zig, 'cc', '-target', 'powerpc-linux-musleabihf', '-mcpu=7450', '-static', '-O2',
		'-mno-altivec', '-fno-pic', '-fno-pie', '-fno-stack-protector', '-w', '-D_GNU_SOURCE',
		'-Wl,-T,' + root + '/tests/powerpc/libc/linker.ld', '-Wl,--build-id=none', '-Wl,--strip-debug', '-I', app, '-I',
		root + '/build-support/aarch64-cc-shim', '-I', root + '/desktop/gpucore', '-I',
		vroot + '/thirdparty/fontstash', '-I', vroot + '/thirdparty/stb_image', output + '/desktop.c',
		output + '/execinfo.c', output + '/gpu-present-soft.c',
		output + '/v-runtime/segfault_handler_nix.c', output + '/v-runtime/execute_capture_nix.c',
		'-lc', '-lm', '-lunwind', '-o', output + '/vinix-desktop'], output, 'link-desktop')!
	image := os.read_bytes(output + '/vinix-desktop')!
	if image.len < 52 || image[..7] != [u8(0x7f), `E`, `L`, `F`, 1, 2, 1]
		|| image[16] != 0 || image[17] != 2 || image[18] != 0 || image[19] != 20 {
		return error('Desktop output is not a big-endian PowerPC ELF32 executable')
	}
	for item in [[root, 'vinix'], [vroot, 'v'], [ui, 'ui2']] {
		run(['git', '-C', item[0], 'rev-parse', 'HEAD'], output, item[1] + '-revision')!
		run(['git', '-C', item[0], 'diff', '--binary', 'HEAD'], output, item[1] + '-overlay')!
		mut archive := ['git', '-C', item[0], 'archive', '--format=tar', '-o',
			output + '/' + item[1] + '-sources.tar', 'HEAD']
		if item[1] == 'vinix' {
			archive << ['desktop', 'tools/accounts', 'tools/packages', 'tests/linuxkpi', 'tests/powerpc', 'build-support',
				'tools/powerpc-desktop']
		}
		run(archive, output, item[1] + '-sources')!
	}
	os.cp(@FILE, output + '/builder.v')!
	run([v, 'version'], output, 'v-version')!
	run([zig, 'version'], output, 'zig-version')!
	mut sums := ''
	for name in os.ls(output)! {
		if name.ends_with('.log') || name.ends_with('.c') || name.ends_with('.tar') || name == 'builder.v' || name == 'vinix-desktop' {
			sums += sha256.hexhash(os.read_bytes(output + '/' + name)!.bytestr()) + '  ' + name + '\n'
		}
	}
	os.write_file(output + '/SHA256SUMS', sums)!
	println('Built PPC32 desktop: ' + output + '/vinix-desktop')
	println('Use VINIX_PPC_INIT=' + output + '/vinix-desktop with tools/powerpc build to bundle the native apps and shell.')
}
