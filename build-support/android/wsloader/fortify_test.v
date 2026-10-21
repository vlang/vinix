module wsloader

import os

fn test_checked_append_preserves_limits_and_aborts_overflow() {
	unsafe {
		mut buffer := [u8(`a`), `b`, 0, 0, 0, 0, 0, 0]!
		if os.getenv('VINIX_TEST_FORTIFY_ABORT') == '1' {
			message := c'FORTIFY-EXPECT-ABORT\n'
			C.write(1, message, C.strlen(message))
			checked_strncat(&char(&buffer[0]), c'123456', 6, 8)
			assert false, 'overflow returned to caller'
		}
		result := checked_strncat(&char(&buffer[0]), c'foo', 2, 8)
		assert voidptr(result) == voidptr(&buffer[0])
		assert buffer[..5] == [u8(`a`), `b`, `f`, `o`, 0]
		checked_strncat(&char(&buffer[0]), c'ignored', 0, 5)
		assert buffer[..5] == [u8(`a`), `b`, `f`, `o`, 0]
		child := os.exec(['env', 'VINIX_TEST_FORTIFY_ABORT=1', os.executable()])
		assert child.exit_code != 0
		assert child.output.contains('FORTIFY-EXPECT-ABORT')
		assert child.output.contains('FORTIFY: strncat: destination buffer too small')
	}
}

fn test_checked_positional_read_checks_capacity_and_preserves_position() {
	unsafe {
		mut buffer := [8]u8{}
		mode := os.getenv('VINIX_TEST_PREAD_ABORT')
		if mode != '' {
			count := if mode == 'ssize' { usize(0x8000000000000000) } else { usize(9) }
			capacity := if mode == 'ssize' { usize(-1) } else { usize(8) }
			checked_pread(-1, &buffer[0], count, 0, capacity)
			assert false, 'overflow returned to caller'
		}
		path := os.join_path(os.temp_dir(), 'vinix-pread-' + os.getpid().str())
		os.write_file(path, 'abcdef')!
		defer { os.rm(path) or {} }
		mut file := os.open(path)!
		defer { file.close() }
		assert checked_pread(file.fd, &buffer[0], 4, 2, 8) == 4
		assert buffer[..4] == 'cdef'.bytes()
		assert file.tell()! == 0
		assert checked_pread64(file.fd, &buffer[0], 8, 4, 8) == 2
		assert checked_pread(file.fd, &buffer[0], 0, 0, 0) == 0
		assert checked_pread(-1, &buffer[0], 1, 0, 8) == -1
		for variant in ['buffer', 'ssize'] {
			child := os.exec(['env', 'VINIX_TEST_PREAD_ABORT=' + variant, os.executable()])
			assert child.exit_code != 0
			assert child.output.contains('FORTIFY: pread: count')
		}
	}
}
