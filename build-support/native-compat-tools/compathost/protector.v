// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import fixturehost
import guesthost
import hosttest
import os
import policyhost

fn llvm_function_attributes(ir string, name string) !string {
	for line in ir.split_into_lines() {
		if !line.starts_with('define') || !line.contains('@' + name + '(') { continue }
		start := line.index('#') or { return error('Missing LLVM attribute group: ' + name) }
		mut end := start + 1
		for end < line.len && line[end].is_digit() { end++ }
		if end == start + 1 || !line[end..].contains('{') { return error('Invalid LLVM definition: ' + name) }
		prefix := 'attributes #' + line[start + 1..end] + ' = {'
		for attribute in ir.split_into_lines() {
			if !attribute.starts_with(prefix) { continue }
			close := attribute.index('}') or { return error('Unclosed LLVM attributes: ' + name) }
			return attribute[prefix.len..close].trim_space()
		}
		return error('Missing LLVM attributes: ' + name)
	}
	return error('Missing LLVM definition: ' + name)
}

fn stack_protected(attributes string) bool {
	mut token := ''
	for byte in (attributes + ' ').bytes() {
		if byte.is_alnum() || byte == `_` { token += byte.ascii_str(); continue }
		if token in ['ssp', 'sspstrong', 'sspreq'] { return true }
		token = ''
	}
	return false
}

fn protector_command(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{ name: '--state-dir', value: true }], 0,
		'Usage: run [--state-dir FRESH-DIR]', 'Exercise production V canaries and independently check LLVM protection attributes.') or { return error_with_code(err.msg(), 2) }
	arch := os.getenv_opt('VINIX_STACK_TEST_ARCH') or { if policyhost.caller_arch() == 'arm64' { 'aarch64' } else { 'x86_64' } }
	if arch !in ['aarch64', 'x86_64'] { return error('Unsupported stack protector host architecture') }
	work := hosttest.work_dir(parsed.options['--state-dir'] or { '' }, 'vinix-stack-protector-')!
	defer { if '--state-dir' !in parsed.options { retire(work) } }
	write(work + '/v.mod', "Module { name: 'vinix_stack_protector_tests' }\n")!
	hosttest.module_copy_file_preserving_stat(root() + '/kernel/lib/stack_protector.v', work + '/protector.v')!
	write(work + '/ports.v', "module lib\nfn C.vinix_stack_test_panic(message charptr)\nfn stack_boot_entropy() u64 { return u64(0x713b38249a6255cb) }\n@[noreturn]\nfn kpanic(state voidptr, message charptr) {\n    _ = state\n    C.vinix_stack_test_panic(message)\n    for {}\n}\n")!
	v := output(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root()])!
	mut env := policyhost.environment()
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	fixturehost.inherited_command_environment_preferred([v, '-shared', '-no-builtin', '-os', 'vinix', '-arch',
		if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-target-libc-headers', '-nofloat', '-gc', 'none',
		'-manualfree', '-o', work + '/protector.c', work], env, policyhost.caller_arch())!
	common := [...compiler_prefix('CC', 'clang')!, '-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror',
		'-fstack-protector-strong', '-mstack-protector-guard=global', '-fno-omit-frame-pointer', '-iquote', root() + '/kernel/c']
	production := [...common, '-Wno-unused-function', '-Wno-unused-parameter', '-ffreestanding', '-fno-builtin', '-fno-strict-aliasing']
	run([...production, '-c', work + '/protector.c', '-o', work + '/protector.o'])!
	imports := output(['nm', '-u', work + '/protector.o'])!
	if hosttest.allocation_symbols(imports) { return error('Unexpected allocation import in stack protector:\n' + imports) }
	guesthost.compile_module(root() + '/tests/stack-protector/protectorfixture', work + '/fixture.o', arch, [...common, '-fno-strict-aliasing'])!
	run([...common, work + '/fixture.o', work + '/protector.o', '-o', work + '/host'])!
	run([work + '/host'])!
	run([...production, '-S', '-emit-llvm', work + '/protector.c', '-o', work + '/protector.ll'])!
	ir := read(work + '/protector.ll')!
	for name in ['lib__stack_guard_init', 'vinix_stack_guard_init'] {
		if stack_protected(llvm_function_attributes(ir, name)!) { return error('Initialization unexpectedly has stack protection: ' + name) }
	}
	run([...common, '-I', root() + '/tests/stack-protector/protectorfixture', '-Wno-unused-function',
		'-Wno-unused-parameter', '-S', '-emit-llvm', work + '/fixture.c', '-o', work + '/fixture.ll'])!
	fixture_ir := read(work + '/fixture.ll')!
	for name in ['main', 'protectorfixture__run', 'protectorfixture__protected_frame'] {
		attributes := llvm_function_attributes(fixture_ir, name)!
		if stack_protected(attributes) != (name == 'protectorfixture__protected_frame') { return error('Wrong independent fixture stack protection: ' + name) }
		if name.ends_with('protected_frame') && !attributes.contains('noinline') { return error('Independent protected frame may be inlined') }
	}
	println('STACK PROTECTOR PASS: allocation imports and unprotected initialization attributes')
	println('STACK PROTECTOR PASS: protected volatile V frame and unprotected caller attributes')
	return 0
}
