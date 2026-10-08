// SPDX-License-Identifier: GPL-2.0-only
module policyhost
fn test_metadata_filters_keep_unterminated_final_lines() {
	assert remove_assembly_lines('.type a, function\nret\n.size a, .-a\n', true) == 'ret\n'
	assert remove_assembly_lines('.type a, function\n.size a, .-a', true) == '.size a, .-a'
	assert remove_assembly_lines('.type a, function\n.size a, .-a\n', false) == '.size a, .-a\n'
	assert remove_assembly_lines('.type\n.typea x\n', true) == '.type\n.typea x\n'
}
fn test_symbol_addresses_keep_all_decimal_digits() {
	mut symbols := map[string]string{}
	for name in [...assembly_globals, 'host_enter', 'host_leave', 'host_switch', 'host_rsb', 'host_probe', 'host_resume_probe'] { symbols['_' + name] = '18446744073709551616000000000000000001' }
	content := assembly_fixture([u8(0), 127, 255], symbols)!
	assert content.contains('static const unsigned char code[]={0,127,255};')
	assert content.contains('blob+18446744073709551616000000000000000001')
	assert content.contains('uint64_t storage[64] = {0}, *frame = storage + 32;')
}
