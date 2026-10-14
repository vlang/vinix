// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A nominal declaration is distinct from both Array<Element> value metadata
// and an allocated storage owner's private header. Publish the measured class
// identity, bounds and single-key generic context in the existing Array arena.
// Accessor, reflection, instantiation cache/pattern and override records are
// absent: storage-class instantiation and ObjC inheritance are not supported.
fn swift_array_class_emit(data u64) {
	descriptor := data + 320
	write32(descriptor,0xd0) // Unique generic class, no unsupported trailing tables.
	swift_protocol_relative(descriptor + 4,data + 224)
	swift_protocol_relative(descriptor + 8,data + 384)
	swift_protocol_relative(descriptor + 20,data + 416)
	write32(descriptor + 24,3) // Metadata prefix in words.
	write32(descriptor + 28,19) // Metadata suffix in words.
	write32(descriptor + 32,1) // One immediate generic argument at word 18.
	write32(descriptor + 40,19) // Empty field offset vector.
	write32(descriptor + 52,1) // NumParams=1, NumRequirements=0.
	write32(descriptor + 56,1) // NumKeyArguments=1, flags=0.
	write32(descriptor + 60,0x80) // One key type parameter, padding zero.
	C.memcpy(unsafe { voidptr(data + 384) },c'_ContiguousArrayStorage',24)
	C.memcpy(unsafe { voidptr(data + 416) },c's28__ContiguousArrayStorageBaseC',33)
}
fn swift_array_class_descriptor() u64 {
	return swift_array_arena() + u64(C.getpagesize()) + 320
}
