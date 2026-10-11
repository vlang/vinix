// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import guesthost
import hosttest
import json2
import os
import policyhost

const speculation_stdout = 'SPECULATION POLICY PASS (6144 cases)\n'

fn speculation_build(work string, arch string, flags []string, reference string, guest bool) !string {
	os.mkdir_all(os.dir(work))!
	os.mkdir(work)!
	production := work + '/speculationpolicy'
	os.mkdir(production)!
	mut hashes := map[string]string{}
	for pair in [['speculation.v', 'policy.v'], ['speculation_amd64.v', 'ports.v']] {
		path := root() + '/kernel/lib/' + pair[0]
		text := read(path)!
		hashes['kernel/lib/' + pair[0]] = hosttest.text_sha(text)
		write(production + '/' + pair[1], text.replace_once('module lib', 'module speculationpolicy'))!
	}
	source := work + '/policy.c'
	generate(production, source, if arch == 'aarch64' { 'arm64' } else { 'amd64' }, ['nofloat', 'speculation_test'], '')!
	compile_flags := flags.filter(!it.starts_with('-L') && !it.starts_with('-l') && !it.starts_with('-fuse-ld='))
	core := work + '/policy.o'
	run([...compile_flags, '-Wno-unused-function', '-Wno-unused-parameter', '-ffreestanding',
		'-fno-builtin', '-fno-strict-aliasing', '-c', source, '-o', core])!
	os.cp(root() + '/kernel/c/speculation.h', work + '/speculation.h')!
	fixture := work + '/fixture.o'
	fixture_flags := [...flags, '-I', work, ...if guest { ['-Dmain=speculation_native_main'] } else { []string{} }]
	if reference != '' {
		os.cp(reference, work + '/fixture.c')!
		native := fixture_flags.filter(!it.starts_with('-L') && !it.starts_with('-l') && !it.starts_with('-fuse-ld='))
		run([...native, '-c', work + '/fixture.c', '-o', fixture])!
	} else { guesthost.compile_module(root() + '/tests/speculation-policy/fixture', fixture, arch, fixture_flags)! }
	mut objects := [core, fixture]
	imports := output([os.getenv_opt('NM') or { 'nm' }, '-u', ...objects])!
	if allocator_imports(imports) || imports.fields().any(it.trim_left('_') in ['aligned_alloc', 'posix_memalign']) {
		return error('Unexpected speculation allocator import:\n' + imports)
	}
	if guest {
		entry := work + '/entry'
		os.mkdir(entry)!
		write(entry + '/entry-native-abi.h', '#include <stdio.h>\n#include <unistd.h>\nint speculation_native_main(void);\n')!
		write(entry + '/core.v', "module entry\n#include <entry-native-abi.h>\nfn C.speculation_native_main() i32\nfn C.fflush(voidptr) i32\nfn C.pause() i32\n@[export: 'main']\npub fn run() i32 {\n result := C.speculation_native_main()\n unsafe { C.fflush(nil) }\n if result == 0 { for { C.pause() } }\n return result\n}\n")!
		guesthost.compile_module(entry, work + '/entry.o', arch, flags)!
		guesthost.compile_module(root() + '/tests/kernel-gaps/serialcore', work + '/serial.o', arch, flags)!
		objects << [work + '/entry.o', work + '/serial.o']
	}
	executable := work + '/test'
	compile := [...flags, ...if guest { ['-static'] } else { []string{} }, ...objects, '-o', executable]
	run(compile)!
	hosttest.write_json(work + '/inputs.json', { 'arch': json2.Any(arch),
		'original': if reference == '' { json2.Any(json2.null) } else { json2.Any(reference) }, 'guest': json2.Any(guest),
		'compiler_flags': json2.Any(hosttest.strings(flags)), 'compile_command': json2.Any(hosttest.strings(compile)),
		'production_sources': json2.Any(hosttest.string_map(hashes)), 'generated_policy_sha256': json2.Any(hosttest.sha(source)!),
		'fixture_source_sha256': json2.Any(hosttest.sha(work + '/fixture.c')!), 'executable_sha256': json2.Any(hosttest.sha(executable)!),
		'imports': json2.Any(hosttest.strings(imports.split_into_lines())) })!
	return executable
}

fn speculation_host_pass(result hosttest.Result) bool {
	return result.code == 0 && result.stdout == speculation_stdout
		&& !['runtime error', 'AddressSanitizer', 'LeakSanitizer'].any(result.stderr.contains(it))
}

fn speculation_command(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--host-arch', value: true, choices: ['arm64', 'amd64'] },
		hosttest.Option{ name: '--state-dir', value: true }, hosttest.Option{ name: '--original-reference', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true }, hosttest.Option{ name: '--guest-state-dir', value: true },
		hosttest.Option{ name: '--build-only' }], 0,
		'Usage: run [--host-arch arm64|amd64] [--state-dir FRESH-DIR] [--original-reference C] [--arch aarch64|x86_64 --kernel-dir DIR --guest-state-dir DIR] [--build-only]',
		'Exercise the exact production CPUID/MSR policy with the independent 6144-case oracle.') or { return error_with_code(err.msg(), 2) }
	guest := '--arch' in parsed.options
	if guest { needed(parsed, ['--state-dir', '--kernel-dir', '--guest-state-dir'])! }
	arch := parsed.options['--arch'] or { if (parsed.options['--host-arch'] or { policyhost.caller_arch() }) == 'arm64' { 'aarch64' } else { 'x86_64' } }
	work := hosttest.work_dir(parsed.options['--state-dir'] or { '' }, 'vinix-speculation-policy-')!
	defer { if '--state-dir' !in parsed.options { retire(work) } }
	reference := if '--original-reference' in parsed.options { resolve(parsed.options['--original-reference'])! } else { '' }
	mut cc := []string{}
	if guest && arch == 'aarch64' {
		sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root() + '/build-aarch64-userland/sysroot' }
		cc = [os.getenv_opt('CC_AARCH64') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk, '-fuse-ld=lld', '-L' + sdk + '/lib']
	} else if guest { cc = [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }] } else {
		cc = [os.getenv_opt('CC') or { 'clang' }]
		$if macos { cc << ['-arch', if arch == 'aarch64' { 'arm64' } else { 'x86_64' }] }
	}
	mut flags := [...cc, '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror']
	if !guest { flags << ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'] }
	program := speculation_build(work + if guest { '/native' } else { '/v' }, arch, flags, if guest { reference } else { '' }, guest)!
	if guest {
		elf_arch(program, arch)!
		private_kernel := snapshot_kernel(work, parsed.options['--kernel-dir'], arch)!
		if '--build-only' in parsed.options { return 0 }
		return guesthost.guest('', program, resolve(parsed.options['--guest-state-dir'])!, private_kernel, arch,
			[speculation_stdout.trim_right('\n')], ['Assertion'], false, true, 3600)!
	}
	if '--build-only' in parsed.options { return 0 }
	mut env := policyhost.environment()
	env['ASAN_OPTIONS'] = 'detect_leaks=1'
	$if macos { env['ASAN_OPTIONS'] = 'detect_leaks=0' }
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	translated := hosttest.capture([program], work + '/v-run.log', 180, env)!
	if !speculation_host_pass(translated) { return error('Speculation host output/status/sanitizer verdict differs: ' + work + '/v-run.log') }
	if reference != '' {
		control := speculation_build(work + '/c', arch, flags, reference, false)!
		control_result := hosttest.capture([control], work + '/c-run.log', 180, env)!
		if control_result != translated { return error('Original C/V speculation outputs, statuses or diagnostics differ') }
	}
	write(work + '/stdout', translated.stdout)!
	write(work + '/stderr', translated.stderr)!
	print(translated.stdout)
	return 0
}
