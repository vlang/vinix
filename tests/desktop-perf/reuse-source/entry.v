// SPDX-License-Identifier: GPL-2.0-or-later
// Appended to the exact qualified foreground-owner source by prepare-reuse-source.v.
// Its original public entry is removed. No historical executable is rewritten.

const reuse_host_root = '/Users/alex/Library/Caches/vinix-codex/section14/perf-runtime-host-20261105-01/reuse-adapter-host-01'

struct ReuseTool {
	state string
mut:
	pid int
}

fn reuse_tool_spawned(pid int, context voidptr) ! {
	mut tool := unsafe { &ReuseTool(context) }
	tool.pid = pid
	os.write_file(tool.state + '/child.json', json2.encode({'pid': pid.str(),
		'ownership': 'sourcecommand private group, WNOWAIT leader reservation and sole raw i32 reap'}) + '\n')!
}

fn reuse_tool_log(chunk string, context voidptr) ! {
	tool := unsafe { &ReuseTool(context) }
	mut file := os.open_append(tool.state + '/command.log')!
	defer { file.close() }
	file.write_string(chunk)!
}

fn reuse_tool(argv []string, state string, seconds int) ! {
	perfconsole.checkpoint()!
	fresh(state)!
	os.mkdir(state)!
	os.write_file(state + '/argv.json', json2.encode(argv) + '\n')!
	os.write_file(state + '/command.log', '')!
	mut tool := ReuseTool{state: state}
	mut failure := ''
	result := sourcecommand.capture_combined_owned(argv, os.environ(), f64(seconds), 65536,
		perfconsole.cancelled, reuse_tool_log, reuse_tool_spawned, &tool, 10, reuseprofile.runtime_root) or {
		failure = err.msg()
		sourcecommand.Output{}
	}
	mut cleanup := ''
	if tool.pid > 1 {
		group_absent(tool.pid) or { cleanup = err.msg() }
		if cleanup == '' { cleanup = no_children() or { err.msg() } }
	} else { cleanup = 'not spawned' }
	os.write_file(state + '/result.json', json2.encode({
		'failure': failure
		'actual_status': if failure == '' { result.status.str() } else { 'unavailable after refusal' }
		'cleanup': cleanup
	}) + '\n')!
	if failure != '' { return error(failure) }
	if cleanup != 'waitpid(-1,WNOHANG)=-1;errno=ECHILD' { return error('reuse helper cleanup differs: ' + cleanup) }
	if result.status != 0 { return error('reuse helper exited ' + result.status.str()) }
}

fn reuse_check_origin(c reuseprofile.Contract, state string, phase string) ! {
	mut manifests := map[string]string{}
	for kind in ['origin', 'base', 'staged', 'sysroot', 'gcc'] {
		manifest := state + '/' + phase + '-' + kind + '.tsv'
		argv := reuseprofile.literal_argv(c, kind, manifest)!
		reuse_tool(argv, state + '/' + phase + '-' + kind + '-tool', 90)!
		manifests[kind] = manifest
	}
	reuseprofile.verify_original(c, manifests)!
}

fn reuse_child(state string, expected_adapter string) ! {
	guard := perfconsole.own_commands()
	defer { guard.close() }
	if hash(os.executable())! != expected_adapter { return error('reviewed reuse adapter pin differs') }
	c := reuseprofile.load(state, os.executable(), true)!
	os.mkdir(state)!
	reuse_check_origin(c, state, 'before')!
	for name in ['base-before.tsv', 'staged-before.tsv', 'sysroot-before.tsv', 'gcc-before.tsv'] {
		os.cp(reuseprofile.origin_state + '/' + name, state + '/' + name, fail_if_exists: true)!
	}
	perfconsole.checkpoint()!
	disk := reuseprofile.disk_path(state)
	os.write_file(disk, '')!
	os.chmod(disk, 0o600)!
	os.truncate(disk, u64(256) << 20)!
	reuse_tool(reuseprofile.mkfs_argv(state), state + '/mkfs', 60)!
	reuseprofile.verify_new_disk(state)!
	reuse_check_origin(c, state, 'after')!
	perfconsole.checkpoint()!
	p := c.prepared(hash(disk)!)!
	c.validate_prepared(p)!
	os.write_file(state + '/prepared.json', json2.encode(p) + '\n')!
	perfconsole.checkpoint()!
	println('PERF REUSE PREPARED ' + hash(state + '/prepared.json')!)
}

fn reuse_reserve(reading BudgetReading, before_disk bool) ! {
	mut future_kib := 786432
	if before_disk { future_kib += 262144 + 8192 }
	// All retained attempts and actual host evidence are already in reading.
	// Leave the full runtime reserve unspent after the new blank disk and an
	// additional 8 MiB allowance for preparation maps/logs/receipts.
	usage_within(reading.allocated_kib, reading.apparent_kib, 4718592 - future_kib)!
}

fn reuse_prepare(owner_state string, state string, expected_adapter string) ! {
	phase_start := time.sys_mono_now()
	if hash(os.executable())! != expected_adapter { return error('reviewed reuse adapter pin differs') }
	if !inside(owner_state, reuseprofile.retry_root) || inside(owner_state, state) || inside(state, owner_state) {
		return error('fresh separate owner/prepared outputs inside fixed retry root required')
	}
	// budget_read also adds R3 when it already exists, so every failed attempt
	// stays charged even at this first admission before possible mkdir.
	pre := Profile{charged_roots: reuseprofile.charged_roots()[..4], charged_limit_kib: 4718592}
	initial := budget_read(pre, reuseprofile.retry_root)!
	budget_admit(initial, pre, true)!
	reuse_reserve(initial, true)!
	if !os.exists(reuseprofile.retry_root) && !os.is_link(reuseprofile.retry_root) {
		os.mkdir(reuseprofile.retry_root)!
	}
	c := reuseprofile.load(state, os.executable(), true)!
	fresh(owner_state)!
	profile := Profile{adapter: os.executable(), prepared_state: state,
		directory: reuseprofile.runtime_root, timeout_seconds: 300, log_limit_bytes: 4194304,
		charged_limit_kib: 4718592, charged_roots: reuseprofile.charged_roots(),
		input_roots: [@FILE, os.executable(), reuseprofile.origin_manifest, reuseprofile.origin_state + '/prepared.json']}
	reading := budget_read(profile, owner_state)!
	budget_admit(reading, profile, true)!
	reuse_reserve(reading, true)!
	admission := reading.raw
	os.mkdir(owner_state)!
	os.write_file(owner_state + '/budget-before.log', admission)!
	os.write_file(owner_state + '/profile.json', json2.encode(profile) + '\n')!
	os.write_file(owner_state + '/contract.json', json2.encode(c) + '\n')!
	status := supervise(profile, owner_state, [os.executable(), '--prepare-child', state, expected_adapter])!
	if status != 0 { return error('reuse preparation child exited ' + status.str()) }
	terminal := json2.decode[map[string]string](os.read_file(owner_state + '/supervisor.json')!, strict: true)!
	if terminal['owner_status'] != '0' || terminal['failure'] != ''
		|| terminal['cleanup'] != 'waitpid(-1,WNOHANG)=-1;errno=ECHILD' {
		return error('reuse preparation owner receipt differs')
	}
	previous := u64(number(terminal['last_sample_start_ns'])!)
	p := json2.decode[reuseprofile.Prepared](os.read_file(state + '/prepared.json')!, strict: true)!
	c.validate_document(p)!
	prepared_sha := hash(state + '/prepared.json')!
	if os.read_file(owner_state + '/command.log')!.trim_space() != 'PERF REUSE PREPARED ' + prepared_sha {
		return error('reuse preparation exact child marker differs')
	}
	start := time.sys_mono_now()
	final_reading := budget_read(profile, owner_state)!
	budget_admit(final_reading, profile, false)!
	reuse_reserve(final_reading, false)!
	os.write_file(owner_state + '/budget-after-output-checks.log', final_reading.raw)!
	finish := time.sys_mono_now()
	observation_timing(previous, start, finish)!
	if finish < phase_start || finish - phase_start >= 300 * u64(time.second) {
		return error('reuse preparation entry-through-output deadline exceeded')
	}
	os.write_file(owner_state + '/preparation.json', json2.encode({
		'verdict': 'PASS fixed immutable-media reuse preparation'
		'prepared_sha256': prepared_sha
		'adapter_sha256': expected_adapter
		'origin_manifest_sha256': reuseprofile.origin_manifest_sha
		'output_sample_start_ns': start.str()
		'output_sample_finish_ns': finish.str()
		'previous_sample_start_ns': previous.str()
		'scope': 'Fresh blank ext2 and new result scope; original R2 untouched. No guest execution or old interrupted-status recovery.'
	}) + '\n')!
	if time.sys_mono_now() < start || time.sys_mono_now() - start > observation_bound
		|| time.sys_mono_now() - phase_start >= 300 * u64(time.second) {
		os.write_file(owner_state + '/preparation.json', json2.encode({'verdict': 'REFUSED',
			'reason': 'final reuse preparation receipt/deadline guard exceeded'}) + '\n')!
		return error('final reuse preparation receipt/deadline guard exceeded')
	}
	println('PERF REUSE PREPARATION PASS ' + prepared_sha)
}

fn reuse_fresh_results(state string, socket string) ! {
	if os.exists(state + '/results') || os.is_link(state + '/results') || os.exists(socket) || os.is_link(socket) {
		return error('fresh results and new absent QMP socket required')
	}
}

fn reuse_run(state string, expected string) !int {
	if hash(state + '/prepared.json')! != expected { return error('prepared reuse receipt differs') }
	c := reuseprofile.load(state, os.executable(), false)!
	p := json2.decode[reuseprofile.Prepared](os.read_file(state + '/prepared.json')!, strict: true)!
	c.validate_prepared(p)!
	reuse_fresh_results(state, p.socket)!
	guard := perfconsole.own_commands()
	defer { guard.close() }
	os.mkdir(state + '/runtime-inputs')!
	reuse_check_origin(c, state + '/runtime-inputs', 'before')!
	plan := perfrunner.parse(p.arguments, p.root, p.root + '/tests/desktop-perf', '')!
	os.mkdir(state + '/results')!
	mut run_failure := ''
	status := perfrunner.drive(plan, perfrunner.Launch{p.command, os.environ(), p.socket}, state + '/results', 10, true) or {
		run_failure = err.msg()
		-1
	}
	// Keep the distinct /tmp socket as a diagnostic. Never unlink a socket whose
	// ownership could have changed after the original absence check.
	mut after_failure := ''
	if perfconsole.cancelled() {
		after_failure = 'cancelled; no fresh post-run helper launched'
	} else {
		reuse_check_origin(c, state + '/runtime-inputs', 'after') or { after_failure = err.msg() }
		if after_failure == '' { c.verify_after(p) or { after_failure = err.msg() } }
	}
	if after_failure == '' {
		mut after := p.inputs.clone()
		current := hash(reuseprofile.disk_path(state)) or { after_failure = err.msg(); '' }
		if after_failure == '' {
			after[reuseprofile.disk_path(state)] = current
			os.write_file(state + '/after-inputs.json', json2.encode(after) + '\n')!
		}
	}
	if after_failure != '' { os.write_file(state + '/after-inputs-error.txt', after_failure + '\n')! }
	os.write_file(state + '/results/run-outcome.json', json2.encode({
		'actual_scenario_status': if run_failure == '' { status.str() } else { 'unavailable after drive failure' }
		'drive_failure': run_failure
		'post_input_failure': after_failure
	}) + '\n')!
	if run_failure != '' || after_failure != '' {
		return error('reuse runtime refused: ' + run_failure + ';post-inputs=' + after_failure)
	}
	os.write_file(state + '/results/status', status.str() + '\n')!
	return status
}

fn reuse_helper_control(kind string, state string) !string {
	guard := perfconsole.own_commands()
	defer { guard.close() }
	mut failure := ''
	reuse_tool([os.executable(), '--fixture', kind], state, 2) or { failure = err.msg() }
	expected := match kind {
		'timeout', 'descendant' { 'command timed out' }
		'output' { 'command output exceeds limit' }
		'signal' { 'command interrupted' }
		'nonzero' { 'reuse helper exited 23' }
		else { '' }
	}
	if failure != expected { return error('reuse helper fixture outcome differs: ' + kind + ':' + failure) }
	receipt := json2.decode[map[string]string](os.read_file(state + '/result.json')!, strict: true)!
	if receipt['cleanup'] != 'waitpid(-1,WNOHANG)=-1;errno=ECHILD' {
		return error('reuse helper fixture cleanup differs')
	}
	if os.file_size(state + '/command.log') > 65536 { return error('reuse helper fixture log limit differs') }
	return 'refusal=' + failure + ';cleanup=' + receipt['cleanup']
}

fn reuse_literal_fixture(root string, kind string) ! {
	os.mkdir(root)!
	os.write_file(root + '/always.txt', 'unchanged independent fixture\n')!
	os.chmod(root + '/always.txt', 0o644)!
	if kind != 'missing' {
		content := if kind == 'content' { 'altered input\n' } else { 'original input\n' }
		mode := if kind == 'mode' { 0o600 } else { 0o644 }
		os.write_file(root + '/input.txt', content)!
		os.chmod(root + '/input.txt', mode)!
	}
	target := if kind == 'link' { '/guest/altered' } else { '/guest/original' }
	os.symlink(target, root + '/absolute-guest-link')!
	if kind == 'added' { os.write_file(root + '/unexpected.txt', 'extra input\n')! }
}

fn reuse_literal_controls(state string) ![]string {
	if reuseprofile.hash(reuseprofile.literal_tool)! != reuseprofile.literal_tool_sha {
		return error('host controls literal tool pin differs')
	}
	os.mkdir(state)!
	mut baseline := ''
	mut outcomes := []string{}
	for kind in ['baseline', 'identical', 'added', 'missing', 'content', 'mode', 'link'] {
		root := state + '/input-' + kind
		reuse_literal_fixture(root, kind)!
		manifest := state + '/' + kind + '.tsv'
		reuse_tool([reuseprofile.literal_tool, 'create', root, manifest], state + '/tool-' + kind, 10)!
		if kind == 'baseline' { baseline = reuseprofile.hash(manifest)! }
		mut refusal := ''
		reuseprofile.verify_manifest_digest(manifest, baseline) or { refusal = err.msg() }
		if (kind in ['baseline', 'identical']) != (refusal == '') {
			return error('real complete literal mutation outcome differs: ' + kind + ':' + refusal)
		}
		result := if refusal == '' { 'accepted exact complete map' } else { refusal }
		outcomes << kind + ': ' + result
	}
	return outcomes
}

fn reuse_output_controls(state string) ![]string {
	os.mkdir(state)!
	mut outcomes := []string{}
	for kind in ['fresh', 'results', 'results-link', 'socket-name', 'socket-link'] {
		root := state + '/' + kind
		os.mkdir(root)!
		socket := root + '/new.qmp'
		if kind == 'results' { os.mkdir(root + '/results')! }
		if kind == 'results-link' { os.symlink('/absent-owned-fixture-result', root + '/results')! }
		if kind == 'socket-name' { os.write_file(socket, 'existing QMP-name sentinel\n')! }
		if kind == 'socket-link' { os.symlink('/absent-owned-fixture-socket', socket)! }
		mut failure := ''
		reuse_fresh_results(root, socket) or { failure = err.msg() }
		if (kind == 'fresh') != (failure == '') { return error('fresh output control differs: ' + kind) }
		outcomes << kind + ':' + failure
	}
	return outcomes
}

fn reuse_reserve_controls() ![]string {
	mut outcomes := []string{}
	for before_disk in [true, false] {
		future := if before_disk { 786432 + 262144 + 8192 } else { 786432 }
		limit := i64(4718592 - future)
		reuse_reserve(BudgetReading{allocated_kib: limit, apparent_kib: limit}, before_disk)!
		for allocated in [true, false] {
			reading := if allocated {
				BudgetReading{allocated_kib: limit + 1, apparent_kib: limit}
			} else {
				BudgetReading{allocated_kib: limit, apparent_kib: limit + 1}
			}
			mut refused := false
			reuse_reserve(reading, before_disk) or { refused = true }
			if !refused { return error('reuse full-reserve boundary accepted one KiB excess') }
		}
		outcomes << 'before_disk=' + before_disk.str() + ': exact limit accepted; allocated/apparent limit+1 refused'
	}
	return outcomes
}

fn reuse_selfcheck(state string) ! {
	if state == reuse_host_root || !inside(state, reuse_host_root) {
		return error('reuse controls require a fresh state inside the fixed cumulative host stage')
	}
	fresh(state)!
	os.mkdir(state)!
	checks := reuseprofile.selfcheck(state + '/contract')!
	mut outcomes := map[string]string{}
	profile := Profile{directory: reuseprofile.runtime_root, timeout_seconds: 2,
		log_limit_bytes: 65536, charged_roots: [os.real_path(os.dir(state))]}
	for kind in ['ok', 'nonzero', 'timeout', 'output', 'signal', 'descendant'] {
		work := state + '/owner-' + kind
		os.mkdir(work)!
		mut failure := ''
		status := supervise(profile, work, [os.executable(), '--fixture', kind]) or { failure = err.msg(); -1 }
		expected := match kind { 'timeout', 'descendant' { 'command timed out' } 'output' { 'command output exceeds limit' } 'signal' { 'command interrupted' } else { '' } }
		if failure != expected || (failure == '' && status != if kind == 'nonzero' { 23 } else { 0 }) {
			return error('reuse owner fixture outcome differs: ' + kind + ':' + failure)
		}
		outcomes[kind] = 'status=' + status.str() + ';refusal=' + failure
	}
	for kind in ['ok', 'nonzero', 'timeout', 'output', 'signal', 'descendant'] {
		outcomes['helper-' + kind] = reuse_helper_control(kind, state + '/helper-' + kind)!
	}
	guard := perfconsole.own_commands()
	defer { guard.close() }
	outcomes['complete_literal_mutations'] = json2.encode(reuse_literal_controls(state + '/literal')!)
	outcomes['fresh_results_and_qmp_names'] = json2.encode(reuse_output_controls(state + '/outputs')!)
	outcomes['inclusive_reserve_boundaries'] = json2.encode(reuse_reserve_controls()!)
	os.mkdir(state + '/ext2')!
	os.write_file(state + '/ext2/root.ext2', '')!
	os.truncate(state + '/ext2/root.ext2', u64(4) << 20)!
	reuse_tool(reuseprofile.mkfs_argv(state + '/ext2'), state + '/ext2-tool', 30)!
	reuseprofile.verify_new_disk(state + '/ext2') or {
		if err.msg() != 'fresh workload disk size differs' { return error('small real ext2 fixture missed the production size guard: ' + err.msg()) }
		outcomes['small_real_ext2'] = 'mkfs succeeded; production disk size refused: ' + err.msg()
	}
	if 'small_real_ext2' !in outcomes { return error('4 MiB host fixture was accepted as production disk') }
	os.write_file(state + '/controls.json', json2.encode({'contract': json2.encode(checks), 'owners': json2.encode(outcomes),
		'scope': 'Host controls only; original qualification functions reused verbatim; no adapter guest launch.'}) + '\n')!
	println('PERF REUSE HOST CONTROLS PASS')
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--fixture' { fixture(os.args[2]); return }
	if os.args.len == 4 && os.args[1] == '--prepare-child' {
		reuse_child(os.args[2], os.args[3]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 5 && os.args[1] == 'prepare' {
		reuse_prepare(os.args[2], os.args[3], os.args[4]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 4 && os.args[1] == 'run' {
		status := reuse_run(os.args[2], os.args[3]) or { eprintln(err); exit(1) }
		exit(status)
	}
	if os.args.len == 3 && os.args[1] == 'selfcheck-reuse' {
		reuse_selfcheck(os.args[2]) or { eprintln(err); exit(1) }
		return
	}
	eprintln('usage: reuse-x86 prepare NEW_OWNER_STATE NEW_PREPARED_STATE REVIEWED_SELF_SHA256 | run PREPARED_STATE PREPARED_SHA256 | selfcheck-reuse NEW_HOST_STATE')
	exit(2)
}
