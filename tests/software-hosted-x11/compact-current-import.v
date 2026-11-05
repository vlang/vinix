// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed staging profile using the already qualified inherited-group owner.
module main

import compactproof
import crypto.sha256
import json2
import launchproof
import nativeguard
import os
import proof
import time

#include <errno.h>

const state = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02'
const source_root = state + '/source'
const suite = source_root + '/tests/software-hosted-x11'
const staging = state + '/compact-import-01'
const observer = state + '/compact-import-observer-01'
const bootstrap = state + '/compact-import-bootstrap-01'
const current_audit = state + '/compact-current-audit-01'
const current_observer = state + '/compact-current-audit-observer-01'
const old_tools = state + '/native-supervision-host-01'
const consumer_tools = state + '/native-consumer-tools-01'
const projection = state + '/compact-stage-projection-02.json'
const frozen_record = state + '/compact-frozen-tools-01.json'
const frozen_verifier = bootstrap + '/compact-projection-02'
const cap = u64(256) << 20
const reserve = u64(2) << 20
const frontend = consumer_tools + '/current-supervision-front-01/bind-current-options'
const frontend_source = consumer_tools + '/current-supervision-front-01/bind-current-options.v'
const frontend_sha = 'REPLACE_WITH_FRONT_EXECUTABLE_SHA256'
const frontend_source_sha = 'REPLACE_WITH_FRONT_SOURCE_SHA256'
const bootstrap_inventory = consumer_tools + '/current-bootstrap-freeze-01/inventory.json'
const consumer_freeze = state + '/compact-consumer-freeze-01'
const consumer_inventory = consumer_freeze + '/inventory.json'

__global audit_directory string

fn need(ok bool, message string) ! { if !ok { return error(message) } }

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn module_files() !map[string]string {
	mut pins := map[string]string{}
	for name in ['proof', 'launchproof', 'optionsfixture', 'compactproof', 'compactui'] {
		for path in os.walk_ext(suite + '/' + name, '.v') {
			need(pins.len < 64 && os.lstat(path)!.mode & 0o170000 == 0o100000
				&& os.file_size(path) < 1024 * 1024, 'staging source inventory bound')!
			pins[path] = digest(path)!
		}
	}
	return pins
}

fn modules() !map[string]string {
	mut pins := module_files()!
	need(frontend_sha.len == 64 && frontend_source_sha.len == 64
		&& digest(frontend)! == frontend_sha && digest(frontend_source)! == frontend_source_sha,
		'bound current-supervision front differs')!
	for path in [suite + '/nativeguard/guard.v', suite + '/diagnostics/recoveryguard/recoveryguard.v', @FILE, os.executable(),
		projection, frozen_record, frozen_verifier, bootstrap + '/projection-source-02/compact-projection.v',
		frontend, frontend_source, bootstrap_inventory, consumer_inventory,
		consumer_freeze + '/inventory.sha256', '/bin/df'] {
		pins[path] = digest(path)!
	}
	return pins
}

fn frozen_pins() ! {
	need(digest('/bin/df')! == '84b985a1e447eb674bd1e8b2209dac5ca2a6803cad6cd0a9543bbd9e6b4e28bd',
		'reviewed fixed df executable changed')!
	need(digest(projection)! == '67ae49eeb2f43ffdc16cbd093a43c3dd93e7a8c4933854913c0e7464ececb1e6'
		&& digest(frozen_record)! == '14a1d04a2288ff548171b8428cabe92582a8ceefc7ea648e25f07f5ef00da579'
		&& digest(frozen_verifier)! == 'd5b6902bd3b96051c15b805fbaf10d0c855ea9323e3b16a8fff26fd17d802b78'
		&& digest(bootstrap + '/projection-source-02/compact-projection.v')! == '372bc38b3fd3dd52995bf0434840eed16d7e02341570f10ffa504ed3e607c857',
		'complete rounded projection or frozen verifier pin differs')!
	need(nativeguard.allocated([old_tools], os.lstat(state)!.dev)! <= u64(31) << 20
		&& nativeguard.allocated([consumer_tools], os.lstat(state)!.dev)! <= u64(48) << 20
		&& nativeguard.allocated([bootstrap], os.lstat(state)!.dev)! <= u64(14) << 20
		&& nativeguard.allocated([bootstrap, consumer_tools, consumer_freeze], os.lstat(state)!.dev)! <= u64(58) << 20,
		'fixed aggregate component bound refused')!
}

fn frozen_check(label string) ! {
	frozen_pins()!
	checked := original_check([frozen_verifier, '--verify-frozen'], label)!
	need(checked.actual_exit == 0, 'complete frozen old tool root changed')!
	frozen_pins()!
}

fn compiled_modules(phase string) ! {
	before_text := os.read_file(bootstrap + '/current-import-source-01/modules-before.json')!
	need(sha256.hexhash(before_text) == '710351295e1be60a49b75f84348493ee85cf1f0777991a8b457ac3f4b83201d4',
		'qualified before-bootstrap importedmodule map differs')!
	before := json2.decode[map[string]string](before_text, strict: true)!
	after := module_files()!
	need(before == after, 'importedmodule files changed across bootstrap')!
	compiled := {
		suite + '/compactproof/admit.v': sha256.hexhash(compactproof.source())
		suite + '/compactproof/current.v': sha256.hexhash(compactproof.source_current())
		suite + '/launchproof/admit.v': sha256.hexhash(launchproof.source())
		suite + '/proof/admit.v': sha256.hexhash(proof.source())
		suite + '/nativeguard/guard.v': sha256.hexhash($embed_file('/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/source/tests/software-hosted-x11/nativeguard/guard.v').to_string())
		suite + '/diagnostics/recoveryguard/recoveryguard.v': sha256.hexhash($embed_file('/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/source/tests/software-hosted-x11/diagnostics/recoveryguard/recoveryguard.v').to_string())
	}
	for path, expected in compiled { need(digest(path)! == expected, 'compiled module differs from captured source: ' + path)! }
	os.write_file(observer + '/' + phase + '-modules-after.json', json2.encode(after))!
	os.write_file(observer + '/' + phase + '-compiled-modules.json', json2.encode(compiled))!
}

fn frozen_pair_check(bootstrap_sha string, consumer_sha string, label string) ! {
	for wanted in [bootstrap_sha, consumer_sha] {
		need(wanted.len == 64 && wanted.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)),
			'fixed frozen-pair hash format differs')!
	}
	need(digest(bootstrap_inventory)! == bootstrap_sha && digest(consumer_inventory)! == consumer_sha
		&& digest(frontend)! == frontend_sha
		&& digest(frontend_source)! == frontend_source_sha, 'fixed bootstrap verifier identity differs')!
	checked := original_check([frontend, '--verify-consumer', consumer_sha, bootstrap_sha], label)!
	need(checked.actual_exit == 0 && os.read_file(checked.log_path)! == 'PASS frozen consumer ' + consumer_sha + '\n',
		'complete frozen consumer/bootstrap comparison failed')!
}

fn original_check(argv []string, label string) !compactproof.CheckRun {
	base := audit_directory + '/' + label
	os.write_file(base + '.argv.json', json2.encode(argv))!
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	os.write_file(base + '.log', text)!
	os.write_file(base + '.exit.json', json2.encode({'exit_code': child.code}))!
	return compactproof.CheckRun{child.code, base + '.argv.json', base + '.log', base + '.exit.json'}
}

fn import_child(bootstrap_sha string, consumer_sha string) ! {
	need(os.args == [os.executable(), '--import-child', bootstrap_sha, consumer_sha] && !os.exists(staging), 'requires fresh fixed staging child')!
	need(bootstrap_sha.len == 64 && bootstrap_sha.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		&& digest(bootstrap_inventory)! == bootstrap_sha, 'import child bootstrap identity differs')!
	before := modules()!
	os.mkdir(staging, mode: 0o700)!
	os.write_file(staging + '/modules-before.json', json2.encode(before))!
	audit_directory = staging
	frozen_pair_check(bootstrap_sha, consumer_sha, 'frozen-pair-before')!
	frozen_check('frozen-tools-before')!
	audit_directory = staging + '/audits-before'
	os.mkdir(audit_directory, mode: 0o700)!
	first := compactproof.check_current_audits(original_check)!
	first.write_record(staging + '/audits-before.json')!
	for arch in ['aarch64', 'x86_64'] {
		compactproof.current_import_build(arch, state + '/import-' + arch, first)!
		compactproof.current_assembled(state + '/import-' + arch,
			'/Users/alex/Library/Caches/vinix-codex/section14/package-hosted-launch-options-native-20261026/restored-stage-' + arch,
			arch, '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v', first)!
	}
	audit_directory = staging + '/audits-after'
	os.mkdir(audit_directory, mode: 0o700)!
	last := compactproof.check_current_audits(original_check)!
	last.write_record(staging + '/audits-after.json')!
	for arch in ['aarch64', 'x86_64'] {
		compactproof.current_assembled(state + '/import-' + arch,
			'/Users/alex/Library/Caches/vinix-codex/section14/package-hosted-launch-options-native-20261026/restored-stage-' + arch,
			arch, '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v', last)!
	}
	audit_directory = staging
	frozen_check('frozen-tools-after')!
	frozen_pair_check(bootstrap_sha, consumer_sha, 'frozen-pair-after')!
	after := modules()!
	os.write_file(staging + '/modules-after.json', json2.encode(after))!
	need(before == after, 'staging modules changed')!
	mut outputs := map[string]string{}
	for arch in ['aarch64', 'x86_64'] {
		for name in ['vinix-desktop', 'desktop-build.json', 'import.json'] {
			outputs[arch + '/' + name] = digest(state + '/import-' + arch + '/' + name)!
		}
	}
	os.write_file(staging + '/result.json', json2.encode({'outcome': 'PASS',
		'outputs': json2.encode(outputs), 'scope': 'Exact complete original pre/post audits, compact compositor imports and separate historical hosted/stage admission; no guest.'}) + '\n')!
	println('COMPACT IMPORT complete original audits and both current compositor imports PASS')
}

// nativeguard records each mark after the df probe and allocation scan. Its
// probe start lies between the previous mark and its own mark. Using two-mark
// brackets conservatively bounds actual start-to-start gaps; one-mark brackets
// bound probe/scan windows. No exact start timestamps are invented.
fn cadence(result nativeguard.Result, call_started i64) !map[string]string {
	need(result.samples.len >= 2, 'positive import requires initial and final samples')!
	mut max_start_gap := i64(0)
	mut max_window := i64(0)
	mut max_mark_gap := i64(0)
	for index, sample in result.samples {
		need(sample.df.cleanup.exit_code == 0 && sample.df.cleanup.reaped && sample.df.cleanup.group_empty
			&& sample.df.cleanup.final_wait == -1 && sample.df.cleanup.final_errno == C.ECHILD,
			'import sample df cleanup differs')!
		if index == 0 {
			window := sample.mono_ns - call_started
			need(window >= 0 && window <= 5 * time.second, 'initial sample window exceeds5s')!
			max_window = window
			continue
		}
		gap := sample.mono_ns - result.samples[index - 1].mono_ns
		window := gap
		start_bound := if index == 1 { sample.mono_ns - call_started }
			else { sample.mono_ns - result.samples[index - 2].mono_ns }
		need(gap >= 0 && gap <= 5 * time.second && window >= 0 && window <= 5 * time.second
			&& start_bound >= 0 && start_bound <= 5 * time.second, 'sample start gap or window exceeds5s')!
		if gap > max_mark_gap { max_mark_gap = gap }
		if window > max_window { max_window = window }
		if start_bound > max_start_gap { max_start_gap = start_bound }
	}
	return {'max_start_gap_upper_bound_ns': max_start_gap.str(), 'max_window_upper_bound_ns': max_window.str(),
		'max_recorded_mark_gap_ns': max_mark_gap.str(), 'scope': 'Source-derived conservative bounds from actual monotonic marks; no exact probe-start timestamps are claimed.'}
}

fn observer_paths() []string {
	mut paths := [current_audit, current_observer, staging, observer,
		state + '/compact-current-import-bootstrap-observer-01', projection, frozen_record,
		state + '/compact-stage-projection-01.json']
	for role in ['current-audit', 'import'] {
		for suffix in ['', '.barrier.json', '.cleanup.json', '.barrier-cleanup.json'] {
			paths << state + '/compact-' + role + '-admission-df' + suffix
		}
	}
	for arch in ['aarch64', 'x86_64'] {
		for leaf in ['desktop-build.json', 'import.json'] { paths << state + '/import-' + arch + '/' + leaf }
	}
	return paths
}

fn run() ! {
	started := time.sys_mono_now()
	$if prod {} $else { return error('requires production source binding') }
	need(os.args.len == 4 && os.args[0] == os.executable() && os.args[1] == '--prepare',
		'requires fixed --prepare and literal frozen-bootstrap/consumer SHA256 values')!
	bootstrap_sha := os.args[2]
	consumer_sha := os.args[3]
	for wanted in [bootstrap_sha, consumer_sha] {
		need(wanted.len == 64 && wanted.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)),
			'frozen-pair hash format differs')!
	}
	need(digest(bootstrap_inventory)! == bootstrap_sha && digest(consumer_inventory)! == consumer_sha,
		'frozen-pair inventories differ from literal arguments')!
	phase := 'import'
	phase_observer := observer
	phase_ms := 240000
	admission_path := state + '/compact-' + phase + '-admission-df'
	need(digest(@FILE)! == sha256.hexhash($embed_file('compact-current-import.v').to_string()), 'staging profile source changed')!
	mut fresh := [staging, observer, state + '/import-aarch64', state + '/import-x86_64']
	for path in fresh {
		need(!os.exists(path) && !os.is_link(path), 'requires fresh staging outputs: ' + path)!
	}
	for suffix in ['', '.barrier.json', '.cleanup.json', '.barrier-cleanup.json'] {
		path := admission_path + suffix
		need(!os.exists(path) && !os.is_link(path), 'requires fresh admission receipt: ' + path)!
	}
	for name in ['modules-after.json', 'compiled-modules.json'] {
		path := observer + '/' + phase + '-' + name
		need(!os.exists(path) && !os.is_link(path), 'requires fresh bootstrap comparison receipt')!
	}
	frozen_pins()!
	nativeguard.watch_interrupts()!
	admission := nativeguard.actual_df(state, admission_path)!
	need(admission.available >= u64(2) << 30, 'staging admission requires2GiB free')!
	os.mkdir(phase_observer, mode: 0o700)!
	os.mkdir(phase_observer + '/tmp', mode: 0o700)!
	for name in ['cache', 'modules'] { os.mkdir(phase_observer + '/' + name, mode: 0o700)! }
	os.write_file(phase_observer + '/admission.json', json2.encode(admission))!
	compiled_modules(phase)!
	for name, _ in os.environ() { os.unsetenv(name) }
	for name, value in {'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex', 'LANG': 'en_US.UTF-8',
		'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'TMPDIR': phase_observer + '/tmp', 'VTMP': phase_observer + '/tmp',
		'V3CACHE': phase_observer + '/cache', 'XDG_CACHE_HOME': phase_observer + '/cache',
		'VMODULES': phase_observer + '/modules'} {
		os.setenv(name, value, true)
	}
	before := modules()!
	os.write_file(phase_observer + '/modules-before.json', json2.encode(before))!
	mut charged := [staging, observer, current_audit, current_observer,
		state + '/import-aarch64', state + '/import-x86_64', bootstrap,
		old_tools, consumer_tools, consumer_freeze, projection, frozen_record, state + '/compact-stage-projection-01.json',
		state + '/compact-current-import-bootstrap-observer-01',
		state + '/compact-wrapper-binding-01', state + '/compact-supervisor-binding-01',
		suite + '/compactproof/current.v', suite + '/compactproof/current_controls.v',
		suite + '/compactproof/currentcheck', suite + '/compactproof-check.v', suite + '/check.v',
		suite + '/retain.v', suite + '/evidence-check.v', suite + '/supervise.v']
	for role in ['import', 'current-audit'] {
		for suffix in ['', '.barrier.json', '.cleanup.json', '.barrier-cleanup.json'] {
			charged << state + '/compact-' + role + '-admission-df' + suffix
		}
	}
	argv := [os.executable(), '--import-child', bootstrap_sha, consumer_sha]
	os.write_file(phase_observer + '/argv.json', json2.encode(argv))!
	os.write_file(phase_observer + '/environment.json', json2.encode(os.environ()))!
	remaining := phase_ms - int((time.sys_mono_now() - started) / time.millisecond)
	need(remaining > 0, 'import phase expired during admission')!
	sampling_started := time.sys_mono_now()
	need(sampling_started - started <= 5 * time.second, 'import preflight window exceeds5s')!
	result := nativeguard.supervise(argv, source_root, state, charged, phase_observer + '/output.log', phase_observer + '/df',
		nativeguard.Limits{start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30,
			cap_bytes: cap - reserve, wall_ms: remaining, sample_ms: 2000})!
	result_text := json2.encode(result)
	if result_text.len > 131072 {
		os.write_file(phase_observer + '/result-refused.json', json2.encode({'bytes': result_text.len.str(),
			'sha256': sha256.hexhash(result_text), 'reason': 'result exceeds reviewed128KiB allowance; raw df and cleanup files retained'}))!
		return error('import result exceeds reviewed128KiB observer allowance')
	}
	os.write_file(phase_observer + '/result.json', result_text)!
	after := modules()!
	os.write_file(phase_observer + '/modules-after.json', json2.encode(after))!
	need(result.reason == '' && result.group_observed && result.cleanup.reaped
		&& result.cleanup.group_empty && result.cleanup.exit_code == 0
		&& result.cleanup.final_wait == -1 && result.cleanup.final_errno == C.ECHILD
		&& before == after, 'staging child, source or cleanup refused')!
	os.write_file(phase_observer + '/cadence.json', json2.encode(cadence(result, sampling_started)!))!
	final_df := nativeguard.actual_df(state, phase_observer + '/final-df')!
	allocated := nativeguard.allocated(charged, os.lstat(state)!.dev)!
	need(final_df.available >= u64(1) << 30 && allocated <= cap - 65536
		&& nativeguard.allocated(observer_paths(), os.lstat(state)!.dev)! <= u64(8) << 20
		&& time.sys_mono_now() - started < i64(phase_ms) * time.millisecond, 'staging final resource checks refused')!
	os.write_file(phase_observer + '/qualification.json', json2.encode({'outcome': 'PASS',
		'allocated_bytes': allocated.str(), 'available_bytes': final_df.available.str(),
		'phase': phase, 'wall_ms': phase_ms.str(),
		'scope': 'Same inherited-group owner; unchanged256MiB total/254MiB pre-final and2GiB/1GiB floors; prospective240s import, retained current diagnosis, complete consumer/bootstrap58MiB freeze and both imports; no guest.'}) + '\n')!
	need(nativeguard.allocated(charged, os.lstat(state)!.dev)! <= cap
		&& nativeguard.allocated(observer_paths(), os.lstat(state)!.dev)! <= u64(8) << 20
		&& time.sys_mono_now() - started < i64(phase_ms) * time.millisecond, 'staging final receipt exceeds limits')!
	finished := time.sys_mono_now()
	last_sample := result.samples.last().mono_ns
	need(finished - last_sample <= 5 * time.second, 'import postflight window exceeds5s')!
	os.write_file(phase_observer + '/timing-final.json', json2.encode({'phase_started_ns': started.str(),
		'sampling_call_started_ns': sampling_started.str(), 'last_sample_mark_ns': last_sample.str(),
		'receipts_finished_ns': finished.str(), 'preflight_window_ns': (sampling_started - started).str(),
		'postflight_window_ns': (finished - last_sample).str(), 'phase_wall_ms': phase_ms.str()}))!
	need(nativeguard.allocated(charged, os.lstat(state)!.dev)! <= cap
		&& nativeguard.allocated(observer_paths(), os.lstat(state)!.dev)! <= u64(8) << 20
		&& time.sys_mono_now() - last_sample <= 5 * time.second
		&& time.sys_mono_now() - started < i64(phase_ms) * time.millisecond, 'import final timing receipt refused')!
	println('PASS bounded complete compact phase: ' + phase)
}

fn main() {
	if os.args.len == 4 && os.args[0] == os.executable() && os.args[1] == '--import-child' {
		import_child(os.args[2], os.args[3]) or { eprintln(err); exit(1) }
	} else { run() or { eprintln(err); exit(1) } }
}
