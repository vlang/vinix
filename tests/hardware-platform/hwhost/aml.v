// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Just enough of an ACPI Machine Language assembler to describe a few devices
// to a machine under test.
//
// A PC's batteries, charger and lid exist for the kernel only as what
// firmware's ACPI tables say about them, and QEMU's PC has none of the three.
// QEMU does accept extra tables (-acpitable), so a test that wants a battery
// writes one. There is no ASL compiler on a machine that only builds Vinix,
// and the handful of opcodes such a table needs are quickly put together by
// hand; these functions each return the bytes of one construct, to be
// concatenated. The encodings are the ACPI specification's (6.5, chapter 20).
module hwhost

// A package length: the count of the bytes that follow it plus its own, in
// one to three bytes.
fn aml_length(body int) []u8 {
	if body + 1 < 0x40 {
		return [u8(body + 1)]
	}
	if body + 2 < 0x1000 {
		total := body + 2
		return [u8(0x40 | (total & 0xf)), u8(total >> 4)]
	}
	total := body + 3
	return [u8(0x80 | (total & 0xf)), u8((total >> 4) & 0xff), u8(total >> 12)]
}

fn aml_block(opcode []u8, body []u8) []u8 {
	mut out := opcode.clone()
	out << aml_length(body.len)
	out << body
	return out
}

// One name segment: four characters, padded with underscores.
fn aml_segment(name string) []u8 {
	mut out := name.bytes()
	for out.len < 4 {
		out << `_`
	}
	return out[..4]
}

// A name: one segment, or a path from the root such as `\_SB.BAT0.TICK`.
pub fn aml_name(path string) []u8 {
	mut out := []u8{}
	mut rest := path
	if rest.starts_with('\\') {
		out << `\\`
		rest = rest[1..]
	}
	segments := rest.split('.')
	if segments.len == 2 {
		out << 0x2e
	} else if segments.len > 2 {
		out << 0x2f
		out << u8(segments.len)
	}
	for segment in segments {
		out << aml_segment(segment)
	}
	return out
}

pub fn aml_integer(value u64) []u8 {
	if value == 0 {
		return [u8(0x00)]
	}
	if value == 1 {
		return [u8(0x01)]
	}
	if value <= 0xff {
		return [u8(0x0a), u8(value)]
	}
	if value <= 0xffff {
		return [u8(0x0b), u8(value), u8(value >> 8)]
	}
	if value <= 0xffffffff {
		return [u8(0x0c), u8(value), u8(value >> 8), u8(value >> 16), u8(value >> 24)]
	}
	mut out := [u8(0x0e)]
	for shift := 0; shift < 64; shift += 8 {
		out << u8(value >> shift)
	}
	return out
}

pub fn aml_string(text string) []u8 {
	mut out := [u8(0x0d)]
	out << text.bytes()
	out << 0
	return out
}

fn aml_join(parts [][]u8) []u8 {
	mut out := []u8{}
	for part in parts {
		out << part
	}
	return out
}

pub fn aml_scope(path string, body [][]u8) []u8 {
	mut inner := aml_name(path)
	inner << aml_join(body)
	return aml_block([u8(0x10)], inner)
}

pub fn aml_device(name string, body [][]u8) []u8 {
	mut inner := aml_name(name)
	inner << aml_join(body)
	return aml_block([u8(0x5b), 0x82], inner)
}

// Name(name, value): a named object holding `value`.
pub fn aml_named(name string, value []u8) []u8 {
	mut out := [u8(0x08)]
	out << aml_name(name)
	out << value
	return out
}

// A method with no arguments.
pub fn aml_method(name string, body [][]u8) []u8 {
	mut inner := aml_name(name)
	inner << 0x00
	inner << aml_join(body)
	return aml_block([u8(0x14)], inner)
}

pub fn aml_return(value []u8) []u8 {
	mut out := [u8(0xa4)]
	out << value
	return out
}

pub fn aml_package(elements [][]u8) []u8 {
	mut inner := [u8(elements.len)]
	inner << aml_join(elements)
	return aml_block([u8(0x12)], inner)
}

pub fn aml_if(predicate []u8, body [][]u8) []u8 {
	mut inner := predicate.clone()
	inner << aml_join(body)
	return aml_block([u8(0xa0)], inner)
}

fn aml_two(opcode u8, a []u8, b []u8) []u8 {
	mut out := [opcode]
	out << a
	out << b
	return out
}

pub fn aml_equal(a []u8, b []u8) []u8 {
	return aml_two(0x93, a, b)
}

pub fn aml_greater(a []u8, b []u8) []u8 {
	return aml_two(0x94, a, b)
}

pub fn aml_less(a []u8, b []u8) []u8 {
	return aml_two(0x95, a, b)
}

// The three arithmetic operators take a place to put the result as well; the
// null name says there is none, and the value is what the expression is.
fn aml_arithmetic(opcode u8, a []u8, b []u8) []u8 {
	mut out := aml_two(opcode, a, b)
	out << 0x00
	return out
}

pub fn aml_add(a []u8, b []u8) []u8 {
	return aml_arithmetic(0x72, a, b)
}

pub fn aml_subtract(a []u8, b []u8) []u8 {
	return aml_arithmetic(0x74, a, b)
}

pub fn aml_multiply(a []u8, b []u8) []u8 {
	return aml_arithmetic(0x77, a, b)
}

pub fn aml_store(value []u8, target []u8) []u8 {
	return aml_two(0x70, value, target)
}

pub fn aml_increment(target []u8) []u8 {
	mut out := [u8(0x75)]
	out << target
	return out
}

// Element `index` of the package or buffer `source`, as a place to store to.
pub fn aml_index(source []u8, index []u8) []u8 {
	return aml_arithmetic(0x88, source, index)
}

pub fn aml_notify(object []u8, value []u8) []u8 {
	return aml_two(0x86, object, value)
}

pub fn aml_local(number int) []u8 {
	return [u8(0x60 + number)]
}

// A buffer holding `bytes`.
pub fn aml_buffer(bytes []u8) []u8 {
	mut inner := aml_integer(u64(bytes.len))
	inner << bytes
	return aml_block([u8(0x11)], inner)
}

// One I/O port, as a descriptor of a resource template: sixteen-bit decode,
// a range of exactly that port.
pub fn aml_io_port(port u16) []u8 {
	return [u8(0x47), 0x01, u8(port), u8(port >> 8), u8(port), u8(port >> 8), 0x01, 0x01]
}

// What _CRS returns: the descriptors and the tag that ends them.
pub fn aml_resources(descriptors [][]u8) []u8 {
	mut bytes := aml_join(descriptors)
	bytes << [u8(0x79), 0x00]
	return aml_buffer(bytes)
}

// The address space of an embedded controller's registers.
pub const aml_embedded_control = u8(3)

// OperationRegion (name, space, offset, length).
pub fn aml_region(name string, space u8, offset u64, length u64) []u8 {
	mut out := [u8(0x5b), 0x80]
	out << aml_name(name)
	out << space
	out << aml_integer(offset)
	out << aml_integer(length)
	return out
}

// How a field reaches its region, and whether the global lock is taken for
// it: the low bits of a field's flags.
pub const aml_byte_access = u8(1)
pub const aml_word_access = u8(2)
pub const aml_dword_access = u8(3)
pub const aml_field_lock = u8(0x10)

// A count of bits in a field list: written the way a package length is, but
// counting only what it says.
fn aml_bits(bits int) []u8 {
	if bits < 0x40 {
		return [u8(bits)]
	}
	if bits < 0x1000 {
		return [u8(0x40 | (bits & 0xf)), u8(bits >> 4)]
	}
	return [u8(0x80 | (bits & 0xf)), u8((bits >> 4) & 0xff), u8(bits >> 12)]
}

// `bits` bits of a region under a name.
pub fn aml_field_unit(name string, bits int) []u8 {
	mut out := aml_segment(name)
	out << aml_bits(bits)
	return out
}

// `bits` bits of a region that have no name.
pub fn aml_field_gap(bits int) []u8 {
	mut out := [u8(0x00)]
	out << aml_bits(bits)
	return out
}

// Field (region, flags) { units }: the units lie one after the other from
// the start of the region.
pub fn aml_field(region string, flags u8, units [][]u8) []u8 {
	mut inner := aml_name(region)
	inner << flags
	inner << aml_join(units)
	return aml_block([u8(0x5b), 0x81], inner)
}

// A whole table: the 36-byte header every ACPI table starts with, then
// `content`, with the checksum that makes all its bytes sum to zero.
pub fn acpi_blob(signature string, revision u8, table_id string, content []u8) []u8 {
	mut out := []u8{len: 36}
	for i in 0 .. 4 {
		out[i] = signature[i]
	}
	length := u32(36 + content.len)
	for i in 0 .. 4 {
		out[4 + i] = u8(length >> (8 * i))
	}
	out[8] = revision
	oem := 'VINIX '
	for i in 0 .. 6 {
		out[10 + i] = oem[i]
	}
	for i in 0 .. 8 {
		out[16 + i] = if i < table_id.len { table_id[i] } else { u8(` `) }
	}
	out[24] = 1 // OEM revision
	creator := 'VNXT'
	for i in 0 .. 4 {
		out[28 + i] = creator[i]
	}
	out[32] = 1 // creator revision
	out << content
	mut sum := u8(0)
	for b in out {
		sum += b
	}
	out[9] = u8(0) - sum
	return out
}

// A table of AML: a definition block, revision 2 for 64-bit integers.
pub fn aml_table(signature string, table_id string, body [][]u8) []u8 {
	return acpi_blob(signature, 2, table_id, aml_join(body))
}

// An I/O port as a table gives it: a generic address, twelve bytes.
fn acpi_io_address(port u16) []u8 {
	return [u8(1), 8, 0, 1, u8(port), u8(port >> 8), 0, 0, 0, 0, 0, 0]
}

// An ECDT (ACPI 6.5, 5.2.15): where the embedded controller is, for a
// kernel that has not loaded the namespace yet. `path` is the controller's
// device in the namespace.
pub fn ecdt_table(command u16, data u16, uid u32, gpe u8, path string) []u8 {
	mut content := acpi_io_address(command)
	content << acpi_io_address(data)
	for i in 0 .. 4 {
		content << u8(uid >> (8 * i))
	}
	content << gpe
	content << path.bytes()
	content << 0
	return acpi_blob('ECDT', 1, 'HWTESTEC', content)
}
