// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import fixturehost
import hosttest
import os
import policyhost

const elf_resource = 'module resource
pub struct Stat { pub: size i64 }
pub struct Resource { pub: stat Stat data []u8 }
pub fn (mut res Resource) read(_handle voidptr, output voidptr, offset u64, length u64) ?i64 {
    if offset > u64(res.data.len) || length > u64(res.data.len) - offset { return none }
    unsafe { C.memcpy(output, &res.data[int(offset)], length) }
    return i64(length)
}
'

const elf_memory = 'module memory
pub struct Lock {
pub mut:
 held bool
}
pub fn (mut l Lock) acquire() { assert !l.held; l.held = true }
pub fn (mut l Lock) release() { assert l.held; l.held = false }
pub struct Range {
pub mut:
 base u64
 length u64
 prot int
 immutable bool
}
pub struct Pagemap {
pub mut:
 l Lock
 ranges []&Range
}
'

const elf_mmap = 'module mmap
import memory
const prot_exec = 4
const prot_write = 2
fn range_lower_bound(pagemap &memory.Pagemap, address u64) &memory.Range {
    assert pagemap.l.held
    for range in pagemap.ranges { if range.base >= address { return unsafe { range } } }
    return unsafe { nil }
}
'

fn original_block(source string, prefix string) !string {
	start := source.index(prefix) or { return error('Missing production block: ' + prefix) }
	end := start + (source[start..].index('\n}') or { return error('Unterminated production block: ' + prefix) }) + 2
	return source[start..end] + '\n'
}

fn elf_host_command(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{ name: '--state-dir', value: true }], 0,
		'Usage: run-host.sh [--state-dir FRESH-DIR]', 'Exercise genuine production ELF dynamic scanning and executable range freezing.') or { return error_with_code(err.msg(), 2) }
	work := hosttest.work_dir(parsed.options['--state-dir'] or { '' }, 'vinix-elf-text-')!
	defer { if '--state-dir' !in parsed.options { retire(work) } }
	for name in ['elf', 'resource', 'mmap', 'memory'] { os.mkdir(work + '/' + name)! }
	write(work + '/v.mod', 'Module { name: "elf_text_tests" }\n')!
	source := read(root() + '/kernel/elf/elf.v')!
	mut production := 'module elf\nimport resource\n'
	for line in source.split_into_lines() {
		if ['const dt_', 'const df_textrel', 'const dynamic_scan_limit'].any(line.starts_with(it)) { production += line + '\n' }
	}
	for name in ['DynamicEntry', 'ProgramHdr'] { production += original_block(source, 'struct ' + name + ' {')! }
	for name in ['requires_text_relocation', 'dynamic_textrel', 'read_exact'] { production += original_block(source, 'fn ' + name + '(')! }
	write(work + '/elf/production.v', production)!
	write(work + '/mmap/production.v', 'module mmap\nimport memory\n' + original_block(read(root() + '/kernel/memory/mmap/immutable.v')!, 'pub fn mimmutable_executable(')!)!
	write(work + '/resource/resource.v', elf_resource)!
	write(work + '/memory/memory.v', elf_memory)!
	write(work + '/mmap/fixture.v', elf_mmap)!
	for pair in [['dynamic_test.v', 'elf'], ['immutable_test.v', 'mmap']] { os.cp(root() + '/tests/elf-text/' + pair[0], work + '/' + pair[1] + '/' + pair[0])! }
	v := output(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root()])!
	mut env := policyhost.environment()
	env['VEXE'] = v
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	for name in ['elf', 'mmap'] {
		fixturehost.inherited_command_environment_preferred([v, '-prod', '-gc', 'none', 'test', work + '/' + name], env, policyhost.caller_arch())!
	}
	return 0
}
