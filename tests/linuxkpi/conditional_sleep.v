// SPDX-License-Identifier: GPL-2.0-or-later
// Original C predicate/call-site boundary, production V leaf and V observations.
module main

import os
import json2
import hosttest

const scope = 'Execute the real conditional-sleep V leaf with a V context spy through its generated C statement adapter. Check C scalar truth, once-only evaluation, false-path query elision, task/IRQ/pin context, fatal caller locations and no scheduling. This is focused host evidence, not a whole-kernel lifetime or hardware result.'
const production_names = ['headercore__might_sleep_if', 'vinix_might_sleep_if_native']
const fixture_file = 'conditional-sleep-callsite.v'
const fixture_line = 730

fn require(valid bool, message string) ! {
	if !valid { return error(message) }
}

// A linear scan of top-level generated functions. Only selected bodies are
// copied; no repeated whole-file tail slices or whole-kernel body enumeration.
fn bodies(raw string) []string {
	mut result := []string{}
	mut start := 0
	mut end := 0
	for end < raw.len {
		if raw[end] != `\n` { end++; continue }
		line := raw[start..end]
		if line.contains('(') && !line.contains(';') && line.ends_with(' {') {
			mut stop := end
			for stop + 1 < raw.len {
				if raw[stop] == `\n` && raw[stop + 1] == `}` {
					result << raw[start..stop + 2]
					end = stop + 2
					break
				}
				stop++
			}
		}
		end++
		start = end
	}
	return result
}

fn named(raw string, name string) !string {
	selected := bodies(raw).filter(hosttest.named_body(it, name))
	require(selected.len == 1, 'Expected exactly one generated body: ' + name)!
	return selected[0]
}

fn generation(compiler string, stage string, output string) []string {
	return [compiler, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', 'amd64',
		'-target-libc-headers', '-gc', 'none', '-manualfree', '-d', 'linuxkpi_host_test', '-o', output, stage]
}

fn select_source(raw string) !(string, int, map[string]string) {
	mut selected := []string{}
	mut hashes := map[string]string{}
	for body in bodies(raw) {
		line := body.all_before('\n')
		if hosttest.named_body(body, 'main') && !body.contains('sleepfixture__run') { continue }
		if ['headercore__', 'sleepfixture__', 'sleepspy__'].any(line.contains(it))
			|| ['vsl_fixture_entry', '_vno_main_init_caller', '_vinit', 'vinix_might_sleep_if_native',
				'vinix_linuxkpi_may_sleep', 'vinix_linuxkpi_bug', 'vsl_condition_value', 'schedule'].any(hosttest.named_body(body, it)) {
			selected << body
			hashes[line] = hosttest.text_sha(body)
		}
	}
	require(selected.len >= 18, 'Missing generated production/spy/fixture functions')!
	mut aliases := []string{}
	mut globals := []string{}
	mut constants := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && !line.contains('{') && (line.contains('Array_fixed_') || line.contains('(*_fn_ptr_')) { aliases << line }
		if line.ends_with(';') && !line.all_before('=').contains('(') && !line.starts_with('typedef ') && !line.starts_with('extern ')
			&& !line.starts_with('\t') && !line.starts_with(' ') && ['sleepspy__', '_v3_no_main_initialized'].any(line.contains(it)) { globals << line }
		if line.starts_with('#define ') && (line.starts_with('#define _S(s) ') || line.contains('sleepfixture__')) { constants << line }
	}
	decls := selected.map(it.all_before('\n').all_before_last(' {') + ';')
	mut text := '#include "contract.h"\n' +
		'typedef int8_t i8; typedef uint64_t u64; typedef int32_t i32; typedef int64_t i64; typedef size_t usize; typedef double f64; typedef void *voidptr;\n' +
		'#define E_STRUCT 0\n#define VNORETURN __attribute__((noreturn))\n' + constants.join('\n') + '\n' + aliases.join('\n') + '\n' + globals.join('\n') + '\n' + decls.join('\n') + '\n'
	mut fatal_line := 0
	for body in selected {
		if hosttest.named_body(body, 'sleepfixture__fatal_case') {
			lines := body.split_into_lines()
			for index, line in lines { if line.contains('might_sleep_if(') { fatal_line = fixture_line + index } }
			text += '#line ' + fixture_line.str() + ' "' + fixture_file + '"\n'
		}
		text += body + '\n\n'
	}
	require(fatal_line > fixture_line, 'Missing actual generated fatal predicate call')!
	require(bodies(text) == selected, 'Metadata selection changed a generated V function')!
	for body in selected {
		for allocator in ['malloc', 'calloc', 'realloc', 'memdup', 'v_malloc', 'new_array', 'array_push', 'array_clone'] {
			require(!hosttest.has_word(body, allocator), 'Allocation in selected real V production/fixture body')!
		}
	}
	return text, fatal_line, hashes
}

fn metadata_controls(work string) ![]json2.Any {
	root := hosttest.root()
	schema := os.read_file(root + '/kernel/linuxkpi/abi/overflow.json')!
	mut results := []json2.Any{}
	mutations := {
		'unknown-location': ['{"source_location": "line"}', '{"source_location": "column"}']
		'extra-location-key': ['{"source_location": "file"}', '{"source_location": "file", "address": "condition"}']
		'nonstring-location': ['{"source_location": "line"}', '{"source_location": 17}']
		'missing-location': ['{"source_location": "line"}', '{}']
		'wrong-const-pointee': ['"pointee": "char"', '"pointee": "void"']
		'extra-const-type-key': ['"pointee": "char"', '"pointee": "char", "extra": true']
		'missing-const-pointee': ['"pointee": "char"', '"missing": "char"']
	}
	for name, mutation in mutations {
		require(schema.count(mutation[0]) == 1, 'Malformed control anchor changed: ' + name)!
		path := work + '/metadata-' + name + '.json'
		output := work + '/metadata-' + name + '.h'
		os.write_file(path, schema.replace(mutation[0], mutation[1]))!
		os.write_file(output, 'existing output must survive invalid metadata\n')!
		before := hosttest.sha(output)!
		mut rejected := false
		mut diagnostic := ''
		hosttest.generate_abi(path, root + '/kernel/linuxkpi', output) or { rejected = true; diagnostic = err.msg() }
		require(rejected && diagnostic != '' && before == hosttest.sha(output)!, 'Malformed metadata accepted or output corrupted: ' + name)!
		results << json2.Any({'name': json2.Any(name), 'rejected': true, 'preserved_output_sha256': before, 'diagnostic': diagnostic, 'schema_sha256': hosttest.sha(path)!})
	}
	return results
}

fn compiler_controls(work string, compiler_v string, flags []string, env map[string]string) ![]json2.Any {
	stage := work + '/controls-stage'
	os.mkdir_all(stage + '/sleepcontrols')!
	os.cp(hosttest.root() + '/tests/linuxkpi/sleepfixture/controls.v', stage + '/sleepcontrols/core.v')!
	os.write_file(stage + '/v.mod', "Module { name: 'conditional_sleep_controls' }\n")!
	os.write_file(stage + '/entry.v', 'module main\nimport sleepcontrols as _\n')!
	generated := work + '/controls-generated.c'
	hosttest.command(generation(compiler_v, stage, generated), work + '/controls-generation.log', 120, env)!
	raw := os.read_file(generated)!
	selected := ['sleepcontrols__probe'].map(named(raw, it)!)
	decls := selected.map(it.all_before('\n').all_before_last(' {') + ';')
	mut result := []json2.Any{}
	for control, native_type in {'record': 'vsl_record', 'union': 'vsl_union', 'integer': 'int', 'pointer': 'void *', 'complex': 'vsl_complex'} {
		source := work + '/control-' + control + '.c'
		text := '#include "contract.h"\ntypedef ' + native_type + ' vsl_control;\n' + decls.join('\n') + '\n' + selected.join('\n\n') + '\n'
		os.write_file(source, text)!
		require(bodies(text) == selected, 'Compiler control changed generated V body')!
		for standard in ['gnu99', 'gnu11'] {
			name := control + '-' + standard
			object := work + '/control-' + name + '.o'
			argv := [...flags, '-std=' + standard, '-c', source, '-o', object]
			compiled := hosttest.capture(argv, object + '.log', 120, env)!
			diagnostic := compiled.stdout + compiled.stderr
			accepted := control !in ['record', 'union']
			if accepted {
				require(compiled.code == 0 && os.exists(object) && diagnostic == '', 'Scalar compiler control failed: ' + name + ': ' + diagnostic)!
			} else {
				require(compiled.code != 0 && !os.exists(object) && diagnostic.contains('incompatible type') && diagnostic.count('error:') == 1, 'Nonscalar condition did not fail solely at actual C adapter: ' + name + ': ' + diagnostic)!
			}
			result << json2.Any({'name': json2.Any(name), 'accepted': accepted, 'compiler_argv': hosttest.strings(argv), 'exit_code': compiled.code, 'generated_sha256': hosttest.sha(generated)!, 'selected_sha256': hosttest.sha(source)!, 'diagnostic_sha256': hosttest.text_sha(diagnostic), 'object_sha256': if accepted { hosttest.sha(object)! } else { '' }})
		}
	}
	return result
}

fn run(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', root + '/third_party/linux-i915/linux-6.6.157')
	pin := hosttest.upstream_pin()!
	hosttest.verify_upstream(linux, pin)!
	work := hosttest.work_dir(keep, 'vinix-conditional-sleep-v-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	mut inputs := [@FILE, root + '/kernel/linuxkpi/abi/overflow.json', root + '/kernel/linuxkpi/include/linux/kernel.h', root + '/kernel/linuxkpi/include/linux/bug.h', root + '/kernel/linuxkpi/upstream.json']
	for directory in ['kernel/linuxkpi/headercore', 'tests/linuxkpi/sleepfixture', 'tests/linuxkpi/hosttest'] {
		for extension in ['.v', '.h'] { inputs << os.walk_ext(root + '/' + directory, extension) }
	}
	compiler := os.real_path(os.find_abs_path_of_executable(hosttest.env_default('CC', 'clang'))!)
	compiler_v := os.real_path(hosttest.command(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root], '', 30, os.environ())!.stdout)
	inputs << [compiler, compiler_v, os.executable()]
	before := hosttest.hashes(inputs)!
	mut env := os.environ()
	env['V3CACHE'] = work + '/v3cache'
	env['VTMP'] = work + '/vtmp'
	env['VCACHE'] = work + '/vcache'
	os.mkdir_all(env['V3CACHE'])!
	os.mkdir_all(env['VTMP'])!
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	stage := work + '/stage'
	for directory in ['headercore', 'sleepfixture', 'sleepspy'] { os.mkdir_all(stage + '/' + directory)! }
	os.cp(root + '/kernel/linuxkpi/headercore/policy.v', stage + '/headercore/policy.v')!
	os.cp(root + '/tests/linuxkpi/sleepfixture/staging/types.v', stage + '/headercore/types.v')!
	os.cp(root + '/tests/linuxkpi/sleepfixture/core.v', stage + '/sleepfixture/core.v')!
	os.cp(root + '/tests/linuxkpi/sleepfixture/spy/core.v', stage + '/sleepspy/core.v')!
	os.write_file(stage + '/v.mod', "Module { name: 'conditional_sleep_fixture' }\n")!
	os.write_file(stage + '/entry.v', 'module main\nimport headercore as _\nimport sleepfixture as _\n')!
	generated := work + '/generated.c'
	argv := generation(compiler_v, stage, generated)
	hosttest.command(argv, work + '/generation.log', 120, env)!
	raw := os.read_file(generated)!
	text, fatal_line, selected_hashes := select_source(raw)!
	source := work + '/selected.c'
	os.write_file(source, text)!
	// Generate every actual headercore source, with its true module globals and
	// initializer. Only the borrowed conditional leaf/thunk bodies are compared.
	reference := work + '/reference'
	os.mkdir_all(reference + '/headercore')!
	for path in os.walk_ext(root + '/kernel/linuxkpi/headercore', '.v') { os.cp(path, reference + '/headercore/' + os.file_name(path))! }
	os.write_file(reference + '/v.mod', "Module { name: 'conditional_sleep_full_reference' }\n")!
	os.write_file(reference + '/entry.v', 'module main\nimport headercore as _\n')!
	reference_c := work + '/reference.c'
	hosttest.command(generation(compiler_v, reference, reference_c), work + '/reference-generation.log', 120, env)!
	reference_raw := os.read_file(reference_c)!
	mut production_hashes := map[string]string{}
	for name in [...production_names, '_vno_main_init_caller', '_vinit'] {
		body := named(raw, name)!
		require(body == named(reference_raw, name)!, 'Host changed real full-module conditional body: ' + name)!
		production_hashes[name] = hosttest.text_sha(body)
	}
	hosttest.audit_headers(work + '/abi')!
	policy := os.read_file(work + '/abi/vinix/integer_policy.h')!
	require(policy.contains('#define vinix_might_sleep_if(condition) do {') && policy.contains('vinix_might_sleep_if_native((condition), __FILE__, __LINE__);') && policy.contains('} while (0)'), 'Conditional adapter statement/source location changed')!
	mut flags := [compiler, '-O1', '-g', '-ffreestanding', '-fno-builtin', '-fwrapv', '-fno-strict-aliasing', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	$if macos { flags << ['-arch', 'x86_64'] }
	flags << ['-D__KERNEL__', '-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-include', root + '/tests/linuxkpi/host_types.h', '-include', 'linux/kconfig.h', '-include', linux + '/include/linux/compiler_types.h']
	for directory in [root + '/tests/linuxkpi/sleepfixture', work + '/abi', root + '/kernel/linuxkpi/include', linux + '/include', linux + '/include/uapi', linux + '/arch/x86/include', linux + '/arch/x86/include/uapi'] { flags << ['-I', directory] }
	flags << ['-idirafter', root + '/kernel/c']
	mut profiles := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		object := work + '/' + standard + '.o'
		depfile := object + '.d'
		preprocessed := object + '.i'
		profile := [...flags, '-std=' + standard]
		hosttest.command([...profile, '-E', '-dD', '-MD', '-MF', depfile, '-MT', object, source, '-o', preprocessed], object + '.preprocess.log', 120, env)!
		dependencies := hosttest.dependency_paths(os.read_file(depfile)!, object)!
		dependency_hashes := hosttest.hashes(dependencies)!
		hosttest.command([...profile, '-c', source, '-o', object], object + '.compile.log', 120, env)!
		require(dependency_hashes == hosttest.hashes(dependencies)!, 'Profile compiler inputs changed')!
		imports := hosttest.command(['nm', '-u', object], object + '.imports.log', 30, env)!.stdout
		require(!hosttest.allocation_symbols(imports), 'Fixture or production gained allocator imports')!
		executable := work + '/' + standard
		mut link := [compiler, '-fsanitize=address,undefined']
		$if macos { link << ['-arch', 'x86_64'] }
		link << [object, '-o', executable]
		hosttest.command(link, object + '.link.log', 120, env)!
		result := hosttest.command([executable], object + '.run.log', 120, env)!
		require(result.stdout.starts_with('PASS: conditional sleep') && result.stderr == '', 'Conditional fixture diagnosed/incomplete')!
		mut fatal := []json2.Any{}
		for mode in 1 .. 5 {
			fatal_result := hosttest.capture([executable, mode.str()], object + '.fatal-' + mode.str() + '.log', 30, env)!
			expected := 'BUG: mode=' + mode.str() + ' queries=1 conditions=1 file=' + fixture_file + ' line=' + fatal_line.str() + '\n'
			require(fatal_result.code != 0 && fatal_result.stdout == expected && !fatal_result.stderr.contains('runtime error:') && !fatal_result.stderr.contains('ERROR: AddressSanitizer'), 'Fatal predicate did not retain context/location: ' + fatal_result.stdout + fatal_result.stderr)!
			fatal << json2.Any({'mode': json2.Any(mode), 'exit_code': fatal_result.code, 'output': fatal_result.stdout, 'stderr_sha256': hosttest.text_sha(fatal_result.stderr)})
		}
		profiles << json2.Any({'standard': json2.Any(standard), 'object_sha256': hosttest.sha(object)!, 'executable_sha256': hosttest.sha(executable)!, 'preprocessed_sha256': hosttest.sha(preprocessed)!, 'dependency_sha256': hosttest.string_map(dependency_hashes), 'output': result.stdout, 'fatal_cases': fatal})
		println(standard + ': ' + result.stdout.trim_space())
	}
	controls := compiler_controls(work, compiler_v, flags, env)!
	metadata := metadata_controls(work)!
	mut accepted_controls := 0
	for control in controls { if control.as_map()['accepted']!.bool() { accepted_controls++ } }
	counts := map[string]json2.Any{
		'sanitizer_profiles': json2.Any(profiles.len)
		'safe_runtime_cases_per_profile': 31
		'false_no_query_cases_per_profile': 13
		'true_single_query_cases_per_profile': 18
		'fatal_children': profiles.len * 4
		'selected_unchanged_v_bodies': selected_hashes.len
		'full_module_identical_leaf_export_guard_and_initializer': production_hashes.len
		'compiler_controls': controls.len
		'accepted_compiler_controls': accepted_controls
		'rejected_compiler_controls': controls.len - accepted_controls
		'malformed_metadata_preservation_controls': metadata.len
	}
	require(before == hosttest.hashes(inputs)!, 'Source/fixture/compiler inputs changed')!
	hosttest.verify_upstream(linux, pin)!
	hosttest.write_json(work + '/result.json', {'scope': json2.Any(scope), 'counts': json2.Any(counts), 'source_sha256': hosttest.string_map(before), 'generation_argv': hosttest.strings(argv), 'generated_sha256': hosttest.sha(generated)!, 'selected_sha256': hosttest.sha(source)!, 'selected_body_sha256': hosttest.string_map(selected_hashes), 'reference_sha256': hosttest.sha(reference_c)!, 'production_body_sha256': hosttest.string_map(production_hashes), 'generated_policy_sha256': hosttest.sha(work + '/abi/vinix/integer_policy.h')!, 'profiles': profiles, 'compiler_controls': controls, 'metadata_controls': metadata, 'fatal_callsite_file': fixture_file, 'fatal_callsite_line': fatal_line, 'limits': hosttest.strings(['Focused V model; genuine native CPU/IRQ context and page recovery are separate checks.', 'All executed selected V bodies are unchanged; the staged initializer owns no unrelated full-headercore globals.', 'The generated statement adapter is source-checked for do/while grouping and exercised in V branches; no handwritten unbraced-C test body is executed.', 'No rescheduling, lockdep service, global allocation gate or hardware GPU support is claimed.'])})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: conditional_sleep.v [--keep-dir NEW]', scope) or { eprintln(err); exit(2) }
	run(keep) or { eprintln(err); exit(1) }
}
