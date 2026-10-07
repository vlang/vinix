// SPDX-License-Identifier: GPL-2.0-or-later
// Independent host orchestration; native fixture texts remain byte-exact.
module main

import os
import json2
import strconv
import hosttest

struct Symbol {
	value u64
	size int
	section string
}

fn command(argv []string, log string, env map[string]string, success bool) !hosttest.Result {
	result := hosttest.capture(argv, '', 180, env)!
	if log != '' { os.write_file(log, hosttest.shell_join(argv) + '\n' + result.stdout + result.stderr)! }
	if success && result.code != 0 { return error('Command failed; see ${log}') }
	return result
}

fn run_command(argv []string, log string) !hosttest.Result {
	return command(argv, log, os.environ(), true)
}

fn flags(linux string, generated string, standard string, target string) []string {
	root := hosttest.root()
	here := os.join_path(root, 'kernel/linuxkpi')
	mut result := ['-std=' + standard, '-O2', '-ffreestanding', '-fwrapv', '-fno-strict-aliasing',
		'-nostdinc', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
		'-Wno-sign-compare', '-D__KERNEL__', '-DVINIX_LINUXKPI', '-include', 'linux/kconfig.h',
		'-include', os.join_path(linux, 'include/linux/compiler_types.h'), '-isystem',
		os.join_path(root, 'kernel/freestnd-c-hdrs')]
	if target != '' { result.prepend('--target=' + target) }
	for path in [generated, os.join_path(here, 'include'), os.join_path(root, 'kernel/c'),
		os.join_path(linux, 'include'), os.join_path(linux, 'include/uapi'),
		os.join_path(linux, 'arch/x86/include'), os.join_path(linux, 'arch/x86/include/uapi')] {
		result << ['-I', path]
	}
	return result
}

fn tar_source(archive string, name string) !string {
	listing := run_command(['tar', '-tvf', archive, name], '')!.stdout
	if listing.split_into_lines().len != 1 || !listing.starts_with('-') {
		return error('Original archive member is not a regular file: ${name}')
	}
	return run_command(['tar', '-xOf', archive, name], '')!.stdout
}

fn symbol_table(obj string) !(map[string]Symbol, string) {
	output := run_command([hosttest.tool('llvm-readelf'), '--symbols', '--wide', obj], '')!.stdout
	mut result := map[string]Symbol{}
	for line in output.split_into_lines() {
		columns := line.fields()
		if columns.len == 8 && columns[3] == 'OBJECT' && columns[4] == 'GLOBAL' {
			result[columns[7]] = Symbol{
				value: strconv.parse_uint(columns[1], 16, 64)!
				size: columns[2].int()
				section: columns[6]
			}
		}
	}
	return result, output
}

fn dump_rodata(obj string, work string, section string) !([]u8, json2.Any) {
	before := hosttest.sha(obj)!
	stem := os.file_name(obj).all_before_last('.')
	output := os.join_path(work, stem + section)
	derived := os.join_path(work, stem + section + '.dump-copy.o')
	run_command([hosttest.tool('llvm-objcopy'), '--dump-section', section + '=' + output,
		obj, derived], os.join_path(work, stem + section + '.dump.log'))!
	if hosttest.sha(obj)! != before { return error('Readonly dump rewrote the original compiler object') }
	return os.read_bytes(output)!, map[string]json2.Any{
		'original_sha256': json2.Any(before)
		'derived_sha256': hosttest.sha(derived)!
		'bytes_sha256': hosttest.sha(output)!
	}
}

fn strip_section(line string) string {
	if line.starts_with('__attribute__') && line.contains('section') {
		if end := line.index(')))') { return line[end + 3..].trim_left(' \t') }
	}
	return line
}

fn storage_source(raw string, stage string, storage_symbols []string) !(string, []string) {
	mut definitions := []string{}
	for symbol in storage_symbols {
		mut found := []string{}
		for line in raw.split_into_lines() {
			trimmed := strip_section(line)
			if !line.ends_with(';') { continue }
			if !['vkms_const_word ', 'struct cpumask ', 'cpumask ', 'atomic_t ', 'u32 '].any(trimmed.starts_with(it)) {
				continue
			}
			if hosttest.has_word(trimmed.all_before('='), symbol) { found << line }
		}
		if found.len != 1 {
			return error('Missing unique V-owned storage definition ${symbol}: ${found}')
		}
		definitions << found[0]
	}
	return '#include <linux/cache.h>\n#include <linux/cpumask.h>\ntypedef struct cpumask cpumask;\n' +
		hosttest.scalar_metadata(os.join_path(stage, 'headercore'), '')! + definitions.join('\n') + '\n', definitions
}

fn function_names(source string, prefix string, public_only bool) []string {
	mut result := []string{}
	for line in source.split_into_lines() {
		if !line.starts_with('pub fn ') && (public_only || !line.starts_with('fn ')) { continue }
		name := line.all_after('fn ').all_before('(')
		if name != '' && name.bytes().all(hosttest.word_char(it)) { result << prefix + name }
	}
	return result
}

fn exported_functions(source string) []string {
	mut result := []string{}
	mut export_name := ''
	for line in source.split_into_lines() {
		if line.starts_with("@[export: '") && line.ends_with("']") {
			export_name = line.all_after("@[export: '").all_before("']")
		} else if line.starts_with('@[') && !line.contains('\n') {
			continue
		} else if line.starts_with('fn ') || line.starts_with('pub fn ') {
			if export_name != '' { result << export_name }
			export_name = ''
		} else if line.trim_space() != '' {
			export_name = ''
		}
	}
	return result
}

fn unique(items []string) []string {
	mut result := []string{}
	for item in items { if item !in result { result << item } }
	return result
}

fn exact_bodies(text string, selected []string) ! {
	mut actual := hosttest.c_bodies(text)
	mut expected := selected.clone()
	actual.sort(); expected.sort()
	if actual != expected { return error('C extraction changed an actual generated body') }
}

fn section_flags(report string, index string, expected string) !string {
	for line in report.split_into_lines() {
		trimmed := line.trim_left(' \t')
		if !trimmed.starts_with('[') || !trimmed.contains(']') { continue }
		if trimmed.all_before(']')[1..].trim_space() != index { continue }
		fields := trimmed.all_after(']').fields()
		if fields.len < 4 || fields[0] != expected { return error('Original object section changed') }
		return fields[fields.len - 4]
	}
	return error('Original object section missing')
}

fn owned_helpers() []string {
	return os.walk_ext(os.join_path(os.dir(@FILE), 'hosttest'), '.v')
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	here := os.join_path(root, 'kernel/linuxkpi')
	core := os.join_path(here, 'compatcore/smp_masks.v')
	queries := os.join_path(here, 'headercore/smp_masks.v')
	storage := os.join_path(here, 'headercore/smp_masks_storage.v')
	primitives := os.join_path(root, 'kernel/c/linuxkpi_smp_masks_v_primitives.h')
	contract := os.join_path(root, 'kernel/c/linuxkpi_smp_masks_v_contract.h')
	pin := json2.decode[json2.Any](os.read_file(os.join_path(here, 'upstream.json'))!)!
	version := pin.as_map()['version']!.str()
	linux := os.real_path(hosttest.env_default('LINUXKPI_SOURCE_DIR',
		os.join_path(root, 'third_party/linux-i915/linux-' + version)))
	compiler := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	work := hosttest.work_dir(keep, 'vinix-cpu-masks-')!
	defer { if keep == '' { os.rmdir_all(work) or { eprintln(err) } } }
	mut observed := [@FILE, core, queries, storage, primitives, contract,
		os.join_path(here, 'compatcore/bitmap.v'), os.join_path(here, 'compatcore/primitives.v'),
		os.join_path(here, 'headercore/primitive.v'), os.join_path(here, 'headercore/wait.v'),
		os.join_path(here, 'include/generated/autoconf.h'), os.join_path(root, 'kernel/GNUmakefile'),
		os.join_path(root, 'kernel/c/linuxkpi_header_primitive_v_contract.h'),
		os.join_path(root, 'kernel/c/linuxkpi_common_v_contract.h'), os.join_path(root, 'build-support/compile-v-module.py'),
		os.join_path(linux, 'include/linux/cpumask.h'), os.join_path(linux, 'include/linux/smp.h'),
		os.join_path(linux, 'lib/find_bit.c'), os.join_path(linux, 'lib/hweight.c')]
	observed << owned_helpers()
	initial := hosttest.hashes(observed)!
	hosttest.write_json(os.join_path(work, 'initial-source-sha256.json'), hosttest.string_map(initial))!
	python := hosttest.env_default('PYTHON', 'python3')
	verify := run_command([python, os.join_path(here, 'upstream.py'), 'verify', '--base', os.dir(linux)],
		os.join_path(work, 'upstream-verification.log'))!
	generated := os.join_path(work, 'include')
	mut adapters := [['spinlock.json', 'spinlock_adapters.h'], ['atomic-exchange.json', 'atomic_exchange.h']]
	if os.is_file(os.join_path(here, 'abi/overflow.json')) { adapters << ['overflow.json', 'integer_policy.h'] }
	for adapter in adapters {
		run_command([python, os.join_path(here, 'generate-abi.py'), os.join_path(here, 'abi', adapter[0]),
			os.join_path(generated, 'vinix', adapter[1])], '')!
	}
	profile := flags(linux, generated, 'gnu11', 'x86_64-unknown-none')
	bounds_path := os.join_path(generated, 'generated/bounds.h')
	archive := os.join_path(os.dir(linux), 'linux-' + version + '.tar.xz')
	mut bounds_command := [python, os.join_path(here, 'generate-bounds.py'), '--source-dir', linux,
		'--archive', archive, '--output', bounds_path, '--depfile', bounds_path + '.d',
		'--provenance', bounds_path + '.json', '--cc', hosttest.shell_join(compiler), '--']
	bounds_command << profile
	run_command(bounds_command, '')!
	provenance := hosttest.decode_json(os.read_file(bounds_path + '.json')!)!
	if archive != provenance.as_map()['archive']!.str() || hosttest.sha(archive)! != provenance.as_map()['archive_sha256']!.str() {
		return error('Pinned reference archive changed')
	}
	original := tar_source(archive, 'linux-' + version + '/kernel/cpu.c')!
	warning := tar_source(archive, 'linux-' + version + '/scripts/Makefile.extrawarn')!
	if !warning.split_into_lines().any(it.trim_right(' \t\r') == 'KBUILD_CFLAGS += -Wno-sign-compare') {
		return error('Selected warning policy differs from exact original Kbuild')
	}
	os.write_file(os.join_path(work, 'original-Makefile.extrawarn'), warning)!
	os.write_file(os.join_path(work, 'original-kernel-cpu.c'), original)!
	original_storage := run_command(['git', '-C', root, 'show', original_storage_revision + ':' + original_storage_path], '')!.stdout
	os.write_file(os.join_path(work, 'original-storage.c'), original_storage)!
	begin := original.index('/* cpu_bit_bitmap[0] is empty') or { return error('Original constant bank missing') }
	end := begin + (original[begin..].index('EXPORT_SYMBOL(cpu_all_bits);') or { return error('Original all-mask export missing') }) +
		'EXPORT_SYMBOL(cpu_all_bits);'.len
	constant_source := original[begin..end]
	os.write_file(os.join_path(work, 'original-constants.c'), '#include <linux/cpumask.h>\n#include <linux/export.h>\n' + constant_source + '\n')!
	for name, text in {'cold': type_checks, 'references': references, 'fixture': fixture, 'runner': runner} {
		os.write_file(os.join_path(work, name + '.c'), text)!
	}
	if !os.read_file(os.join_path(root, 'kernel/GNUmakefile'))!.contains('-fno-strict-aliasing') {
		return error('Native compiler alias policy changed')
	}
	stage := os.join_path(work, 'stage')
	for module_name in ['compatcore', 'headercore'] { os.mkdir_all(os.join_path(stage, module_name))! }
	os.write_file(os.join_path(stage, 'v.mod'), "Module { name: 'cpu_mask_probe' }\n")!
	os.write_file(os.join_path(stage, 'entry.v'), 'module main\nimport compatcore as _\nimport headercore as _\nfn main() {}\n')!
	os.cp(core, os.join_path(stage, 'compatcore/smp_masks.v'))!
	os.cp(queries, os.join_path(stage, 'headercore/smp_masks.v'))!
	os.cp(storage, os.join_path(stage, 'headercore/smp_masks_storage.v'))!
	weight := hosttest.v_function(os.read_file(os.join_path(here, 'compatcore/bitmap.v'))!, 'bitmap_weight')!
	hweight := hosttest.v_function(os.read_file(os.join_path(here, 'compatcore/primitives.v'))!, 'native_hweight_long')!
	os.write_file(os.join_path(stage, 'compatcore/weight.v'), '@[translated]\nmodule compatcore\n' + weight + hweight)!
	atomic_body := hosttest.v_function(os.read_file(os.join_path(here, 'headercore/primitive.v'))!, 'atomic_read')!
	os.write_file(os.join_path(stage, 'headercore/bindings.v'), '@[translated]\nmodule headercore\n' +
		'#include "linuxkpi_header_primitive_v_contract.h"\n@[typedef]\nstruct C.atomic_t { counter i32 }\n' +
		'@[typedef]\nstruct C.vhp_const_atomicp {}\nfn C.test_bit(i32,voidptr) bool\n' +
		"@[c: '__atomic_load_n']\nfn C.vhp_load32(&i32,i32) i32\n" + atomic_body)!
	v_selection := hosttest.env_default('V', 'v')
	v := os.real_path(os.find_abs_path_of_executable(v_selection) or { v_selection })
	native_c := os.join_path(work, 'actual-v.c')
	mut environment := os.environ()
	environment['VCACHE'] = os.join_path(work, 'vcache')
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	generation := [v, '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', 'amd64',
		'-target-libc-headers', '-gc', 'none', '-manualfree', '-o', native_c, stage]
	command(generation, os.join_path(work, 'generation.log'), environment, true)!
	mut rejection_cases := []json2.Any{}
	metadata_probe := os.join_path(work, 'metadata-rejections')
	os.mkdir(metadata_probe)!
	case_names := ['unknown-type', 'invalid-identifier', 'missing-foreign-type', 'duplicate-alias', 'compiler-conflict']
	case_sources := [valid_metadata.replace('const_unsigned_long_64', 'writable_word'),
		valid_metadata.replace('probe_word const', 'probe_word; const'), valid_metadata.all_before('@[typedef]'),
		valid_metadata, valid_metadata]
	for index, name in case_names {
		case_path := os.join_path(metadata_probe, name)
		os.mkdir(case_path)!
		os.write_file(os.join_path(case_path, 'a.v'), case_sources[index])!
		if name == 'duplicate-alias' { os.write_file(os.join_path(case_path, 'b.v'), case_sources[index])! }
		text := if name == 'compiler-conflict' { 'typedef unsigned long probe_word;' } else { '' }
		hosttest.scalar_metadata(case_path, text) or {
			rejection_cases << json2.Any(map[string]json2.Any{'case': json2.Any(name), 'error': err.msg()})
			continue
		}
		return error('Invalid scalar producer metadata was accepted: ${name}')
	}
	raw := hosttest.scalar_metadata(os.join_path(stage, 'headercore'), os.read_file(native_c)!)!
	os.write_file(native_c, raw)!
	host_c := os.join_path(work, 'actual-host-v.c')
	mut host_generation := generation[..generation.len - 3].clone()
	host_generation << ['-d', 'linuxkpi_host_test', '-o', host_c, stage]
	command(host_generation, os.join_path(work, 'host-generation.log'), environment, true)!
	host_raw := hosttest.scalar_metadata(os.join_path(stage, 'headercore'), os.read_file(host_c)!)!
	os.write_file(host_c, host_raw)!
	storage_symbols := ['cpu_bit_bitmap', 'cpu_all_bits', '__cpu_possible_mask', '__cpu_online_mask',
		'__cpu_present_mask', '__cpu_active_mask', '__cpu_dying_mask', '__num_online_cpus', 'nr_cpu_ids']
	data_source, data_definitions := storage_source(raw, stage, storage_symbols)!
	host_data_source, host_data_definitions := storage_source(host_raw, stage, storage_symbols)!
	if data_definitions.map(strip_section(it)) != host_data_definitions {
		return error('Host profile changed V-owned storage types/initializers')
	}
	os.write_file(os.join_path(work, 'data.c'), data_source)!
	os.write_file(os.join_path(work, 'host-data.c'), host_data_source)!
	mut staged_paths := os.walk_ext(stage, '.v')
	staged_paths.sort()
	mut staged_sources := []string{}
	for path in staged_paths { staged_sources << os.read_file(path)! }
	core_internal := function_names(os.read_file(core)!, 'compatcore__', true)
	query_internal := function_names(os.read_file(queries)!, 'headercore__', false)
	mut names := exported_functions(staged_sources.join('\n'))
	names << core_internal
	names << query_internal
	names << ['compatcore__native_hweight_long', 'compatcore__bitmap_weight', 'headercore__atomic_read']
	names = unique(names)
	mut bodies := map[string]string{}
	for name in names {
		body := hosttest.extract_body(raw, name)!
		for allocator in ['malloc', 'calloc', 'realloc', 'memdup', 'v_malloc', 'new_array', 'array_clone', 'array_push'] {
			if hosttest.has_word(body, allocator) { return error('Actual selected generated mask body allocates') }
		}
		bodies[name] = body
	}
	ready := raw.split_into_lines().filter(it.starts_with('u32 compatcore__vkms_ready') && it.ends_with(';'))
	if ready.len == 0 { return error('Missing genuine zero-initialized ready slot') }
	mut core_names := names.filter(it.starts_with('vkm_cpu_masks'))
	core_names << core_internal
	core_names = unique(core_names)
	weight_names := ['compatcore__native_hweight_long', 'compatcore__bitmap_weight', '__bitmap_weight']
	query_names := names.filter(it !in core_names && it !in weight_names)
	query_prefix := c_prefix.replace('typedef uint32_t u32; ', '')
	mut body_sources := map[string]string{}
	mut selections := map[string][]string{}
	for group, selected in {'core': core_names, 'weight': weight_names, 'queries': query_names} {
		mut sorted := selected.clone(); sorted.sort()
		picked := sorted.map(bodies[it])
		selections[group] = picked
		front := if group == 'core' {
			c_prefix + '#include "linuxkpi_smp_masks_v_primitives.h"\n' + ready[0] + '\n'
		} else if group == 'weight' { c_prefix } else {
			query_prefix + '#include "linuxkpi_header_primitive_v_contract.h"\n' +
			'#include "linuxkpi_smp_masks_v_contract.h"\n' +
			'_Static_assert(__builtin_types_compatible_p(u32,uint32_t), "identical native scalar alias");\n'
		}
		text := front + hosttest.c_declarations(raw, sorted)! + picked.join('\n\n') + '\n'
		exact_bodies(text, picked)!
		body_sources[group] = text
		os.write_file(os.join_path(work, group + '.c'), text)!
	}
	mut foreign := []string{}
	for path, expected in {
		contract: 'typedef const struct cpumask *vkms_const_cpumask;'
		os.join_path(root, 'kernel/c/linuxkpi_header_primitive_v_contract.h'): 'typedef const atomic_t *vhp_const_atomicp;'
	} {
		if expected !in os.read_file(path)!.split_into_lines() { return error('Actual foreign alias changed') }
		foreign << expected
	}
	contract_text := os.read_file(contract)!
	for name in ['vkms_all_mask', 'vkms_const_bits'] {
		found := contract_text.split_into_lines().filter(it.starts_with('#define ' + name + '('))
		if found.len == 0 { return error('Actual original query alias changed') }
		foreign << found[0]
	}
	mut sorted_queries := query_names.clone(); sorted_queries.sort()
	host_query_source := query_prefix.replace('typedef uint64_t u64; ', '') +
		'#include <linux/cpumask.h>\n#include "linuxkpi_smp_masks_v_primitives.h"\n' +
		foreign.join('\n') + '\n' + hosttest.c_declarations(raw, sorted_queries)! +
		sorted_queries.map(bodies[it]).join('\n\n') + '\n'
	exact_bodies(host_query_source, selections['queries'])!
	os.write_file(os.join_path(work, 'host-queries.c'), host_query_source)!
	host_include := os.join_path(work, 'host-include')
	os.mkdir_all(os.join_path(host_include, 'asm'))!
	os.write_file(os.join_path(host_include, 'asm/cache.h'), host_cache_adapter)!
	os.mkdir(os.join_path(host_include, 'linux'))!
	os.write_file(os.join_path(host_include, 'linux/compiler_attributes.h'), host_section_adapter)!
	run_compiler_profiles(work, linux, generated, compiler, host_include, storage_symbols,
		initial, observed, provenance, verify.stdout.trim_space(), constant_source, original_storage,
		v, generation, native_c, bodies, data_definitions, host_data_definitions, rejection_cases, foreign)!
}

fn run_compiler_profiles(work string, linux string, generated string, compiler []string,
	host_include string, storage_symbols []string, initial map[string]string,
	observed []string, provenance json2.Any, verification string, constant_source string,
	original_storage string, v string, generation []string, native_c string,
	bodies map[string]string, data_definitions []string, host_data_definitions []string,
	rejection_cases []json2.Any, foreign []string) ! {
	root := hosttest.root()
	mut proofs := []json2.Any{}
	mut runtime := []json2.Any{}
	mut final_mutable_bytes := map[string]json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		native_flags := flags(linux, generated, standard, 'x86_64-unknown-none')
		mut objects := map[string]string{}
		allowed := {
			'cold': []string{}
			'data': []string{}
			'original-data': []string{}
			'original-storage': []string{}
			'weight': []string{}
			'core': ['vkm_cpu_ids_storage', 'vkm_mask_storage', 'vkm_online_storage']
			'queries': ['__cpu_possible_mask', '__cpu_online_mask', '__cpu_present_mask',
				'__cpu_active_mask', '__cpu_dying_mask', '__num_online_cpus', 'nr_cpu_ids',
				'cpu_bit_bitmap', 'cpu_all_bits', 'vkm_cpu_masks_ready', '__bitmap_weight']
			'references': ['total_cpus', 'cpus_booted_once_mask', 'set_cpu_online', 'init_cpu_present',
				'init_cpu_possible', 'init_cpu_online', 'smp_call_function_single']
		}
		names := ['cold', 'references', 'data', 'original-data', 'original-storage', 'core', 'queries', 'weight']
		sources := ['cold.c', 'references.c', 'data.c', 'original-constants.c', 'original-storage.c', 'core.c', 'queries.c', 'weight.c']
		for index, name in names {
			obj := os.join_path(work, '${standard}-native-${name}.o')
			mut argv := compiler.clone(); argv << native_flags
			argv << ['-c', os.join_path(work, sources[index]), '-o', obj]
			run_command(argv, hosttest.replace_suffix(obj, '.log'))!
			objects[name] = obj
			imports := run_command([hosttest.tool('llvm-nm'), '--undefined-only', obj], '')!.stdout
			mut actual_imports := unique(imports.split_into_lines().filter(it.trim_space() != '').map(it.fields().last()))
			mut expected := allowed[name].clone(); expected.sort(); actual_imports.sort()
			if actual_imports != expected { return error('Genuine native imports changed for ${name}: ${imports}') }
			proofs << json2.Any(map[string]json2.Any{
				'standard': json2.Any(standard)
				'variant': name
				'argv': hosttest.strings(argv)
				'object_sha256': hosttest.sha(obj)!
				'undefined_symbols': imports
			})
		}
		cold_symbols := run_command([hosttest.tool('llvm-nm'), objects['cold']], '')!.stdout
		if cold_symbols.trim_space() != '' { return error('Cold original declarations created storage/runtime') }
		mut constants := map[string]map[string]string{}
		mut storage_inventory := map[string]map[string]string{}
		mut mutable_bytes := map[string]map[string]string{}
		for name in ['data', 'original-data', 'original-storage'] {
			symbols, table := symbol_table(objects[name])!
			data, receipt := dump_rodata(objects[name], work, '.rodata')!
			section_report := run_command([hosttest.tool('llvm-readelf'), '--sections', '--wide', objects[name]], '')!.stdout
			mut values := map[string]string{}
			if name in ['data', 'original-storage'] {
				expected_sizes := {
					'cpu_bit_bitmap': 2080
					'cpu_all_bits': 32
					'__cpu_possible_mask': 32
					'__cpu_online_mask': 32
					'__cpu_present_mask': 32
					'__cpu_active_mask': 32
					'__cpu_dying_mask': 32
					'__num_online_cpus': 4
					'nr_cpu_ids': 4
				}
				mut actual_sizes := map[string]int{}
				mut inventory := map[string]string{}
				for key, value in symbols {
					actual_sizes[key] = value.size
					alignment := if value.size >= 32 { 8 } else { 4 }
					inventory[key] = '${value.size}:${value.value % u64(alignment)}'
				}
				if actual_sizes != expected_sizes { return error('Real storage-only CPU-mask symbol inventory changed') }
				if hosttest.has_word(table, 'FUNC') || run_command([hosttest.tool('llvm-nm'), '--undefined-only', objects[name]], '')!.stdout.trim_space() != '' {
					return error('Constant/storage translation unit contains code or runtime imports')
				}
				storage_inventory[name] = inventory
				relocations := run_command([hosttest.tool('llvm-readelf'), '--relocations', objects[name]], '')!.stdout
				if !relocations.contains('There are no relocations') { return error('Permanent V/original storage acquired relocations') }
				payload, _ := dump_rodata(objects[name], work, '.data..read_mostly')!
				mut mutable := map[string]string{}
				for symbol in storage_symbols[2..] {
					field := symbols[symbol]
					if !section_flags(section_report, field.section, '.data..read_mostly')!.contains('W') {
						return error('Original writable storage section changed: ${symbol}')
					}
					value := payload[int(field.value)..int(field.value) + field.size]
					mut expected := []u8{len: field.size}
					if symbol == 'nr_cpu_ids' { expected[1] = 1 }
					if value != expected { return error('Original permanent storage cold bytes changed: ${symbol}') }
					mutable[symbol] = value.hex()
				}
				mutable_bytes[name] = mutable
			}
			for index, symbol in ['cpu_bit_bitmap', 'cpu_all_bits'] {
				size := [2080, 32][index]
				field := symbols[symbol]
				if field.size != size || section_flags(section_report, field.section, '.rodata')!.contains('W') {
					return error('Original constants are not exact readonly objects')
				}
				values[symbol] = hosttest.text_sha(data[int(field.value)..int(field.value) + size].bytestr())
			}
			constants[name] = values
			proofs << json2.Any(map[string]json2.Any{
				'standard': json2.Any(standard)
				'variant': name + '-readonly'
				'symbols': table
				'sections': section_report
				'constant_sha256': hosttest.string_map(values)
				'dump': receipt
			})
		}
		if constants['data'] != constants['original-data'] || constants['data'] != constants['original-storage'] {
			return error('Production readonly constant bytes differ from actual pinned definitions')
		}
		if storage_inventory['data'] != storage_inventory['original-storage'] {
			return error('V/original permanent storage symbol size/alignment differs')
		}
		if mutable_bytes['data'] != mutable_bytes['original-storage'] {
			return error('V/original permanent storage bytes differ')
		}
		final_mutable_bytes = map[string]json2.Any{}
		for name, value in mutable_bytes { final_mutable_bytes[name] = hosttest.string_map(value) }
		native_alias := os.join_path(work, '${standard}-native-word-alias.c')
		os.write_file(native_alias, type_checks + '\n_Static_assert(__builtin_types_compatible_p(uint64_t,unsigned long),"native scalar view exact alias");\n')!
		mut alias_argv := compiler.clone(); alias_argv << native_flags; alias_argv << ['-fsyntax-only', native_alias]
		run_command(alias_argv, hosttest.replace_suffix(native_alias, '.log'))!
		for name, wrong in {
			'wrong-table': 'extern const unsigned long cpu_bit_bitmap[256][4];'
			'wrong-counter': 'extern uint64_t __num_online_cpus;'
		} {
			source := os.join_path(work, '${standard}-${name}.c')
			os.write_file(source, type_checks + wrong + '\n')!
			mut argv := compiler.clone(); argv << native_flags; argv << ['-fsyntax-only', source]
			rejected := command(argv, hosttest.replace_suffix(source, '.log'), os.environ(), false)!
			if rejected.code == 0 || !rejected.stderr.contains('different type') {
				return error('Wrong original storage declaration was accepted')
			}
		}
		mut host_flags := ['-I', host_include]
		host_flags << flags(linux, generated, standard, '')
		host_flags << ['-O1', '-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
		mut host_objects := []string{}
		host_names := ['core', 'queries', 'weight', 'data', 'fixture', 'find-bit', 'hweight']
		host_sources := [os.join_path(work, 'core.c'), os.join_path(work, 'host-queries.c'),
			os.join_path(work, 'weight.c'), os.join_path(work, 'host-data.c'), os.join_path(work, 'fixture.c'),
			os.join_path(linux, 'lib/find_bit.c'), os.join_path(linux, 'lib/hweight.c')]
		for index, name in host_names {
			obj := os.join_path(work, '${standard}-host-${name}.o')
			mut argv := compiler.clone(); argv << host_flags; argv << ['-c', host_sources[index], '-o', obj]
			run_command(argv, hosttest.replace_suffix(obj, '.log'))!
			host_objects << obj
		}
		runner_obj := os.join_path(work, '${standard}-runner.o')
		mut runner_argv := compiler.clone()
		runner_argv << ['-std=' + standard, '-O1', '-g', '-Wall', '-Wextra', '-Werror',
			'-iquote', os.join_path(root, 'kernel/c'), '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
			'-c', os.join_path(work, 'runner.c'), '-o', runner_obj]
		run_command(runner_argv, hosttest.replace_suffix(runner_obj, '.log'))!
		original_host_data := os.join_path(work, '${standard}-host-original-storage.o')
		mut original_argv := compiler.clone(); original_argv << host_flags
		original_argv << ['-c', os.join_path(work, 'original-storage.c'), '-o', original_host_data]
		run_command(original_argv, hosttest.replace_suffix(original_host_data, '.log'))!
		mut variant_totals := []i64{}
		for variant in ['V', 'original-C'] {
			mut selected_objects := host_objects.clone()
			if variant == 'original-C' { selected_objects[3] = original_host_data }
			executable := os.join_path(work, '${standard}-${variant}-runtime')
			mut link := compiler.clone(); link << '-fsanitize=address,undefined'; link << selected_objects
			link << [runner_obj, '-pthread', '-o', executable]
			run_command(link, hosttest.replace_suffix(executable, '.link.log'))!
			mut total := i64(0)
			count_cases := [u64(1), 2, 4, 63, 64, 65, 127, 128, 129, 191, 192, 193, 255, 256, 0, 257, 0xffffffff]
			for count in count_cases {
				mut env := os.environ(); env['UBSAN_OPTIONS'] = 'halt_on_error=1'
				env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'
				result := command([executable, count.str()],
					os.join_path(work, '${standard}-${variant}-count-${count}.log'), env, true)!
				ending := ' original mask/publisher assertions (count=${count})\n'
				if !result.stdout.starts_with('PASS: ') || !result.stdout.ends_with(ending) || result.stderr != '' {
					return error('Unclean original mask sanitizer execution')
				}
				digits := result.stdout[6..result.stdout.len - ending.len]
				if digits == '' || !digits.bytes().all(it.is_digit()) { return error('Unclean original mask sanitizer execution') }
				total += digits.i64()
			}
			variant_totals << total
			mut object_hashes := map[string]string{}
			for path in selected_objects { object_hashes[path] = hosttest.sha(path)! }
			runtime << json2.Any(map[string]json2.Any{
				'standard': json2.Any(standard)
				'storage_variant': variant
				'assertions': total
				'process_count': count_cases.len
				'count_cases': count_cases.map(json2.Any(it))
				'executable_sha256': hosttest.sha(executable)!
				'actual_objects': hosttest.string_map(object_hashes)
				'scope': 'Separate cold processes and joined immutable reader actors; no live reset/constructor races/native CPU execution'
			})
			println('${standard} ${variant}: ${total} clean original mask and unchanged V publisher assertions')
		}
		if variant_totals[0] != variant_totals[1] { return error('Original-C/V storage assertion totals differ') }
	}
	if initial != hosttest.hashes(observed)! { return error('Owned source/profile changed during isolated validation') }
	for item in proofs {
		entry := item.as_map()
		if 'object_sha256' in entry {
			obj := os.join_path(work, entry['standard']!.str() + '-native-' + entry['variant']!.str() + '.o')
			if hosttest.sha(obj)! != entry['object_sha256']!.str() { return error('Saved native object differs from recorded compiler hash') }
		}
	}
	mut selected_body_hashes := map[string]string{}
	for name, body in bodies { selected_body_hashes[name] = hosttest.text_sha(body) }
	hosttest.write_json(os.join_path(work, 'result.json'), json2.Any(map[string]json2.Any{
		'scope': json2.Any(scope)
		'source_sha256': hosttest.string_map(initial)
		'bounds': provenance
		'upstream_verification': verification
		'original_cpu_source_sha256': hosttest.sha(os.join_path(work, 'original-kernel-cpu.c'))!
		'original_constant_block_sha256': hosttest.text_sha(constant_source)
		'pinned_warning_policy_sha256': hosttest.sha(os.join_path(work, 'original-Makefile.extrawarn'))!
		'v': v
		'v_sha256': hosttest.sha(v)!
		'generation_argv': hosttest.strings(generation)
		'generated_c_sha256': hosttest.sha(native_c)!
		'actual_selected_body_sha256': hosttest.string_map(selected_body_hashes)
		'original_storage_revision': original_storage_revision
		'original_storage_path': original_storage_path
		'original_storage_sha256': hosttest.text_sha(original_storage)
		'actual_storage_definitions': hosttest.strings(data_definitions)
		'host_storage_definitions': hosttest.strings(host_data_definitions)
		'native_storage_cold_bytes': final_mutable_bytes
		'producer_metadata_rejections': rejection_cases
		'native_proofs': proofs
		'runtime': runtime
		'host_foreign_aliases': hosttest.strings(foreign)
		'host_cache_metadata_adapter_sha256': hosttest.sha(os.join_path(host_include, 'asm/cache.h'))!
		'host_section_metadata_adapter_sha256': hosttest.sha(os.join_path(host_include, 'linux/compiler_attributes.h'))!
		'strict_query_scaffold': 'Original Linux owns the identical u32 typedef; all selected native/host bodies remain byte-identical'
		'alias_policy': 'Actual kernel -fno-strict-aliasing on host; genuine x86 uint64_t/unsigned-long type identity explicitly compiled'
	}))!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'usage: cpu_masks.v [--keep-dir KEEP_DIR]', scope) or {
		eprintln(err); exit(2)
	}
	run_profile(keep) or { eprintln(err); exit(1) }
}

const scope = 'Execute the unchanged V boot-mask publisher and original Linux mask queries.

The original struct, atomic counter, constant objects and bitmap helpers retain
their real owners. Private host processes supply cold storage for each case;
there is no production reset, concurrent constructor, CPU hotplug or SMP call
implementation. Numerical CPU65/255 coverage does not boot those CPUs.
TLS caller-state values are host observers; native IRQ/migration behavior needs
the separate full kernel fixture. Native objects reject context/allocator imports.
Private Mach-O scaffolding adjusts only ELF section metadata and borrows the
actual foreign type/query aliases; full native contracts compile separately.
'

const type_checks = '
#include <linux/cpumask.h>
#include "linuxkpi_smp_masks_v_primitives.h"
_Static_assert(NR_CPUS == 256 && BITS_PER_LONG == 64 &&
    sizeof(struct cpumask) == 32 && _Alignof(struct cpumask) == 8,
    "original complete four-word CPU mask");
_Static_assert(sizeof(cpu_bit_bitmap) == 2080 && sizeof(cpu_all_bits) == 32,
    "original compressed constants");
_Static_assert(offsetof(struct cpumask, bits) == 0 &&
    __builtin_types_compatible_p(__typeof__(((struct cpumask *)0)->bits), unsigned long[4]),
    "original bitmap word type");
_Static_assert(__builtin_types_compatible_p(__typeof__(__cpu_possible_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_online_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_present_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_active_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_dying_mask), struct cpumask),
    "genuine five original objects");
_Static_assert(sizeof(atomic_t) == 4 && offsetof(atomic_t, counter) == 0 &&
    __builtin_types_compatible_p(__typeof__(__num_online_cpus), atomic_t) &&
    __builtin_types_compatible_p(__typeof__(__num_online_cpus.counter), int) &&
    __builtin_types_compatible_p(__typeof__(nr_cpu_ids), unsigned int),
    "genuine original count fields");
#if defined(CONFIG_HOTPLUG_CPU) || defined(CONFIG_CPUMASK_OFFSTACK)
#error This test establishes only permanent native boot masks
#endif
'

const fixture = '
#include <linux/cpumask.h>
#include "linuxkpi_smp_masks_v_primitives.h"
_Static_assert(NR_CPUS == 256 && BITS_PER_LONG == 64 &&
    sizeof(struct cpumask) == 32 && _Alignof(struct cpumask) == 8,
    "original complete four-word CPU mask");
_Static_assert(sizeof(cpu_bit_bitmap) == 2080 && sizeof(cpu_all_bits) == 32,
    "original compressed constants");
_Static_assert(offsetof(struct cpumask, bits) == 0 &&
    __builtin_types_compatible_p(__typeof__(((struct cpumask *)0)->bits), unsigned long[4]),
    "original bitmap word type");
_Static_assert(__builtin_types_compatible_p(__typeof__(__cpu_possible_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_online_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_present_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_active_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_dying_mask), struct cpumask),
    "genuine five original objects");
_Static_assert(sizeof(atomic_t) == 4 && offsetof(atomic_t, counter) == 0 &&
    __builtin_types_compatible_p(__typeof__(__num_online_cpus), atomic_t) &&
    __builtin_types_compatible_p(__typeof__(__num_online_cpus.counter), int) &&
    __builtin_types_compatible_p(__typeof__(nr_cpu_ids), unsigned int),
    "genuine original count fields");
#if defined(CONFIG_HOTPLUG_CPU) || defined(CONFIG_CPUMASK_OFFSTACK)
#error This test establishes only permanent native boot masks
#endif

extern void mask_check(bool, int);
#define CHECK(value) mask_check((value), __LINE__)
static struct cpumask *original_mask(unsigned kind) {
    switch (kind) {
    case 0: return &__cpu_possible_mask;
    case 1: return &__cpu_online_mask;
    case 2: return &__cpu_present_mask;
    case 3: return &__cpu_active_mask;
    case 4: return &__cpu_dying_mask;
    default: return NULL;
    }
}
static unsigned long expected_word(unsigned count, unsigned word) {
    unsigned long value = 0;
    for (unsigned bit = 0; bit < 64; ++bit)
        if (word * 64 + bit < count) value |= 1UL << bit;
    return value;
}
static unsigned long poison_word(unsigned kind, unsigned word) {
    return 0xfedcba9876543210UL ^ ((unsigned long)kind << 12) ^ word;
}
void mask_poison(void) {
    for (unsigned kind = 0; kind < 5; ++kind)
        for (unsigned word = 0; word < 4; ++word)
            original_mask(kind)->bits[word] = poison_word(kind, word);
    __num_online_cpus.counter = 0x12345678;
    nr_cpu_ids = 0x23456789;
}
void mask_poison_unchanged(void) {
    for (unsigned kind = 0; kind < 5; ++kind)
        for (unsigned word = 0; word < 4; ++word)
            CHECK(original_mask(kind)->bits[word] == poison_word(kind, word));
    CHECK(__num_online_cpus.counter == 0x12345678);
    CHECK(nr_cpu_ids == 0x23456789);
}
void mask_initial_state(void) {
    CHECK(!vkm_cpu_masks_ready()); CHECK(nr_cpu_ids == 256);
    CHECK(__num_online_cpus.counter == 0);
    CHECK(vkm_cpu_ids() == 0 && vkm_online_count() == 0);
    for (unsigned kind = 0; kind < 5; ++kind) {
        CHECK(vkm_mask_storage(kind) == original_mask(kind)->bits);
        CHECK(vkm_mask_weight(kind) == 0);
        for (unsigned word = 0; word < 4; ++word)
            CHECK(original_mask(kind)->bits[word] == 0);
        for (unsigned cpu = 0; cpu < 256; ++cpu) CHECK(!vkm_mask_has(kind,cpu));
    }
    CHECK(vkm_mask_storage(5) == NULL && vkm_mask_storage(~0U) == NULL);
    CHECK(vkm_cpu_ids_storage() == &nr_cpu_ids);
    CHECK(vkm_online_storage() == &__num_online_cpus.counter);
}
void mask_constants(void) {
    const struct cpumask *static_all = cpu_all_mask;
    const struct cpumask *static_none = cpu_none_mask;
    CHECK(static_all->bits == cpu_all_bits);
    CHECK(static_none->bits == cpu_bit_bitmap[0]);
    for (unsigned word = 0; word < 4; ++word) {
        CHECK(static_all->bits[word] == ~0UL);
        CHECK(static_none->bits[word] == 0);
    }
    for (unsigned selected = 0; selected < 256; ++selected) {
        const struct cpumask *one = cpumask_of(selected);
        /* Address arithmetic spans the complete original compressed table,
         * rather than subtracting beyond a C array-row object in the oracle. */
        uintptr_t expected_address = (uintptr_t)&cpu_bit_bitmap[0][0] +
            (4 * (1 + selected%64) - selected/64) * sizeof(unsigned long);
        CHECK((uintptr_t)one->bits == expected_address);
        CHECK(cpumask_of(selected) == one);
        struct cpumask copied;
        cpumask_copy(&copied,one);
        for (unsigned word = 0; word < 4; ++word) {
            unsigned long value = word == selected/64 ? 1UL << (selected%64) : 0;
            CHECK(one->bits[word] == value && copied.bits[word] == value);
        }
        cpumask_clear(&copied);
        for (unsigned word = 0; word < 4; ++word) CHECK(copied.bits[word] == 0);
        for (unsigned cpu = 0; cpu < 256; ++cpu) {
            CHECK(vkm_mask_of_has(selected,cpu) == (selected == cpu));
            CHECK(vkm_all_has(cpu));
            CHECK(!test_bit(cpu,static_none->bits));
        }
    }
    const unsigned invalid[] = {256,257,0xffffffffU};
    for (unsigned i=0;i<3;++i) {
        CHECK(!vkm_all_has(invalid[i]));
        CHECK(!vkm_mask_of_has(invalid[i],0));
        CHECK(!vkm_mask_of_has(0,invalid[i]));
        CHECK(!vkm_mask_of_has(invalid[i],invalid[i]));
    }
}
void mask_contents(unsigned count) {
    CHECK(vkm_cpu_masks_ready()); CHECK(vkm_cpu_ids()==count);
    CHECK(vkm_online_count()==count && num_online_cpus()==count);
    CHECK(nr_cpu_ids==count && __num_online_cpus.counter==(int)count);
    for (unsigned kind=0;kind<5;++kind) {
        const struct cpumask *mask=original_mask(kind);
        CHECK(vkm_mask_weight(kind)==(kind==4 ? 0 : count));
        CHECK(cpumask_weight(mask)==(kind==4 ? 0 : count));
        for (unsigned word=0;word<4;++word)
            CHECK(mask->bits[word]==(kind==4 ? 0 : expected_word(count,word)));
        for (unsigned cpu=0;cpu<257;++cpu)
            CHECK(vkm_mask_has(kind,cpu)==(kind!=4 && cpu<count));
        CHECK(!vkm_mask_has(kind,0xffffffffU));
        unsigned seen=0,cpu;
        for_each_cpu(cpu,mask) { CHECK(kind!=4 && cpu==seen && cpu<count); ++seen; }
        CHECK(seen==(kind==4 ? 0 : count));
        CHECK(cpumask_first(mask)==(kind==4 ? count : 0));
        CHECK(cpumask_next((int)count-1,mask)==count);
    }
    CHECK(vkm_mask_weight(5)==0 && vkm_mask_weight(0xffffffffU)==0);
    CHECK(!vkm_mask_has(5,0) && !vkm_mask_has(0xffffffffU,0));
    unsigned seen=0,cpu;
    for_each_online_cpu(cpu) { CHECK(cpu==seen); ++seen; } CHECK(seen==count);
    seen=0; for_each_possible_cpu(cpu) { CHECK(cpu==seen); ++seen; } CHECK(seen==count);
    seen=0; for_each_present_cpu(cpu) { CHECK(cpu==seen); ++seen; } CHECK(seen==count);
}
void mask_reader_batch(unsigned count,unsigned rounds) {
    for (unsigned iteration=0;iteration<rounds;++iteration) {
        CHECK(vkm_cpu_masks_ready()); CHECK(vkm_cpu_ids()==count);
        CHECK(vkm_online_count()==count);
        unsigned selected=(iteration*73)%256;
        for (unsigned kind=0;kind<5;++kind) {
            CHECK(vkm_mask_weight(kind)==(kind==4 ? 0 : count));
            CHECK(vkm_mask_has(kind,selected)==(kind!=4 && selected<count));
        }
        CHECK(vkm_mask_of_has(selected,selected));
        CHECK(!vkm_mask_of_has(selected,(selected+1)%256));
        CHECK(vkm_all_has(255)); CHECK(!vkm_all_has(256));
    }
}
'

const runner = '
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include "linuxkpi_smp_masks_v_primitives.h"
void mask_initial_state(void); void mask_poison(void); void mask_poison_unchanged(void);
void mask_constants(void); void mask_contents(unsigned); void mask_reader_batch(unsigned,unsigned);
static unsigned long long assertions;
static _Thread_local unsigned irq_state,preempt_depth,cpu_number;
void mask_check(bool passed,int line) {
    __atomic_add_fetch(&assertions,1,__ATOMIC_RELAXED);
    if (!passed) { fprintf(stderr,"mask assertion at %d\\n",line); abort(); }
}
static void *reader(void *argument) {
    unsigned count=*(const unsigned *)argument;
    irq_state=0; preempt_depth=7; cpu_number=63;
    mask_reader_batch(count,10000);
    mask_check(irq_state==0 && preempt_depth==7 && cpu_number==63,__LINE__);
    return NULL;
}
int main(int argc,char **argv) {
    if (argc!=2) return 2;
    unsigned long input=strtoul(argv[1],NULL,10);
    if (input>UINT32_MAX) return 2;
    unsigned count=(unsigned)input;
    mask_initial_state(); mask_constants();
    irq_state=1; preempt_depth=2; cpu_number=65;
    mask_poison();
    mask_check(vkm_cpu_masks_bootstrap(0)==-22,__LINE__); mask_poison_unchanged();
    mask_check(vkm_cpu_masks_bootstrap(257)==-22,__LINE__); mask_poison_unchanged();
    mask_check(vkm_cpu_masks_bootstrap(UINT32_MAX)==-22,__LINE__); mask_poison_unchanged();
    mask_check(!vkm_cpu_masks_ready(),__LINE__);
    if (count==0 || count>256) {
        mask_check(vkm_cpu_masks_bootstrap(count)==-22,__LINE__);
        mask_poison_unchanged();
    } else {
        mask_check(vkm_cpu_masks_bootstrap(count)==0,__LINE__); mask_contents(count);
        mask_check(vkm_cpu_masks_bootstrap(count)==-114,__LINE__);
        mask_check(vkm_cpu_masks_bootstrap(count==256 ? 1 : 256)==-114,__LINE__);
        mask_check(vkm_cpu_masks_bootstrap(0)==-22,__LINE__);
        mask_check(vkm_cpu_masks_bootstrap(257)==-22,__LINE__);
        mask_check(vkm_cpu_masks_bootstrap(UINT32_MAX)==-22,__LINE__);
        mask_contents(count);
        pthread_t actors[4];
        for (unsigned i=0;i<4;++i) if (pthread_create(&actors[i],NULL,reader,&count)) abort();
        for (unsigned i=0;i<4;++i) if (pthread_join(actors[i],NULL)) abort();
        /* No cold process is reused and no storage is mutated under readers. */
        mask_contents(count); mask_constants();
    }
    mask_check(irq_state==1 && preempt_depth==2 && cpu_number==65,__LINE__);
    printf("PASS: %llu original mask/publisher assertions (count=%u)\\n",assertions,count);
    return 0;
}
'

const references = '
#include <linux/cpumask.h>
#include "linuxkpi_smp_masks_v_primitives.h"
_Static_assert(NR_CPUS == 256 && BITS_PER_LONG == 64 &&
    sizeof(struct cpumask) == 32 && _Alignof(struct cpumask) == 8,
    "original complete four-word CPU mask");
_Static_assert(sizeof(cpu_bit_bitmap) == 2080 && sizeof(cpu_all_bits) == 32,
    "original compressed constants");
_Static_assert(offsetof(struct cpumask, bits) == 0 &&
    __builtin_types_compatible_p(__typeof__(((struct cpumask *)0)->bits), unsigned long[4]),
    "original bitmap word type");
_Static_assert(__builtin_types_compatible_p(__typeof__(__cpu_possible_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_online_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_present_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_active_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_dying_mask), struct cpumask),
    "genuine five original objects");
_Static_assert(sizeof(atomic_t) == 4 && offsetof(atomic_t, counter) == 0 &&
    __builtin_types_compatible_p(__typeof__(__num_online_cpus), atomic_t) &&
    __builtin_types_compatible_p(__typeof__(__num_online_cpus.counter), int) &&
    __builtin_types_compatible_p(__typeof__(nr_cpu_ids), unsigned int),
    "genuine original count fields");
#if defined(CONFIG_HOTPLUG_CPU) || defined(CONFIG_CPUMASK_OFFSTACK)
#error This test establishes only permanent native boot masks
#endif

#include <linux/smp.h>
unsigned int *pending_total_cpus=&total_cpus;
struct cpumask *pending_booted_once=&cpus_booted_once_mask;
void (*pending_online)(unsigned int,bool)=set_cpu_online;
void (*pending_present)(const struct cpumask *)=init_cpu_present;
void (*pending_possible)(const struct cpumask *)=init_cpu_possible;
void (*pending_initial_online)(const struct cpumask *)=init_cpu_online;
int (*pending_dispatch)(int,smp_call_func_t,void *,int)=smp_call_function_single;
'

const original_storage_revision = '2a5abc36175a5177828d86aad71667787eb68110'

const original_storage_path = 'kernel/c/linuxkpi_cpu_masks_data.c'

const host_cache_adapter = '/* Private section metadata adapter; all original cache definitions retained. */
#include_next <asm/cache.h>
#if defined(__APPLE__)
#undef __read_mostly
#define __read_mostly __attribute__((section("__DATA,__data")))
#endif
'

const host_section_adapter = '/* Private Mach-O declaration metadata; native attributes remain original. */
#include_next <linux/compiler_attributes.h>
#if defined(__APPLE__)
#undef __section
#define __section(name)
#endif
'

const c_prefix = '#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
typedef uint32_t u32; typedef uint64_t u64; typedef int32_t i32;
typedef int64_t i64; typedef uintptr_t usize; typedef void *voidptr;
'

const valid_metadata = '// ABI native-scalar: probe_word const_unsigned_long_64
@[typedef]
struct C.probe_word {}
'
