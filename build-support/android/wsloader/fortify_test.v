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
