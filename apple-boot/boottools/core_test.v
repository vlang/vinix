// SPDX-License-Identifier: GPL-2.0-or-later
module boottools

import compress.zlib
import cachecli
import hash.crc32
import os
import plist

fn test_payload_layout_padding_utf8_and_invalid_elf() {
	loader := [u8(1), 2, 3]
	kernel := [u8(0x7f), `E`, `L`, `F`, 0xaa]
	image := pack(loader, 32, kernel, [u8(0x55)], 'é', 1, 0x123456789abcdef0) or { panic(err) }
	assert image.len == 32 + 0x10000
	assert image[..3] == loader
	assert image[3..32] == []u8{len: 29}
	assert image[32..40].bytestr() == 'VNXAPPL1'
	assert image[40..48] == [u8(80), 0, 0, 0, 1, 0, 0, 0]
	// Explicit original <8sII8Q wire fields; offsets are payload-relative.
	for index, value in [u64(0x4000), 5, 0x8000, 1, 0xc000, 2, 0x123456789abcdef0, 0x10000] {
		assert word(image, u64(48 + index * 8), 8, true) or { panic(err) } == value
	}
	assert image[32 + 0x4000..32 + 0x4005] == kernel
	assert image[32 + 0x8000] == 0x55
	assert image[32 + 0xc000..32 + 0xc003] == [u8(0xc3), 0xa9, 0]
	pack(loader, 2, kernel, []u8{}, '', 0, 0) or {
		assert err.msg().contains('loader')
		return
	}
	assert false
}

fn test_elf_symbol_bounds_and_missing_symbol() {
	mut elf := []u8{len: 320}
	copy(mut elf, [u8(0x7f), `E`, `L`, `F`, 2, 1])
	put(mut elf, 0x28, 64, 8, true)
	put(mut elf, 0x3a, 64, 2, true)
	put(mut elf, 0x3c, 3, 2, true)
	put(mut elf, 64 + 4, 2, 4, true)
	put(mut elf, 64 + 24, 256, 8, true)
	put(mut elf, 64 + 32, 24, 8, true)
	put(mut elf, 64 + 40, 1, 4, true)
	put(mut elf, 64 + 56, 24, 8, true)
	put(mut elf, 128 + 24, 280, 8, true)
	put(mut elf, 128 + 32, 12, 8, true)
	put(mut elf, 256, 1, 4, true)
	put(mut elf, 264, 0x8000, 8, true)
	copy(mut elf[281..], 'loader_end'.bytes())
	assert elf_symbol(elf, 'loader_end') or { panic(err) } == 0x8000
	for bytes in [elf[..50], elf[..270], []u8{}, []u8{len: 64}] {
		if _ := elf_symbol(bytes, 'loader_end') {
			assert false
		}
	}
	put(mut elf, 64 + 56, 0, 8, true)
	if _ := elf_symbol(elf, 'loader_end') {
		assert false
	}
}

fn test_ioreg_property_order_padding_windows_and_masks() {
	root := plist.Value{
		kind:   .dictionary
		fields: {
			'name':                             plist.Value{ kind: .data, data: 'root\x00'.bytes() }
			'abc':                              plist.Value{ kind: .data, data: [
				u8(1),
				2,
				3,
			] }
			'text':                             plist.Value{ kind: .string, text: 'not a property' }
			'IOIgnored':                        plist.Value{ kind: .data, data: [u8(1)] }
			'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx': plist.Value{ kind: .data, data: [u8(2)] }
			'IODeviceMemory':                   plist.Value{
				kind:   .array
				values: [plist.Value{
					kind:   .array
					values: [plist.Value{
						kind:   .dictionary
						fields: {
							'address': plist.Value{ kind: .integer, integer: 0x1000 }
							'length':  plist.Value{ kind: .integer, integer: 16 }
						}
					}]
				}]
			}
		}
	}
	xml := plist.encode_xml(plist.Value{ kind: .array, values: [root] }) or { panic(err) }
	adt := adt_from_plist(xml.bytes(), false) or { panic(err) }
	assert adt.data.len == 8 + 36 + 8 + 36 + 4
	assert adt.data[..8] == [u8(2), 0, 0, 0, 0, 0, 0, 0]
	assert adt.data[8..12].bytestr() == 'name' && adt.data[12..40] == []u8{len: 28}
	assert adt.data[40..44] == [u8(5), 0, 0, 0]
	assert adt.data[44..52] == [u8(114), 111, 111, 116, 0, 0, 0, 0]
	assert adt.data[52..55].bytestr() == 'abc' && adt.data[55..84] == []u8{len: 29}
	assert adt.data[88..] == [u8(1), 2, 3, 0]
	assert adt.memory['/'] == [Range{0x1000, 16}]
	assert node_name(plist.Value{
		kind:   .dictionary
		fields: {
			'name': plist.Value{ kind: .data, data: [u8(0xff), 0] }
		}
	}) == '\ufffd'
}

fn test_fdt_translation_defaults_apple_stop_unsupported_and_checks() {
	mut tree := Tree{
		nodes: [
			Node{
				name:       ''
				children:   [1]
				properties: {
					'#address-cells':  [u8(0), 0, 0, 2]
					'vinix,apple-adt': []u8{}
				}
			},
			Node{
				name:       'bus'
				parent:     0
				children:   [2]
				properties: {
					'#address-cells': [u8(0), 0, 0, 1]
					'#size-cells':    [u8(0), 0, 0, 1]
					'ranges':         [u8(0), 0, 0, 0x10, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0x20]
				}
			},
			Node{
				name:       'wdt'
				parent:     1
				properties: {
					'reg': [u8(0), 0, 0, 0x18, 0, 0, 0, 4]
				}
			},
		]
		root:  0
	}
	assert tree.path(2) == '/bus/wdt'
	assert tree.translated_reg(2) == Regs{true, [Range{0x100000008, 4}]}
	tree.nodes[1].properties.delete('ranges')
	assert tree.translated_reg(2) == Regs{true, [Range{0x18, 4}]}
	tree.nodes[1].properties['#address-cells'] = [u8(0), 0, 0, 3]
	assert !tree.translated_reg(2).supported
	for bytes in [[]u8{}, [u8(0xd0), 0x0d, 0xfe, 0xed], []u8{len: 40}] {
		if _ := parse_fdt(bytes) {
			assert false
		}
	}
	comparison := check_tree(tree, {
		'/bus/wdt': [Range{0x18, 4}]
	}, 'x')
	assert comparison.skipped == 1 && comparison.failures == ['/chosen/bootargs is missing or wrong']
}

fn test_png_channels_padding_crc_and_boot_arguments() {
	pixels := [u8(0), 0, 0xf0, 0x3f, 0xfc, 0x0f, 0, 0, 0xaa, 0xbb, 0xcc, 0xdd]
	png := framebuffer_png(pixels, 2, 1, 12) or { panic(err) }
	assert png[..8] == '\x89PNG\r\n\x1a\n'.bytes()
	assert png[12..16].bytestr() == 'IHDR'
	length := int(word(png, 33, 4, false) or { panic(err) })
	assert png[37..41].bytestr() == 'IDAT'
	assert zlib.decompress(png[41..41 + length]) or { panic(err) } == [u8(0), 255, 0, 0, 0, 0,
		255]
	assert png[png.len - 8..png.len - 4].bytestr() == 'IEND'
	mut offset := 8
	for offset < png.len {
		count := int(word(png, u64(offset), 4, false) or { panic(err) })
		assert u32(word(png, u64(offset + 8 + count), 4, false) or { panic(err) }) == crc32.sum(png[offset + 4..offset + 8 + count])
		offset += 12 + count
	}
	assert offset == png.len
	if _ := framebuffer_png([u8(0)], 2, 1, 8) {
		assert false
	}
	args := boot_args(0x40900000, 1340, 0x40c00000) or { panic(err) }
	assert args.len == 736
	assert args[..4] == [u8(2), 0, 2, 0]
	assert word(args, 0x60, 8, true) or { panic(err) } == virt_base + 0x100000
	assert word(args, 728, 8, true) or { panic(err) } == ram_bytes
	assert args[0x6c..720] == []u8{len: 720 - 0x6c}
}

fn test_path_values_and_retained_work_merge_and_failures() {
	assert path_value('') == '.' && path_value('a') == 'a'
	assert path_option(cachecli.Arguments{}, '--keep', '') == ''
	assert path_option(cachecli.Arguments{ options: {
		'--keep': ['']
	} }, '--keep', '') == '.'
	old := os.getenv_opt('LLVM_BIN')
	defer { if value := old { os.setenv('LLVM_BIN', value, true) } else { os.unsetenv('LLVM_BIN') } }
	os.setenv('LLVM_BIN', '', true)
	assert llvm() == '.'
	base := os.join_path(os.temp_dir(), 'vinix-apple-retain-unit-' + os.getpid().str())
	source := base + '/source'
	destination := base + '/retained'
	os.mkdir_all(source + '/nested') or { panic(err) }
	os.mkdir_all(destination) or { panic(err) }
	defer { os.rmdir_all(base) or {} }
	os.write_file(source + '/nested/file', 'new') or { panic(err) }
	os.write_file(destination + '/existing', 'kept') or { panic(err) }
	retain_work(source, destination) or { panic(err) }
	assert os.read_file(destination + '/nested/file') or { panic(err) } == 'new'
	assert os.read_file(destination + '/existing') or { panic(err) } == 'kept'
	for path in [source, source + '/recursive'] {
		if _ := retain_work(source, path) {
			assert false
		}
	}
	os.write_file(base + '/file', 'protected') or { panic(err) }
	if _ := retain_work(source, base + '/file') {
		assert false
	}
	assert os.read_file(base + '/file') or { panic(err) } == 'protected'
}

fn test_dump_failure_domains() {
	work := os.join_path(os.temp_dir(), 'vinix-apple-dump-unit-' + os.getpid().str())
	os.mkdir_all(work) or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	os.write_file_array(work + '/scratch.dump', []u8{len: 0x400}) or { panic(err) }
	os.write_file_array(work + '/segment.dump', []u8{len: segment_bytes, init: 0xa5}) or { panic(err) }
	mut aic := []u8{len: aic_size}
	for at in aic_mask_set .. aic_mask_set + 128 { aic[at] = 0xff }
	aic[0x14] = 1
	os.write_file_array(work + '/aic.dump', aic) or { panic(err) }
	assert check_dumps(work, Preparation{ with_aic: true }, false, 'aic: masked') or { panic(err) } == []string{}
	os.write_file_array(work + '/scratch.dump', []u8{len: 0x400, init: 0xff}) or { panic(err) }
	os.write_file_array(work + '/segment.dump', []u8{len: segment_bytes}) or { panic(err) }
	os.write_file_array(work + '/aic.dump', []u8{len: aic_size}) or { panic(err) }
	assert (check_dumps(work, Preparation{ with_aic: true }, false, '') or { panic(err) }).len == 6
	assert (check_dumps(work, Preparation{}, true, '') or { panic(err) }).len == 0
}
