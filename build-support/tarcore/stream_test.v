// SPDX-License-Identifier: GPL-2.0-only
module tarcore

import os

#include <stdlib.h>

fn C.mkstemp(&u8) i32

fn test_stream_write_visibility_close_and_failure() {
	mut pattern := (os.temp_dir() + '/vinix-tar-write-XXXXXX\x00').bytes()
	fd := unsafe { C.mkstemp(pattern.data) }
	assert fd >= 0
	C.close(fd)
	path := pattern[..pattern.len - 1].bytestr()
	defer { os.rm(path) or {} }
	mut writer := create_stream(path)!
	defer { writer.close() }
	writer.write('visible before close'.bytes())!
	assert os.read_file(path)! == 'visible before close'
	writer.close_checked()!
	writer.write('closed'.bytes()) or {
		assert err.code() == C.EBADF
		writer.close_checked()!
		return
	}
	assert false
}

fn test_stream_write_reports_device_full_before_close() {
	$if linux {
		mut writer := create_stream('/dev/full')!
		defer { writer.close() }
		writer.write('cannot fit'.bytes()) or {
			assert err.code() == C.ENOSPC
			return
		}
		assert false
	}
}

fn test_gzip_close_reports_pending_write_failure() {
	// A buffered compressor can first report a device failure while closing.
	$if linux {
		mut writer := create_gzip('/dev/full')!
		writer.write('pending'.bytes()) or {}
		writer.close_checked() or {
			assert err.code() == C.ENOSPC
			writer.close_checked()!
			return
		}
		assert false
	}
}

fn test_gzip_pending_close_error_retires_the_owner() {
	mut writer := create_gzip('/dev/null')!
	writer.write('pending'.bytes())!
	// No descriptor is opened between this deliberate retirement and gzclose.
	assert C.close(writer.stream_fd) == 0
	writer.close_checked() or {
		assert err.code() == C.EBADF
		writer.close_checked()!
		writer.write('closed'.bytes()) or {
			assert err.msg() == 'gzip archive is closed'
			return
		}
		assert false
		return
	}
	assert false
}
