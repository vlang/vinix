module wsloader

import os

#include <errno.h>
#include <signal.h>

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

fn test_checked_positional_write_checks_capacity_and_preserves_position() {
	unsafe {
		mode := os.getenv('VINIX_TEST_PWRITE_ABORT')
		if mode != '' {
			message := c'PWRITE-EXPECT-ABORT\n'
			C.write(1, message, C.strlen(message))
			count := if mode.ends_with('ssize') { usize(0x8000000000000000) } else { usize(9) }
			capacity := if mode.ends_with('ssize') { usize(-1) } else { usize(8) }
			if mode.starts_with('64-') {
				checked_pwrite64(-1, nil, count, 0, capacity)
			} else {
				checked_pwrite(-1, nil, count, 0, capacity)
			}
			message_after := c'PWRITE-RETURNED\n'
			C.write(1, message_after, C.strlen(message_after))
			return
		}
		path := os.join_path(os.temp_dir(), 'vinix-pwrite-' + os.getpid().str())
		os.write_file(path, 'abcdef')!
		defer { os.rm(path) or {} }
		mut file := os.open_file(path, 'r+')!
		defer { file.close() }
		assert checked_pwrite(file.fd, c'XY', 2, 2, 2) == 2
		assert checked_pwrite64(file.fd, c'Z', 1, 5, usize(-1)) == 1
		assert file.tell()! == 0
		assert os.read_file(path)! == 'abXYeZ'
		assert checked_pwrite(file.fd, nil, 0, 0, 0) == 0
		assert checked_pwrite64(file.fd, nil, 0, 0, 0) == 0
		for wide in [false, true] {
			C.errno = 0
			result := if wide { checked_pwrite64(-1, c'x', 1, 0, 1) } else { checked_pwrite(-1, c'x', 1, 0, 1) }
			assert result == -1
			assert C.errno == C.EBADF
			C.errno = 0
			negative := if wide { checked_pwrite64(file.fd, c'x', 1, -1, 1) } else { checked_pwrite(file.fd, c'x', 1, -1, 1) }
			assert negative == -1
			assert C.errno == C.EINVAL
		}
		mut readonly := os.open(path)!
		defer { readonly.close() }
		C.errno = 0
		assert checked_pwrite(readonly.fd, c'x', 1, 0, 1) == -1
		assert C.errno == C.EBADF
		// A sparse write verifies that the offset is not truncated to 32 bits.
		high := i64(0x100000002)
		assert checked_pwrite64(file.fd, c'HI', 2, high, 2) == 2
		mut bytes := [2]u8{}
		assert checked_pread(file.fd, &bytes[0], 2, high, 2) == 2
		assert bytes[..] == 'HI'.bytes()
		assert file.tell()! == 0
		for variant in ['buffer', 'ssize', '64-buffer', '64-ssize'] {
			mut child := os.new_process(os.find_abs_path_of_executable('env')!)
			child.set_args(['VINIX_TEST_PWRITE_ABORT=' + variant, os.executable()])
			child.set_redirect_stdio_merged()
			child.run()
			output := child.stdout_slurp()
			child.wait()
			assert child.status == .aborted
			assert child.code == 128 + int(C.SIGABRT)
			assert output.contains('PWRITE-EXPECT-ABORT')
			assert output.contains('FORTIFY: pwrite: count')
			assert !output.contains('PWRITE-RETURNED')
			child.close()
		}
	}
}
