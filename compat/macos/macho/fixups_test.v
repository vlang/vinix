module macho

fn test_decodes_classic_rebase_program() {
	// pointer, segment 2 + offset 0x88, rebase twice, done
	stream := [u8(0x11), 0x22, 0x88, 0x01, 0x52, 0x00]
	fixups := decode_rebases(stream, 4) or { panic(err) }
	assert fixups.len == 2
	assert fixups[0].segment_index == 2
	assert fixups[0].offset == 0x88
	assert fixups[1].offset == 0x90
}

fn test_decodes_classic_symbol_bind() {
	mut stream := [u8(0x11), 0x40]
	stream << '_objc_msgSend'.bytes()
	stream << u8(0)
	stream << [u8(0x51), 0x72, 0xb8, 0x02, 0x90, 0x00]
	fixups := decode_binds(stream, 4, false) or { panic(err) }
	assert fixups.len == 1
	assert fixups[0].segment_index == 2
	assert fixups[0].offset == 0x138
	assert fixups[0].symbol == '_objc_msgSend'
}

fn test_rejects_unknown_rebase_opcode() {
	decode_rebases([u8(0x90)], 1) or {
		assert err.msg().contains('opcode')
		return
	}
	assert false
}

fn test_empty_optional_fixup_streams_are_valid() {
	assert (decode_rebases([]u8{}, 1) or { panic(err) }).len == 0
	assert (decode_binds([]u8{}, 1, false) or { panic(err) }).len == 0
}
