// SPDX-License-Identifier: GPL-2.0-only
module agxhost

import hosttest
import fixturehost
import os

pub fn (mut out Transcript) generate_trace(root string, output string, arch string, temp_dir string) ! {
	compiler := out.capture_output(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
		'find-v', root], os.environ())!
	work := private_directory(temp_dir, 'vinix-agx-trace-v-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	hosttest.module_copy_tree(root + '/tools/agx-re/tracecore', work + '/tracecore')!
	fixturehost.write(work + '/v.mod', "Module { name: 'agx_trace' }\n")!
	fixturehost.write(work + '/entry.v', 'module main\nimport tracecore as _\n')!
	mut environment := os.environ()
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	out.command([compiler, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', arch,
		'-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree', '-o', output, work], environment)!
	text := fixturehost.read(output)!
	hosttest.module_decode_utf8(text)!
	fixturehost.write(output, '#pragma GCC diagnostic ignored "-Wunused-function"\n' + text.replace('\r\n', '\n').replace('\r', '\n'))!
}

pub fn (mut out Transcript) host_verifier(root string, machine string, encoder_reference string, verifier_reference string) ! {
	arch := hosttest.env_default('VINIX_G17_TEST_ARCH', if machine.to_lower() in [
		'arm64',
		'aarch64',
	] {
		'aarch64'
	} else {
		'x86_64'
	})
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported host architecture') }
	compiler := out.capture_output(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
		'find-v', root], os.environ())!
	common := [hosttest.env_default('CC', 'clang'), '-std=gnu11', '-O2', '-g', '-Wall', '-Wextra',
		'-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	work := private_directory('/tmp', 'vinix-g17-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	fixturehost.write(work + '/v.mod', "Module { name: 'vinix_g17_tests' }\n")!
	for name in ['agx_fake_g17.v', 'agx_fake_g17_encode.v'] {
		hosttest.module_copy_file(root + '/kernel/lib/' + name, work + '/' + name)!
	}
	mut environment := os.environ()
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	out.command([compiler, '-shared', '-no-builtin', '-os', 'vinix', '-arch',
		if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-target-libc-headers', '-nofloat',
		'-gc', 'none', '-manualfree', '-o', work + '/core.c', work], environment)!
	out.command([...common, '-Wno-unused-function', '-Wno-unused-parameter', '-ffreestanding',
		'-fno-builtin', '-fno-strict-aliasing', '-DVINIX_V_RUNTIME', '-I', root + '/kernel/c',
		'-c', work + '/core.c', '-o', work + '/core.o'], os.environ())!
	core_imports := out.capture_output(['nm', '-u', work + '/core.o'], os.environ())!
	if forbidden_imports(core_imports, false) {
		return error('unexpected allocator import in G17 verifier:\n' + core_imports)
	}
	fixture := work + '/fixture.o'
	out.compile_module(root + '/tests/agx-fake-g17/encodefixture', fixture, arch, [
		...common,
		'-fno-strict-aliasing',
		'-iquote',
		root + '/kernel/c',
	])!
	encoder_imports := out.capture_output(['nm', '-u', fixture], os.environ())!
	if forbidden_imports(encoder_imports, false) {
		return error('unexpected allocator import in G17 encoder fixture:\n' + encoder_imports)
	}
	verifier := work + '/verifier.o'
	out.compile_module(root + '/tests/agx-fake-g17/verifyfixture', verifier, arch, [
		...common,
		'-fno-strict-aliasing',
		'-iquote',
		root + '/kernel/c',
	])!
	verifier_imports := out.capture_output(['nm', '-u', verifier], os.environ())!
	if forbidden_imports(verifier_imports, true) {
		return error('unexpected allocator import in G17 verifier fixture:\n' + verifier_imports)
	}
	generated := fixturehost.read(hosttest.replace_suffix(verifier, '.c'))!
	if allocation_call_count(generated, 'calloc') != 1 || allocation_call_count(generated, 'free') != 1 {
		return error('G17 verifier fixture changed its original allocation ownership')
	}
	mut fixtures := [verifier, fixture]
	if verifier_reference != '' { fixtures << hosttest.module_resolve(verifier_reference)! }
	if encoder_reference != '' { fixtures << hosttest.module_resolve(encoder_reference)! }
	for input in fixtures {
		out.command([...common, '-iquote', root + '/kernel/c', input, work + '/core.o', '-o',
			work + '/host'], os.environ())!
		out.command([work + '/host'], os.environ())!
	}
	out.stdout += 'PASS V G17 verifier native ABI, independent encoder integration, ASan/UBSan and no allocator imports\n'
}
