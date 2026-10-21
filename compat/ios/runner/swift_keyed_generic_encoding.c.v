// SPDX-License-Identifier: GPL-2.0-or-later
module main

// KeyedEncodingContainer<K>.encode<T: Encodable>(_:forKey:) borrows value
// and key in x0/x1, container in x20 and container metadata in x2. Save T
// metadata from x3 in x8, then supply T in x2, K in x3 and K:CodingKey in
// x5; preserve T:Encodable in x4. The box's class slot 232 returns Void or
// its exact owned error in x21. Restore the caller's x20 on either path.
// Callers own readable header/metadata/slot spans. Value/key bytes, type
// records, witnesses, box payload and refcounts are not inspected or owned.
fn swift_keyed_generic_encoding_emit(code u64) {
	for i, op in [u32(0xa9be7bfd), // stp x29,x30,[sp,#-32]!
		0xf9000bf4, // str x20,[sp,#16]
		0x910003fd, // mov x29,sp
		0xaa0303e8, // mov x8,x3
		0xf9400294, // ldr x20,[x20]
		0xf9400290, // ldr x16,[x20]
		0xf9407609, // ldr x9,[x16,#232]
		0xa9411443, // ldp x3,x5,[x2,#16]
		0xaa0803e2, // mov x2,x8
		0xd63f0120, // blr x9
		0xf9400bf4, // ldr x20,[sp,#16]
		0xa8c27bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn swift_keyed_generic_encoding_symbol(symbol string) ?u64 {
	if symbol != '_$ss22KeyedEncodingContainerV6encode_6forKeyyqd___xtKSERd__lF'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_hash_entry(1728)
}
