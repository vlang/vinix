// SPDX-License-Identifier: GPL-2.0-or-later
// Original SMP header compiler closure and native CPU query relocation checks.
module main

import os
import json2
import crypto.sha256
import strconv
import hosttest
import smpfixture

fn require(passed bool, message string) ! {
	if !passed { return error(message) }
}

fn command(argv []string, log string, success bool) !hosttest.Result {
	outcome := hosttest.capture(argv, log, 180, os.environ())!
	if success && outcome.code != 0 { return error('Compiler failed; see ' + log) }
	return outcome
}

fn inspect(argv []string) !string {
	result := hosttest.capture(argv, '', -1, os.environ())!
	require(result.code == 0, 'Object inspection failed: ' + result.stderr)!
	return result.stdout
}

fn symbol_names(output string) []string {
	mut names := []string{}
	for line in output.split_into_lines() {
		words := line.fields()
		if words.len != 0 && words.last() !in names { names << words.last() }
	}
	names.sort()
	return names
}

fn word_count(text string, target string) int {
	mut count := 0
	mut remaining := text
	for {
		index := remaining.index(target) or { break }
		end := index + target.len
		if (index == 0 || !hosttest.word_char(remaining[index - 1]))
			&& (end == remaining.len || !hosttest.word_char(remaining[end])) {
			count++
		}
		remaining = remaining[end..]
	}
	return count
}

fn assembly_body(text string, name string) !string {
	marker := '<' + name + '>:\n'
	start := text.index(marker) or { return error('Missing disassembly function: ' + name) }
	remaining := text[start + marker.len..]
	mut position := 0
	for line in remaining.split_into_lines() {
		if position != 0 && line.contains(' <') && line.ends_with('>:') {
			address := line.all_before(' <')
			if address.len != 0 && address.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
				return remaining[..position]
			}
		}
		position += line.len + 1
	}
	return remaining
}

fn ops_members(text string) ![]string {
	marker := 'struct smp_ops {'
	start := text.index(marker) or { return error('Missing original smp_ops declaration') }
	remaining := text[start + marker.len..]
	end := remaining.index('\n};') or { return error('Unclosed original smp_ops declaration') }
	mut body := remaining[..end]
	mut names := []string{}
	for {
		index := body.index('(*') or { break }
		body = body[index + 2..]
		mut length := 0
		for length < body.len && hosttest.word_char(body[length]) { length++ }
		if length != 0 && length < body.len && body[length] == `)` { names << body[..length] }
		body = body[length..]
	}
	return names
}

struct Context {
	work       string
	linux      string
	generated  string
	production string
	compiler   []string
	abi_count  int
mut:
	results []json2.Any
}

fn (context Context) flags(overlay string, standard string) []string {
	mut selected := smpfixture.flags(context.linux, context.generated, 'x86_64-unknown-none', standard)
	original := os.join_path(hosttest.upstream_here(), 'include')
	for index, item in selected {
		if item == original { selected[index] = overlay }
	}
	selected << '-Wno-sign-compare'
	return selected
}

fn (mut context Context) probe(standard string, name string, code string, expected []string, overlay string, cold bool, reject string) !map[string]json2.Any {
	source := os.join_path(context.work, standard + '-' + name + '.c')
	os.write_file(source, code)!
	obj := source.all_before_last('.') + '.o'
	dep := source.all_before_last('.') + '.d'
	argv := [...context.compiler, ...context.flags(overlay, standard), '-MD', '-MF', dep, '-MQ',
		obj, '-c', source, '-o', obj]
	outcome := command(argv, source.all_before_last('.') + '.log', reject == '')!
	mut item := map[string]json2.Any{
		'probe':    json2.Any(name)
		'standard': standard
		'argv':     hosttest.strings(argv)
		'exit':     outcome.code
	}
	if reject != '' {
		require(outcome.code != 0 && outcome.stderr.contains(reject), 'Genuine prerequisite rejection missing: ' + name)!
		item['diagnostics'] = outcome.stderr
	} else {
		undefined := inspect([hosttest.tool('llvm-nm'), '--undefined-only', obj])!
		mut wanted := expected.clone()
		wanted.sort()
		require(symbol_names(undefined) == wanted, 'Genuine runtime imports changed: ' + name + ' ' + undefined)!
		symbols := inspect([hosttest.tool('llvm-nm'), obj])!
		require(!cold || symbols.trim_space() == '', 'Declaration-only include order emitted an object symbol')!
		inputs := hosttest.dependency_paths(os.read_file(dep)!, obj)!
		for path in ['include/linux/smp.h', 'include/linux/smp_types.h', 'arch/x86/include/asm/smp.h'] {
			require(hosttest.resolve_path(os.join_path(context.linux, path))! in inputs, 'Original dependency was bypassed: ' + path)!
		}
		disassembly := inspect([hosttest.tool('llvm-objdump'), '-dr', '--no-show-raw-insn', obj])!
		os.write_file(source.all_before_last('.') + '.disassembly', disassembly)!
		relocations := inspect([hosttest.tool('llvm-readelf'), '--relocations', obj])!
		os.write_file(source.all_before_last('.') + '.relocations', relocations)!
		if name == 'cpu-queries' {
			require(!(relocations + symbols + disassembly).contains('pcpu_hot'), 'Foreign Linux GS query escaped into native accessor probe')!
			for function, target in {
				'query_raw':         'raw_smp_processor_id'
				'query_stable':      'raw_smp_processor_id'
				'query_arch_stable': 'raw_smp_processor_id'
				'query_safe':        'raw_smp_processor_id'
				'query_pinned':      'vinix_get_cpu'
				'release_pin':       'vinix_linuxkpi_preempt_enable'
			} {
				require(word_count(assembly_body(disassembly, function)!, target) == 1, 'Wrong actual query/pin relocation: ' + function)!
			}
		}
		if name == 'stack-disabled' {
			body := disassembly.all_after('<original_stack_query>:')
			mut clears_eax := false
			for line in body.split_into_lines() {
				words := line.fields()
				if words.len >= 3 && words[words.len - 3..] == ['xorl', '%eax,', '%eax'] {
					clears_eax = true
				}
			}
			require(clears_eax && hosttest.has_word(body, 'retq'), 'Disabled original frame helper did not return NOT_STACK')!
		}
		item['object_sha256'] = hosttest.file_digest(obj)!
		item['undefined_symbols'] = undefined
		item['symbols'] = symbols
		item['input_sha256'] = hosttest.string_map(hosttest.hashes(inputs)!)
		item['relocations_sha256'] = sha256.sum(relocations.bytes()).hex()
		if name.ends_with('abi') {
			output := source.all_before_last('.') + '.abi-bytes'
			derived := source.all_before_last('.') + '.dump-copy.o'
			command([hosttest.tool('llvm-objcopy'), '--dump-section', '.rodata=' + output, obj,
				derived], source.all_before_last('.') + '.objcopy.log', true)!
			require(hosttest.file_digest(obj)! == item['object_sha256']!.str(), 'Section dump changed the original compiler object')!
			bytes := os.read_bytes(output)!
			require(bytes.len == context.abi_count * 8, 'ABI vector was not exactly one original 64-bit word per field')!
			mut words := []json2.Any{}
			for index := 0; index < bytes.len; index += 8 {
				mut value := u64(0)
				for bit in 0 .. 8 { value |= u64(bytes[index + bit]) << u32(bit * 8) }
				words << json2.Any(value)
			}
			item['observable_abi_sha256'] = hosttest.file_digest(output)!
			item['abi_dump_derived_object_sha256'] = hosttest.file_digest(derived)!
			item['observable_abi_words'] = words
		}
	}
	context.results << json2.Any(item)
	return item
}

fn run_profile(keep string) ! {
	work := hosttest.work_dir(keep, 'vinix-smp-headers-')!
	defer { if keep == '' { os.rmdir_all(work) or { eprintln(err) } } }
	root := hosttest.root()
	here := hosttest.upstream_here()
	pin := hosttest.upstream_pin()!
	linux := hosttest.resolve_path(hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(hosttest.upstream_default(), 'linux-' + pin['version']!.str())))!
	archive := os.join_path(os.dir(linux), 'linux-' + pin['version']!.str() + '.tar.xz')
	compiler_text := hosttest.env_default('CC', 'clang')
	compiler := hosttest.shell_split(compiler_text)!
	mut observed := ['linux/smp.h', 'asm/percpu.h', 'asm/smp.h', 'generated/autoconf.h'].map(os.join_path(here, 'include', it))
	observed << [@FILE, os.join_path(root, 'tests/linuxkpi/smpfixture/core.v'),
		os.join_path(here, 'audit.py'), os.join_path(here, 'generate-bounds.py'),
		os.join_path(here, 'upstream.py'), os.join_path(here, 'upstream.json')]
	mut guarded := observed.clone()
	guarded << os.walk_ext(os.join_path(root, 'tests/linuxkpi/hosttest'), '.v')
	guarded << os.walk_ext(os.join_path(root, 'tests/linuxkpi/upstreamsource'), '.v')
	guarded << os.join_path(root, 'tests/linuxkpi/upstream_source.v')
	initial := hosttest.hashes(guarded)!
	verification := command([os.join_path(root, 'build-support/run-v-tool.sh'),
		os.join_path(root, 'tests/linuxkpi/upstream_source.v'), 'verify', '--base', os.dir(linux)], os.join_path(work, 'upstream-verification.log'), true)!
	generated := os.join_path(work, 'generated')
	hosttest.audit_headers(generated)!
	production := os.join_path(work, 'production')
	os.cp_all(os.join_path(here, 'include'), production, false)!
	reference := os.join_path(work, 'original-profile')
	os.cp_all(production, reference, false)!
	os.rm(os.join_path(reference, 'asm/smp.h'))!
	os.write_file(os.join_path(reference, 'linux/smp.h'), '#include_next <linux/smp.h>\n')!
	mut context := Context{ work: work, linux: linux, generated: generated, production: production, compiler: compiler }
	bounds := os.join_path(generated, 'generated/bounds.h')
	raw := hosttest.generate_bounds(linux, archive, bounds, bounds + '.d', bounds + '.json', compiler_text, context.flags(production, 'gnu11'))!
	provenance := hosttest.decode_json(hosttest.bounds_metadata_json(raw))!
	require(hosttest.file_digest(archive)! == pin['sha256']!.str(), 'Pinned archive changed before reference extraction')!
	originals := os.join_path(work, 'archive-reference')
	archive_names := ['arch/x86/Kconfig', 'scripts/Makefile.extrawarn']
	members := hosttest.archive_members(archive, archive_names.map(os.file_name(linux) + '/' + it))!
	mut archive_hashes := map[string]string{}
	for name in archive_names {
		bytes := members[os.file_name(linux) + '/' + name] or { return error('Missing original reference: ' + name) }
		destination := os.join_path(originals, name)
		os.mkdir_all(os.dir(destination))!
		os.write_file_array(destination, bytes)!
		archive_hashes[name] = hosttest.file_digest(destination)!
	}
	mut selection := ''
	for line in os.read_file(os.join_path(originals, 'arch/x86/Kconfig'))!.split_into_lines() {
		if line.trim_space() == 'select HAVE_ARCH_WITHIN_STACK_FRAMES' {
			selection = line.trim_space()
			break
		}
	}
	mut policy := ''
	for line in os.read_file(os.join_path(originals, 'scripts/Makefile.extrawarn'))!.split_into_lines() {
		if line.trim_right(' \t\r\n\v\f') == 'KBUILD_CFLAGS += -Wno-sign-compare' {
			policy = line.trim_space()
			break
		}
	}
	require(selection != '' && policy != '', 'Actual original Kconfig/Kbuild compiler prerequisites changed')!
	exact_early := smpfixture.macros(os.read_file(os.join_path(linux, 'arch/x86/include/asm/percpu.h'))!, 'DECLARE_EARLY_PER_CPU_READ_MOSTLY')!
	require(exact_early.len == 2 && smpfixture.macros(os.read_file(os.join_path(production, 'asm/percpu.h'))!, 'DECLARE_EARLY_PER_CPU_READ_MOSTLY')! == exact_early, 'SMP/non-SMP early declaration macros differ from pinned source')!
	arch_smp := os.read_file(os.join_path(linux, 'arch/x86/include/asm/smp.h'))!
	member_names := ops_members(arch_smp)!
	mut unique := map[string]bool{}
	for name in member_names { unique[name] = true }
	require(member_names.len == 14 && unique.len == member_names.len, 'Original smp_ops field inventory changed')!
	mut abi_words := ['sizeof(struct __call_single_node)', '_Alignof(struct __call_single_node)',
		'sizeof(struct __call_single_data)', '_Alignof(struct __call_single_data)',
		'sizeof(call_single_data_t)', '_Alignof(call_single_data_t)',
		'offsetof(struct __call_single_data,node)', 'offsetof(struct __call_single_data,func)',
		'offsetof(struct __call_single_data,info)', 'sizeof(struct smp_ops)', '_Alignof(struct smp_ops)',
		'sizeof(struct cpumask)', 'CSD_FLAG_LOCK', 'CSD_TYPE_SYNC', 'CSD_TYPE_ASYNC']
	abi_words << member_names.map('offsetof(struct smp_ops,' + it + ')')
	context = Context{ ...context, abi_count: abi_words.len }
	abi := 'const unsigned long original_abi_words[] = {\n' + abi_words.join(',\n') + '\n};\n'
	baseline := '#include "' + os.join_path(linux, 'include/linux/smp.h') + '"\n'
	cold := smpfixture.node.all_before('unsigned long csd_node_bytes') + smpfixture.layout.all_before('static void callback') + cold_checks
	for standard in ['gnu99', 'gnu11'] {
		context.probe(standard, 'cold', header + cold, []string{}, production, true, '')!
		reference_abi := context.probe(standard, 'original-abi', baseline + cold + abi, []string{}, reference, false, '')!
		actual_abi := context.probe(standard, 'production-abi', header + cold + abi, []string{}, production, false, '')!
		require(reference_abi['observable_abi_sha256']!.str() == actual_abi['observable_abi_sha256']!.str(), 'Production changed actual original CSD/smp_ops ABI bytes')!
		context.probe(standard, 'cpu-queries', header + query, ['raw_smp_processor_id', 'vinix_get_cpu',
			'vinix_linuxkpi_preempt_enable'], production, false, '')!
		context.probe(standard, 'early-references', header + early, [
			'x86_cpu_to_apicid',
			'x86_cpu_to_acpiid',
			'x86_cpu_to_apicid_early_ptr',
			'x86_cpu_to_acpiid_early_ptr',
			'x86_cpu_to_apicid_early_map',
			'x86_cpu_to_acpiid_early_map',
		], production, false, '')!
		context.probe(standard, 'runtime-references', header + smpfixture.reference, [
			'__cpu_online_mask',
			'__smp_call_single_queue',
			'on_each_cpu_cond_mask',
			'smp_call_function',
			'smp_call_function_many',
			'smp_call_function_single',
			'smp_call_function_single_async',
			'smp_ops',
		], production, false, '')!
		context.probe(standard, 'stack-disabled', header + stack, []string{}, production, false, '')!
		for index, order in ['#include <asm/percpu.h>\n', '#include <asm/smp.h>\n',
			'#include <linux/percpu.h>\n'] {
			context.probe(standard, 'include-order-' + index.str(), order + header + cold, []string{}, production, true, '')!
		}
		context.probe(standard, 'missing-config', '#undef CONFIG_HAVE_ARCH_WITHIN_STACK_FRAMES\n' + header, []string{}, production, false, "redefinition of 'arch_within_stack_frames'")!
		context.probe(standard, 'missing-declaration', '#include <asm/percpu.h>\n#undef DECLARE_EARLY_PER_CPU_READ_MOSTLY\n' + header, []string{}, production, false, 'type specifier missing')!
		context.probe(standard, 'foreign-pcpu-query', baseline + 'unsigned int foreign_query(void) { return raw_smp_processor_id(); }\n', []string{}, reference, false, "undeclared identifier 'pcpu_hot'")!
	}
	mut controls := map[string]u64{}
	for name in ['STARTUP_READ_APICID', 'STARTUP_PARALLEL_MASK'] {
		for line in arch_smp.split_into_lines() {
			words := line.fields()
			if words.len >= 3 && words[0] == '#define' && words[1] == name && words[2].starts_with('0x') {
				controls[name] = strconv.parse_uint(words[2][2..], 16, 64)!
				break
			}
		}
		require(name in controls, 'Original assembler control missing: ' + name)!
	}
	mut assembly := []json2.Any{}
	for name, overlay in {
		'production': production
		'original':   reference
	} {
		source := os.join_path(work, name + '-assembly.S')
		os.write_file(source, '#include <asm/smp.h>\n.equ probe_read_apicid, STARTUP_READ_APICID\n.equ probe_parallel_mask, STARTUP_PARALLEL_MASK\n')!
		obj := source.all_before_last('.') + '.o'
		dep := source.all_before_last('.') + '.d'
		argv := [...compiler, '--target=x86_64-unknown-none', '-nostdinc', '-D__KERNEL__',
			'-D__ASSEMBLY__', '-include', 'linux/kconfig.h', '-I', overlay, '-I',
			os.join_path(linux, 'include'), '-I', os.join_path(linux, 'arch/x86/include'), '-Wall',
			'-Wextra', '-Werror', '-MD', '-MF', dep, '-MQ', obj, '-c', source, '-o', obj]
		command(argv, source.all_before_last('.') + '.log', true)!
		undefined := inspect([hosttest.tool('llvm-nm'), '--undefined-only', obj])!
		require(undefined.trim_space() == '', 'Original assembler profile imported a C runtime')!
		symbols := inspect([hosttest.tool('llvm-nm'), obj])!
		mut values := map[string]u64{}
		for line in symbols.split_into_lines() {
			words := line.fields()
			if words.len != 0 { values[words.last()] = strconv.parse_uint(words[0], 16, 64)! }
		}
		require(values == {
			'probe_read_apicid':   controls['STARTUP_READ_APICID']
			'probe_parallel_mask': controls['STARTUP_PARALLEL_MASK']
		}, 'Forwarding header changed original assembler control constants')!
		inputs := hosttest.dependency_paths(os.read_file(dep)!, obj)!
		require(hosttest.resolve_path(os.join_path(linux, 'arch/x86/include/asm/smp.h'))! in inputs, 'Original assembly header was not discovered')!
		assembly << json2.Any(map[string]json2.Any{
			'profile':           json2.Any(name)
			'argv':              hosttest.strings(argv)
			'object_sha256':     hosttest.file_digest(obj)!
			'input_sha256':      hosttest.string_map(hosttest.hashes(inputs)!)
			'symbols':           symbols
			'undefined_symbols': undefined
		})
	}
	require(initial == hosttest.hashes(guarded)!, 'Production/test/profile changed during isolated compiler checks')!
	mut positive := assembly.len
	mut rejected := 0
	for value in context.results {
		item := value.as_map()
		if item['exit']!.str() == '0' {
			obj := os.join_path(work, item['standard']!.str() + '-' + item['probe']!.str() + '.o')
			require(hosttest.file_digest(obj)! == item['object_sha256']!.str(), 'Saved compiler object no longer matches its recorded hash')!
			positive++
		} else {
			rejected++
		}
	}
	hosttest.write_json(os.join_path(work, 'result.json'), map[string]json2.Any{
		'scope':                          json2.Any(scope)
		'source_sha256':                  hosttest.string_map(hosttest.hashes(observed)!)
		'bounds':                         provenance
		'upstream_verification':          verification.stdout.trim_space()
		'archive_reference_sha256':       hosttest.string_map(archive_hashes)
		'genuine_early_macros':           hosttest.strings(exact_early)
		'original_smp_ops_members':       hosttest.strings(member_names)
		'pinned_configuration_selection': selection
		'pinned_warning_policy':          policy
		'probes':                         context.results
		'assembly':                       assembly
		'positive_objects':               positive
		'genuine_rejections':             rejected
	})!
	println('PASS: ' + positive.str() + ' original SMP compiler/assembly objects; ' + rejected.str() + ' genuine prerequisite rejections')
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: smp_headers.v [--keep-dir DIRECTORY]', scope) or {
		eprintln(err.msg())
		exit(2)
	}
	run_profile(keep) or {
		eprintln(err.msg())
		exit(1)
	}
}

const cold_checks = '
_Static_assert(CONFIG_SMP == 1 && CONFIG_HAVE_ARCH_WITHIN_STACK_FRAMES == 1,
    "actual x86 SMP compiler configuration");
_Static_assert(CONFIG_NR_CPUS == 256 && sizeof(struct cpumask) == 32,
    "genuine configured CPU mask width");
#if defined(CONFIG_FRAME_POINTER) || defined(CONFIG_HARDENED_USERCOPY)
#error This compiler profile supplies no Linux stack validation
#endif
'

const header = '#include <linux/smp.h>
#include <linux/smp.h>
#include <asm/smp.h>
'

const query = '
_Static_assert(__builtin_types_compatible_p(__typeof__(&raw_smp_processor_id),
    unsigned int (*)(void)), "native CPU accessor ABI");
_Static_assert(__builtin_types_compatible_p(__typeof__(&vinix_get_cpu),
    unsigned int (*)(void)), "native scheduler pin ABI");
unsigned int query_raw(void) { return raw_smp_processor_id(); }
unsigned int query_stable(void) { return smp_processor_id(); }
unsigned int query_arch_stable(void) { return __smp_processor_id(); }
unsigned int query_safe(void) { return safe_smp_processor_id(); }
unsigned int query_pinned(void) { return get_cpu(); }
void release_pin(void) { put_cpu(); }
unsigned int (*native_accessor_reference)(void) = raw_smp_processor_id;
'

const early = '
_Static_assert(__builtin_types_compatible_p(__typeof__(x86_cpu_to_apicid_early_ptr), u16 *),
    "original early APIC pointer");
_Static_assert(__builtin_types_compatible_p(__typeof__(x86_cpu_to_acpiid_early_ptr), u32 *),
    "original early ACPI pointer");
_Static_assert(__builtin_types_compatible_p(__typeof__(&x86_cpu_to_apicid_early_map[0]), u16 *),
    "original early APIC map");
_Static_assert(__builtin_types_compatible_p(__typeof__(&x86_cpu_to_acpiid_early_map[0]), u32 *),
    "original early ACPI map");
u16 *apic_template_reference = &x86_cpu_to_apicid;
u32 *acpi_template_reference = &x86_cpu_to_acpiid;
u16 **apic_pointer_reference = &x86_cpu_to_apicid_early_ptr;
u32 **acpi_pointer_reference = &x86_cpu_to_acpiid_early_ptr;
u16 *apic_map_reference = x86_cpu_to_apicid_early_map;
u32 *acpi_map_reference = x86_cpu_to_acpiid_early_map;
'

const stack = '
_Static_assert(NOT_STACK == 0, "original unable-to-determine result");
int original_stack_query(const void *s, const void *e, const void *p, unsigned long n) {
    return arch_within_stack_frames(s,e,p,n);
}
'

const scope = 'Check original SMP/CSD compiler closure and native CPU query relocations.

Original headers own every CSD, cpumask and smp_ops representation. These tests
compare observable ABI bytes and preserve genuinely unresolved dispatch, mask
and early-map references. They neither implement SMP calls nor validate Linux
stack ownership, CPU hotplug, runtime masks or hardware interrupt delivery.
'
