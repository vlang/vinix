// SPDX-License-Identifier: GPL-2.0-or-later
module tarstream

import strconv
import tarcore

fn (mut reader Reader) sparse_pairs(data []u8, start int, count int, keep_zero bool) ! {
	for i in 0 .. count {
		offset := number(data, start + i * 24, 12) or { break }
		length := number(data, start + i * 24 + 12, 12) or { break }
		if offset < 0 || length < 0 { return error('negative sparse extent') }
		if keep_zero || offset != 0 || length != 0 {
			reader.sparse << SparseExtent{offset, length}
		}
	}
}

fn (mut reader Reader) sparse_decimal() !i64 {
	mut text := ''
	mut byte := []u8{len: 1}
	for {
		reader.exact(mut byte, false)!
		reader.sparse_meta_bytes++
		if byte[0] == `\n` { break }
		if text.len >= 128 { return error('sparse number is too large') }
		text += byte.bytestr()
	}
	value := strconv.parse_int(text, 10, 64)!
	if value < 0 { return error('negative sparse extent') }
	return value
}

fn (mut reader Reader) process_sparse(mut member tarcore.Member, header []u8, local map[string]string) ! {
	mut fields := reader.globals.clone()
	for key, value in local { fields[key] = value }
	if member.kind == `S` {
		reader.logical_size = number(header, 483, 12)!
		reader.sparse_pairs(header, 386, 4, true)!
		mut extended := header[482] != 0
		for extended {
			mut block := []u8{len: 512}
			reader.exact(mut block, false)!
			reader.sparse_pairs(block, 0, 21, false)!
			extended = block[504] != 0
		}
	} else if 'GNU.sparse.map' in fields {
		values := fields['GNU.sparse.map']!.split(',')
		for i := 0; i + 1 < values.len; i += 2 {
			reader.sparse << SparseExtent{strconv.parse_int(values[i], 10, 64)!, strconv.parse_int(values[i + 1], 10, 64)!}
		}
	} else if 'GNU.sparse.size' in fields {
		offsets := (fields['_native.GNU.sparse.offset'] or { '' }).trim_right(',').split(',')
		lengths := (fields['_native.GNU.sparse.numbytes'] or { '' }).trim_right(',').split(',')
		for i, offset in offsets {
			if offset == '' || i >= lengths.len { break }
			reader.sparse << SparseExtent{strconv.parse_int(offset, 10, 64)!, strconv.parse_int(lengths[i], 10, 64)!}
		}
	} else if (fields['GNU.sparse.major'] or { '' }) == '1' && (fields['GNU.sparse.minor'] or { '' }) == '0' {
		reader.sparse_meta_bytes = 0
		count := reader.sparse_decimal()!
		if count > 0x7fffffff { return error('too many sparse extents') }
		for _ in 0 .. count {
			offset := reader.sparse_decimal()!
			length := reader.sparse_decimal()!
			reader.sparse << SparseExtent{offset, length}
		}
		padding := (512 - reader.sparse_meta_bytes % 512) % 512
		mut bytes := []u8{len: padding}
		reader.exact(mut bytes, false)!
		member.size -= reader.sparse_meta_bytes + padding
	}
	if name := fields['GNU.sparse.name'] { member.name = name.trim_right('/') }
	if size := fields['GNU.sparse.size'] { reader.logical_size = strconv.parse_int(size, 10, 64)! }
	if size := fields['GNU.sparse.realsize'] {
		reader.logical_size = strconv.parse_int(size, 10, 64)!
	}
	if reader.logical_size < -1 { return error('negative sparse file size') }
	for extent in reader.sparse {
		if extent.offset < 0 || extent.length < 0 { return error('negative sparse extent') }
	}
}
