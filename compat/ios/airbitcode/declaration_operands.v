// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Module v2 GLOBALVAR: name offset/length, type, flags, initializer, linkage,
// alignment, section, ... . Only the declared pointer type is read here.
fn (mut b OperandBuilder) global_pointer(values []u64) !int {
	if values.len < 8 || values[2] >= u64(b.ir.types.len) { return error('AIR globals: declaration header/type') }
	if values[3] & 2 == 0 {
		if values[3] > 1 { return error('AIR globals: legacy declaration flags') }
		pointer := int(values[2])
		element := b.pointee(pointer)!
		if element < 0 { return error('AIR globals: legacy pointee unavailable') }
		b.storable(element)!
		return pointer
	}
	if b.mixed_pointers { return error('AIR globals: mixed pointer model unsupported') }
	element := b.type_id(values[2])!
	b.storable(element)!
	space := values[3] >> 2
	if space > 0xffffff { return error('AIR globals: address space limit') }
	return b.pointer(element, u32(space), b.opaque_allocas)!
}
