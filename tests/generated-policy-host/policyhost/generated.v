// SPDX-License-Identifier: GPL-2.0-only
module policyhost
import json2

const syscall_names = ['mmap__syscall_instruction_size', 'mmap__syscall_instruction_word', 'mmap__syscall_instruction_aligned', 'mmap__validate_syscall_pin_region', 'proc__policy_pins', 'proc__policy_drop', 'proc__syscall_origin_allowed', 'proc__syscall_policy_control', 'proc__syscall_policy_inherit', 'proc__syscall_policy_reset']
const execute_arm_names = ['memory__disable_execute_only', 'memory__execute_only_supported', 'cpu__has_epan', 'cpu__enable_pan', 'mmap__page_table_flags', 'memory__portable_to_arm64_pte']
const mounted_names = ['resource__BlockIdentity__valid', 'resource__BlockIdentity__overlaps', 'resource__block_identity', 'fs__begin_filesystem_block_mount', 'fs__MknodDeviceResource__block_identity', 'ext2__EXT2Filesystem__block_identity', 'security__block_policy_index', 'security__block_write_allowed_locked', 'security__user_device_write_allowed', 'security__begin_user_device_write', 'security__end_user_device_write', 'security__begin_block_mount', 'security__finish_block_mount']

pub fn syscall_content(source string) !string {
	mut bodies := []string{}
	for name in syscall_names { bodies << extract(source, name, 'syscall')! }
	for i, body in bodies { if allocation(body, 'syscall') { return failure('SystemExit', 'Unexpected allocation in ' + syscall_names[i]) } }
	if bodies[7].count('vinix_stack_alloc(') != 1 { return failure('SystemExit', 'Policy request must use exactly one caller-stack descriptor') }
	declarations := bodies.map(strip_right(it[..it.index('{') or { 0 }]) + ';').join('\n')
	return syscall_adapters + declarations + '\n' + bodies.join('\n\n') + syscall_tests
}

pub fn execute_content(source string) !(string, int) {
	arm := source.split('\n').any(it.starts_with('u64 memory__portable_to_arm64_pte(') && it.all_before(';').contains(') {'))
	names := if arm { execute_arm_names } else { ['mmap__page_table_flags'] }
	mut bodies := []string{}
	for name in names { bodies << extract(source, name, 'execute')! }
	if arm {
		adapted, count := pan_adapter(bodies[3]); bodies[3] = adapted
		if count != 1 || bodies[3].contains('__asm__') { return failure('RuntimeError', 'unexpected PAN instruction adapter; inspect generated C') }
	}
	prefixes := ['memory__pte_', 'mmap__prot_', ...if arm { ['memory__arm64_pte_', 'cpu__pstate_pan'] } else { []string{} }]
	mut defines := []string{}
	for line in split_lines(source) {
		if line.starts_with('#define ') {
			fields := whitespace_fields(line)
			if fields.len < 2 { return failure('IndexError', 'list index out of range') }
			if prefixes.any(fields[1].starts_with(it)) { defines << line }
		}
	}
	mut declaration := ''
	if arm {
		for line in source.split('\n') { if line in ['bool memory__arm64_execute_only = true;', 'bool memory__arm64_execute_only = false;'] { declaration = line; break } }
		if declaration == '' { return failure('RuntimeError', 'missing production execute-only boot gate') }
	}
	return '#define TEST_ARM ' + (if arm { '1' } else { '0' }) + '\n' + execute_adapters + defines.join('\n') + '\n' + declaration + '\n' + bodies.join('\n\n') + execute_tests, bodies.len
}

fn hardware_layout(source string, name string) !string {
	start := source.index('struct ' + name + ' {') or { return failure('RuntimeError', 'missing hardware register layout: ' + name) }
	end := source.index_after('\n};', start) or { return failure('RuntimeError', 'missing hardware register layout: ' + name) }
	return source[start..end + 3]
}
fn expression(value string, name string, label string) !string {
	prefix := 'c->' + name + ' = '
	start := value.index(prefix) or { return failure('RuntimeError', 'missing production ' + label + ' decode') }
	end := value.index_after(';', start + prefix.len) or { return failure('RuntimeError', 'missing production ' + label + ' decode') }
	if end == start + prefix.len { return failure('RuntimeError', 'missing production ' + label + ' decode') }
	return value[start + prefix.len..end]
}
pub fn mounted_content(source string, architecture string) !(string, int) {
	names := [ ...mounted_names, ...if architecture == 'aarch64' { ['virtio_blk__VirtioBlockDevice__block_identity'] } else { ['ahci__AHCIDevice__block_identity', 'nvme__NVMENamespace__block_identity', 'partition__Partition__block_identity', 'partition__partition_identity'] } ]
	mut bodies := map[string]string{}
	for name in names { bodies[name] = extract(source, name, 'mounted')! }
	for name in names { if allocation(bodies[name], 'mounted') { return failure('RuntimeError', 'per-call allocation in ' + name) } }
	for name in ['resource__block_identity', 'fs__begin_filesystem_block_mount'] {
		if bodies[name].count('vinix_stack_alloc(') != 1 { return failure('RuntimeError', 'missing bounded caller-stack dispatch in ' + name) }
	}
	transfer := extract(source, 'pipe__move_between', 'mounted')!
	// Keep Python's short-circuit evaluation: a missing later token is inspected
	// only when the preceding ordering comparison succeeds.
	begin := index_required(transfer, 'security__begin_user_device_write(')!
	allocation_index := index_required(transfer, 'memory__malloc(')!
	if begin >= allocation_index || allocation_index >= index_required(transfer, 'resource__Resource__read(')! { return failure('RuntimeError', 'transfer authorizes after allocating or consuming input') }
	if transfer.count('security__end_user_device_write(block_token)') != 4 { return failure('RuntimeError', 'transfer token is not released on all four exit paths') }
	mut code := mounted_fixture_0 + bodies['resource__BlockIdentity__valid'] + '\n' + bodies['resource__BlockIdentity__overlaps'] + '\n'
	mut extra := ''
	if architecture == 'amd64' {
		code += bodies['partition__partition_identity'] + '\n'
		for name in ['ahci__AHCIRegisters', 'ahci__AHCIPortRegisters'] { code += '#pragma pack(push, 1)\n' + hardware_layout(source, name)! + '\n#pragma pack(pop)\n' }
		code += mounted_fixture_1
		code += extract(source, 'ahci__AHCIDevice__find_cmd_slot', 'mounted')! + '\n'
		initialisation := extract(source, 'ahci__AHCIController__initialise', 'mounted')!
		code += 'static u32 ports(u32 cap) { struct ahci__AHCIRegisters reg = {.cap = cap}; struct ahci__AHCIRegisters *regs = &reg; return ' + expression(initialisation, 'port_cnt', 'CAP.NP')! + '; }\n'
		code += 'static u32 command_slots(u32 cap) { struct ahci__AHCIRegisters reg = {.cap = cap}; struct ahci__AHCIRegisters *regs = &reg; return ' + expression(initialisation, 'cmd_slots', 'CAP.NCS')! + '; }\n'
		extra = mounted_fixture_2
	}
	code += mounted_fixture_4 + extra + mounted_fixture_3
	return code, bodies.len
}
fn compile_test(directory string, filename string, content string, family string) ! {
	write_text(directory + '/' + filename + '.c', content)!
	flags := if family == 'syscall' { ['-std=gnu11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-fsanitize=address,undefined', '-pthread'] } else if family == 'execute' { ['-std=gnu11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer'] } else { ['-O2', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined'] }
	run(['clang', ...flags, directory + '/' + filename + '.c', '-o', directory + '/' + filename])!
	run([directory + '/' + filename])!
}
pub fn dispatch(row map[string]json2.Any) !json2.Any {
	operation := text(row, 'operation')
	if operation == 'assembly_main' { return assembly_main(decoded(text(row, 'root'))!) }
	if operation == 'assembly_content' { return json2.Any(assembly_content(decoded(text(row, 'header'))!, decoded(text(row, 'source'))!)!.bytes().hex()) }
	if operation == 'assembly_constant' { return json2.Any((if text(row, 'name') == 'C' { assembly_c } else { assembly_ports }).bytes().hex()) }
	if operation == 'extract' { return json2.Any(extract(decoded(text(row, 'source'))!, text(row, 'name'), text(row, 'family'))!.bytes().hex()) }
	if operation == 'allocation' { return json2.Any(allocation(decoded(text(row, 'source'))!, text(row, 'family'))) }
	family := text(row, 'family')
	if operation == 'constant' {
		name := text(row, 'name')
		if name == 'FUNCTIONS' { return json2.Any(syscall_names.map(json2.Any(it))) }
		value := if family == 'syscall' { if name == 'ADAPTERS' { syscall_adapters } else { syscall_tests } } else { if name == 'ADAPTERS' { execute_adapters } else { execute_tests } }
		return json2.Any(value.bytes().hex())
	}
	source := if operation == 'content' { decoded(text(row, 'source'))! } else { read_text(decoded(text(row, 'path'))!)! }
	mut count := 0
	content := if family == 'syscall' { syscall_content(source)! } else if family == 'execute' { value, total := execute_content(source)!; count = total; value } else { value, total := mounted_content(source, text(row, 'arch'))!; count = total; value }
	if operation == 'content' { return json2.Any(content.bytes().hex()) }
	prefix := if family == 'syscall' { 'vinix-syscall-policy-host-' } else if family == 'execute' { 'vinix-xom-generated-' } else { 'vinix-block-generated-' }
	filename := if family == 'syscall' { 'host' } else { 'test' }
	directory := temporary(prefix)!
	compile_test(directory, filename, content, family) or { retire(directory)!; return err }
	retire(directory)!
	if family == 'execute' { emit('PASS: ${count} actual production functions checked')! }
	if family == 'mounted' { emit('PASS ' + text(row, 'arch') + ': ${count} production dispatch/token helpers have no per-call allocation')! }
	return json2.Null{}
}
