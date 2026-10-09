// SPDX-License-Identifier: MIT
module robloxhost

import androidhost as ah

fn at(id string, start string, end string, stride string) !string {
	return call('operator.getitem', o(id), o(call('builtins.slice', o(start), o(end), o(stride))!))!
}

fn op(name string, a string, b string) !string { return call('operator.' + name, o(a), o(b))! }

fn byte(value string) !string { return bytes(value.bytes().hex())! }

fn png_chunk(kind string, body string) !string {
	prefix := call('struct.pack', v(ah.Value('>I')), o(length(body)!))!
	data := op('add', kind, body)!
	crc := call('struct.pack', v(ah.Value('>I')), o(call('zlib.crc32', o(data))!))!
	return op('add', op('add', op('add', prefix, kind)!, body)!, crc)!
}

fn image(source string, target string) !string {
	data := method(source, 'read_bytes', [], {})!
	if compare('lt', length(data)!, value_int(100)!)! { return literal(ah.Value(false))! }
	header := call('struct.unpack', v(ah.Value('>25I')), o(slice(data, null()!, value_int(100)!)!))!
	header_size, width, height := take(header, 0)!, take(header, 4)!, take(header, 5)!
	bits, line_bytes, colours := take(header, 11)!, take(header, 12)!, take(header, 19)!
	little := compare('eq', take(header, 7)!, value_int(0)!)!
	start := op('add', header_size, op('mul', colours, value_int(12)!)!)!
	if compare('ne', bits, value_int(32)!)! || compare('lt', length(data)!, op('add', start, op('mul', line_bytes, height)!)!)! {
		return literal(ah.Value(false))!
	}
	mut rows := call('bytearray')!
	mut drawn := literal(ah.Value(false))!
	indices := iterator(call('range', o(height))!)!
	for {
		index := next(indices)!
		if index.done { break }
		begin := op('add', start, op('mul', index.value, line_bytes)!)!
		line := slice(data, begin, op('add', begin, op('mul', width, value_int(4)!)!)!)!
		red := at(line, value_int(if little { 2 } else { 1 })!, null()!, value_int(4)!)!
		green := at(line, value_int(if little { 1 } else { 2 })!, null()!, value_int(4)!)!
		blue := at(line, value_int(if little { 0 } else { 3 })!, null()!, value_int(4)!)!
		row := call('bytearray', o(op('mul', width, value_int(3)!)!))!
		for channel, value in [red, green, blue] {
			call('operator.setitem', o(row), o(call('builtins.slice', v(ah.Value(channel)), o(null()!), v(ah.Value(3)))!), o(value))!
		}
		if !truth(drawn)! { drawn = call('any', o(row))! }
		rows = op('iadd', rows, op('add', bytes('00')!, row)!)!
	}
	info := call('struct.pack', v(ah.Value('>IIBBBBB')), o(width), o(height), v(ah.Value(8)), v(ah.Value(2)), v(ah.Value(0)), v(ah.Value(0)), v(ah.Value(0)))!
	compressed := call('zlib.compress', o(call('bytes', o(rows))!), v(ah.Value(6)))!
	mut png := bytes('89504e470d0a1a0a')!
	for chunk in [png_chunk(byte('IHDR')!, info)!, png_chunk(byte('IDAT')!, compressed)!,
		png_chunk(byte('IEND')!, bytes('')!)!] {
		png = op('add', png, chunk)!
	}
	method(target, 'write_bytes', [o(png)], {})!
	return drawn
}
