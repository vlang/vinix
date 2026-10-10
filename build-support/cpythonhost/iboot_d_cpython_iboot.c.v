// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn C.PyNumber_Add(voidptr, voidptr) voidptr
fn C.PyNumber_Subtract(voidptr, voidptr) voidptr
fn C.PyNumber_Multiply(voidptr, voidptr) voidptr
fn C.PyNumber_FloorDivide(voidptr, voidptr) voidptr
fn C.PyNumber_Remainder(voidptr, voidptr) voidptr
fn C.PyNumber_Negative(voidptr) voidptr
fn C.PyNumber_InPlaceAdd(voidptr, voidptr) voidptr
fn C.PyObject_GetItem(voidptr, voidptr) voidptr
fn C.PyUnicode_InternFromString(&char) voidptr
fn C.PyObject_GetAttr(voidptr, voidptr) voidptr
fn C.PyUnicode_Concat(voidptr, voidptr) voidptr
fn C.PyObject_Format(voidptr, voidptr) voidptr
fn C.PyEval_GetBuiltins() voidptr
fn C.PyDict_SetItem(voidptr, voidptr, voidptr) i32
fn C.PyList_Append(voidptr, voidptr) i32
fn C.PyList_Insert(voidptr, isize, voidptr) i32

struct IbootCodec {
	namespace voidptr
	pins      voidptr
	pair      voidptr
	single    voidptr
 raise_ voidptr
}

// These arguments are the finite numeric constants in the seven helper bodies.
__global ib_integer_literals = map[i64]voidptr{}
fn ib_int(value i64) voidptr {
 if result := ib_integer_literals[value] { return own(result) }
 result := C.PyLong_FromLongLong(value)
 if result != unsafe { nil } { ib_integer_literals[value] = own(result) }
 return result
}
__global ib_text_literals = map[string]voidptr{}
fn ib_text(value string) voidptr {
 if result := ib_text_literals[value] { return own(result) }
 result := if value.len > 0 && value.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`) || (it >= `0` && it <= `9`) || it == `_`) {
  unsafe { C.PyUnicode_InternFromString(value.str) }
 } else { py_string(value) }
 if result != unsafe { nil } { ib_text_literals[value] = own(result) }
 return result
}

// Finite byte literals in the helper and PNG bodies, never caller data.
__global ib_byte_literals = map[string]voidptr{}
fn ib_bytes(value string) voidptr {
 if result := ib_byte_literals[value] { return own(result) }
 result := unsafe { C.PyBytes_FromStringAndSize(value.str, value.len) }
 if result != unsafe { nil } { ib_byte_literals[value] = own(result) }
 return result
}

// Fixed LOAD_ATTR literals have native implementation lifetime.
__global ib_literal_names = map[string]voidptr{}

fn ib_literal_name(name string) voidptr {
	if value := ib_literal_names[name] { return own(value) }
	value := unsafe { C.PyUnicode_InternFromString(name.str) }
	if value != unsafe { nil } { ib_literal_names[name] = own(value) }
	return value
}

fn ib_attr(value voidptr, name string) voidptr {
	key := ib_literal_name(name)
	if key == unsafe { nil } { return key }
	result := C.PyObject_GetAttr(value, key)
	drop(key)
	return result
}

fn (s &IbootCodec) global(name string) voidptr {
	value := unsafe { C.PyDict_GetItemString(s.namespace, name.str) }
	if value != unsafe { nil } { return own(value) }
	dictionary := C.PyEval_GetBuiltins()
	fallback := unsafe { C.PyDict_GetItemString(dictionary, name.str) }
	if fallback != unsafe { nil } { return own(fallback) }
	message := py_string("name '" + name + "' is not defined")
	C.PyErr_SetObject(unsafe { voidptr(C.PyExc_NameError) }, message)
	drop(message)
	return unsafe { nil }
}

fn (s &IbootCodec) pin(names []string, values []voidptr) {
	if C.PyErr_Occurred() == unsafe { nil } { return }
	error := caught()
	scope := C.PyDict_New()
	if scope != unsafe { nil } {
		for i, value in values {
			if value == unsafe { nil } { continue }
			key := py_string(names[i])
			if key == unsafe { nil } { break }
			status := C.PyDict_SetItem(scope, key, value)
			drop(key)
			if status != 0 { break }
		}
		if !pending_error() { C.PyList_Insert(s.pins, 0, scope) }
		drop(scope)
	}
	error.restore()
	error.discard()
}

// Consume temporary arguments in reverse order before the actual borrowed callable, including
// exceptional returns. Named callers supply their own independent references.
fn ib_invoke(target voidptr, values []voidptr) voidptr {
	if target == unsafe { nil } || values.any(it == unsafe { nil }) {
		for i := values.len - 1; i >= 0; i-- { drop(values[i]) }
		drop(target)
		return unsafe { nil }
	}
	args := C.PyTuple_New(values.len)
	if args == unsafe { nil } {
		for i := values.len - 1; i >= 0; i-- { drop(values[i]) }
		drop(target)
		return args
	}
	for i, value in values { C.PyTuple_SetItem(args, i, own(value)) }
	result := C.PyObject_Call(target, args, unsafe { nil })
	drop(args)
	for i := values.len - 1; i >= 0; i-- { drop(values[i]) }
	drop(target)
	return result
}

fn ib_binary(operation string, left voidptr, right voidptr) voidptr {
	if left == unsafe { nil } || right == unsafe { nil } {
		drop(left)
		drop(right)
		return unsafe { nil }
	}
	result := match operation {
		'add' { C.PyNumber_Add(left, right) }
		'sub' { C.PyNumber_Subtract(left, right) }
		'mul' { C.PyNumber_Multiply(left, right) }
		'div' { C.PyNumber_FloorDivide(left, right) }
		'mod' { C.PyNumber_Remainder(left, right) }
		else { C.PyNumber_InPlaceAdd(left, right) }
	}
	drop(left)
	drop(right)
	return result
}

fn (s &IbootCodec) len(value voidptr) voidptr { return ib_invoke(s.global('len'), [own(value)]) }

fn (s &IbootCodec) member(module string, name string) voidptr {
	receiver := s.global(module)
	if receiver == unsafe { nil } { return receiver }
	target := ib_attr(receiver, name)
	drop(receiver)
	return target
}

fn ib_method(receiver voidptr, name string, values []voidptr) voidptr {
	target := ib_attr(receiver, name)
	drop(receiver)
	return ib_invoke(target, values)
}

fn (s &IbootCodec) align(value voidptr, alignment voidptr) voidptr {
	sum := ib_binary('add', own(value), own(alignment))
	if sum == unsafe { nil } { return sum }
	adjusted := ib_binary('sub', sum, ib_int(1))
	if adjusted == unsafe { nil } { return adjusted }
	quotient := ib_binary('div', adjusted, own(alignment))
	if quotient == unsafe { nil } { return quotient }
	return ib_binary('mul', quotient, own(alignment))
}

fn (s &IbootCodec) cstr(text voidptr) voidptr {
	encoded := ib_method(own(text), 'encode', [])
	if encoded == unsafe { nil } { return encoded }
	return ib_binary('add', encoded, ib_bytes('\x00'))
}

fn (s &IbootCodec) u32(value voidptr) voidptr {
	return ib_invoke(s.member('struct', 'pack'), [ib_text('<I'), own(value)])
}

fn (s &IbootCodec) u64s(values voidptr) voidptr {
	target := s.member('struct', 'pack')
	if target == unsafe { nil } { return target }
	count := s.len(values)
	if count == unsafe { nil } {
		drop(target)
		return count
	}
	empty := ib_text('')
	formatted := C.PyObject_Format(count, empty)
	drop(count)
	drop(empty)
	if formatted == unsafe { nil } {
		drop(target)
		return formatted
	}
	prefix := ib_text('<')
	start := C.PyUnicode_Concat(prefix, formatted)
	drop(prefix)
	drop(formatted)
	if start == unsafe { nil } {
		drop(target)
		return start
	}
	suffix := ib_text('Q')
	format := C.PyUnicode_Concat(start, suffix)
	drop(start)
	drop(suffix)
	if format == unsafe { nil } {
		drop(target)
		return format
	}
	args := C.PyTuple_New(C.PyTuple_Size(values) + 1)
	C.PyTuple_SetItem(args, 0, format)
	for i in 0 .. int(C.PyTuple_Size(values)) {
		C.PyTuple_SetItem(args, i + 1, own(C.PyTuple_GetItem(values, i)))
	}
	result := C.PyObject_Call(target, args, unsafe { nil })
	drop(args)
	drop(target)
	return result
}

fn (s &IbootCodec) adt(properties voidptr, children voidptr) voidptr {
	mut out := voidptr(0)
	mut name := voidptr(0)
	mut value := voidptr(0)
	mut child := voidptr(0)
	defer {
		s.pin(['out', 'name', 'value', 'child'], [out, name, value, child])
		drop(out)
		drop(name)
		drop(value)
		drop(child)
	}
	bytearray_target := s.global('bytearray')
	if bytearray_target == unsafe { nil } { return bytearray_target }
	pack := s.member('struct', 'pack')
	if pack == unsafe { nil } {
		drop(bytearray_target)
		return pack
	}
	property_count := s.len(properties)
	if property_count == unsafe { nil } {
		drop(pack)
		drop(bytearray_target)
		return property_count
	}
	child_count := s.len(children)
	if child_count == unsafe { nil } {
		drop(property_count)
		drop(pack)
		drop(bytearray_target)
		return child_count
	}
	header := ib_invoke(pack, [ib_text('<II'), property_count, child_count])
	if header == unsafe { nil } {
		drop(bytearray_target)
		return header
	}
	out = ib_invoke(bytearray_target, [header])
	if out == unsafe { nil } { return out }
	items := C.PyObject_GetIter(properties)
	if items == unsafe { nil } { return items }
	for {
		item := C.PyIter_Next(items)
		if item == unsafe { nil } { break }
		pair := ib_invoke(own(s.pair), [item])
		if pair == unsafe { nil } { break }
		next_name := own(C.PyTuple_GetItem(pair, 0))
		next_value := own(C.PyTuple_GetItem(pair, 1))
		drop(pair)
		drop(name)
		name = next_name
		drop(value)
		value = next_value
		encoded := ib_method(own(name), 'encode', [])
		if encoded == unsafe { nil } { break }
		padded := ib_method(encoded, 'ljust', [ib_int(32), ib_bytes('\x00')])
		if padded == unsafe { nil } { break }
		size_target := s.member('struct', 'pack')
		if size_target == unsafe { nil } {
			drop(padded)
			break
		}
		size := s.len(value)
		if size == unsafe { nil } {
			drop(size_target)
			drop(padded)
			break
		}
		length := ib_invoke(size_target, [ib_text('<I'), size])
		if length == unsafe { nil } {
			drop(padded)
			break
		}
		entry := ib_binary('add', padded, length)
		if entry == unsafe { nil } { break }
		updated := ib_binary('iadd', own(out), entry)
		if updated == unsafe { nil } { break }
		drop(out)
		out = updated
		bytes_target := s.global('bytes')
		if bytes_target == unsafe { nil } { break }
		size2 := s.len(value)
		if size2 == unsafe { nil } {
			drop(bytes_target)
			break
		}
		negative := C.PyNumber_Negative(size2)
		drop(size2)
		if negative == unsafe { nil } {
			drop(bytes_target)
			break
		}
		amount := ib_binary('mod', negative, ib_int(4))
		if amount == unsafe { nil } {
			drop(bytes_target)
			break
		}
		padding := ib_invoke(bytes_target, [amount])
		if padding == unsafe { nil } { break }
		payload := ib_binary('add', own(value), padding)
		if payload == unsafe { nil } { break }
		updated2 := ib_binary('iadd', own(out), payload)
		if updated2 == unsafe { nil } { break }
		drop(out)
		out = updated2
	}
	drop(items)
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	children_iter := C.PyObject_GetIter(children)
	if children_iter == unsafe { nil } { return children_iter }
	for {
		next_child := C.PyIter_Next(children_iter)
		if next_child == unsafe { nil } { break }
		drop(child)
		child = next_child
		updated := ib_binary('iadd', own(out), own(child))
		if updated == unsafe { nil } { break }
		drop(out)
		out = updated
	}
	drop(children_iter)
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	return ib_invoke(s.global('bytes'), [own(out)])
}

fn (s &IbootCodec) pack_into(format string, arguments []voidptr) bool {
	target := s.member('struct', 'pack_into')
	mut values := [ib_text(format)]
	values << arguments
	result := ib_invoke(target, values)
	drop(result)
	return C.PyErr_Occurred() == unsafe { nil }
}

fn (s &IbootCodec) boot_args(devtree voidptr, size voidptr, top voidptr) voidptr {
	mut args := voidptr(0)
	mut tail := voidptr(0)
	defer {
		s.pin(['args', 'tail'], [args, tail])
		drop(args)
		drop(tail)
	}
	args = ib_invoke(s.global('bytearray'), [ib_int(736)])
	if args == unsafe { nil } { return args }
	if !s.pack_into('<HH', [own(args), ib_int(0), ib_int(2), ib_int(2)]) { return unsafe { nil } }
	target1 := s.member('struct', 'pack_into')
	if target1 == unsafe { nil } { return target1 }
	virt := s.global('VIRT_BASE')
	if virt == unsafe { nil } {
		drop(target1)
		return virt
	}
	phys := s.global('PHYS_BASE')
	if phys == unsafe { nil } {
		drop(virt)
		drop(target1)
		return phys
	}
	fb := s.global('FB_BASE')
	if virt == unsafe { nil } || phys == unsafe { nil } || fb == unsafe { nil } {
		drop(virt)
		drop(phys)
		drop(fb)
		drop(target1)
		return unsafe { nil }
	}
	range := ib_binary('sub', fb, own(phys))
	if range == unsafe { nil } {
		drop(virt)
		drop(phys)
		drop(target1)
		return range
	}
	ignored1 := ib_invoke(target1, [ib_text('<4Q'), own(args), ib_int(0x08), virt, phys, range,
		own(top)])
	drop(ignored1)
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	target2 := s.member('struct', 'pack_into')
	if target2 == unsafe { nil } { return target2 }
	mut values2 := [ib_text('<6Q'), own(args), ib_int(0x28)]
	base2 := s.global('FB_BASE')
	if base2 == unsafe { nil } {
		for value in values2 { drop(value) }
		drop(target2)
		return base2
	}
	values2 << base2
	values2 << ib_int(0)
	for field in ['FB_STRIDE', 'FB_WIDTH', 'FB_HEIGHT'] {
		value := s.global(field)
		if value == unsafe { nil } {
			for item in values2 { drop(item) }
			drop(target2)
			return value
		}
		values2 << value
	}
	values2 << ib_int(30)
	ignored2 := ib_invoke(target2, values2)
	drop(ignored2)
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	if !s.pack_into('<I', [own(args), ib_int(0x58), ib_int(0)]) { return unsafe { nil } }
	target3 := s.member('struct', 'pack_into')
	if target3 == unsafe { nil } { return target3 }
	phys2 := s.global('PHYS_BASE')
	if phys2 == unsafe { nil } {
		drop(target3)
		return phys2
	}
	offset := ib_binary('sub', own(devtree), phys2)
	if offset == unsafe { nil } {
		drop(target3)
		return offset
	}
	virt2 := s.global('VIRT_BASE')
	if virt2 == unsafe { nil } {
		drop(offset)
		drop(target3)
		return virt2
	}
	address := ib_binary('add', offset, virt2)
	if address == unsafe { nil } {
		drop(target3)
		return address
	}
	ignored3 := ib_invoke(target3, [ib_text('<QI'), own(args), ib_int(0x60), address, own(size)])
	drop(ignored3)
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	tail = ib_invoke(s.global('align'), [ib_int(0x6c + 608), ib_int(8)])
	if tail == unsafe { nil } { return tail }
	target4 := s.member('struct', 'pack_into')
	if target4 == unsafe { nil } { return target4 }
	ram := s.global('RAM_BYTES')
	if ram == unsafe { nil } {
		drop(target4)
		return ram
	}
	ignored4 := ib_invoke(target4, [ib_text('<QQ'), own(args), own(tail), ib_int(0), ram])
	drop(ignored4)
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	return ib_invoke(s.global('bytes'), [own(args)])
}

struct IbootNode {
	target     voidptr
	properties voidptr
}

fn (s &IbootCodec) node() IbootNode {
	target := s.global('adt_node')
	return IbootNode{
		target:     target
		properties: if target != unsafe { nil } {
			C.PyList_New(0)
		} else {
			unsafe { nil }
		}
	}
}

fn (n &IbootNode) add(name string, value voidptr) bool {
	if value == unsafe { nil } { return false }
	pair := C.PyTuple_New(2)
	C.PyTuple_SetItem(pair, 0, ib_text(name))
	C.PyTuple_SetItem(pair, 1, value)
	result := C.PyList_Append(n.properties, pair)
	drop(pair)
	return result == 0
}

fn (n &IbootNode) abandon() {
	drop(n.properties)
	drop(n.target)
}

fn (n &IbootNode) finish(children voidptr) voidptr {
	if children == unsafe { nil } { return ib_invoke(n.target, [n.properties]) }
	return ib_invoke(n.target, [n.properties, children])
}

fn (s &IbootCodec) text(text string) voidptr {
	return ib_invoke(s.global('cstr'), [ib_text(text)])
}

fn (s &IbootCodec) word(value i64) voidptr { return ib_invoke(s.global('u32'), [ib_int(value)]) }

fn (s &IbootCodec) words(values []voidptr) voidptr { return ib_invoke(s.global('u64s'), values) }

fn (s &IbootCodec) constant_word(name string) voidptr {
	target := s.global('u32')
	if target == unsafe { nil } { return target }
	return ib_invoke(target, [s.global(name)])
}

fn (s &IbootCodec) constant_words(names []string) voidptr {
	target := s.global('u64s')
	if target == unsafe { nil } { return target }
	mut values := []voidptr{}
	for name in names {
		value := s.global(name)
		if value == unsafe { nil } {
			for item in values { drop(item) }
			drop(target)
			return value
		}
		values << value
	}
	return ib_invoke(target, values)
}

fn (s &IbootCodec) build_adt(segment voidptr, with_aic voidptr) voidptr {
	mut wdt := voidptr(0)
	mut firmware := voidptr(0)
	mut aic := voidptr(0)
	mut arm_io := voidptr(0)
	mut chosen := voidptr(0)
	defer {
		s.pin(['wdt', 'firmware', 'aic', 'arm_io', 'chosen'], [wdt, firmware, aic, arm_io, chosen])
		drop(wdt)
		drop(firmware)
		drop(aic)
		drop(arm_io)
		drop(chosen)
	}
	wdt_node := s.node()
	if wdt_node.target == unsafe { nil } { return unsafe { nil } }
	if !wdt_node.add('name', s.text('wdt')) || !wdt_node.add('compatible', s.text('wdt,vinix-test')) || !wdt_node.add('wdt-version', s.word(3)) || !wdt_node.add('reg', s.words([
		ib_int(0x110000),
		ib_int(0x4000),
		ib_int(0x110200),
		ib_int(0x100),
		ib_int(0x110100),
		ib_int(4),
	])) {
		wdt_node.abandon()
		return unsafe { nil }
	}
	wdt = wdt_node.finish(unsafe { nil })
	if wdt == unsafe { nil } { return wdt }
	firmware_node := s.node()
	if firmware_node.target == unsafe { nil } { return unsafe { nil } }
	if !firmware_node.add('name', s.text('test-asc')) {
		firmware_node.abandon()
		return unsafe { nil }
	}
	prefix := s.words([own(segment), ib_int(0), ib_int(0)])
	if prefix == unsafe { nil } {
		firmware_node.abandon()
		return prefix
	}
	pack_target := s.member('struct', 'pack')
	if pack_target == unsafe { nil } {
		drop(prefix)
		firmware_node.abandon()
		return pack_target
	}
	segment_size := s.global('SEGMENT_BYTES')
	if segment_size == unsafe { nil } {
		drop(pack_target)
		drop(prefix)
		firmware_node.abandon()
		return segment_size
	}
	tail := ib_invoke(pack_target, [ib_text('<II'), segment_size, ib_int(0)])
	if tail == unsafe { nil } {
		drop(prefix)
		firmware_node.abandon()
		return tail
	}
	if !firmware_node.add('segment-ranges', ib_binary('add', prefix, tail)) {
		firmware_node.abandon()
		return unsafe { nil }
	}
	firmware = firmware_node.finish(unsafe { nil })
	if firmware == unsafe { nil } { return firmware }
	aic_node := s.node()
	if aic_node.target == unsafe { nil } { return unsafe { nil } }
	if !aic_node.add('name', s.text('aic')) || !aic_node.add('compatible', s.text('aic,3')) {
		aic_node.abandon()
		return unsafe { nil }
	}
	reg_target := s.global('u64s')
	if reg_target == unsafe { nil } {
		aic_node.abandon()
		return reg_target
	}
	base := s.global('FAKE_AIC')
	if base == unsafe { nil } {
		drop(reg_target)
		aic_node.abandon()
		return base
	}
	ram_base := s.global('RAM_BASE')
	if ram_base == unsafe { nil } {
		drop(base)
		drop(reg_target)
		aic_node.abandon()
		return ram_base
	}
	offset := ib_binary('sub', base, ram_base)
	if offset == unsafe { nil } {
		drop(reg_target)
		aic_node.abandon()
		return offset
	}
	aic_size := s.global('AIC_SIZE')
	if aic_size == unsafe { nil } {
		drop(offset)
		drop(reg_target)
		aic_node.abandon()
		return aic_size
	}
	if !aic_node.add('reg', ib_invoke(reg_target, [offset, aic_size])) {
		aic_node.abandon()
		return unsafe { nil }
	}
	if !aic_node.add('aic-iack-offset', s.constant_words(['AIC_IACK'])) || !aic_node.add('cap0-offset', s.word(4)) || !aic_node.add('maxnumirq-offset', s.word(0xc)) || !aic_node.add('extint-baseaddress', s.constant_word('AIC_CONFIG')) || !aic_node.add('extintrcfg-stride', s.constant_word('AIC_STRIDE')) || !aic_node.add('intmaskset-stride', s.constant_word('AIC_STRIDE')) || !aic_node.add('intmaskclear-stride', s.constant_word('AIC_STRIDE')) || !aic_node.add('aicglbcfg-offset', s.constant_word('AIC_GLOBAL_CONFIG')) {
		aic_node.abandon()
		return unsafe { nil }
	}
	aic = aic_node.finish(unsafe { nil })
	if aic == unsafe { nil } { return aic }
	arm_node := s.node()
	if arm_node.target == unsafe { nil } { return unsafe { nil } }
	if !arm_node.add('name', s.text('arm-io')) || !arm_node.add('#address-cells', s.word(2)) || !arm_node.add('#size-cells', s.word(2)) {
		arm_node.abandon()
		return unsafe { nil }
	}
	ranges_target := s.global('u64s')
	if ranges_target == unsafe { nil } {
		arm_node.abandon()
		return ranges_target
	}
	origin := s.global('RAM_BASE')
	if origin == unsafe { nil } {
		drop(ranges_target)
		arm_node.abandon()
		return origin
	}
	physical := s.global('PHYS_BASE')
	if physical == unsafe { nil } {
		drop(origin)
		drop(ranges_target)
		arm_node.abandon()
		return physical
	}
	origin2 := s.global('RAM_BASE')
	if origin2 == unsafe { nil } {
		drop(physical)
		drop(origin)
		drop(ranges_target)
		arm_node.abandon()
		return origin2
	}
	length := ib_binary('sub', physical, origin2)
	if length == unsafe { nil } {
		drop(origin)
		drop(ranges_target)
		arm_node.abandon()
		return length
	}
	if !arm_node.add('ranges', ib_invoke(ranges_target, [ib_int(0), origin, length])) {
		arm_node.abandon()
		return unsafe { nil }
	}
	children := C.PyList_New(2)
	C.PyList_SetItem(children, 0, own(wdt))
	C.PyList_SetItem(children, 1, own(firmware))
	include := C.PyObject_IsTrue(with_aic)
	if include < 0 {
		drop(children)
		arm_node.abandon()
		return unsafe { nil }
	}
	if include > 0 { C.PyList_Append(children, aic) }
	if C.PyErr_Occurred() != unsafe { nil } {
		drop(children)
		arm_node.abandon()
		return unsafe { nil }
	}
	arm_io = arm_node.finish(children)
	if arm_io == unsafe { nil } { return arm_io }
	chosen_node := s.node()
	if chosen_node.target == unsafe { nil } { return unsafe { nil } }
	if !chosen_node.add('name', s.text('chosen')) || !chosen_node.add('dram-base', s.constant_words(['RAM_BASE'])) || !chosen_node.add('dram-size', s.constant_words(['RAM_BYTES'])) {
		chosen_node.abandon()
		return unsafe { nil }
	}
	chosen = chosen_node.finish(unsafe { nil })
	if chosen == unsafe { nil } { return chosen }
	root := s.node()
	if root.target == unsafe { nil } { return unsafe { nil } }
	if !root.add('name', s.text('device-tree')) || !root.add('compatible', s.text('vinix,qemu-iboot')) || !root.add('#address-cells', s.word(2)) || !root.add('#size-cells', s.word(2)) {
		root.abandon()
		return unsafe { nil }
	}
	root_children := C.PyList_New(2)
	C.PyList_SetItem(root_children, 0, own(chosen))
	C.PyList_SetItem(root_children, 1, own(arm_io))
	return root.finish(root_children)
}

pub fn iboot_codec_entry(operation &char, namespace voidptr, arguments voidptr, syntax voidptr) voidptr {
	s := IbootCodec{ namespace: namespace, pins: unsafe { C.PyDict_GetItemString(syntax, c'pins') }, pair: unsafe { C.PyDict_GetItemString(syntax, c'pair') }, single: unsafe { C.PyDict_GetItemString(syntax, c'single') }, raise_: unsafe { C.PyDict_GetItemString(syntax, c'raise') } }
	op := unsafe { operation.vstring() }
	return match op {
		'qmp_init' { s.qmp_init(C.PyTuple_GetItem(arguments,0), C.PyTuple_GetItem(arguments,1)) }
 'qmp_reply' { s.qmp_reply(C.PyTuple_GetItem(arguments,0)) }
 'qmp_execute' { s.qmp_execute(C.PyTuple_GetItem(arguments,0), C.PyTuple_GetItem(arguments,1), C.PyTuple_GetItem(arguments,2)) }
 'png_chunk' { s.png_chunk(C.PyTuple_GetItem(arguments,0), C.PyTuple_GetItem(arguments,1)) }
		'write_png' { s.png(C.PyTuple_GetItem(arguments,0), C.PyTuple_GetItem(arguments,1), C.PyTuple_GetItem(arguments,2)) }
		'align' { s.align(C.PyTuple_GetItem(arguments, 0), C.PyTuple_GetItem(arguments, 1)) }
		'cstr' { s.cstr(C.PyTuple_GetItem(arguments, 0)) }
		'u32' { s.u32(C.PyTuple_GetItem(arguments, 0)) }
		'u64s' { s.u64s(arguments) }
		'build_adt' {
			s.build_adt(C.PyTuple_GetItem(arguments, 0), C.PyTuple_GetItem(arguments, 1))
		}
		'adt_node' { s.adt(C.PyTuple_GetItem(arguments, 0), C.PyTuple_GetItem(arguments, 1)) }
		'boot_args' {
			s.boot_args(C.PyTuple_GetItem(arguments, 0), C.PyTuple_GetItem(arguments, 1), C.PyTuple_GetItem(arguments, 2))
		}
		else {
			C.PyErr_SetObject(unsafe { voidptr(C.PyExc_KeyError) }, arguments)
			unsafe { nil }
		}
	}
}
