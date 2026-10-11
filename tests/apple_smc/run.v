// SPDX-License-Identifier: GPL-2.0-only
module main

import applehost
import crypto.sha256
import hosttest
import json2
import os

const original_revision = 'c93d331c5201b2bdd942e46c69f8c0a5ed534cbd'

fn command(argv []string) ! { applehost.inherited(argv, applehost.environment(), '')! }
fn capture(argv []string, directory string, binary bool) !string {
	return applehost.capture(argv, applehost.environment(), '', directory, binary)!
}
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn strings(values []string) json2.Any { return json2.Any(hosttest.strings(values)) }
fn join(parts ...[]string) []string { mut result := []string{}; for part in parts { result << part }; return result }

// Preserve both Unicode word boundaries and the fixture's narrower ban.
fn forbidden(text string, fixture bool) bool {
	mut word := ''
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) { word += ch.str(); continue }
		name := if word.starts_with('_') { word[1..] } else { word }
		if name in ['malloc', 'realloc', 'memdup'] || name.starts_with('new_array')
			|| (!fixture && name in ['calloc', 'free']) { return true }
		word = ''
	}
	return false
}

fn run() ! {
	r := applehost.runtime('smc', os.args[1..])!
	defer { r.close() or { eprintln(err.msg()) } }
	root := r.root
	here := root + '/tests/apple_smc'
	work := r.work
	v := capture(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root], '', false)!
	mut common := [hosttest.env_default('CC', 'clang')]
	$if macos { common << ['-arch', if r.host_arch == 'arm64' { 'arm64' } else { 'x86_64' }] }
	common << ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	os.write_file(work + '/v.mod', "Module { name: 'vinix_smc_tests' }\n")!
	hosttest.module_copy_file(root + '/kernel/apple/smc/core/core.v', work + '/core.v')!
	mut env := applehost.environment()
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	// This original producer intentionally compiles the complete standalone
	// provider, without the generic producer's module renaming or entry wrapper.
	applehost.inherited([v, '-shared', '-no-builtin', '-os', 'vinix', '-target-libc-headers',
		'-nofloat', '-gc', 'none', '-manualfree', '-arch', r.host_arch, '-o', work + '/core.c', work], env, '')!
	command(join(common, ['-Wno-unused-function', '-ffreestanding', '-fno-builtin',
		'-fno-strict-aliasing', '-DVINIX_V_RUNTIME', '-I', root + '/kernel/c',
		'-c', work + '/core.c', '-o', work + '/core.o']))!
	imports := capture(['nm', '-u', work + '/core.o'], '', false)!
	if forbidden(imports, false) { return error('unexpected allocator import in SMC core:\n' + imports) }
	command([here + '/compile-fixture', work + '/fixture.c'])!
	command(join(common, ['-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label',
		'-fwrapv', '-fno-strict-aliasing', '-iquote', root + '/kernel/c', '-iquote', here,
		'-c', work + '/fixture.c', '-o', work + '/fixture.o']))!
	fixture_imports := capture(['nm', '-u', work + '/fixture.o'], '', false)!
	if forbidden(fixture_imports, true) { return error('unexpected allocator import in SMC fixture:\n' + fixture_imports) }
	original := capture(['git', 'show', original_revision + ':tests/apple_smc/test_smc.c'], root, true)!
	os.write_file(work + '/original.c', original)!
	command(join(common, ['-iquote', root + '/kernel/c', work + '/original.c', work + '/core.o', '-o', work + '/original']))!
	command(join(common, [work + '/fixture.o', work + '/core.o', '-o', work + '/host']))!
	baseline := capture([work + '/original'], '', true)!
	actual := capture([work + '/host'], '', true)!
	if actual != baseline || !actual.ends_with('27 tests passed\n') || actual.count('PASS test_') != 27 {
		return error('SMC original/V result or complete 27-test verdict mismatch')
	}
	hosttest.module_decode_utf8(actual)!
	os.write_file(work + '/validation.json', json2.encode(json2.Any({
		'original_revision': json2.Any(capture(['git', 'rev-parse', original_revision], root, false)!.trim_space())
		'original_sha256': json2.Any(sha256.sum(original.bytes()).hex())
		'original_lines': json2.Any(original.split_into_lines().len)
		'stdout': json2.Any(actual)
		'fixture_imports': strings(fixture_imports.split_into_lines())
		'core_imports': strings(imports.split_into_lines())
	}), prettify: true) + '\n')!
	print(actual)
	println('PASS V SMC fixture C/V goldens, C ABI, ASan/UBSan and no implicit allocator imports')
	if r.arch == '' { return }
	command([here + '/compile-fixture', '--guest', '--arch', if r.arch == 'aarch64' { 'arm64' } else { 'amd64' }, work + '/native.c'])!
	mut cc := []string{}
	if r.arch == 'aarch64' {
		base := root + '/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl'
		mut versions := os.ls(base)!
		versions.sort()
		if versions.len == 0 { return error('Missing AArch64 GCC installation') }
		cc = [hosttest.env_default('CC_AARCH64', '/opt/homebrew/opt/llvm/bin/clang'),
			'--target=aarch64-linux-musl', '--sysroot=' + root + '/build-aarch64-userland/sysroot',
			'--gcc-install-dir=' + base + '/' + versions.last()]
	} else { cc = [hosttest.env_default('CC_AMD64', 'x86_64-linux-musl-gcc')] }
	flags := ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
		'-Wno-unused-parameter', '-Wno-unused-label', '-fwrapv', '-fno-strict-aliasing',
		'-iquote', root + '/kernel/c', '-iquote', here]
	for filename in ['core.c', 'native.c'] {
		mut extra := []string{}
		if filename == 'core.c' {
			extra = ['-DVINIX_V_RUNTIME', '-ffreestanding', '-fno-builtin']
			if r.arch == 'x86_64' { extra << '-Wno-array-parameter' }
		}
		command(join(cc, flags, extra, ['-c', work + '/' + filename, '-o', work + '/' + filename + '.o']))!
	}
	applehost.serial(work + '/serial.o', r.arch, join(cc, flags))!
	init := work + '/native-init'
	command(join(cc, if r.arch == 'aarch64' { ['-fuse-ld=lld'] } else { []string{} },
		['-static', work + '/core.c.o', work + '/native.c.o', work + '/serial.o', '-o', init]))!
	markers := actual.split_into_lines()
	argv := applehost.guest_command(root, init, r.arch, r.kernel, r.guest, '300', markers, []string{})
	os.write_file(work + '/native-inputs.json', json2.encode(json2.Any({
		'arch': json2.Any(r.arch)
		'fixture_sha256': json2.Any(digest(init)!)
		'kernel_sha256': json2.Any(digest(r.kernel + '/bin/vinix')!)
		'expected_markers': strings(markers)
		'command': strings(argv)
	}), prettify: true) + '\n')!
	if !r.build_only { applehost.guest(init, r.arch, r.kernel, r.guest, '300', markers, []string{})! }
}

fn main() { run() or { applehost.report(err) } }
