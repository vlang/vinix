// SPDX-License-Identifier: GPL-2.0-or-later
module jobcore

import devcore
import json2
import os
import sourcecommand
import time

fn test_attempt_arguments_reserve_fresh_outputs_and_survive_acknowledgement() {
	root := sourcecommand.temporary('vinix-jobs-attempts')!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/main.v', 'module main\nimport os\nfn main() { if os.getenv("TOKEN") != "private-token" || os.args[2] != "literal-" + os.base(os.args[1]).all_after("output-") { exit(1) }; if os.exists(os.args[1]) { exit(2) }; os.mkdir(os.args[1], mode: 0o700)!; os.write_file(os.args[1] + "/result", "42")! }\n')!
	compiled := sourcecommand.capture([@VEXE, '-gc', 'none', '-cc', 'cc', '-o', root + '/job', root + '/main.v'],
		os.environ(), 120, 65536, unsafe { nil })!
	assert compiled.status == 0, compiled.stderr
	os.write_file(root + '/credential', 'private-token')!
	os.chmod(root + '/credential', 0o600)!
	plan := Plan{uid: os.getuid(), jobs: [Job{id: 'ci', executable: devcore.Pin{root + '/job', devcore.file_hash(root + '/job')!},
		arguments: [root + '/output-{attempt}', 'literal-{attempt}'], directory: root, interval_seconds: 1,
		credential_files: {'TOKEN': root + '/credential'}}]}
	// Literal arguments retain their meaning until expansion is selected.
	initialise(json2.encode(plan), root + '/literal-state')!
	assert run_due(root + '/literal-state', time.now().unix())!.jobs['ci'].exit_code == 0
	assert os.read_file(root + '/output-{attempt}/result')! == '42'
	selected := Plan{...plan, jobs: [Job{...plan.jobs[0], expand_attempt: true}]}
	state_path := root + '/state'
	initialise(json2.encode(selected), state_path)!
	first := run_due(state_path, time.now().unix())!.jobs['ci']
	assert first.attempts == 1 && first.runs == 1 && first.exit_code == 0
	second := run_due(state_path, first.next_due)!.jobs['ci']
	assert second.attempts == 2 && second.runs == 2 && second.exit_code == 0
	assert os.read_file(root + '/output-1/result')! == '42'
	assert os.read_file(root + '/output-2/result')! == '42'
	// Simulate the durable reservation left by a killed owner after it wrote
	// output-3. Neither a normal tick nor acknowledgement may reuse it.
	mut abandoned := inspect(state_path)!
	mut running := abandoned.jobs['ci']
	running.attempts = 3
	running.in_flight = true
	running.next_due = 0
	abandoned.jobs['ci'] = running
	write_atomic(state_path + '/state.json', json2.encode(abandoned))!
	os.mkdir(root + '/output-3', mode: 0o700)!
	os.write_file(root + '/output-3/result', 'preserved')!
	assert run_due(state_path, time.now().unix())!.jobs['ci'].attempts == 3
	acknowledge(state_path, 'ci')!
	recovered := run_due(state_path, time.now().unix())!.jobs['ci']
	assert recovered.attempts == 4 && recovered.runs == 3 && recovered.exit_code == 0
	assert os.read_file(root + '/output-3/result')! == 'preserved'
	assert os.read_file(root + '/output-4/result')! == '42'
	assert !os.read_file(state_path + '/state.json')!.contains('private-token')
}

fn test_legacy_attempt_migration_and_counter_exhaustion_preserve_state() {
	root := sourcecommand.temporary('vinix-jobs-attempt-migration')!
	defer { os.rmdir_all(root) or {} }
	program := os.real_path(os.find_abs_path_of_executable('true')!)
	plan := Plan{uid: os.getuid(), jobs: [Job{id: 'ci', executable: devcore.Pin{program, devcore.file_hash(program)!},
		directory: root, interval_seconds: 1}]}
	path := root + '/state'
	initialise(json2.encode(plan), path)!
	mut legacy := inspect(path)!
	legacy.jobs['ci'] = JobState{runs: 7}
	write_atomic(path + '/state.json', json2.encode(legacy).replace(',"attempts":0', ''))!
	state := run_due(path, time.now().unix())!
	assert state.jobs['ci'].runs == 8 && state.jobs['ci'].attempts == 8
	mut exhausted := State{...state, jobs: state.jobs.clone()}
	mut job := exhausted.jobs['ci']
	job.attempts = u64(0xffffffffffffffff)
	job.next_due = 0
	exhausted.jobs['ci'] = job
	write_atomic(path + '/state.json', json2.encode(exhausted))!
	before := os.read_file(path + '/state.json')!
	if _ := run_due(path, time.now().unix()) { assert false, 'attempt counter wrapped' }
	assert os.read_file(path + '/state.json')! == before
}
