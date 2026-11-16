// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn test_packet_initializer_and_restricted_translation() {
	assert packet_expected('    helper_arg: U64(cmdbuf.helper.data), // comment\n', 'helper_arg')! == 'input.helper.data'
	assert packet_expression('(cmdbuf.sampler_count as u32) + 1')! == '(u32(input.sampler_count) + u32(1))'
	assert packet_expression('F32::from_bits(cmdbuf.isp_merge_upper_x)')! == 'input.isp_merge_upper_x'
	assert packet_expression('U64(self.usc_exec_base)')! == 'usc'
	for source in ['cmdbuf.helper.data + 1', 'new_default()', '0xzz', 'U64(cmdbuf.foo', '-1', 'cmdbuf.x; side_effect()'] {
		if value := packet_expression(source) { assert false, 'accepted ${source}: ${value}' }
	}
	for source in ['other: 0,\n', 'value: 0,\nvalue: 1,\n'] {
		if value := packet_initializer(source, 'value') { assert false, 'accepted ambiguous/missing ${value}' }
	}
}

fn test_packet_canonical_field_inventory() {
	assert packet_fields('pub struct Command {\npub:\n\tflags u64\n\tattachments [16]Attachment\n}\n')! == {'flags': 'u64', 'attachments': '[16]Attachment'}
	if _ := packet_fields('pub struct Command {\nfield u32 = 1\n}\n') { assert false }
	assert packet_attachment_field('compute', 'attachments')
	assert packet_attachment_field('render', 'vertex_attachment_count')
	assert !packet_attachment_field('compute', 'unknown_attachments')
	assert !packet_attachment_field('render', 'extra_attachment_count')
}
