// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

import hosttest
import os

#include <sys/stat.h>

fn C.mkfifo(&char, u32) i32

fn test_original_oracle_and_ranges_preserve_provenance() {
	source := original_source()!
	for kind in ['signal', 'touch', 'restart', 'nanosleep', 'blocked', 'poll', 'epoll', 'int'] {
		text := original_reference(kind, source, false)
		assert text.contains('#line 52 "test.c"\n')
		assert !text.contains('static int test_')
		assert text.contains('original_test_')
	}
}

fn test_copy_lifetime_backslashes_duplicate_and_fifo_inputs() {
	work := hosttest.work_dir('', 'vinix-qemu-copy-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	mkdir_all(work + '/source')!
	mkdir_all(work + '/target')!
	write(work + '/source/literal\\name.v', 'module example\n')!
	stage_pending(work + '/source', work + '/target')!
	assert read(work + '/target/literal\\name.v')! == 'module example\n'
	if _ := stage_pending(work + '/source', work + '/source') {
		assert false
	} else {
		assert err.msg().contains('same file')
	}
	write(work + '/source/literal\\name.v.pending', 'duplicate')!
	if _ := stage_pending(work + '/source', work + '/target') {
		assert false
	} else {
		assert err.msg().contains('Duplicate maintained/pending input:')
	}
	assert read(work + '/target/literal\\name.v')! == 'module example\n'
	os.rm(work + '/source/literal\\name.v.pending')!
	assert C.mkfifo((work + '/source/pipe.v').str, 0o600) == 0
	assert C.mkfifo((work + '/target/pipe.v').str, 0o600) == 0
	if _ := stage_pending(work + '/source', work + '/target') {
		assert false
	} else {
		assert err is CopyFileError && err.source == work + '/source/pipe.v'
	}
	for directory in [work + '/source', work + '/target'] {
		for name in os.ls(directory)! { os.rm(directory + '/' + name)! }
	}
}

fn test_reader_failures_and_child_streams_restore_descriptor_set() {
	work := hosttest.work_dir('', 'vinix-qemu-fd-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	write(work + '/inherited', 'owned')!
	mut inherited := os.open(work + '/inherited')!
	defer { inherited.close() }
	inherited_fd := C.fcntl(i32(inherited.fd), C.F_DUPFD, 100)
	assert inherited_fd >= 100
	defer { C.close(inherited_fd) }
	assert command(['/bin/sh', '-c', 'test ! -e /dev/fd/' + inherited_fd.str()], '')! == ''
	mut before := os.ls('/dev/fd')!
	before.sort()
	for _ in 0 .. 100 {
		if _ := read(work) {
			assert false
		} else {
			assert err is FileError && err.number == 21
		}
		if _ := write(work, 'data') {
			assert false
		} else {
			assert err is FileError && err.number == 21
		}
		assert command(['/bin/sh', '-c', 'printf "first\\n"; printf "second\\r\\n" >&2'], '')! == 'first\nsecond\n'
	}
	inherited_command_environment(['/bin/sh', '-c', 'test "$VINIX_FIXTURE_ENV_CONTROL" = custom'], {
		'VINIX_FIXTURE_ENV_CONTROL': 'custom'
	})!
	if _ := inherited_command(['/bin/sh', '-c', 'kill -PIPE $$']) {
		assert false
	} else {
		assert err is CommandError && err.status == -13
	}
	mut after := os.ls('/dev/fd')!
	after.sort()
	assert before == after
}

fn test_python_metadata_framing_preserves_ascii_and_unicode() {
	assert quoted('plain "\\\n\x7f é 😀') == '"plain \\"\\\\\\n\\u007f \\u00e9 \\ud83d\\ude00"'
	assert pretty(hosttest.decode_json('{"list":[1,true,null],"empty":[]}')!, 0) == '{\n  "list": [\n    1,\n    true,\n    null\n  ],\n  "empty": []\n}'
}

fn test_spawn_errors_signal_status_and_log_order_preserve_contract() {
	work := hosttest.work_dir('', 'vinix-qemu-spawn-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	mut before := os.ls('/dev/fd')!
	before.sort()
	for _ in 0 .. 100 {
		if _ := command([work + '/missing'], work + '/missing.log') {
			assert false
		} else {
			assert err is FileError && err.number == 2
		}
		assert !os.exists(work + '/missing.log')
		if _ := command(['/bin/sh', '-c', 'printf "before\r\n"; exit 7'], work + '/failure.log') {
			assert false
		} else {
			assert err is CommandError && err.status == 7 && err.output == 'before\n'
		}
		assert read(work + '/failure.log')! == 'before\n'
		if _ := inherited_command(['/bin/sh', '-c', 'kill -TERM $$']) {
			assert false
		} else {
			assert err is CommandError && err.status == -15
		}
	}
	if _ := inherited_command(['/bin/sh', '-c', 'kill -PIPE $$']) {
		assert false
	} else {
		assert err is CommandError && err.status == -13
	}
	mut after := os.ls('/dev/fd')!
	after.sort()
	assert before == after
}

fn test_invalid_child_output_is_decoded_before_log_and_status() {
	work := hosttest.work_dir('', 'vinix-qemu-decode-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	for suffix in ['', '; exit 7'] {
		if _ := command(['/bin/sh', '-c', 'printf "before\\377after"' + suffix], work + '/invalid.log') {
			assert false
		} else {
			assert err is hosttest.ModuleDecodeError && err.start == 6 && err.end == 7
			assert err.reason == 'invalid start byte'
			assert err.data.hex() == '6265666f7265ff6166746572'
		}
		assert !os.exists(work + '/invalid.log')
	}
}

fn test_oracle_commands_preserve_cwd_stderr_and_raw_bytes() {
	work := hosttest.work_dir('', 'vinix-qemu-raw-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	write(work + '/marker', 'present')!
	result := capture_in(['/bin/sh', '-c', 'test -f marker && printf "raw\\377\\r\\n"'], '', os.environ(), false, work, true)!
	assert result.bytes().hex() == '726177ff0d0a'
	if _ := capture_in(['/bin/sh', '-c', 'printf "raw\\377"; exit 7'], '', os.environ(), false, work, true) {
		assert false
	} else {
		assert err is CommandError && err.status == 7 && err.binary_output
		assert err.output.bytes().hex() == '726177ff'
	}
}
