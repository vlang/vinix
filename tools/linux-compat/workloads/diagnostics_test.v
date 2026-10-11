module main

import os
import time

fn test_proc_reader_bounds_data_without_using_reported_file_size() {
	root := os.join_path(os.temp_dir(), 'vinix-diagnostic-${os.getpid()}-${time.now().unix_nano()}')
	os.mkdir_all(root + '/42')!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/meminfo', 'm'.repeat(8192))!
	os.write_file(root + '/kernel-resources', 'budget=19\n')!
	os.write_file(root + '/42/maps', 'x'.repeat(32769))!
	suite := Suite{diagnostics_root: root}
	snapshot := suite.diagnostic_snapshot('timeout', 42)
	assert snapshot.phase == 'timeout' && snapshot.files.len == 5
	assert snapshot.files[0].content.len == 8192 && !snapshot.files[0].truncated
	assert snapshot.files[1].content == 'budget=19\n' && snapshot.files[1].error == ''
	assert snapshot.files[2].content == '' && snapshot.files[2].error != ''
	assert snapshot.files[3].content.len == 32768 && snapshot.files[3].truncated
	assert snapshot.files[3].error == ''
	assert Suite{}.diagnostic_snapshot('timeout', 42).files.len == 0
}

fn test_unknown_length_stream_is_still_bounded() {
	file := diagnostic_file('/dev/zero', 16)
	assert file.content.len == 16 && file.truncated && file.error == ''
	assert file.content.bytes().all(it == 0)
}

fn test_failure_diagnostics_preserve_exit_and_deadline_verdicts() {
	root := os.join_path(os.temp_dir(), 'vinix-diagnostic-run-${os.getpid()}-${time.now().unix_nano()}')
	os.mkdir_all(root + '/work')!
	os.mkdir(root + '/proc')!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/proc/meminfo', 'MemFree: 1234 kB\n')!
	mut suite := Suite{work: root + '/work', path: 'native-aarch64', timeout: 1, diagnostics_root: root + '/proc'}
	suite.execute('false', []) or {
		assert suite.commands.len == 1 && suite.commands[0].exit_code != 0
		assert !suite.commands[0].timed_out
		assert suite.commands[0].diagnostics.len == 2
		assert suite.commands[0].diagnostics[1].phase == 'nonzero-exit'
		assert suite.commands[0].diagnostics[1].files[1].error != ''
		suite.execute('sleep', ['5']) or {
			assert suite.commands.len == 2 && suite.commands[1].timed_out
			last := suite.commands[1].diagnostics[1]
			assert last.phase == 'timeout' && last.files.len == 5
			assert last.files[0].content == 'MemFree: 1234 kB\n'
			assert last.files[2].path.ends_with('/status') && last.files[2].error != ''
			assert os.read_file(root + '/work/command-2.json')!.contains('"diagnostics"')
			return
		}
		assert false, 'timeout was accepted despite diagnostics'
		return
	}
	assert false, 'nonzero exit was accepted despite diagnostics'
}
