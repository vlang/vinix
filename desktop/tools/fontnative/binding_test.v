// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module fontnative

import encoding.binary
import json2
import os

fn test_native_font_owners_keep_copied_masks_after_face_retirement() ! {
	root := os.real_path(os.dir(@FILE) + '/../../..')
	path := root + '/third_party/ui2/assets/fonts/Roboto-Regular.ttf'
	baseline := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		mut ctx := context()!
		id := callback('open', {
			'path':  json2.Any(path.bytes().hex())
			'size':  json2.Any(13)
			'owner': json2.Any('test')
		}, unsafe { &ctx })!.int()
		mask := callback('mask', {
			'font':       json2.Any(id)
			'code_point': json2.Any(int(`M`))
		}, unsafe { &ctx })!.as_map()['mask']!.int()
		pixels := callback('pixels', {
			'mask': json2.Any(mask)
		}, unsafe { &ctx })!.str()
		callback('release', {
			'fonts': json2.Any([json2.Any(id)])
			'owner': json2.Any('test')
		}, unsafe { &ctx })!
		assert ctx.fonts.len == 0 && callback('pixels', {
			'mask': json2.Any(mask)
		}, unsafe { &ctx })!.str() == pixels
		callback('mask_release', {
			'mask': json2.Any(mask)
		}, unsafe { &ctx })!
		assert ctx.masks.len == 0
		ctx.close()
		ctx.close()
		assert os.ls('/dev/fd')!.len == baseline
	}
}

fn test_malformed_font_paths_and_sfnt_bounds_are_rejected() ! {
	mut lib := library()!
	defer { lib.close() }
	baseline := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		lib.open('/missing/native-font.ttf', 13) or {
			assert os.ls('/dev/fd')!.len == baseline
			continue
		}
		assert false
	}
	for data in [[]u8{}, 'bad SFNT'.bytes(), [u8(0), 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
		[u8(0), 0, 0, 0, 0, 0]] {
		sfnt_tables(data) or { continue }
		assert false
	}
	name_records([u8(0), 0, 0, 1, 0, 6]) or { return }
	assert false
}

fn test_native_variable_subsets_keep_coverage_names_timestamps_and_checksums() ! {
	source := os.getenv('VINIX_TEST_JAPANESE_SOURCE')
	if source == '' { return }
	data := os.read_bytes(source)!
	mut original := ttf(data)!
	defer { original.close() }
	points := [int(`の`), int(`日`), int(`本`), int(`語`)]
	assert points.all(it in original.cmap()!)
	original.subset(points, [13, 14, 16, 17])!
	assert original.cmap()! == points.sorted()
	for weight in [400, 700] {
		mut font := original.instantiate(weight)!
		defer { font.close() }
		for record in font.records()! {
			if record.id == 1 { font.renamed[name_key(record)] = 'Vinix Japanese' }
		}
		first := font.publication()!
		assert first == font.publication()! && checksum(first) == u32(0xb1b0afba)
		tables := sfnt_tables(first)!
		assert 'fvar' !in tables && tables['head'][20..36] == original.timestamps
		assert binary.big_endian_u16_at(tables['OS/2'], 4) == u16(weight)
		for record in name_records(tables['name'])! {
			if record.id == 1 {
				assert record.data == [u8(0), `V`, 0, `i`, 0, `n`, 0, `i`, 0, `x`, 0, ` `, 0, `J`,
					0, `a`, 0, `p`, 0, `a`, 0, `n`, 0, `e`, 0, `s`, 0, `e`]
			}
		}
		mut reopened := ttf(first)!
		assert reopened.cmap()! == points.sorted()
		reopened.close()
	}
}
