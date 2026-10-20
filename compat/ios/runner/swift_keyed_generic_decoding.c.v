// SPDX-License-Identifier: GPL-2.0-or-later
module main

// KeyedDecodingContainer<K>.decode<T: Decodable>(_:forKey:) borrows the
// container through x20, key through x1 and container metadata through x2.
// T metadata in x3 supplies x0/x2; K and K:CodingKey supply x3/x5. Leave
// T:Decodable in x4 and the indirect result address in x8 untouched.
// The box's class slot 248 initializes the result or returns its original
// owned error in x21. Restore the caller's x20 on either path. No key,
// result, box payload or refcount is inspected, retained or allocated here.
fn swift_keyed_generic_decoding_emit(code u64) {
	for i, op in [u32(0xa9be7bfd), // stp x29,x30,[sp,#-32]!
		0xf9000bf4, // str x20,[sp,#16]
		0x910003fd, // mov x29,sp
		0xaa0303e0, // mov x0,x3
		0xf9400294, // ldr x20,[x20]
		0xf9400290, // ldr x16,[x20]
		0xf9407e09, // ldr x9,[x16,#248]
		0xa9411443, // ldp x3,x5,[x2,#16]
		0xaa0003e2, // mov x2,x0
		0xd63f0120, // blr x9
		0xf9400bf4, // ldr x20,[sp,#16]
		0xa8c27bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn swift_keyed_generic_decoding_symbol(symbol string) ?u64 {
	if symbol != '_$ss22KeyedDecodingContainerV6decode_6forKeyqd__qd__m_xtKSeRd__lF'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_hash_entry(1536)
}
