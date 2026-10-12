// SPDX-License-Identifier: GPL-2.0-or-later
module launcherhost

import cachecli
import cachekey
import gamehost
import hosttest
import os
import sourcecommand
import steamshim

pub struct Tools {
pub:
	root string
}

const reference = '8f7239d1fd4c593746279699f6ff25df5f4dd7bd'
const vnc_calls = ['XOpenDisplay', 'XCreateSimpleWindow', 'XSelectInput', 'XStoreName', 'XMapWindow',
	'XCreateGC', 'calloc', 'XCreateImage', 'socket', 'connect', 'close', 'usleep', 'recv', 'send',
	'select', 'XPutImage', 'XFlush', 'XPending', 'XNextEvent', 'XLookupKeysym', 'XFreeGC',
	'XDestroyWindow', 'XCloseDisplay']
const warnings = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
	'-Wno-unused-label', '-Wno-unused-parameter']

fn command(argv []string, environment map[string]string) !sourcecommand.Output {
	result := sourcecommand.capture_full(argv, environment, -1, 64 * 1024 * 1024, cachecli.cancelled)!
	if result.status != 0 || result.stdout.contains('retrying with') || result.stderr.contains('retrying with') {
		return error('launcher command failed: ' + argv.str() + '\n' + result.stdout + result.stderr)
	}
	return result
}

fn compile(argv []string) ! {
	result := command(argv, os.environ())!
	print(result.stdout)
	eprint(result.stderr)
}

fn generate(tools Tools, module_ string, output string, arch string, header string, defines []string) ! {
	result := hosttest.generate_module_capture(tools.root + '/' + module_, output, arch, defines)!
	print(result.stdout)
	eprint(result.stderr)
	if result.stdout.contains('retrying with') || result.stderr.contains('retrying with') {
		return error('compiler fallback is not qualification')
	}
	if header != '' { hosttest.emit_module_header(tools.root + '/' + module_, output, header)! }
}

fn renamed_header(path string, function string) ! {
	text := os.read_file(path)!
	os.write_file(path, text.replace(' main(', ' ' + function + '('))!
}

fn frozen(tools Tools, path string, output string) ! {
	result := command(['git', '-C', tools.root, 'show', reference + ':' + path], os.environ())!
	os.write_file(output, result.stdout)!
}

fn import_tokens(text string) []string {
	mut result := []string{}
	mut token := ''
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) {
			token += ch.str()
			continue
		}
		if token != '' {
			result << if token.starts_with('_') { token[1..] } else { token }
			token = ''
		}
	}
	return result
}

pub fn allocator_imports(text string, allow_calloc bool) bool {
	return import_tokens(text).any(it in ['malloc', 'realloc', 'free', 'memdup'] || it.starts_with('new_array') || (!allow_calloc && it == 'calloc'))
}

fn model_result(executable string, work string, kind string, env map[string]string) !sourcecommand.Output {
	result := sourcecommand.capture_full([executable], env, -1, 64 * 1024 * 1024, cachecli.cancelled)!
	os.write_file(work + '/' + kind + '.stdout', result.stdout)!
	os.write_file(work + '/' + kind + '.stderr', result.stderr)!
	if result.status != 0 || result.stderr.contains('runtime error:') || result.stderr.contains('ERROR: AddressSanitizer') {
		return error(kind + ' model failed: ' + result.stdout + '\n' + result.stderr)
	}
	return result
}

fn sanitize_environment() map[string]string {
	mut env := os.environ()
	env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
	return env
}

fn vnc_remap() []string {
	mut result := ['-Dmain=vnf_viewer']
	for name in vnc_calls { result << '-D' + name + '=vnf_' + name }
	return result
}

pub fn vnc_host(tools Tools, work string, headers string) ! {
	core := work + '/amd64-core.c'
	fixture := work + '/amd64-fixture.c'
	api := work + '/amd64-api.h'
	generate(tools, 'build-support/qemu-system/vnccore', core, 'amd64', api, [])!
	renamed_header(api, 'vnf_viewer')!
	generate(tools, 'build-support/qemu-system/tests/vncfixture', fixture, 'amd64', '', [])!
	original := work + '/frozen-viewer.c'
	frozen(tools, 'build-support/qemu-system/vinix-vnc-window.c', original)!
	flags := [os.getenv_opt('CC') or { 'clang' }, '-std=c11', '-D_DEFAULT_SOURCE', '-O2', '-Wall',
		'-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter',
		'-g', '-fsanitize=address,undefined', '-fsanitize-address-use-after-return=always',
		'-fno-omit-frame-pointer', '-idirafter', headers]
	model := work + '/fixture.o'
	compile([...flags, '-I', tools.root + '/build-support/qemu-system/tests/vncfixture', '-include', api, '-c', fixture, '-o', model])!
	mut results := []sourcecommand.Output{}
	for i, source in [original, core] {
		kind := ['c', 'v'][i]
		object := work + '/' + kind + '-viewer.o'
		binary := work + '/' + kind + '-viewer'
		compile([...flags, ...vnc_remap(), '-c', source, '-o', object])!
		compile([...flags, model, object, '-o', binary])!
		results << model_result(binary, work, kind, sanitize_environment())!
	}
	if results[0].stdout != results[1].stdout || results[0].stderr != results[1].stderr {
		return error('Frozen C and V protocol/lifetime traces differ')
	}
	if results[1].stdout.count('CASE ') != 34 || !results[1].stdout.ends_with('VNC MODEL PASS\n') {
		return error('VNC model did not cover all 34 original cases')
	}
	imports := command(['nm', '-u', work + '/v-viewer.o'], os.environ())!.stdout
	if allocator_imports(imports, true) || 'vnf_calloc' !in import_tokens(imports) {
		return error('unexpected VNC allocation imports: ' + imports)
	}
	print(results[1].stdout)
	println('VNC viewer: 34 exact C/V protocol, pixel, Xlib and ownership traces; ASan/UBSan PASS')
}

pub fn vnc_native(tools Tools, work string, headers string, arch string) ! {
	v_arch := if arch == 'aarch64' { 'arm64' } else { 'amd64' }
	core := work + '/' + v_arch + '-core.c'
	fixture := work + '/' + v_arch + '-fixture.c'
	api := work + '/' + v_arch + '-api.h'
	generate(tools, 'build-support/qemu-system/vnccore', core, v_arch, api, [])!
	renamed_header(api, 'vnf_viewer')!
	generate(tools, 'build-support/qemu-system/tests/vncfixture', fixture, v_arch, '', ['vnc_guest'])!
	compiler := os.getenv_opt(if arch == 'aarch64' { 'CC_ARM64' } else { 'CC_AMD64' }) or { arch + '-linux-musl-gcc' }
	flags := [compiler, '-std=c11', '-D_DEFAULT_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-idirafter', headers]
	object := work + '/' + arch + '-core.o'
	model := work + '/' + arch + '-fixture.o'
	binary := work + '/' + arch + '-viewer'
	compile([...flags, ...vnc_remap(), '-c', core, '-o', object])!
	compile([...flags, '-I', tools.root + '/build-support/qemu-system/tests/vncfixture', '-include', api, '-c', fixture, '-o', model])!
	compile([compiler, '-static', model, object, '-o', binary])!
	println('Native ' + arch + ' V model: ' + binary)
}

pub fn venus_host(tools Tools, work string, headers string, darwin_arm64 bool) ! {
	core := work + '/available-v.c'
	fixture := work + '/fixture-v.c'
	api := work + '/api.h'
	generate(tools, 'build-support/venus/availablecore', core, 'amd64', api, [])!
	renamed_header(api, 'vinix_venus_probe')!
	generate(tools, 'build-support/venus/tests/probefixture', fixture, 'amd64', '', if darwin_arm64 {
		['probe_darwin_arm64']
	} else {
		[]string{}
	})!
	original := work + '/available-c.c'
	frozen(tools, 'build-support/venus/available.c', original)!
	compiler := os.getenv_opt('CC') or { 'clang' }
	flags := [compiler, ...warnings, '-g', '-fsanitize=address,undefined',
		'-fsanitize-address-use-after-return=always', '-fno-omit-frame-pointer', '-I', headers]
	compile([...flags, '-include', api, '-c', fixture, '-o', work + '/fixture.o'])!
	mut objects := [work + '/fixture.o']
	if darwin_arm64 {
		compile([compiler, '-c',
			tools.root + '/build-support/venus/tests/probefixture/ioctl_darwin_arm64.S', '-o',
			work + '/ioctl.o'])!
		objects << work + '/ioctl.o'
	}
	mut results := []sourcecommand.Output{}
	for i, source in [original, core] {
		kind := ['c', 'v'][i]
		object := work + '/' + kind + '.o'
		binary := work + '/' + kind + '-probe'
		compile([...flags, '-Dmain=vinix_venus_probe', '-Dopen=vhs_open', '-Dclose=vhs_close',
			'-Dioctl=vhs_ioctl', '-c', source, '-o', object])!
		compile([...flags, ...objects, object, '-o', binary])!
		results << model_result(binary, work, kind, sanitize_environment())!
	}
	if results[0].stdout != results[1].stdout || results[0].stderr != results[1].stderr {
		return error('Original C and V device-probe traces differ')
	}
	if !results[1].stdout.contains('VENUS PROBE PASS\n') {
		return error('Venus probe did not pass')
	}
	imports := command(['nm', '-u', work + '/v.o'], os.environ())!.stdout
	if allocator_imports(imports, false) {
		return error('unexpected Venus allocation imports: ' + imports)
	}
	print(results[1].stdout)
	println('Venus probe: exact C/V device/close/ioctl outcomes, ASan/UBSan PASS')
}

pub fn venus_native(tools Tools, work string, headers string, arch string) ! {
	core := work + '/' + arch + '-core.c'
	fixture := work + '/' + arch + '-fixture.c'
	api := work + '/' + arch + '-api.h'
	v_arch := if arch == 'aarch64' { 'arm64' } else { 'amd64' }
	generate(tools, 'build-support/venus/availablecore', core, v_arch, api, [])!
	renamed_header(api, 'vinix_venus_probe')!
	generate(tools, 'build-support/venus/tests/probefixture', fixture, v_arch, '', ['probe_native_guest'])!
	sysroot := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { tools.root + '/build-aarch64-userland/sysroot' }
	compiler := if arch == 'aarch64' {
		[os.getenv_opt('CC') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sysroot]
	} else {
		[os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }]
	}
	link := if arch == 'aarch64' { ['-L' + sysroot + '/lib', '-fuse-ld=lld'] } else { []string{} }
	flags := ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-D__EXPORTED_HEADERS__',
		'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-I', headers]
	object := work + '/' + arch + '-core.o'
	model := work + '/' + arch + '-fixture.o'
	binary := work + '/' + arch + '-probe'
	compile([...compiler, ...flags, '-Dmain=vinix_venus_probe', '-Dopen=vhs_open', '-Dclose=vhs_close',
		'-Dioctl=vhs_ioctl', '-c', core, '-o', object])!
	compile([...compiler, ...flags, '-include', api, '-c', fixture, '-o', model])!
	compile([...compiler, ...link, '-static', object, model, '-o', binary])!
	println('Native ' + arch + ' fixture: ' + binary)
}

pub fn model_cli(tools Tools, command_ string, argv []string) !int {
	args := cachecli.arguments(argv, ['--headers', '--state-dir', '--native'], [], [], 0, 0, 'Compare unchanged V model and production core with frozen C.\nUsage: run [--headers DIR --state-dir DIR --native aarch64|x86_64]') or { return error_with_code(err.msg(), 2) }
	arch := args.value('--native', '')
	if arch != '' && arch !in ['aarch64', 'x86_64'] {
		return error_with_code('unsupported native architecture', 2)
	}
	if arch != '' && '--state-dir' !in args.options {
		return error_with_code('--native requires --state-dir to retain the guest ELF', 2)
	}
	vnc := command_ == 'vnc'
	headers := args.value('--headers', tools.root + if vnc {
		'/build-aarch64-userland/staging/usr/include'
	} else {
		'/build-aarch64-venus/mesa-25.0.5/include/drm-uapi'
	})
	temporary := '--state-dir' !in args.options
	work := if temporary {
		sourcecommand.temporary(if vnc { 'vinix-vnc-model-' } else { 'vinix-venus-probe-' })!
	} else {
		cachekey.resolve_path(args.value('--state-dir', ''))!
	}
	if work == tools.root || work.starts_with(tools.root + '/') {
		return error_with_code('Frozen C/build artifacts must stay outside the checkout', 2)
	}
	defer { if temporary { gamehost.remove(work) or {} } }
	gamehost.mkdir(work)!
	if vnc {
		vnc_host(tools, work, headers)!
	} else {
		venus_host(tools, work, headers, $if darwin { os.uname().machine == 'arm64' } $else { false })!
	}
	if arch != '' {
		if vnc {
			vnc_native(tools, work, headers, arch)!
		} else {
			venus_native(tools, work, headers, arch)!
		}
	}
	return 0
}

pub fn dispatch(tools Tools, name string, argv []string) !int {
	return match name {
		'vnc', 'venus' { model_cli(tools, name, argv)! }
		'steam-lsof' { steamshim.lsof_cli(argv)! }
		'steam-tar' { steamshim.tar_cli(argv)! }
		'unpack-steam-deb' { unpack_steam_deb(argv)! }
		'relative-link' { relative_link(argv)! }
		else { return error_with_code('unknown launcher command: ' + name, 2) }
	}
}
