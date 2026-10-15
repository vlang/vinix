// SPDX-License-Identifier: GPL-2.0-or-later
// Execute exact generated native V policy bodies against independent inputs.
module main

import os
import strconv
import json2
import hosttest

const scope = 'Execute the actual native L1TF classifier, IRQ-off sampler, fault-safe MSR Option helper, boot-record validation/publication and public query. The complete first-match vulnerability whitelist and raw vendor registrations come independently from the authenticated Linux 6.6.157 archive. CPUID/MSR/IRQ/atomic/fatal/boot-record transports are explicit V models. Native hardware, boot CPU publication and allocation recovery are separate kernel evidence.'

fn integer(raw string) !int { return int(strconv.parse_int(raw, 0, 32)!) }

fn original_oracle(work string, linux string) !json2.Any {
	archive := os.join_path(os.dir(linux), 'linux-6.6.157.tar.xz')
	pin := hosttest.upstream_pin()!
	if hosttest.sha(archive)! != (pin['sha256'] or { return error('Missing archive pin') }).str() {
		return error('Original archive differs from pin')
	}
	mut paths := ['arch/x86/kernel/cpu/common.c', 'arch/x86/kernel/cpu/match.c', 'arch/x86/lib/cpu.c',
		'arch/x86/include/asm/intel-family.h', 'arch/x86/include/asm/processor.h',
		'arch/x86/include/asm/cpufeatures.h', 'include/linux/mod_devicetable.h']
	vendor_files := ['intel', 'amd', 'hygon', 'centaur', 'cyrix', 'vortex', 'zhaoxin', 'transmeta',
		'umc']
	for name in vendor_files { paths << 'arch/x86/kernel/cpu/' + name + '.c' }
	selected := hosttest.archive_members(archive, paths.map('linux-6.6.157/' + it))!
	mut original := map[string]string{}
	mut identities := map[string]string{}
	for path in paths {
		member := 'linux-6.6.157/' + path
		bytes := selected[member] or { return error('Missing original ' + member) }
		original[path] = bytes.bytestr()
		reference := work + '/reference/' + path
		os.mkdir_all(os.dir(reference))!
		os.write_file(reference, bytes.bytestr())!
		identities[path] = hosttest.sha(reference)!
		if os.exists(linux + '/' + path) && hosttest.sha(linux + '/' + path)! != identities[path] {
			return error('Imported source differs from exact archive: ' + path)
		}
	}
	mut constants := map[string]int{}
	for path in ['arch/x86/include/asm/intel-family.h', 'arch/x86/include/asm/processor.h',
		'include/linux/mod_devicetable.h'] {
		for line in original[path].split_into_lines() {
			fields := line.fields()
			if fields.len >= 3 && fields[0] == '#define' && (fields[1].starts_with('INTEL_FAM6_') || fields[1].starts_with('X86_VENDOR_') || fields[1] in [
				'X86_FAMILY_ANY',
				'X86_MODEL_ANY',
			]) {
				if fields[2][0].is_digit() { constants[fields[1]] = integer(fields[2])! }
			}
		}
	}
	if constants['X86_FAMILY_ANY'] != 0 || constants['X86_MODEL_ANY'] != 0 || constants['X86_VENDOR_ANY'] != 65535 {
		return error('Original wildcard representation changed')
	}
	mut flags := map[string]int{}
	for line in original['arch/x86/kernel/cpu/common.c'].split_into_lines() {
		fields := line.fields()
		if fields.len == 3 && fields[0] == '#define' && fields[2].starts_with('BIT(') && (fields[1].starts_with('NO_') || fields[1] == 'MSBDS_ONLY') {
			flags[fields[1]] = 1 << integer(fields[2].all_after('BIT(').all_before(')'))!
		}
	}
	if flags['NO_SPECULATION'] != 1 || flags['NO_MELTDOWN'] != 2 || flags['NO_L1TF'] != 8 {
		return error('Original classifier flags changed')
	}
	common := original['arch/x86/kernel/cpu/common.c']
	table := common.all_after('cpu_vuln_whitelist[] = {').all_before('\n};')
	mut rows := []json2.Any{}
	mut code := '// Exact archive-derived values, preserving complete original first-match order.\nmodule cpubugfixture\nfn original_entry(index int) OracleEntry {\n match index {\n'
	mut row_count := 0
	for source_line in table.split_into_lines() {
		line := source_line.trim_space()
		if !line.starts_with('VULNWL') { continue }
		kind := line.all_before('(')
		values := line.all_after('(').all_before_last(')').split(',').map(it.trim_space())
		mut vendor := ''
		mut family := 0
		mut model := 0
		mut expression := ''
		match kind {
			'VULNWL' {
				if values.len != 4 { return error('Unexpected original table row') }
				vendor = values[0]
				family = integer(values[1])!
				model = constants[values[2]] or { return error('Unknown wildcard') }
				expression = values[3]
			}
			'VULNWL_INTEL' {
				if values.len != 2 { return error('Unexpected Intel row') }
				vendor = 'INTEL'
				family = 6
				model = constants['INTEL_FAM6_' + values[0]] or { return error('Unknown original Intel model') }
				expression = values[1]
			}
			'VULNWL_AMD', 'VULNWL_HYGON' {
				if values.len != 2 { return error('Unexpected family row') }
				vendor = kind.all_after('VULNWL_')
				family = if values[0] == 'X86_FAMILY_ANY' { 0 } else { integer(values[0])! }
				expression = values[1]
			}
			else { return error('Unhandled original whitelist macro ' + kind) }
		}
		mut mask := 0
		for name in expression.split('|').map(it.trim_space()) {
			mask |= flags[name] or { return error('Unknown original flag ' + name) }
		}
		vendor_id := if vendor == 'ANY' {
			-1
		} else {
			constants['X86_VENDOR_' + vendor] or { return error('Unknown original vendor') }
		}
		code += '  ${row_count} {return OracleEntry{vendor:${vendor_id},family:${family},model:${model},flags:${mask}}}\n'
		rows << json2.Any({
			'source': json2.Any(line)
			'vendor': vendor_id
			'family': family
			'model':  model
			'flags':  mask
		})
		row_count++
	}
	if row_count != 38 {
		return error('Expected all 38 original whitelist entries, got ${row_count}')
	}
	code += '  else {require(false,100);return OracleEntry{}}\n }\n}\nconst oracle_entry_count = ${row_count}\n'
	mut vendors := []json2.Any{}
	mut vendor_code := 'fn original_vendor(index int) Vendor {\n match index {\n'
	mut vendor_count := 0
	for name in vendor_files {
		source := original['arch/x86/kernel/cpu/' + name + '.c']
		if !source.contains('.c_ident') {
			return error('Missing original vendor registration ' + name)
		}
		mut registrations := source
		for registrations.contains('.c_ident') {
			registrations = registrations.all_after('.c_ident')
			if !registrations.trim_space().starts_with('=') { continue }
			registration := registrations.all_after('{').all_before('}')
			enum_name := registrations.all_after('.c_x86_vendor').all_after('=').all_before(',').trim_space()
			// Some registrations list identity before the string; either field is in
			// the same final cpu_dev declaration and is independently authenticated.
			vendor_id := constants[enum_name] or { return error('Unrecognized original vendor enum ' + enum_name) }
			mut remaining := registration
			for remaining.contains('"') {
				remaining = remaining.all_after('"')
				identity := remaining.all_before('"')
				remaining = remaining.all_after('"')
				if identity.len > 12 || identity.len == 0 {
					return error('Unexpected original vendor length: ' + identity)
				}
				raw_identity := identity + '\x00'.repeat(12 - identity.len)
				b := word(raw_identity, 0)
				d := word(raw_identity, 4)
				c := word(raw_identity, 8)
				vendor_code += '  ${vendor_count} {return Vendor{b:${b},d:${d},c:${c},identity:${vendor_id}}}\n'
				vendors << json2.Any({
					'identity': json2.Any(identity)
					'vendor':   vendor_id
					'b':        b
					'd':        d
					'c':        c
				})
				vendor_count++
			}
		}
	}
	// These often-cited names are not aliases in the pinned registration set.
	// Test them as unknown alongside an all-zero identity and a generic string.
	for identity in ['AMDisbetter!', 'Genuineintel', 'UnknownCPU12', '\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'] {
		b := word(identity, 0)
		d := word(identity, 4)
		c := word(identity, 8)
		vendor_code += '  ${vendor_count} {return Vendor{b:${b},d:${d},c:${c},identity:255}}\n'
		vendors << json2.Any({
			'identity': json2.Any(identity)
			'vendor':   255
			'b':        b
			'd':        d
			'c':        c
		})
		vendor_count++
	}
	vendor_code += '  else {require(false,101);return Vendor{}}\n }\n}\nconst oracle_vendor_count = ${vendor_count}\n'
	os.write_file(work + '/stage/cpubugfixture/oracle.v', code + vendor_code)!
	return {
		'archive_sha256': json2.Any(hosttest.sha(archive)!)
		'source_sha256':  hosttest.string_map(identities)
		'whitelist':      rows
		'vendors':        vendors
		'oracle_sha256':  hosttest.sha(work + '/stage/cpubugfixture/oracle.v')!
		'scope':          'Full 38-entry whitelist, every flag and first-match order parsed independently from original common.c. Vendor identities are original c_ident registrations, including aliases. The generic fixture interpreter preserves original u8 family storage and decoded-family model rule; synthetic nonaliases and corrupt vendor words remain unknown.'
	}
}

fn word(text string, index int) u32 {
	return u32(text[index]) | (u32(text[index + 1]) << 8) | (u32(text[index + 2]) << 16) | (u32(text[index + 3]) << 24)
}

fn selected_source(raw string) !string {
	mut bodies := []string{}
	for body in hosttest.c_bodies(raw) {
		line := body.all_before('\n')
		if hosttest.named_body(body, 'array_get') && !body.contains('cpubugfixture__borrowed_index') {
			continue
		}
		if hosttest.named_body(body, 'v_panic') && !body.contains('cpubugfixture__unexpected_v_panic') {
			continue
		}
		if hosttest.named_body(body, 'main') && !body.contains('cpubugfixture__run') { continue }
		if ['linuxkpi__', 'cpubugfixture__', 'cpu__', 'msr__', 'katomic__', 'lib__'].any(line.contains(it))
			|| ['vinix_linuxkpi_boot_cpu_has_bug', 'cpubug_configure', 'cpubug_initialize',
				'cpubug_state', 'cpubug_seed_ready', 'array_get', 'v_panic', 'x86_rdmsr_safe',
				'main', '_vno_main_init_caller'].any(hosttest.named_body(body, it)) {
			bodies << body
		}
	}
	if bodies.len < 30 { return error('Missing actual generated production/fixture bodies') }
	mut metadata := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && !line.contains('Array_fixed_') && (line.contains('cpubugfixture__') || line.contains('struct array ') || line.contains('struct string ') || line == 'typedef array Array;' || line.contains('multi_return_bool_u32_u32_u32_u32') || line.contains('__v_option_u64')) && line !in metadata {
			metadata << line
		}
	}
	mut records := []string{}
	for name in ['string', 'array', 'cpubugfixture__Local', 'cpubugfixture__OracleEntry',
		'cpubugfixture__Vendor', 'multi_return_bool_u32_u32_u32_u32'] {
		records << hosttest.record(raw, name)!
	}
	mut late := []string{}
	text := bodies.join('\n')
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && (line.contains('Array_fixed_') || line.contains('(*_fn_ptr_')) {
			name := if line.contains('(*') {
				line.all_after('(*').all_before(')')
			} else {
				line.fields().last().all_before('[').all_before(';')
			}
			if text.contains(name) && line !in metadata { late << line }
		}
	}
	mut globals := []string{}
	mut constants := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('#define ') && (line.contains('linuxkpi__') || line.contains('cpubugfixture__') || line.starts_with('#define E_STRUCT ') || line.starts_with('#define _S(s) ')) {
			constants << line
		}
		if line.ends_with(';') && !line.contains('(') && !line.starts_with('typedef ') && !line.starts_with('extern ') && !line.starts_with('\t') && !line.starts_with(' ')
			&& ['linuxkpi__', 'cpubugfixture__', '_v3_no_main_initialized'].any(line.contains(it)) {
			globals << line
		}
	}
	decls := bodies.map(it.all_before('\n').all_before_last(' {') + ';')
	prefix := '#include "cpubugfixture/contract.h"\n' +
		'typedef uint8_t byte; typedef int32_t i32; typedef int64_t i64; typedef void *voidptr; typedef size_t usize;\n' +
		'#define VNORETURN __attribute__((noreturn))\n' + metadata.join('\n') + '\n' + records.join('\n') + '\n' + late.join('\n') + '\n' + globals.join('\n') + '\n' + constants.join('\n') + '\n' + decls.join('\n') + '\n'
	selected := prefix + bodies.join('\n\n') + '\n'
	if hosttest.c_bodies(selected) != bodies {
		return error('Metadata selection changed an actual generated V body')
	}
	return selected
}

fn compile_input(argv []string, source string, object string, log string, environment map[string]string) !json2.Any {
	preprocess := object + '.i'
	depfile := object + '.d'
	hosttest.command([...argv, '-E', '-dD', '-MD', '-MF', depfile, '-MT', object, source, '-o',
		preprocess], log + '.preprocess', 180, environment)!
	dependencies := hosttest.dependency_paths(os.read_file(depfile)!, object)!
	before := hosttest.hashes(dependencies)!
	hosttest.command([...argv, '-c', source, '-o', object], log, 180, environment)!
	if before != hosttest.hashes(dependencies)! { return error('Compiler dependency changed') }
	return {
		'source':              json2.Any(source)
		'source_sha256':       hosttest.sha(source)!
		'object':              object
		'object_sha256':       hosttest.sha(object)!
		'preprocessed':        preprocess
		'preprocessed_sha256': hosttest.sha(preprocess)!
		'dependency_sha256':   hosttest.string_map(before)
		'compiler_argv':       hosttest.strings(argv)
	}
}

fn production_objects(work string, raw string, selected string, names []string, environment map[string]string) !json2.Any {
	mut bodies := []string{}
	for name in names { bodies << hosttest.extract_body(raw, name)! }
	mut metadata := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef struct __v_option_u64 ') || (line.starts_with('typedef ') && line.ends_with(' linuxkpi__Local;')) {
			metadata << line
		}
		if line.starts_with('#define linuxkpi__') || line.starts_with('#define _S(s) ') {
			metadata << line
		}
		if line.ends_with(';') && !line.contains('(') && !line.starts_with('\t') && !line.starts_with(' ') && (line.contains('linuxkpi__boot_bug_') || line.contains('linuxkpi__boot_l1tf_sample') || line.starts_with('Array linuxkpi__cpu_locals ')) {
			metadata << line
		}
	}
	mut records := []string{}
	for name in ['string', 'array', 'cpubugfixture__Local', 'multi_return_bool_u32_u32_u32_u32'] {
		records << hosttest.record(raw, name)!
	}
	mut declarations := bodies.map(it.all_before('\n').all_before_last(' {') + ';')
	for name in ['array_get', 'v_panic', 'cpu__cpuid', 'cpu__interrupt_state', 'katomic__load_T_u32',
		'katomic__load_T_u64', 'katomic__store_T_u32', 'lib__kpanic', 'x86_rdmsr_safe'] {
		declarations << hosttest.extract_body(selected, name)!.all_before('\n').all_before_last(' {') + ';'
	}
	prefix := '#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\ntypedef uint8_t u8; typedef uint8_t byte; typedef uint32_t u32; typedef uint64_t u64; typedef int32_t i32; typedef int64_t i64; typedef size_t usize; typedef void *voidptr;\n' +
		'typedef struct string string; typedef struct array array; typedef array Array; typedef array cbh_array; typedef string cbh_string; typedef struct cpubugfixture__Local cpubugfixture__Local; typedef struct multi_return_bool_u32_u32_u32_u32 multi_return_bool_u32_u32_u32_u32;\n#define VNORETURN __attribute__((noreturn))\n' +
		records.join('\n') + '\n' + metadata.join('\n') + '\n' + declarations.join('\n') + '\n'
	source := work + '/production.c'
	os.write_file(source, prefix + bodies.join('\n\n') + '\n')!
	if hosttest.c_bodies(os.read_file(source)!) != bodies {
		return error('Production-only extraction changed a body')
	}
	mut objects := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for optimization in ['O0', 'O1', 'O2'] {
			object := work + '/production-' + standard + '-' + optimization + '.o'
			argv := [hosttest.env_default('CC', 'clang'), '--target=x86_64-unknown-none',
				'-std=' + standard, '-' + optimization, '-ffreestanding', '-fno-builtin', '-fwrapv',
				'-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
				'-nostdinc', '-isystem', hosttest.root() + '/kernel/freestnd-c-hdrs']
			proof := compile_input(argv, source, object, object + '.compile.log', environment)!
			imports := hosttest.command([hosttest.tool('llvm-nm'), '--undefined-only', object], object + '.imports.log', 30, environment)!.stdout
			mut actual := []string{}
			for line in imports.split_into_lines() {
				if line.fields().len > 0 { actual << line.fields().last() }
			}
			mut expected := ['array_get', 'cpu__cpuid', 'cpu__interrupt_state', 'katomic__load_T_u32',
				'katomic__load_T_u64', 'katomic__store_T_u32', 'lib__kpanic', 'x86_rdmsr_safe']
			// The genuine scalar Option helper zeroes its stack return record;
			// clang lowers that aggregate initialization to memset at O0.
			if optimization == 'O0' { expected << 'memset' }
			actual.sort()
			expected.sort()
			if actual != expected || hosttest.allocation_symbols(imports) {
				return error('Unexpected production-only imports: ' + imports)
			}
			objects << json2.Any({
				'standard':     json2.Any(standard)
				'optimization': optimization
				'compiled':     proof
				'imports':      hosttest.strings(actual)
			})
		}
	}
	return {
		'objects': json2.Any(objects)
		'scope':   'All six unchanged generated production bodies, including the actual private query, public export adapter and genuine native fault-safe MSR Option helper, separately compiled for freestanding x86_64-unknown-none. Only bounded native transport/boot-record/panic callees remain unresolved; no allocator import. Actual native Local metadata and #GP recovery are separate kernel-artifact evidence.'
	}
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', root + '/third_party/linux-i915/linux-6.6.157')
	hosttest.verify_upstream(linux, hosttest.upstream_pin()!)!
	work := hosttest.work_dir(keep, 'vinix-cpu-bug-v-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	stage := work + '/stage'
	for module_name in ['linuxkpi', 'katomic', 'lib', 'x86/cpu', 'x86/msr', 'cpubugfixture'] {
		os.mkdir_all(stage + '/' + module_name)!
	}
	mut inputs := [@FILE, root + '/kernel/x86/cpu/linuxkpi_l1tf_amd64.v',
		root + '/kernel/linuxkpi/cpu_bugs_amd64.v', root + '/kernel/x86/msr/safe.v',
		root + '/kernel/linuxkpi/include/asm/cpufeature.h',
		root + '/kernel/linuxkpi/include/vinix/runtime.h', root + '/kernel/linuxkpi/upstream.json']
	for directory in ['tests/linuxkpi/cpubugfixture', 'tests/linuxkpi/hosttest'] {
		for extension in ['.v', '.h'] { inputs << os.walk_ext(root + '/' + directory, extension) }
	}
	before := hosttest.hashes(inputs)!
	os.cp(root + '/kernel/x86/cpu/linuxkpi_l1tf_amd64.v', stage + '/x86/cpu/linuxkpi_l1tf_amd64.v')!
	os.cp(root + '/kernel/linuxkpi/cpu_bugs_amd64.v', stage + '/linuxkpi/cpu_bugs_amd64.v')!
	os.cp(root + '/tests/linuxkpi/cpubugfixture/core.v', stage + '/cpubugfixture/core.v')!
	os.cp(root + '/tests/linuxkpi/cpubugfixture/contract.h', stage + '/cpubugfixture/contract.h')!
	oracle := original_oracle(work, linux)!
	safe_source := hosttest.v_function(os.read_file(root + '/kernel/x86/msr/safe.v')!, 'read_safe')!
	os.write_file(stage + '/x86/msr/selected.v', 'module msr\nfn C.x86_rdmsr_safe(u32,&u64)bool\n' + safe_source)!
	os.write_file(stage + '/x86/cpu/transport.v', 'module cpu\nimport cpubugfixture as model\npub fn interrupt_state()bool{return model.interrupt_state()}\npub fn cpuid(a u32,b u32)(bool,u32,u32,u32,u32){return model.cpuid(a,b)}\n')!
	os.write_file(stage + '/katomic/transport.v', 'module katomic\nimport cpubugfixture as model\npub fn load[T](value &T)T{return model.load(value)}\npub fn store[T](mut value T,item T){model.store(unsafe {&u32(value)},u32(item))}\n')!
	os.write_file(stage + '/lib/transport.v', 'module lib\nimport cpubugfixture as model\n@[noreturn] pub fn kpanic(_frame voidptr,message &char){model.fatal(message)}\n')!
	os.write_file(stage + '/linuxkpi/transport.v', '@[has_globals]\nmodule linuxkpi\nimport cpubugfixture as model\npub type Local=model.Local\n__global cpu_locals []&Local\n' +
		"@[export:'cpubug_configure'] pub fn configure(count i64,sample u32){boot_l1tf_sample=0;boot_bug_count=0;boot_bug_ready=0;model.configure(unsafe {&cpu_locals},count,sample);model.register_slots(&boot_l1tf_sample,&boot_bug_count,&boot_bug_ready)}\n" +
		"@[export:'cpubug_initialize'] pub fn initialize(){initialise_cpu_bugs()}\n" +
		"@[export:'cpubug_state'] pub fn state(which int)u32{return match which {0 {boot_l1tf_sample}1 {boot_bug_count}else{boot_bug_ready}}}\n" +
		"@[export:'cpubug_seed_ready'] pub fn seed(value u32){boot_bug_ready=value}\n")!
	os.write_file(stage + '/v.mod', "Module { name:'cpu_bug_fixture' }\n")!
	os.write_file(stage + '/entry.v', 'module main\nimport cpubugfixture as _\nimport linuxkpi as _\nimport x86.cpu as _\nfn main(){}\n')!
	compiler := os.real_path(hosttest.command(['sh', '-c',
		'. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root], '', 30, os.environ())!.stdout)
	compiler_before := hosttest.sha(compiler)!
	mut compiler_inputs := [os.dir(compiler) + '/vlib/builtin/array.v',
		os.dir(compiler) + '/vlib/builtin/string.v']
	compiler_inputs = compiler_inputs.filter(os.exists(it))
	compiler_source_before := hosttest.hashes(compiler_inputs)!
	mut environment := os.environ()
	environment['VCACHE'] = work + '/vcache'
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	environment['UBSAN_OPTIONS'] = 'halt_on_error=1'
	environment['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	raw_path := work + '/generated.c'
	generation := [compiler, '-nocache', '-no-closures', '-os', 'vinix', '-arch', 'amd64',
		'-target-libc-headers', '-gc', 'none', '-manualfree', '-d', 'nofloat', '-d',
		'linuxkpi_host_test', '-d', 'linuxkpi', '-o', raw_path, stage]
	hosttest.command(generation, work + '/generation.log', 180, environment)!
	raw := os.read_file(raw_path)!
	selected := work + '/selected.c'
	os.write_file(selected, selected_source(raw)!)!
	production_names := ['cpu__linuxkpi_classify_l1tf', 'cpu__linuxkpi_sample_l1tf', 'msr__read_safe',
		'linuxkpi__initialise_cpu_bugs', 'linuxkpi__boot_cpu_has_bug', 'vinix_linuxkpi_boot_cpu_has_bug']
	mut production_hashes := map[string]string{}
	for name in production_names {
		body := hosttest.extract_body(raw, name)!
		if hosttest.extract_body(os.read_file(selected)!, name)! != body {
			return error('Production body changed: ' + name)
		}
		for allocator in ['malloc', 'calloc', 'realloc', 'memdup', 'v_malloc', 'new_array',
			'array_clone', 'array_push', 'string_clone', 'IError'] {
			if hosttest.has_word(body, allocator) {
				return error('Allocation/boxing in production body ' + name)
			}
		}
		production_hashes[name] = hosttest.text_sha(body)
	}
	mut includes := ['-D__KERNEL__', '-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-include',
		root + '/tests/linuxkpi/host_types.h', '-include', 'linux/kconfig.h', '-include',
		linux + '/include/linux/compiler_types.h']
	for directory in [stage, root + '/kernel/linuxkpi/include', linux + '/include',
		linux + '/include/uapi', linux + '/arch/x86/include', linux + '/arch/x86/include/uapi'] {
		includes << ['-I', directory]
	}
	mut common := [hosttest.env_default('CC', 'clang'), '-g', '-ffreestanding', '-fno-builtin',
		'-fwrapv', '-fno-strict-aliasing', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
		'-Wno-unused-parameter', '-pthread', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	$if macos {
		common << ['-arch', 'x86_64']
	}
	mut profiles := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for optimization in ['O0', 'O1', 'O2'] {
			name := standard + '-' + optimization
			object := work + '/' + name + '.o'
			executable := work + '/' + name
			compiled := compile_input([...common, '-std=' + standard, '-' + optimization, ...includes], selected, object, work + '/' + name + '.compile.log', environment)!
			symbols := hosttest.command(['nm', '-u', object], work + '/' + name + '.imports.log', 30, environment)!.stdout
			if hosttest.allocation_symbols(symbols) {
				return error('Generated CPU bug fixture imports allocator: ' + symbols)
			}
			hosttest.command([...common, object, '-o', executable], work + '/' + name + '.link.log', 180, environment)!
			result := hosttest.command([executable], work + '/' + name + '.run.log', 180, environment)!
			if !result.stdout.contains('PASS: V L1TF source-derived matrix=') || result.stderr != '' {
				return error('Incomplete/diagnosed V CPU bug fixture')
			}
			profiles << json2.Any({
				'standard':          json2.Any(standard)
				'optimization':      optimization
				'compiled':          compiled
				'executable_sha256': hosttest.sha(executable)!
				'run_log':           work + '/' + name + '.run.log'
				'output':            result.stdout
			})
			println(name + ': ' + result.stdout.trim_space())
		}
	}
	production := production_objects(work, raw, os.read_file(selected)!, production_names, environment)!
	if before != hosttest.hashes(inputs)! || compiler_before != hosttest.sha(compiler)!
		|| compiler_source_before != hosttest.hashes(compiler_inputs)! {
		return error('Source/compiler changed during validation')
	}
	hosttest.write_json(work + '/result.json', {
		'scope':                         json2.Any(scope)
		'source_sha256':                 hosttest.string_map(before)
		'compiler':                      compiler
		'compiler_sha256':               compiler_before
		'compiler_source_sha256':        hosttest.string_map(compiler_source_before)
		'generation_argv':               hosttest.strings(generation)
		'generated_sha256':              hosttest.sha(raw_path)!
		'selected_sha256':               hosttest.sha(selected)!
		'production_body_sha256':        hosttest.string_map(production_hashes)
		'production_only_objects':       production
		'original_msr_read_safe_sha256': hosttest.text_sha(safe_source)
		'oracle':                        oracle
		'profiles':                      profiles
	})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: cpu_bugs.v [--keep-dir NEW]', scope) or {
		eprintln(err)
		exit(2)
	}
	run_profile(keep) or {
		eprintln(err)
		exit(1)
	}
}
