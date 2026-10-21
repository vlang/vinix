module wsloader

import os

fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr

fn test_copy_mapping_preserves_misaligned_shared_pages_and_zeroes_bss() {
	assert sizeof(SegmentHeader) == 56
	path := os.join_path(os.temp_dir(), 'vinix-copy-segments-${os.getpid()}')
	defer { os.rm(path) or {} }
	mut input := []u8{len: 0x4000}
	for i in 0 .. input.len { input[i] = u8(i % 251 + 1) }
	os.write_file_array(path, input)!
	mut file := os.open(path)!
	defer { file.close() }
	headers := [
		SegmentHeader{ kind: 1, flags: 4, offset: 0, address: 0, file: 0x2000, memory: 0x2000, align: 4096 },
		SegmentHeader{ kind: 1, flags: 6, offset: 0x2000, address: 0x3000, file: 0x1000, memory: 0x1000, align: 4096 },
		SegmentHeader{ kind: 1, flags: 6, offset: 0x3000, address: 0x5000, file: 0x500, memory: 0x1000, align: 4096 },
		SegmentHeader{ kind: 2, offset: 0x2100, address: 0x3100, file: 32, memory: 32, align: 8 },
	]!
	unsafe {
		assert copy_required(&headers[0], usize(headers.len)) == 1
		assert segment_page_protection(&headers[0], usize(headers.len), 0) == 3
		assert segment_page_protection(&headers[0], usize(headers.len), 0x4000) == 3
		assert segment_page_protection(&headers[0], usize(headers.len), 0x8000) == 0
		base := usize(C.mmap(nil, 0xc000, 0, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert base != ~usize(0)
		mut dynamic := voidptr(nil)
		mut read_start, mut read_end, mut relro_size := u32(0), u32(0), u32(0)
		mut relro_start := usize(0)
		assert copy_segments(file.fd, &headers[0], usize(headers.len), base, 0xc000, &dynamic,
			&read_start, &read_end, &relro_start, &relro_size) == 0
		defer { C.munmap(voidptr(base), 0xc000) }
		assert usize(dynamic) == base + 0x3100
		assert read_start == 0xffffffff && read_end == 0 && relro_start == 0 && relro_size == 0
		pixels := &u8(base)
		for i in 0 .. 0x2000 { assert pixels[i] == input[i] }
		for i in 0 .. 0x1000 { assert pixels[0x3000 + i] == input[0x2000 + i] }
		for i in 0 .. 0x500 { assert pixels[0x5000 + i] == input[0x3000 + i] }
		for i in 0x5500 .. 0x6000 { assert pixels[i] == 0 }
		assert finish_copy_segments(&headers[0], usize(headers.len), base, 0xc000) == 0
		assert pixels[0x3100] == input[0x2100]
		pixels[0x3000] = 17
		assert pixels[0x3000] == 17
	}
}

fn test_copy_mapping_relro_preserves_partial_pages_and_rejects_ranges() {
	unsafe {
		mut headers := [
			SegmentHeader{ kind: 1, flags: 6, address: 0, memory: 0x8000, align: 16384 },
			SegmentHeader{ kind: 0x6474e552, address: 0x1000, memory: 0x7000 },
		]!
		assert copy_required(&headers[0], usize(headers.len)) == 0
		assert segment_page_protection(&headers[0], usize(headers.len), 0) == 3
		assert segment_page_protection(&headers[0], usize(headers.len), 0x4000) == 1
		assert !segment_in_image(SegmentHeader{ address: 0x8000, memory: 1 }, 0x8000)
		assert !segment_in_image(SegmentHeader{ file: 2, memory: 1 }, 0x8000)
		assert !segment_in_image(SegmentHeader{ offset: u64(0x7fffffffffffffff), file: 2, memory: 2 }, 0x8000)
		// A truncated source must fail rather than publish a partly copied image.
		mut empty := os.open('/dev/null')!
		defer { empty.close() }
		headers[0] = SegmentHeader{ kind: 1, flags: 6, file: 4096, memory: 4096, align: 4096 }
		base := usize(C.mmap(nil, 0x8000, 0, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert base != ~usize(0)
		mut value := u32(0)
		mut address := usize(0)
		mut dynamic := voidptr(nil)
		assert copy_segments(empty.fd, &headers[0], 1, base, 0x8000, &dynamic, &value, &value, &address, &value) == -1
	}
}
