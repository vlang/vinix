// SPDX-License-Identifier: GPL-2.0-or-later
module archivercheck

import hosttest
import os

fn test_real_archiver_command_and_failed_compiler_cleanup() {
	tool := os.getenv('VINIX_ARCHIVER_CHECK')
	if tool == '' { return }
	work := hosttest.work_dir('', 'vinix-ar-cleanup-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	temporary := work + '/temporary'
	os.mkdir(temporary)!
	mut environment := os.environ()
	environment['TMPDIR'] = temporary
	success := hosttest.capture([tool], '', 60, environment)!
	assert success.code == 0 && success.stdout == 'Kernel archiver tests passed.\n' && success.stderr == ''
	assert os.ls(temporary)! == []string{}
	os.mkdir(work + '/commands')!
	false_command := os.find_abs_path_of_executable('false')!
	os.symlink(false_command, work + '/commands/clang')!
	environment['PATH'] = work + '/commands' + os.path_delimiter + environment['PATH']
	failed := hosttest.capture([tool], '', 60, environment)!
	assert failed.code == 1 && failed.stdout == '' && failed.stderr.contains('cc-runtime-aarch64/cc-runtime.a')
	assert os.ls(temporary)! == []string{}
}
