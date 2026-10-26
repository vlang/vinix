// SPDX-License-Identifier: GPL-2.0-or-later
module winejitstream

fn assert_parse_refused(text string, role string) {
	parse(text, role) or { return }
	assert false, 'malformed capture was accepted'
}

fn test_parse_scopes_rows_to_ready_and_normalizes_words() {
	capture := parse('0x1000:  d503201f  nop\nOUT: [size=8]\nJITSTREAM READY parent pid=123\n0x2000:  D503201F  nop\n0x2004:  d65f03c0  ret\nJITSTREAM ARITHMETIC parent PASS pid=123\n',
		'parent')!
	assert capture.role == 'parent'
	assert capture.pid == 123
	assert capture.arithmetic_pass
	assert capture.instructions.len == 2
	assert u64(0x1000) !in capture.instructions
	assert capture.instructions[u64(0x2000)] == ['d503201f']
	assert capture.instructions[u64(0x2004)] == ['d65f03c0']
}

fn test_parse_requires_one_exact_ready_and_canonical_positive_pid() {
	row := '\n0x2000:  d503201f  nop\n'
	for marker in [
		'',
		'JITSTREAM READY child pid=123',
		'JITSTREAM READY parent pid=',
		'JITSTREAM READY parent pid=0',
		'JITSTREAM READY parent pid=0123',
		'JITSTREAM READY parent pid=-1',
		'JITSTREAM READY parent pid=+1',
		'JITSTREAM READY parent pid=1x',
		'JITSTREAM READY parent pid=123 ',
		' JITSTREAM READY parent pid=123',
		'JITSTREAM READY parent pid=2147483648',
		'JITSTREAM READY parent pid=9999999999999999999999999999',
		'JITSTREAM READY parent pid=123\nJITSTREAM READY parent pid=123',
		'JITSTREAM READY parent pid=123\nJITSTREAM READY child pid=124',
	] {
		assert_parse_refused(marker + row, 'parent')
	}
	assert_parse_refused('JITSTREAM READY parent pid=123' + row, 'other')
	assert_parse_refused('JITSTREAM READY parent pid=123\n', 'parent')
	assert_parse_refused('0x2000:  d503201f  nop\nJITSTREAM READY parent pid=123\n',
		'parent')
	assert parse('JITSTREAM READY parent pid=2147483647' + row, 'parent')!.pid == 2147483647
}

fn test_parse_rejects_malformed_aarch64_instruction_rows() {
	for row in [
		'0x2000',
		'0x:  d503201f  nop',
		'0X2000:  d503201f  nop',
		'0x2g00:  d503201f  nop',
		'0x10000000000000000:  d503201f  nop',
		' 0x2000:  d503201f  nop',
		'0x2000: d503201f  nop',
		'0x2000:   d503201f  nop',
		'0x2000:\td503201f  nop',
		'0x2000:  d503201  nop',
		'0x2000:  d503201ff  nop',
		'0x2000:  d503201g  nop',
		'0x2000:  d503201f',
		'0x2000:  d503201f ',
		'0x2000:  d503201f  \t',
	] {
		assert_parse_refused('JITSTREAM READY parent pid=123\n' + row + '\n', 'parent')
	}
}

fn test_parse_checks_optional_arithmetic_marker() {
	base := 'JITSTREAM READY parent pid=123\n0x2000:  d503201f  nop\n'
	assert !parse(base, 'parent')!.arithmetic_pass
	for marker in [
		'JITSTREAM ARITHMETIC child PASS pid=123',
		'JITSTREAM ARITHMETIC parent FAIL pid=123',
		'JITSTREAM ARITHMETIC parent PASS pid=124',
		'JITSTREAM ARITHMETIC parent PASS pid=0123',
		'JITSTREAM ARITHMETIC parent PASS pid=123 ',
		' JITSTREAM ARITHMETIC parent PASS pid=123',
		'JITSTREAM ARITHMETIC parent PASS pid=123\nJITSTREAM ARITHMETIC parent PASS pid=123',
	] {
		assert_parse_refused(base + marker + '\n', 'parent')
	}
	assert_parse_refused('JITSTREAM ARITHMETIC parent PASS pid=123\n' + base, 'parent')
}

fn test_compare_identical_different_and_disjoint_addresses() {
	parent := parse('JITSTREAM READY parent pid=123\n0x2000:  d503201f  nop\n0x2004:  d65f03c0  ret\n',
		'parent')!
	identical := parse('JITSTREAM READY child pid=124\n0x2000:  D503201F  nop\n0x2004:  d65f03c0  ret\n',
		'child')!
	equal := compare(parent, identical)!
	assert equal.parent_pid == 123
	assert equal.child_pid == 124
	assert equal.overlapping_addresses == 2
	assert equal.differing_addresses == 0
	assert equal.examples.len == 0
	different := parse('JITSTREAM READY child pid=124\n0x2000:  d503201f  nop\n0x2004:  d61f0200  br x16\n0x3000:  d65f03c0  ret\n',
		'child')!
	delta := compare(parent, different)!
	assert delta.overlapping_addresses == 2
	assert delta.differing_addresses == 1
	assert delta.examples.len == 1
	assert delta.examples[0].address == u64(0x2004)
	assert delta.examples[0].parent_words == ['d65f03c0']
	assert delta.examples[0].child_words == ['d61f0200']
	disjoint := parse('JITSTREAM READY child pid=124\n0x3000:  d503201f  nop\n', 'child')!
	separate := compare(parent, disjoint)!
	assert separate.overlapping_addresses == 0
	assert separate.differing_addresses == 0
	assert separate.examples.len == 0
}

fn test_duplicate_address_retains_all_unique_words_and_compares_any_pair() {
	parent := parse('JITSTREAM READY parent pid=123\n0x2000:  d65f03c0  ret\n0x2000:  d503201f  nop\n0x2000:  D503201F  nop\n',
		'parent')!
	child := parse('JITSTREAM READY child pid=124\n0x2000:  d503201f  nop\n0x2000:  d65f03c0  ret\n',
		'child')!
	assert parent.instructions[u64(0x2000)] == ['d503201f', 'd65f03c0']
	assert child.instructions[u64(0x2000)] == ['d503201f', 'd65f03c0']
	comparison := compare(parent, child)!
	assert comparison.overlapping_addresses == 1
	assert comparison.differing_addresses == 1
	assert comparison.examples[0].parent_words == ['d503201f', 'd65f03c0']
	assert comparison.examples[0].child_words == ['d503201f', 'd65f03c0']
}

fn test_compare_rejects_same_pid_or_reversed_roles() {
	parent := parse('JITSTREAM READY parent pid=123\n0x2000:  d503201f  nop\n', 'parent')!
	child := parse('JITSTREAM READY child pid=123\n0x2000:  d503201f  nop\n', 'child')!
	mut refused := false
	compare(parent, child) or {
		refused = true
		Comparison{}
	}
	assert refused
	refused = false
	compare(child, parent) or {
		refused = true
		Comparison{}
	}
	assert refused
}

fn test_compare_limits_examples_and_sorts_addresses() {
	mut parent_text := 'JITSTREAM READY parent pid=123\n'
	mut child_text := 'JITSTREAM READY child pid=124\n'
	for offset in 0 .. 12 {
		address := u64(0x2000 + (11 - offset) * 4)
		parent_text += '0x${address:x}:  d503201f  nop\n'
		child_text += '0x${address:x}:  d65f03c0  ret\n'
	}
	comparison := compare(parse(parent_text, 'parent')!, parse(child_text, 'child')!)!
	assert comparison.overlapping_addresses == 12
	assert comparison.differing_addresses == 12
	assert comparison.examples.len == 8
	for index, example in comparison.examples {
		assert example.address == u64(0x2000 + index * 4)
	}
}

fn test_parse_byte_limit_accepts_boundary_and_rejects_next_byte() {
	base := 'JITSTREAM READY parent pid=123\n0xffffffffffffffff:  d503201f  nop\n'
	padding := '#'.repeat(log_limit - base.len)
	boundary := base + padding
	assert boundary.len == log_limit
	capture := parse(boundary, 'parent')!
	assert capture.instructions[u64(0xffffffffffffffff)] == ['d503201f']
	assert_parse_refused(boundary + '#', 'parent')
}
