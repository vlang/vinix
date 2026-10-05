module elf

import resource

fn scan(words []u64) bool {
	mut data := []u8{len: words.len * 8}
	defer { unsafe { data.free() } }
	unsafe { C.memcpy(data.data, words.data, data.len) }
	mut res := resource.Resource{stat: resource.Stat{size: data.len}, data: data}
	return dynamic_textrel(mut res, ProgramHdr{p_filesz: u64(data.len)}) or { panic(err) }
}

fn test_both_textrel_encodings() {
	assert scan([u64(22), 0, 0, 0])
	// DT_FLAGS=DF_TEXTREL followed by DT_NULL, with no legacy DT_TEXTREL.
	assert scan([u64(30), 4, 0, 0])
	assert scan([u64(30), 5, 0, 0])
	assert !scan([u64(30), 1, 0, 0])
	assert !scan([u64(0), 0])
	// Values after the terminator are outside the dynamic table.
	assert !scan([u64(0), 0, 22, 0])
}

fn test_malformed_tables_stay_mutable() {
	assert scan([u64(30), 0])
	mut data := []u8{len: 65537}
	defer { unsafe { data.free() } }
	mut res := resource.Resource{stat: resource.Stat{size: data.len}, data: data}
	assert dynamic_textrel(mut res, ProgramHdr{p_filesz: u64(data.len)}) or { panic(err) }
	assert dynamic_textrel(mut res, ProgramHdr{p_filesz: 8}) or { panic(err) }
	if _ := dynamic_textrel(mut res, ProgramHdr{p_offset: 65537, p_filesz: 1}) {
		assert false
	}
	if _ := dynamic_textrel(mut res, ProgramHdr{p_offset: u64(-1), p_filesz: 0}) {
		assert false
	}
}
