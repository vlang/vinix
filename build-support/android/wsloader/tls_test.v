module wsloader

@[typedef]
struct C.pthread_t {}

fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, &voidptr) i32

fn tls_test_thread(data voidptr) voidptr {
	unsafe {
		index := &TlsIndex(data)
		address := tls_address(index)
		if address == 0 || *(&u64(address)) != 0x123456789abcdef0 { return nil }
		*(&u64(address)) = 99
		return voidptr(usize(1))
	}
}

fn test_tls_templates_alignment_late_modules_and_thread_isolation() {
	unsafe {
		mut image := u64(0x123456789abcdef0)
		slot := tls_register(&image, 8, 256, 64)
		assert slot != ~usize(0)
		index := TlsIndex{slot, 0}
		address := tls_address(&index)
		assert address != 0 && address % 64 == 0
		assert *(&u64(address)) == image
		for i in 8 .. 256 {
			assert (&u8(address))[i] == 0
		}
		*(&u64(address)) = 42
		// The old registry indexed a vector allocated before these modules.
		for i in 0 .. 40 {
			late := tls_register(nil, 0, 128, 16)
			late_index := TlsIndex{late, 127}
			last := tls_address(&late_index)
			assert last != 0 && *(&u8(last)) == 0
			*(&u8(last)) = u8(i)
			assert tls_address(&index) == address && *(&u64(address)) == 42
		}
		mut threads := [16]C.pthread_t{}
		for i in 0 .. threads.len {
			assert C.pthread_create(&threads[i], nil, tls_test_thread, voidptr(&index)) == 0
		}
		for worker in threads {
			mut result := voidptr(nil)
			assert C.pthread_join(worker, &result) == 0 && usize(result) == 1
		}
		assert *(&u64(address)) == 42
		bad := TlsIndex{~usize(0), 0}
		assert tls_address(&bad) == 0
		assert tls_register(nil, 1, 8, 8) == ~usize(0)
		assert tls_register(&image, 8, 4, 8) == ~usize(0)
		assert tls_register(&image, 8, 8, 3) == ~usize(0)
		assert tls_register(&image, 8, 8, 0) == ~usize(0)
		empty := tls_register(nil, 0, 0, 0)
		assert empty != ~usize(0)
		empty_index := TlsIndex{empty, 0}
		assert tls_address(&empty_index) != 0
	}
}

fn tls_test_missing(library voidptr, name &char, base &usize) &TlsSymbol { return unsafe { nil } }

fn tls_test_owner(base voidptr) voidptr { return base }

fn test_tls_relocations_use_symbol_offsets_and_reject_missing_definitions() {
	unsafe {
		mut slot := usize(17)
		mut destination := usize(0)
		local := TlsSymbol{ info: 6, section: 1, value: 24 }
		assert relocate_tls(1029, &destination, &slot, &local, c'', 5, slot, 0, tls_test_missing, tls_test_owner) == 1
		assert destination == 29
		assert relocate_tls(1028, &destination, &slot, &local, c'', 0, slot, 0, tls_test_missing, tls_test_owner) == 1
		assert destination == 17
		strong := TlsSymbol{ info: 0x16 }
		assert relocate_tls(1029, &destination, &slot, &strong, c'missing', 0, slot, 0, tls_test_missing, tls_test_owner) == -1
		weak := TlsSymbol{ info: 0x26 }
		assert relocate_tls(1029, &destination, &slot, &weak, c'weak', 7, slot, 0, tls_test_missing, tls_test_owner) == 1
		assert destination == 7
		assert relocate_tls(1030, &destination, &slot, nil, c'', 0, slot, 0, tls_test_missing, tls_test_owner) == -1
		assert relocate_tls(1027, &destination, &slot, nil, c'', 0, slot, 0, tls_test_missing, tls_test_owner) == 0
	}
}
