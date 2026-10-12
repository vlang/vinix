// SPDX-License-Identifier: GPL-2.0-or-later
module jobcore

import devcore
import json2
import os
import sourcecommand
import time

#include <signal.h>

fn C.kill(int, int) int

fn test_due_job_runs_with_owned_credentials_and_no_credential_receipt() {
	root := sourcecommand.temporary('vinix-jobs-test')!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/main.v', 'module main\nimport os\nfn main() { if os.getenv("TOKEN") != "private-token" { exit(1) }; os.write_file("job-output", "completed")!; println(os.getenv("TOKEN")) }\n')!
	compiled := sourcecommand.capture([@VEXE, '-gc', 'none', '-cc', 'cc', '-o', root + '/job',
		root + '/main.v'], os.environ(), 120, 65536, unsafe { nil })!
	assert compiled.status == 0, compiled.stderr
	os.write_file(root + '/credential', 'private-token')!
	os.chmod(root + '/credential', 0o600)!
	plan := Plan{
		uid:  os.getuid()
		jobs: [Job{
			id:               'build'
			executable:       devcore.Pin{root + '/job', devcore.file_hash(root + '/job')!}
			arguments:        []
			directory:        root
			interval_seconds: 3600
			credential_files: {
				'TOKEN': root + '/credential'
			}
		}]
	}
	state_path := root + '/state'
	initialise(json2.encode(plan), state_path)!
	first := run_due(state_path, time.now().unix())!
	assert first.jobs['build'].runs == 1 && first.jobs['build'].exit_code == 0
	assert !first.jobs['build'].in_flight
	assert os.read_file(root + '/job-output')! == 'completed'
	assert !os.read_file(state_path + '/state.json')!.contains('private-token')
	assert os.ls(state_path)!.sorted() == ['plan.json', 'run.lock', 'state.json']
	second := run_due(state_path, time.now().unix())!
	assert second.jobs['build'].runs == 1
	// A process killed after publication cannot cause an overlapping retry.
	mut abandoned := inspect(state_path)!
	mut job := abandoned.jobs['build']
	job.in_flight = true
	job.next_due = 0
	abandoned.jobs['build'] = job
	write_atomic(state_path + '/state.json', json2.encode(abandoned))!
	assert run_due(state_path, time.now().unix())!.jobs['build'].runs == 1
	acknowledge(state_path, 'build')!
	assert !inspect(state_path)!.jobs['build'].in_flight
}

fn test_credentials_reject_symlinks_public_modes_nuls_and_oversized_values() {
	root := sourcecommand.temporary('vinix-jobs-secrets')!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/secret', 'value')!
	os.chmod(root + '/secret', 0o600)!
	assert private_file(root + '/secret', 64)! == 'value'
	os.symlink(root + '/secret', root + '/link')!
	if _ := private_file(root + '/link', 64) {
		assert false, 'secret symlink accepted'
	} else {
		assert err.msg().contains('cannot open')
	}
	os.chmod(root + '/secret', 0o644)!
	if _ := private_file(root + '/secret', 64) {
		assert false, 'public secret accepted'
	} else {
		assert err.msg().contains('0600')
	}
	os.chmod(root + '/secret', 0o600)!
	os.write_file(root + '/secret', 'null\x00byte')!
	if _ := private_file(root + '/secret', 64) {
		assert false, 'NUL secret accepted'
	} else {
		assert err.msg().contains('invalid')
	}
	os.write_file(root + '/secret', 'x'.repeat(65))!
	private_file(root + '/secret', 64) or {
		assert err.msg().contains('oversized')
		return
	}
	assert false
}

fn test_changed_executable_is_rejected_and_accounted_without_running_it() {
	root := sourcecommand.temporary('vinix-jobs-pins')!
	defer { os.rmdir_all(root) or {} }
	program := os.real_path(os.find_abs_path_of_executable('echo')!)
	plan := Plan{ uid: os.getuid(), jobs: [Job{ id: 'bad', executable: devcore.Pin{program, '0'.repeat(64)}, directory: root, interval_seconds: 1 }] }
	initialise(json2.encode(plan), root + '/state') or {
		assert err.msg().contains('changed')
		return
	}
	assert false
}

fn test_job_deadline_retires_child_and_records_failure() {
	root := sourcecommand.temporary('vinix-jobs-timeout')!
	defer { os.rmdir_all(root) or {} }
	program := os.real_path(os.find_abs_path_of_executable('sleep')!)
	plan := Plan{
		uid:  os.getuid()
		jobs: [Job{
			id:               'slow'
			executable:       devcore.Pin{program, devcore.file_hash(program)!}
			arguments:        ['30']
			directory:        root
			interval_seconds: 60
			timeout_seconds:  1
		}]
	}
	initialise(json2.encode(plan), root + '/state')!
	state := run_due(root + '/state', time.now().unix())!
	assert state.jobs['slow'].exit_code == -1 && !state.jobs['slow'].in_flight
	assert state.jobs['slow'].detail.contains('deadline')
}

fn test_watch_reexec_keeps_one_owner_and_repeats_due_jobs() {
	root := sourcecommand.temporary('vinix-jobs-watch')!
	defer { os.rmdir_all(root) or {} }
	compiled := sourcecommand.capture([@VEXE, '-enable-globals', '-gc', 'none', '-cc', 'cc', '-o',
		root + '/vinix-jobs', os.dir(os.dir(@FILE)) + '/jobs.v'], os.environ(), 120, 65536, unsafe { nil })!
	assert compiled.status == 0, compiled.stderr
	program := os.real_path(os.find_abs_path_of_executable('true')!)
	plan := Plan{ uid: os.getuid(), jobs: [Job{ id: 'tick', executable: devcore.Pin{program, devcore.file_hash(program)!}, directory: root, interval_seconds: 1 }] }
	initialise(json2.encode(plan), root + '/state')!
	mut owner := os.new_process(root + '/vinix-jobs')
	owner.set_args(['watch', root + '/state'])
	owner.set_redirect_stdio()
	owner.run()
	mut reaped := false
	defer {
		if !reaped && owner.pid > 0 {
			C.kill(owner.pid, C.SIGTERM)
			owner.wait()
		}
		owner.close()
	}
	deadline := time.sys_mono_now() + u64(20 * time.second)
	for inspect(root + '/state')!.jobs['tick'].runs < 2 {
		assert time.sys_mono_now() < deadline, owner.stdout_read() + owner.stderr_read()
		time.sleep(20 * time.millisecond)
	}
	assert C.kill(owner.pid, 0) == 0
	assert C.kill(owner.pid, C.SIGTERM) == 0
	owner.wait()
	reaped = true
	assert owner.code == 0, owner.stdout_read() + owner.stderr_read()
}
