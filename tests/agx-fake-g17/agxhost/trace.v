// SPDX-License-Identifier: GPL-2.0-only
module agxhost

import fixturehost
import hosttest
import traceanalysis as j
import os

fn (mut out Transcript) trace_git(root string, revision string, path string, binary bool) !string {
	if out.inherit {
		return fixturehost.capture_in_preferred(['git', 'show', revision + ':' + path], '', os.environ(), false, root, binary, out.host_arch)
	}
	return out.capture_output(['git', '-C', root, 'show', revision + ':' + path], os.environ())
}

pub fn (mut out Transcript) trace_test(root string, baseline string, temp_dir string) ! {
	cc := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	flags := ['-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-pthread']
	work := private_directory(temp_dir, 'vinix-agx-trace-test-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	core := work + '/core.c'
	out.generate_trace(root, core, 'arm64', temp_dir)!
	obj := work + '/core.o'
	out.command([...cc, ...flags, '-DVINIX_V_RUNTIME', '-DVINIX_AGX_TRACE_TEST', '-Dmalloc=vagt_test_malloc', '-Dfree=vagt_test_free',
		'-I', root + '/tools/agx-re', '-c', core, '-o', obj], os.environ())!
	imports := out.capture_output(['nm', '-u', obj], os.environ())!
	trace_assert_argument(!forbidden_imports(imports, false), j.Value(imports), false)!
	trace_assert(imports.contains('vagt_test_malloc') && imports.contains('vagt_test_free'))!
	text := fixturehost.read(core)!
	trace_assert(!text.contains('memdup') && !text.contains('new_array'))!
	binary := work + '/v-test'
	native := work + '/native.c'
	fixture := work + '/fixture.c'
	out.generate_module(root + '/tools/agx-re/nativecore', native, 'arm64', ['agx_trace_fixture'])!
	out.generate_module(root + '/tests/agx-trace/tracefixture', fixture, 'arm64', []string{})!
	for source in [native, fixture] {
		argv := [...cc, ...flags, '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter',
			'-fsanitize-address-use-after-return=always', '-c', source, '-o', hosttest.replace_suffix(source, '.o')]
		out.command_typed(argv, os.environ(), [argv.len - 3, argv.len - 1])!
	}
	native_obj := work + '/native.o'
	fixture_obj := work + '/fixture.o'
	native_imports := out.capture_output(['nm', '-u', native_obj], os.environ())!
	trace_assert_argument(!forbidden_imports(native_imports, false), j.Value(native_imports), false)!
	out.command([...cc, ...flags, fixture_obj, native_obj, obj, '-o', binary], os.environ())!
	fixturehost.write(work + '/original.c', out.trace_git(root, baseline, 'tools/agx-re/agx_trace.c', true)!)!
	mut baseline_fixture := out.trace_git(root, '8f7239d1fd4c593746279699f6ff25df5f4dd7bd', 'tests/agx-trace/host.c', false)!
	bridge := work + '/mach-bridge.c'
	bridge_api := work + '/mach-bridge-api.h'
	bridge_source := root + '/tests/agx-trace/machfixture'
	out.generate_module(bridge_source, bridge, 'arm64', []string{})!
	hosttest.emit_module_header(bridge_source, bridge, bridge_api)!
	fixture_api := work + '/fixture-api.h'
	hosttest.emit_module_header(root + '/tests/agx-trace/tracefixture', fixture, fixture_api)!
	mut allocator_lines := []string{}
	for line in fixturehost.read(fixture_api)!.split('\n') {
		if allocation_call_count(line, 'vagt_test_malloc') != 0 || allocation_call_count(line, 'vagt_test_free') != 0 { allocator_lines << line }
	}
	fixturehost.write(work + '/allocator-api.h', allocator_lines.join('\n') + '\n')!
	includes := ['<stdlib.h>', '<mach/mach.h>', '<mach/mach_vm.h>', '"allocator-api.h"', '"mach-bridge-api.h"']
	remaps := {'malloc': 'vagt_test_malloc', 'free': 'vagt_test_free', 'mach_vm_read_overwrite': 'vagt_mock_read'}
	mut prefix := includes.map('#include ' + it).join('\n') + '\n'
	mut suffix_lines := []string{}
	for name, symbol in remaps { prefix += '#define ' + name + ' ' + symbol + '\n'; suffix_lines << '#undef ' + name }
	baseline_fixture = baseline_fixture.replace('#include "../../tools/agx-re/agx_trace.c"', prefix + '#include "original.c"\n' + suffix_lines.join('\n'))
	baseline_source := work + '/reference.c'
	fixturehost.write(baseline_source, baseline_fixture)!
	reference := work + '/c-test'
	bridge_obj := work + '/mach-bridge.o'
	bridge_argv := [...cc, ...flags, '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-c', bridge, '-o', bridge_obj]
	out.command_typed(bridge_argv, os.environ(), [bridge_argv.len - 3, bridge_argv.len - 1])!
	reference_argv := [...cc, ...flags, '-I', root + '/tools/agx-re', baseline_source, bridge_obj, '-o', reference]
	out.command_typed(reference_argv, os.environ(), [reference_argv.len - 4, reference_argv.len - 3, reference_argv.len - 1])!
	for index, mode in ['normal', 'all', 'normal', 'normal'] {
		setting := ['8', '8', '999999', '0'][index]
		limit := [8, 8, 65536, 0][index]
		v_log := work + '/v-' + mode + '-' + setting + '.jsonl'
		c_log := work + '/c-' + mode + '-' + setting + '.jsonl'
		actual_report := out.capture_output([binary, v_log, mode, setting], os.environ())!
		expected_report := out.capture_output([reference, c_log, mode, setting], os.environ())!
		trace_assert_argument(actual_report == expected_report, j.Value([j.Value(actual_report), j.Value(expected_report)]), true)!
		out.stdout += actual_report.trim_space() + '\n'
		actual := trace_normalized(fixturehost.read(v_log)!)!
		expected := trace_normalized(fixturehost.read(c_log)!)!
		trace_check(actual, mode, limit)!
		trace_compare(actual, expected)!
	}
	production := work + '/production.c'
	abi_fixture := work + '/native-abi.c'
	out.generate_module(root + '/tools/agx-re/nativecore', production, 'arm64', []string{})!
	out.generate_module(root + '/tests/agx-trace/nativefixture', abi_fixture, 'arm64', []string{})!
	native_flags := [...flags, '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fsanitize-address-use-after-return=always']
	for source in [production, abi_fixture] {
		argv := [...cc, ...native_flags, '-c', source, '-o', hosttest.replace_suffix(source, '.o')]
		out.command_typed(argv, os.environ(), [argv.len - 3, argv.len - 1])!
	}
	real_core := work + '/real-core.o'
	real_argv := [...cc, ...native_flags, '-DVINIX_V_RUNTIME', '-I', root + '/tools/agx-re', '-c', core, '-o', real_core]
	out.command_typed(real_argv, os.environ(), [real_argv.len - 3, real_argv.len - 1])!
	probe := work + '/native-abi'
	probe_argv := [...cc, ...flags, work + '/native-abi.o', work + '/production.o', real_core, '-framework', 'IOKit',
		'-F/System/Library/PrivateFrameworks', '-framework', 'IOGPU', '-o', probe]
	out.command_typed(probe_argv, os.environ(), [probe_argv.len - 10, probe_argv.len - 9, probe_argv.len - 8, probe_argv.len - 1])!
	out.stdout += out.capture_typed([probe], os.environ(), [0])!.trim_space() + '\n'
	for arch in ['arm64', 'x86_64'] {
		target := work + '/native-' + arch + '.o'
		argv := [...cc, '-arch', arch, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
			'-Wno-unused-label', '-Wno-unused-parameter', '-c', production, '-o', target]
		out.command_typed(argv, os.environ(), [argv.len - 3, argv.len - 1])!
		target_imports := out.capture_typed(['nm', '-u', target], os.environ(), [2])!
		trace_assert_argument(!forbidden_imports(target_imports, false), j.Value(target_imports), false)!
		sections := out.capture_typed(['otool', '-l', target], os.environ(), [2])!
		trace_assert_argument(trace_interpose_section(sections)!, j.Value(sections), false)!
	}
	out.stdout += 'AGX trace: ASan/UBSan, explicit allocation rollback, typed driver forwarding and frozen-C JSON parity passed\n'
}
