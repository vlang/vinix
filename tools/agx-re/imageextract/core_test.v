module imageextract

import os
import traceanalysis as j

fn fixture_header(commands [][]u8, file_type u32) []u8 {
	mut data := []u8{len: 32}
	set_u32(mut data, 0, macho_magic_64)
	set_u32(mut data, 4, 0x0100000c)
	set_u32(mut data, 8, 0xc0000002)
	set_u32(mut data, 12, file_type)
	set_u32(mut data, 16, u32(commands.len))
	mut count := 0
	for command in commands { count += command.len }
	set_u32(mut data, 20, u32(count))
	for command in commands { data << command }
	return data
}

struct FixtureSection {
	name   string
	offset u32
	size   u64
}

fn fixture_segment(name string, address u64, file_offset u64, size u64, sections []FixtureSection) []u8 {
	mut data := []u8{len: 72 + sections.len * 80}
	set_u32(mut data, 0, lc_segment_64)
	set_u32(mut data, 4, u32(data.len))
	for index, byte in name.bytes() { data[8 + index] = byte }
	set_u64(mut data, 24, address)
	set_u64(mut data, 32, size)
	set_u64(mut data, 40, file_offset)
	set_u64(mut data, 48, size)
	set_u32(mut data, 56, 7)
	set_u32(mut data, 60, 5)
	set_u32(mut data, 64, u32(sections.len))
	for index, section in sections {
		offset := 72 + index * 80
		for i, byte in section.name.bytes() { data[offset + i] = byte }
		for i, byte in name.bytes() { data[offset + 16 + i] = byte }
		set_u64(mut data, offset + 32, address + u64(section.offset) - file_offset)
		set_u64(mut data, offset + 40, section.size)
		set_u32(mut data, offset + 48, section.offset)
		set_u32(mut data, offset + 52, 2)
	}
	return data
}

fn fixture_command(id u32, size int) []u8 {
	mut data := []u8{len: size}
	set_u32(mut data, 0, id)
	set_u32(mut data, 4, u32(size))
	return data
}

fn fixture_uuid() []u8 {
	mut uuid := fixture_command(lc_uuid, 24)
	for index in 0 .. 16 { uuid[8 + index] = u8(index) }
	return uuid
}

fn fixture_macho() []u8 {
	mut segment := fixture_segment('__TEXT', 0xfffffc0000000000, 0, 0x1000, [])
	set_u64(mut segment, 32, 0x17c000)
	mut header := fixture_header([segment, fixture_uuid()], 5)
	header << []u8{len: 0x1000 - header.len}
	return header
}

fn fixture_im4p(image_type string, payload []u8, extra bool, wrapped bool) []u8 {
	mut sequence := der_encode(0x16, 'IM4P'.bytes())
	sequence << der_encode(0x16, image_type.bytes())
	sequence << der_encode(0x16, '1'.bytes())
	sequence << der_encode(4, payload)
	if extra { sequence << der_encode(0x30, der_encode(2, [u8(1)])) }
	image := der_encode(0x30, sequence)
	if !wrapped { return image }
	mut outer := der_encode(0x16, 'IMG4'.bytes())
	outer << image
	outer << der_encode(0xa0, 'manifest'.bytes())
	return der_encode(0x30, outer)
}

fn fixture_firmware() []u8 {
	mut payload := []u8{len: 80 + 512}
	for index, byte in 'rkosftab'.bytes() { payload[32 + index] = byte }
	set_u64(mut payload, 40, 2)
	for index, variant in ['g17s', 'g17c'] {
		start := 80 + index * 256
		tag := if index == 0 { 'a010' } else { 'a000' }
		for i, byte in tag.bytes() { payload[48 + index * 16 + i] = byte }
		set_u32(mut payload, 52 + index * 16, u32(start))
		set_u64(mut payload, 56 + index * 16, 256)
		set_u32(mut payload, start, macho_magic_64)
		for i, byte in ('FW Build variant: ' + variant + '\x00').bytes() {
			payload[start + 4 + i] = byte
		}
	}
	return fixture_im4p('gfxf', payload, false, false)
}

fn fixture_collection() ([]u8, int) {
	offset := 0x4000
	text := fixture_segment('__TEXT', 0x100000, u64(offset), 0x1000, [
		FixtureSection{'__const', 0x4400, 0x20},
		FixtureSection{'__empty', 0x5400000, 0},
	])
	code := fixture_segment('__TEXT_EXEC', 0x200000, 0x9000, 0x1000, [FixtureSection{'__text', 0x9000, 0x100}])
	link := fixture_segment('__LINKEDIT', 0x300000, 0xd000, 0x2000, [])
	mut symtab := fixture_command(lc_symtab, 24)
	set_u32(mut symtab, 8, 0xd100)
	set_u32(mut symtab, 12, 1)
	set_u32(mut symtab, 16, 0xd200)
	set_u32(mut symtab, 20, 16)
	mut starts := fixture_command(lc_function_starts, 16)
	set_u32(mut starts, 8, 0xd300)
	set_u32(mut starts, 12, 8)
	header := fixture_header([text, code, link, symtab, starts, fixture_uuid()], 11)
	name := 'com.apple.AGXG17X\x00'
	mut entry := fixture_command(lc_fileset_entry, align_up(32 + name.len, 8))
	set_u64(mut entry, 8, 0x100000)
	set_u64(mut entry, 16, u64(offset))
	set_u32(mut entry, 24, 32)
	for index, byte in name.bytes() { entry[32 + index] = byte }
	root := fixture_header([entry], 12)
	mut collection := []u8{len: 0xf000}
	for index, byte in root { collection[index] = byte }
	for index, byte in header { collection[offset + index] = byte }
	for index in 0 .. 0x20 { collection[0x4400 + index] = u8(index) }
	for index in 0 .. 0x100 { collection[0x9000 + index] = `C` }
	for index in 0 .. 16 { collection[0xd100 + index] = `S` }
	return collection, offset
}

fn fixture_pmp(file_type u32) []u8 {
	segment := fixture_segment('__TEXT', 0x1000000, 0, 0x1000, [])
	mut image := fixture_header([segment, fixture_command(lc_symtab, 24), fixture_uuid()], file_type)
	image << []u8{len: 0x1000 - image.len}
	return image
}

fn test_selects_g17c_table_entry() {
	directory := os.join_path(os.temp_dir(), 'agx-v-select-' + os.getpid().str())
	os.mkdir_all(directory)!
	defer { os.rmdir_all(directory) or {} }
	path := os.join_path(directory, 'armfw_g17x.im4p')
	os.write_file_array(path, fixture_firmware())!
	tag, image := select_variant(path, 'g17c')!
	assert tag == 'a000'
	assert image_variant(image)! == 'g17c'
}

fn test_rejects_non_agx_im4p() {
	im4p_payload(fixture_im4p('krnl', 'payload'.bytes(), false, false)) or {
		assert err.msg().contains('not an AGX firmware')
		return
	}
	assert false
}

fn test_parses_macho_identity_and_virtual_layout() {
	metadata := macho_metadata(fixture_macho())!
	assert j.string_value(j.value(metadata, 'uuid')) == '00010203-0405-0607-0809-0A0B0C0D0E0F'
	assert j.value(metadata, 'virtual_address_start').u64() == 0xfffffc0000000000
	assert j.value(metadata, 'virtual_address_end').u64() == 0xfffffc000017c000
	assert j.string_value(j.value(j.value(metadata, 'segments').arr()[0].as_map(), 'name')) == '__TEXT'
}

fn test_default_entries_cover_cross_kext_gpu_event_targets() {
	assert 'com.apple.iokit.IOGPUFamily' in default_entries
	assert 'com.apple.iokit.IOSurface' in default_entries
}

fn test_default_entries_cover_t6050_power_owners() {
	for name in ['AppleARMPlatform', 'ApplePMGR', 'AppleT6050PMGR', 'ApplePMP', 'ApplePMPFirmware',
		'RTBuddy', 'AppleA7IOP', 'AppleA7IOP-ASCWrap-v6', 'AppleT8110DART', 'IODARTFamily'] {
		assert 'com.apple.driver.' + name in default_entries
	}
}

fn test_extracts_kernel_payload_with_modern_trailing_metadata() {
	payload := 'bvx2 compressed bytes'.bytes()
	image := fixture_im4p('krnl', payload, true, true)
	span := kernel_im4p_payload(image)!
	assert image[span.start..span.end] == payload
}

fn test_discovers_and_compacts_fileset_entry() {
	collection, offset := fixture_collection()
	entries := fileset_entries(collection)!
	entry := entries['com.apple.AGXG17X'] or { panic('missing entry') }
	assert entry.virtual_address == 0x100000 && entry.file_offset == u64(offset)
	image := extract_entry(collection, offset)!
	commands := load_commands(image, 0)!
	mut segments := []Segment{}
	for command in commands {
		if command.command == lc_segment_64 { segments << parse_segment(image, command)! }
	}
	assert segments.map(it.file_offset) == [u64(0), 0x4000, 0x8000]
	assert image[0x4000..0x4100] == []u8{len: 0x100, init: `C`}
	assert u32_at(image, segments[0].command_offset + 72 + 48) == 0x400
	assert u32_at(image, segments[0].command_offset + 72 + 80 + 48) == 0
	for command in commands {
		if command.command == lc_symtab {
			assert [u32_at(image, command.offset + 8), u32_at(image, command.offset + 12),
				u32_at(image, command.offset + 16), u32_at(image, command.offset + 20)] == [
				u32(0x8100),
				1,
				0x8200,
				16,
			]
			assert image[0x8100..0x8110] == []u8{len: 16, init: `S`}
		}
	}
}

fn test_accepts_uncompressed_kernel_payload() {
	collection, _ := fixture_collection()
	result := decompress_kernel(collection, 0)!
	assert result.data == collection.data
}

fn test_extracts_bare_pmp_and_reports_stripped_boundary() {
	image := fixture_pmp(5)
	container := fixture_im4p('pmpf', image, true, false)
	span := pmp_payload(container)!
	assert container[span.start..span.end] == image
	metadata := macho_metadata(image)!
	assert j.value(metadata, 'file_type').u64() == 5
	assert j.string_value(j.value(metadata, 'uuid')) == '00010203-0405-0607-0809-0A0B0C0D0E0F'
	summary := pmp_command_summary(image)!
	assert j.value(summary, 'symbol_count').u64() == 0
	assert j.value(summary, 'has_function_starts') == j.Value(false)
}

fn test_extracts_img4_wrapped_pmp() {
	image := fixture_pmp(5)
	container := fixture_im4p('pmpf', image, true, true)
	span := pmp_payload(container)!
	assert container[span.start..span.end] == image
}

fn test_rejects_non_pmp_payload() {
	pmp_payload(fixture_im4p('krnl', fixture_pmp(5), false, false)) or {
		assert err.msg().contains('not a PMP firmware')
		return
	}
	assert false
}

fn test_rejects_non_preload_macho() {
	pmp_command_summary(fixture_pmp(2)) or {
		assert err.msg().contains('not MH_PRELOAD')
		return
	}
	assert false
}

fn test_finds_one_restore_image() {
	root := os.join_path(os.temp_dir(), 'agx-v-pmp-' + os.getpid().str())
	defer { os.rmdir_all(root) or {} }
	parent := os.join_path(root, 'volume/restore/Firmware/pmp')
	os.mkdir_all(parent)!
	path := os.join_path(parent, 't6050pmp.im4p')
	os.write_file_array(path, fixture_im4p('pmpf', fixture_pmp(5), true, false))!
	assert find_source(root, 'pmp', '')! == path
}

fn test_der_length_preserves_32_bit_unsigned_length() {
	length, offset := der_length([u8(0x84), 0xff, 0xff, 0xff, 0xff], 0)!
	assert length == 0xffffffff && offset == 5
}

fn test_der_rejects_truncated_length_and_item() {
	for data in [[]u8{}, [u8(0x80)], [u8(0x85), 0, 0, 0, 0, 0]] {
		der_length(data, 0) or { continue }
		assert false
	}
	der_item([u8(0x30), 5, 0], 0, 0x30) or {
		assert err.msg() == 'truncated DER item'
		return
	}
	assert false
}

fn test_extra_agx_fields_rejected_but_kernel_fields_allowed() {
	data := fixture_im4p('gfxf', fixture_macho(), true, true)
	im4p_payload(data) or {
		assert err.msg() == 'unsupported extra IM4P fields'
		return
	}
	assert false
}

fn test_virtual_address_end_does_not_overflow_u64() {
	mut image := fixture_macho()
	set_u64(mut image, 32 + 24, 0xffffffffffffffff)
	set_u64(mut image, 32 + 32, 2)
	metadata := macho_metadata(image)!
	assert j.string_value(j.value(metadata, 'virtual_address_end')) == '18446744073709551617'
}

fn test_rebased_linkedit_overflow_is_rejected() {
	mut data := []u8{len: 4}
	set_u32(mut data, 0, 0xffffffff)
	rebase_linkedit_offset(mut data, 0, 1) or {
		assert err.msg() == 'rebased Mach-O linkedit offset exceeds 32 bits'
		return
	}
	assert false
}

fn test_cli_preserves_path_values_and_last_option() {
	options := parse_options('extract_firmware', ['extract_firmware', '--source-dir', '', '--out',
		'-1', '--output', '', '--preboot', 'a/../b//'])
	assert options.source == '.' && options.output == '.' && options.preboot == 'a/../b'
	assert path_value('//a//./b') == '//a/b'
	assert negative_number('-1') && negative_number('-.5') && !negative_number('-1.')
}

fn test_strict_utf8_name_errors_preserve_byte_positions() {
	assert utf8_error([u8(0x80)]) == "'utf-8' codec can't decode byte 0x80 in position 0: invalid start byte"
	assert utf8_error([u8(0xe0), 0xa0]) == "'utf-8' codec can't decode bytes in position 0-1: unexpected end of data"
	assert utf8_error([u8(0xe0), 0xa0, `x`]) == "'utf-8' codec can't decode bytes in position 0-1: invalid continuation byte"
}
