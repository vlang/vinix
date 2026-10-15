// SPDX-License-Identifier: GPL-2.0-or-later
module jobcore

import devcore
import json2
import os
import sourcecommand

fn C.mkfifo(&char, u32) i32

fn test_fifo_credentials_and_schedule_files_refuse_without_waiting_for_a_writer() {
	root := os.real_path(sourcecommand.temporary('vinix-jobs-fifo')!)
	defer { os.rmdir_all(root) or {} }
	compiled := sourcecommand.capture([@VEXE, '-enable-globals', '-gc', 'none', '-cc', 'cc',
		'-o', root + '/jobs', os.dir(os.dir(@FILE)) + '/jobs.v'],
		os.environ(), 120, 65536, unsafe { nil })!
	assert compiled.status == 0, compiled.stderr
	mkdir := os.find_abs_path_of_executable('mkdir')!
	for kind in ['credential', 'plan', 'state'] {
		case_root := root + '/' + kind
		os.mkdir(case_root)!
		credential := case_root + '/credential'
		os.write_file(credential, 'private-token')!
		os.chmod(credential, 0o600)!
		plan := Plan{uid: os.getuid(), jobs: [Job{
			id: 'fixture'
			executable: devcore.Pin{mkdir, devcore.file_hash(mkdir)!}
			arguments: [case_root + '/job-output']
			directory: case_root
			interval_seconds: 1
			timeout_seconds: 1
			credential_files: {'TOKEN': credential}
		}]}
		path := case_root + '/schedule'
		initialise(json2.encode(plan), path)!
		fifo := if kind == 'credential' { credential } else { path + '/' + kind + '.json' }
		os.rm(fifo)!
		assert C.mkfifo(fifo.str, 0o600) == 0
		before := os.lstat(fifo)!
		for action in if kind == 'credential' { ['run-due'] } else { ['status', 'run-due'] } {
			status := devcore.run([root + '/jobs', action, path], root, devcore.environment(0),
				2, case_root + '/' + action + '.log') or {
				assert false, '${kind} FIFO blocked the scheduler: ${err.msg()}'
				-1
			}
			assert status == 1
			assert !os.exists(case_root + '/job-output'), 'job executed with a non-regular credential'
			assert os.lstat(fifo)!.inode == before.inode, 'refusal replaced the FIFO'
			assert !os.read_file(case_root + '/' + action + '.log')!.contains('private-token')
			if kind != 'credential' {
				assert os.read_file(case_root + '/' + action + '.log')!.contains('must be regular')
			}
		}
		if kind == 'credential' {
			failed := inspect(path)!.jobs['fixture']
			assert failed.attempts == 1 && failed.runs == 1 && failed.exit_code == -1
			assert !failed.in_flight && failed.detail.contains('must be regular')
			assert !os.read_file(path + '/state.json')!.contains('private-token')
			// Rotation back to an ordinary private file permits a fresh attempt.
			os.rm(fifo)!
			os.write_file(credential, 'rotated-token')!
			os.chmod(credential, 0o600)!
			recovered := run_due(path, failed.next_due)!.jobs['fixture']
			assert recovered.attempts == 2 && recovered.runs == 2 && recovered.exit_code == 0
			assert os.is_dir(case_root + '/job-output')
		}
	}
}
