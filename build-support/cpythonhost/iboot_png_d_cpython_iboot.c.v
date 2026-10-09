// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn C.PyNumber_Rshift(voidptr, voidptr) voidptr
fn C.PyNumber_And(voidptr, voidptr) voidptr
fn C.PySlice_New(voidptr, voidptr, voidptr) voidptr

fn ib_bit(operation string, left voidptr, right voidptr) voidptr {
	if left == unsafe { nil } || right == unsafe { nil } {
		drop(left)
		drop(right)
		return unsafe { nil }
	}
	result := if operation == 'shift' { C.PyNumber_Rshift(left, right) } else { C.PyNumber_And(left, right) }
	drop(left)
	drop(right)
	return result
}

fn (s &IbootCodec) png_chunk(kind voidptr, data voidptr) voidptr {
	target := s.member('struct', 'pack')
	if target == unsafe { nil } { return target }
	length := s.len(data)
	if length == unsafe { nil } { drop(target); return length }
	prefix := ib_invoke(target, [ib_text('>I'), length])
	if prefix == unsafe { nil } { return prefix }
	with_kind := ib_binary('add', prefix, own(kind))
	if with_kind == unsafe { nil } { return with_kind }
	with_data := ib_binary('add', with_kind, own(data))
	if with_data == unsafe { nil } { return with_data }
	tail_target := s.member('struct', 'pack')
	if tail_target == unsafe { nil } { drop(with_data); return tail_target }
	checksum_target := s.member('zlib', 'crc32')
	if checksum_target == unsafe { nil } { drop(tail_target); drop(with_data); return checksum_target }
	checksum_input := ib_binary('add', own(kind), own(data))
	if checksum_input == unsafe { nil } { drop(checksum_target); drop(tail_target); drop(with_data); return checksum_input }
	checksum := ib_invoke(checksum_target, [checksum_input])
	if checksum == unsafe { nil } { drop(tail_target); drop(with_data); return checksum }
	masked := ib_bit('and', checksum, ib_int(0xffffffff))
	if masked == unsafe { nil } { drop(tail_target); drop(with_data); return masked }
	tail := ib_invoke(tail_target, [ib_text('>I'), masked])
	if tail == unsafe { nil } { drop(with_data); return tail }
	return ib_binary('add', with_data, tail)
}

fn (s &IbootCodec) png_line(pixels voidptr, y voidptr) voidptr {
	stride := s.global('FB_STRIDE')
	if stride == unsafe { nil } { return stride }
	low := ib_binary('mul', own(y), stride)
	if low == unsafe { nil } { return low }
	stride2 := s.global('FB_STRIDE')
	if stride2 == unsafe { nil } { drop(low); return stride2 }
	start := ib_binary('mul', own(y), stride2)
	if start == unsafe { nil } { drop(low); return start }
	width := s.global('FB_WIDTH')
	if width == unsafe { nil } { drop(start); drop(low); return width }
	length := ib_binary('mul', width, ib_int(4))
	if length == unsafe { nil } { drop(start); drop(low); return length }
	high := ib_binary('add', start, length)
	if high == unsafe { nil } { drop(low); return high }
	slice := C.PySlice_New(low, high, unsafe { nil })
	drop(low)
	drop(high)
	if slice == unsafe { nil } { return slice }
	result := C.PyObject_GetItem(pixels, slice)
	drop(slice)
	return result
}

fn (s &IbootCodec) png_channels(word voidptr) voidptr {
	target := s.global('bytes')
	if target == unsafe { nil } { return target }
	values := C.PyTuple_New(3)
	if values == unsafe { nil } { drop(target); return values }
	for i, shift in [i64(22), 12, 2] {
		shifted := ib_bit('shift', own(word), ib_int(shift))
		if shifted == unsafe { nil } { drop(values); drop(target); return shifted }
		masked := ib_bit('and', shifted, ib_int(0xff))
		if masked == unsafe { nil } { drop(values); drop(target); return masked }
		C.PyTuple_SetItem(values, i, masked)
	}
	return ib_invoke(target, [values])
}

fn (s &IbootCodec) png_header() voidptr {
	target := s.member('struct', 'pack')
	if target == unsafe { nil } { return target }
	width := s.global('FB_WIDTH')
	if width == unsafe { nil } { drop(target); return width }
	height := s.global('FB_HEIGHT')
	if height == unsafe { nil } { drop(width); drop(target); return height }
	return ib_invoke(target, [ib_text('>IIBBBBB'), width, height, ib_int(8), ib_int(2), ib_int(0), ib_int(0), ib_int(0)])
}

fn (s &IbootCodec) png_data(rows voidptr) voidptr {
	target := s.member('zlib', 'compress')
	if target == unsafe { nil } { return target }
	data := ib_invoke(s.global('bytes'), [own(rows)])
	if data == unsafe { nil } { drop(target); return data }
	return ib_invoke(target, [data, ib_int(6)])
}

fn (s &IbootCodec) png(path voidptr, pixels voidptr, chunk_factory voidptr) voidptr {
	mut rows := voidptr(0)
	mut y := voidptr(0)
	mut line := voidptr(0)
	mut word := voidptr(0)
	mut chunk := voidptr(0)
	defer {
		s.pin(['rows', 'y', 'line', 'word', 'chunk'], [rows, y, line, word, chunk])
		drop(rows)
		drop(y)
		drop(line)
		drop(word)
		drop(chunk)
	}
	rows = ib_invoke(s.global('bytearray'), [])
	if rows == unsafe { nil } { return rows }
	range_target := s.global('range')
	if range_target == unsafe { nil } { return range_target }
	height := s.global('FB_HEIGHT')
	if height == unsafe { nil } { drop(range_target); return height }
	range_value := ib_invoke(range_target, [height])
	if range_value == unsafe { nil } { return range_value }
	iterator := C.PyObject_GetIter(range_value)
	drop(range_value)
	if iterator == unsafe { nil } { return iterator }
	for {
		next_y := C.PyIter_Next(iterator)
		if next_y == unsafe { nil } { break }
		drop(y)
		y = next_y
		append := ib_attr(rows, 'append')
		if append == unsafe { nil } { break }
		appended := ib_invoke(append, [ib_int(0)])
		if appended == unsafe { nil } { break }
		drop(appended)
		new_line := s.png_line(pixels, y)
		if new_line == unsafe { nil } { break }
		drop(line)
		line = new_line
		unpack := s.member('struct', 'iter_unpack')
		if unpack == unsafe { nil } { break }
		pairs := ib_invoke(unpack, [ib_text('<I'), own(line)])
		if pairs == unsafe { nil } { break }
		words := C.PyObject_GetIter(pairs)
		drop(pairs)
		if words == unsafe { nil } { break }
		for {
			pair := C.PyIter_Next(words)
			if pair == unsafe { nil } { break }
			new_word := ib_invoke(own(s.single), [pair])
			if new_word == unsafe { nil } { break }
			drop(word)
			word = new_word
			channels := s.png_channels(word)
			if channels == unsafe { nil } { break }
			updated := ib_binary('iadd', own(rows), channels)
			if updated == unsafe { nil } { break }
			drop(rows)
			rows = updated
		}
		drop(words)
		if pending_error() { break }
	}
	drop(iterator)
	if pending_error() { return unsafe { nil } }
	chunk = ib_invoke(own(chunk_factory), [])
	if chunk == unsafe { nil } { return chunk }
	writer := ib_attr(path, 'write_bytes')
	if writer == unsafe { nil } { return writer }
	header_target := own(chunk)
	header := s.png_header()
	if header == unsafe { nil } { drop(header_target); drop(writer); return header }
	ihdr := ib_invoke(header_target, [ib_bytes('IHDR'), header])
	if ihdr == unsafe { nil } { drop(writer); return ihdr }
	initial := ib_binary('add', ib_bytes('\x89PNG\x0d\x0a\x1a\x0a'), ihdr)
	if initial == unsafe { nil } { drop(writer); return initial }
	data_target := own(chunk)
	data := s.png_data(rows)
	if data == unsafe { nil } { drop(data_target); drop(initial); drop(writer); return data }
	idat := ib_invoke(data_target, [ib_bytes('IDAT'), data])
	if idat == unsafe { nil } { drop(initial); drop(writer); return idat }
	body := ib_binary('add', initial, idat)
	if body == unsafe { nil } { drop(writer); return body }
	iend := ib_invoke(own(chunk), [ib_bytes('IEND'), ib_bytes('')])
	if iend == unsafe { nil } { drop(body); drop(writer); return iend }
	image := ib_binary('add', body, iend)
	if image == unsafe { nil } { drop(writer); return image }
	written := ib_invoke(writer, [image])
	if written == unsafe { nil } { return written }
	drop(written)
	return py_none()
}
