module ninep

fn test_options_bounds_duplicates_and_dialect() {
	mut opts := Options{}
	assert parse_options('trans=virtio,version=9p2000.L,cache=none,msize=65536', unsafe { &opts })
	assert opts.msize == 65536
	assert parse_options('', unsafe { &opts })
	assert parse_options('ro,msize=4096,noexec', unsafe { &opts })
	assert opts.msize == 4096
	for bad in ['msize=0', 'msize=4095', 'msize=65537', 'msize=4294967296', 'msize=18446744073709551616',
		'msize=-1', 'msize=+4096', 'msize=4096x', 'msize=', 'msize=4096,msize=8192', 'cache=loose',
		'version=9P2000.L', 'version=9p2000', 'trans=tcp', 'cache=none,cache=none', ',ro', 'ro,',
		'ro,,rw', 'unknown=1'] {
		assert !parse_options(bad, unsafe { &opts }), bad
	}
}

fn test_reader_truncation_and_writer_capacity() {
	mut buf := [64]u8{}
	mut w := writer(&buf[0], 64, 116, 19)
	w.word(0x1234)
	w.dword(0x89abcdef)
	w.qword(0xfedcba9876543210)
	assert w.finish() == 21
	for length in 0 .. 21 {
		mut r := reader(&buf[0], u32(length))
		r.dword()
		r.byte()
		r.word()
		r.word()
		r.dword()
		r.qword()
		assert !r.done()
	}
	mut r := reader(&buf[0], 21)
	assert r.dword() == 21 && r.byte() == 116 && r.word() == 19
	assert r.word() == 0x1234 && r.dword() == 0x89abcdef && r.qword() == 0xfedcba9876543210
	assert r.done()
	mut tiny := writer(&buf[0], 7, 100, 0)
	tiny.qword(1)
	assert tiny.finish() == 0
	mut invalid := reader(&buf[0], 0xffffffff)
	assert !invalid.take(1)
	invalid.pos = 0xffffffff
	assert !invalid.take(2)
}

fn test_reply_header_errors_and_size_validation() {
	mut buf := [64]u8{}
	mut w := writer(&buf[0], 64, 117, 3)
	w.dword(0)
	n := w.finish()
	mut r := Reader{}
	assert reply(&buf[0], n, 4096, 116, 3, unsafe { &r }) == 0
	assert reply(&buf[0], n, 4096, 116, 4, unsafe { &r }) == eproto
	assert reply(&buf[0], n, 4096, 118, 3, unsafe { &r }) == eproto
	assert reply(&buf[0], n - 1, 4096, 116, 3, unsafe { &r }) == eproto
	assert reply(&buf[0], 65537, 65536, 116, 3, unsafe { &r }) == eproto
	assert reply(&buf[0], 65536, 4096, 116, 3, unsafe { &r }) == eproto
	for length in 0 .. 7 {
		assert reply(&buf[0], u32(length), 4096, 116, 3, unsafe { &r }) == eproto
	}
	for code in [u32(0), 1, 2, 5, 95, 4095, 4096, 0xffffffff] {
		mut error_frame := writer(&buf[0], 64, 7, 3)
		error_frame.dword(code)
		length := error_frame.finish()
		assert reply(&buf[0], length, 4096, 116, 3, unsafe { &r }) == if code > 0 && code <= 4095 {
			int(code)
		} else {
			eproto
		}
	}
}

fn put_dir(mut w Writer, cookie u64, name string) {
	w.byte(0)
	w.dword(0)
	w.qword(1)
	w.qword(cookie)
	w.byte(8)
	w.text(name)
}

fn test_readdir_bounded_names_cookies_truncation_and_payload() {
	mut buf := [1024]u8{}
	mut w := writer(&buf[0], 1024, 41, 1)
	put_dir(mut w, 42, 'hello')
	n := w.finish()
	mut entry := DirEntry{}
	for length in 0 .. int(n - 7) {
		mut r := reader(unsafe { &buf[7] }, u32(length))
		assert !next_entry(mut r, 0, unsafe { &entry })
	}
	mut good := reader(unsafe { &buf[7] }, n - 7)
	assert next_entry(mut good, 0, unsafe { &entry })
	assert entry.offset == 42 && entry.length == 5 && entry.name[0] == `h` && good.done()
	mut loop := reader(unsafe { &buf[7] }, n - 7)
	assert !next_entry(mut loop, 42, unsafe { &entry })
	for name in ['', 'a/b', 'a\x00b', 'x'.repeat(256)] {
		mut bad := writer(&buf[0], 1024, 41, 1)
		put_dir(mut bad, 2, name)
		length := bad.finish()
		mut r := reader(unsafe { &buf[7] }, length - 7)
		assert !next_entry(mut r, 0, unsafe { &entry })
	}
	mut data := writer(&buf[0], 1024, 117, 1)
	data.dword(0xffffffff)
	length := data.finish()
	mut body := reader(unsafe { &buf[7] }, length - 7)
	mut start := u32(0)
	mut count := u32(0)
	assert !payload(mut body, 100, unsafe { &start }, unsafe { &count })
}

fn attr_frame(mut w Writer, size u64, nanos u64) {
	w.qword(0x7ff)
	w.byte(0)
	w.dword(1)
	w.qword(99)
	w.dword(0o100644)
	w.dword(1000)
	w.dword(1000)
	w.qword(1)
	w.qword(0)
	w.qword(size)
	w.qword(4096)
	w.qword(8)
	w.qword(1)
	w.qword(nanos)
	w.qword(2)
	w.qword(0)
	w.qword(3)
	w.qword(0)
	for _ in 0 .. 4 { w.qword(0) }
}

fn test_getattr_truncation_overflow_and_time_validation() {
	mut buf := [512]u8{}
	mut w := writer(&buf[0], 512, 25, 1)
	attr_frame(mut w, 1234, 999999999)
	n := w.finish()
	assert n == 160
	mut attr := Attr{}
	for length in 0 .. int(n - 7) {
		mut r := reader(unsafe { &buf[7] }, u32(length))
		assert !parse_attr(mut r, unsafe { &attr })
	}
	mut r := reader(unsafe { &buf[7] }, n - 7)
	assert parse_attr(mut r, unsafe { &attr })
	assert attr.size == 1234 && attr.qid.path == 99 && attr.mode == 0o100644
	for value in [u64(0x8000000000000000), u64(-1)] {
		mut bad := writer(&buf[0], 512, 25, 1)
		attr_frame(mut bad, value, 0)
		length := bad.finish()
		mut b := reader(unsafe { &buf[7] }, length - 7)
		assert !parse_attr(mut b, unsafe { &attr })
	}
	mut bad := writer(&buf[0], 512, 25, 1)
	attr_frame(mut bad, 1, 1000000000)
	length := bad.finish()
	mut b := reader(unsafe { &buf[7] }, length - 7)
	assert !parse_attr(mut b, unsafe { &attr })
	assert valid_range(0x7fffffffffffffff, 0)
	assert !valid_range(0x7fffffffffffffff, 1)
	assert !valid_range(u64(-1), 2)
}

fn test_arbitrary_bounded_reply_bytes_never_panic() {
	mut buf := [512]u8{}
	mut seed := u32(0x12345678)
	mut attr := Attr{}
	mut entry := DirEntry{}
	for round in 0 .. 4096 {
		for i in 0 .. buf.len {
			seed = seed * 1664525 + 1013904223
			buf[i] = u8(seed >> 24)
		}
		n := u32(round % 513)
		mut r := reader(&buf[0], n)
		parse_attr(mut r, unsafe { &attr })
		mut d := reader(&buf[0], n)
		next_entry(mut d, 0, unsafe { &entry })
		mut h := Reader{}
		reply(&buf[0], n, 4096, 116, 1, unsafe { &h })
	}
}
