// SPDX-License-Identifier: GPL-2.0-only
module policyhost

fn test_original_greedy_opening_conventions() {
	source := 'u64 target(void) { } ) { tail }'
	assert extract(source, 'target', 'mounted')! == source
	assert extract(source, 'target', 'syscall')! == 'u64 target(void) { }'
	assert extract(source, 'target', 'execute')! == 'u64 target(void) { }'
	assert extract('u64 target(void) { x; } ) { tail }', 'target', 'mounted')! == 'u64 target(void) { x; }'
}
fn test_unicode_word_and_guard_boundaries() {
	assert allocation('αmalloc¹\u2003(1)', 'execute')
	assert !allocation('not_memdup(1)', 'syscall')
	assert allocation('!memdup\u0085(1)', 'syscall')
	assert allocation('__new_array𐐀(1)', 'mounted')
	assert !allocation('malloc\u0301(1)', 'execute')
	assert split_lines('a\r\nb\u0085c\u2028d\x1ce\n') == ['a', 'b', 'c', 'd', 'e']
}
fn test_pan_adapter_only_changes_the_privileged_instruction() {
	source := 'before __asm__ volatile (\n "msr pan, #1\\n\\t" : : : "memory" ); after'
	adapted, count := pan_adapter(source)
	assert count == 1
	assert adapted == 'before host_set_pan(); after'
	invalid, rejected := pan_adapter(source.replace('pan, #1', 'pan, #0'))
	assert rejected == 0 && invalid == source.replace('pan, #1', 'pan, #0')
}
