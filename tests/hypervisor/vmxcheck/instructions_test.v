// SPDX-License-Identifier: GPL-2.0-only
module vmxcheck

import os

fn instruction_fixture() (string, string) {
	mut assembly := ''
	mut text := ''
	for pair in [['on', 'vmxon'], ['off', 'vmxoff'], ['clear', 'vmclear'], ['load', 'vmptrld'],
		['write', 'vmwriteq'], ['read', 'vmreadq'], ['invept', 'invept']] {
		assembly += '<vinix_vmx_${pair[0]}>:\n  0:\t${pair[1]} %rax\n  3:\tsetbe %al\n\n'
		opcode := if pair[0] == 'write' {
			'vmwrite %[value], %[field]'
		} else if pair[0] == 'read' {
			'vmread %[field], %[result]'
		} else if pair[0] == 'invept' {
			'invept %[operand], %[extent]'
		} else {
			pair[1]
		}
		text += '__asm__ volatile ("${opcode}" : : : "cc", "memory");\n'
	}
	return assembly, text
}

fn refused(assembly string, text string, message string) {
	check_instructions(assembly, text) or {
		assert err.msg() == message
		return
	}
	assert false, 'accepted invalid instruction evidence: ${message}'
}

fn test_cf_zf_immediacy_operand_order_clobbers_and_ept_invalidation() {
	assembly, text := instruction_fixture()
	check_instructions(assembly, text)!
	for opcode in ['vmxon', 'vmxoff', 'vmclear', 'vmptrld', 'vmwriteq', 'vmreadq', 'invept'] {
		refused(assembly.replace('${opcode} %rax\n  3:\tsetbe', '${opcode} %rax\n  2:\tnop\n  3:\tsetbe'), text, '${opcode} must immediately capture CF/ZF')
	}
	refused(assembly, text.replace('vmwrite %[value], %[field]', 'vmwrite %[field], %[value]'), 'VMWRITE operand order changed')
	refused(assembly, text.replace('vmread %[field], %[result]', 'vmread %[result], %[field]'), 'VMREAD operand order changed')
	refused(assembly, text.replace('invept %[operand], %[extent]', 'invept %[extent], %[operand]'), 'INVEPT operand order changed')
	for field in ['"cc"', '"memory"'] {
		refused(assembly, text.replace(field, '"other"'), 'VMX flags/memory clobbers changed')
	}
	refused(assembly, text + '__asm__ volatile ("vmxon" : : : "cc", "memory");', 'VMX flags/memory clobbers changed')
	refused(assembly.replace('<vinix_vmx_on>:', '<other>:'), text, 'list index out of range')
	refused(assembly.replace('vmxon %rax', 'nop'), text, '')
	refused('<vinix_vmx_on>:\n  0:\tvmxon %rax', text, 'list index out of range')
}

fn test_allocator_boundaries_unicode_lines_and_objdump_search() {
	for name in ['malloc', '_calloc', 'realloc', '_free', 'memdup', '_new_array_from_c_array',
		'new_array猫'] {
		assert forbidden(' U ${name}\n')
	}
	for name in ['xmalloc', '__malloc', 'malloc_suffix', 'freeing', 'notnew_array'] {
		assert !forbidden(' U ${name}\n')
	}
	for separator in ['\n', '\r', '\r\n', '\v', '\f', '\x1c', '\x1d', '\x1e', '\u0085', '\u2028',
		'\u2029'] {
		assert text_lines('one${separator}two${separator}') == ['one', 'two']
	}
	c := Config{
		env: {
			'PATH': ''
		}
	}
	assert c.objdump_path() == '/opt/homebrew/opt/llvm/bin/llvm-objdump'
	work := os.getenv('VINIX_VMX_OBJDUMP_TEST_DIR')
	if work != '' {
		executable := join(work, 'llvm-objdump')
		os.write_file(executable, '')!
		os.chmod(executable, 0o700)!
		assert Config{
			env: {
				'PATH': work + ':' + work
			}
		}.objdump_path() == executable
		os.chmod(executable, 0o600)!
		assert Config{
			env: {
				'PATH': work
			}
		}.objdump_path() == '/opt/homebrew/opt/llvm/bin/llvm-objdump'
		os.rm(executable)!
	}
}
