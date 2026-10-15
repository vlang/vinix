// SPDX-License-Identifier: GPL-2.0-or-later
module jobcore

import desktop.sessioncore
import devcore
import json2
import os
import sourcecommand
import time

fn service_cli(root string) !string {
	path := root + '/jobs "quoted" \\ literal'
	compiled := sourcecommand.capture([@VEXE, '-enable-globals', '-gc', 'none', '-cc', 'cc',
		'-o', root + '/compiled-jobs', os.dir(os.dir(@FILE)) + '/jobs.v'], os.environ(), 120, 65536, unsafe { nil })!
	if compiled.status != 0 { return error(compiled.stderr) }
	os.rename(root + '/compiled-jobs', path)!
	return path
}

fn service_plan(root string) !Plan {
	program := os.find_abs_path_of_executable('true')!
	return Plan{uid: os.getuid(), jobs: [Job{
		id: 'tick'
		executable: devcore.Pin{program, devcore.file_hash(program)!}
		directory: root
		interval_seconds: 1
		credential_files: {'TOKEN': root + '/private-credential'}
	}]}
}

fn test_exported_service_preserves_literal_argv_and_runs_under_the_native_supervisor() {
	root := os.real_path(sourcecommand.temporary('vinix-jobs-service')!)
	defer { os.rmdir_all(root) or {} }
	cli := service_cli(root)!
	state := root + '/schedule "quoted" \\ literal'
	plan := service_plan(root)!
	initialise(json2.encode(plan), state)!
	os.write_file(root + '/private-credential', 'service-private-token')!
	os.chmod(root + '/private-credential', 0o600)!
	before := os.read_file(state + '/state.json')!
	output := sourcecommand.capture([cli, 'service-unit', state], os.environ(), 5, 65536, unsafe { nil })!
	assert output.status == 0, output.stderr
	assert !output.stdout.contains('service-private-token')
	assert !output.stdout.contains('private-credential')
	assert os.read_file(state + '/state.json')! == before
	service := sessioncore.import_linux_service('scheduled-ci.service', output.stdout, false)!
	assert !service.enabled && !service.system
	assert service.executable.str() == cli
	assert service.argument_count == 2
	assert service.arguments[0].str() == 'watch'
	assert service.arguments[1].str() == state
	assert service.restart == .on_failure && service.stop_timeout_ms == 10000
	mut supervisor := sessioncore.Supervisor{count: 1}
	supervisor.services[0] = service
	supervisor.validate()!
	assert supervisor.tick(0).count == 0, 'export/import enabled execution without an explicit start'
	supervisor.enable(0, true)!
	commands := supervisor.tick(0)
	assert commands.count == 1 && commands.items[0].operation == .start
	mut owner := os.new_process(service.executable.str())
	owner.set_args([service.arguments[0].str(), service.arguments[1].str()])
	owner.set_redirect_stdio()
	owner.run()
	mut reaped := false
	defer {
		if !reaped && owner.pid > 0 { owner.signal_kill(); owner.wait() }
		owner.close()
	}
	supervisor.started(0, owner.pid, 0)
	deadline := time.sys_mono_now() + u64(10 * time.second)
	for inspect(state)!.jobs['tick'].runs < 2 {
		assert time.sys_mono_now() < deadline && owner.is_alive(), 'exported watcher did not complete two ticks'
		time.sleep(20 * time.millisecond)
	}
	supervisor.enable(0, false)!
	stop := supervisor.tick(1)
	assert stop.count == 1 && stop.items[0].operation == .terminate
	assert C.kill(owner.pid, C.SIGTERM) == 0
	end := time.sys_mono_now() + u64(service.stop_timeout_ms) * u64(time.millisecond)
	for owner.is_alive() {
		assert time.sys_mono_now() < end, 'service stop window expired'
		time.sleep(10 * time.millisecond)
	}
	owner.wait()
	reaped = true
	assert owner.code == 0, owner.stdout_read() + owner.stderr_read()
	supervisor.exited(0, owner.code, 2)
	assert supervisor.finished() && supervisor.services[0].state == .stopped
	assert !inspect(state)!.jobs['tick'].in_flight
}

fn test_service_export_refuses_expansion_and_control_paths_without_changing_the_schedule() {
	root := os.real_path(sourcecommand.temporary('vinix-jobs-service-refusal')!)
	defer { os.rmdir_all(root) or {} }
	cli := service_cli(root)!
	for name in ['dollar$path', 'percent%path', 'newline\npath'] {
		path := root + '/' + name
		initialise(json2.encode(service_plan(root)!), path)!
		before := os.read_file(path + '/state.json')!
		output := sourcecommand.capture([cli, 'service-unit', path], os.environ(), 5, 65536, unsafe { nil })!
		assert output.status != 0 && output.stdout == ''
		assert output.stderr.contains('service paths')
		assert os.read_file(path + '/state.json')! == before
	}
	parent := root + '/' + 'a'.repeat(220) + '/' + 'b'.repeat(220)
	os.mkdir_all(parent)!
	long := parent + '/' + 'c'.repeat(100)
	initialise(json2.encode(service_plan(root)!), long)!
	oversized := sourcecommand.capture([cli, 'service-unit', long], os.environ(), 5, 65536, unsafe { nil })!
	assert oversized.status != 0 && oversized.stdout == ''
	assert oversized.stderr.contains('argument too long')
	// Exports validate the account's pinned schedule before emitting a unit.
	bad := root + '/changed-plan'
	initialise(json2.encode(service_plan(root)!), bad)!
	os.write_file(bad + '/plan.json', os.read_file(bad + '/plan.json')! + ' ')!
	output := sourcecommand.capture([cli, 'service-unit', bad], os.environ(), 5, 65536, unsafe { nil })!
	assert output.status != 0 && output.stdout == '' && output.stderr.contains('plan changed')
}
