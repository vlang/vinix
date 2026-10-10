// SPDX-License-Identifier: GPL-2.0-or-later
module linkedcheck

fn fixture(count int) string {
	return 'file format elf64-x86-64\n<vinix_x86_resume_context>:\n<__x86_indirect_thunk_rax>:\n' +
		'  1: callq 0 <__x86_indirect_thunk_rax>\n'.repeat(count)
}

fn test_linked_policy_rejects_every_original_failure() {
	assert check(fixture(100))! == 100
	for listing, message in {
		fixture(100).replace('elf64-x86-64', 'elf64-aarch64'):           'FAIL: expected an x86-64 production ELF'
		fixture(100) + '  2: jmpq *%rax\n':                              'FAIL: raw indirect branches:\n  2: jmpq *%rax'
		fixture(100) + '  2: call 0 <__x86_indirect_thunk_rbx+4>\n':     'FAIL: unresolved thunk rbx'
		fixture(100).replace('<vinix_x86_resume_context>:', '<other>:'): 'FAIL: missing final scheduler mitigation stub'
		fixture(99):                                                     'FAIL: compiler mitigation appears absent'
	} {
		check(listing) or {
			assert err.msg() == message
			continue
		}
		assert false, 'accepted broken mitigation listing'
	}
	assert check(fixture(100) + '<__x86_indirect_thunk_rbx>:\n  call 0 <__x86_indirect_thunk_rbx+4>\n')! == 101
}

fn test_unicode_boundaries_greedy_matches_and_cross_line_space() {
	text := fixture(100)
	assert check(text + 'αcall *%rax\nnotjmp *%rax\ncallable *%rax\n')! == 100
	for line in ['call\u2003*%rax', 'jmpq\u0085*%rax', '\u0301call *%rax', 'call\n  *%rax'] {
		check(text + line + '\n') or {
			assert err.msg().starts_with('FAIL: raw indirect branches:\n')
			continue
		}
		assert false, 'accepted raw branch with Unicode boundary/space'
	}
	assert check(text + 'call\n <__x86_indirect_thunk_rax>\n')! == 101
	assert check(text + 'call <__x86_indirect_thunk_rax> call <__x86_indirect_thunk_rax>\n')! == 101
	assert check(text + 'xcall <__x86_indirect_thunk_rax>\ncallx <__x86_indirect_thunk_rax>\n')! == 100
	mut many := []string{}
	for i in 0 .. 21 { many << '${i}: call *%rax' }
	check(text + many.join('\n')) or {
		assert err.msg() == 'FAIL: raw indirect branches:\n' + many[..20].join('\n')
		return
	}
	assert false, 'accepted raw branches'
}
