// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed staging profile using the already qualified inherited-group owner.
module main

import compactproof
import compactdiagnosis
import crypto.sha256
import json2
import launchproof
import nativeguard
import os
import proof
import time

#include <errno.h>

const repository = '/Users/alex/code/vinix'
const state = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02'
const source_root = state + '/source'
const suite = source_root + '/tests/software-hosted-x11'
const staging = state + '/compact-import-01'
const observer = state + '/compact-import-observer-01'
const bootstrap = state + '/compact-import-bootstrap-01'
const current_audit = state + '/compact-current-audit-01'
const current_observer = state + '/compact-current-audit-observer-01'
const compact_root = '/Users/alex/Library/Caches/vinix-codex/section14/compact-launch-entry-20261026'
const original_checker = '/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const old_tools = state + '/native-supervision-host-01'
const consumer_tools = state + '/native-consumer-tools-01'
const projection = state + '/compact-stage-projection-02.json'
const frozen_record = state + '/compact-frozen-tools-01.json'
const frozen_verifier = bootstrap + '/compact-projection-02'
const cap = u64(256) << 20
const reserve = u64(2) << 20

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
	for path in [suite + '/nativeguard/guard.v', suite + '/diagnostics/recoveryguard/recoveryguard.v', @FILE, os.executable(),
		projection, frozen_record, frozen_verifier, bootstrap + '/projection-source-02/compact-projection.v',
		repository + '/tests/software-hosted-x11/compactdiagnosis/compare.v',
		repository + '/tests/software-hosted-x11/compactdiagnosis/controls.v'] {
		pins[path] = digest(path)!
	}
	return pins
}

fn frozen_pins() ! {
	need(digest(projection)! == '67ae49eeb2f43ffdc16cbd093a43c3dd93e7a8c4933854913c0e7464ececb1e6'
		&& digest(frozen_record)! == '14a1d04a2288ff548171b8428cabe92582a8ceefc7ea648e25f07f5ef00da579'
		&& digest(frozen_verifier)! == 'd5b6902bd3b96051c15b805fbaf10d0c855ea9323e3b16a8fff26fd17d802b78'
		&& digest(bootstrap + '/projection-source-02/compact-projection.v')! == '372bc38b3fd3dd52995bf0434840eed16d7e02341570f10ffa504ed3e607c857',
		'complete rounded projection or frozen verifier pin differs')!
	need(nativeguard.allocated([old_tools], os.lstat(state)!.dev)! <= u64(31) << 20
		&& nativeguard.allocated([consumer_tools], os.lstat(state)!.dev)! <= u64(40) << 20
		&& nativeguard.allocated([bootstrap], os.lstat(state)!.dev)! <= u64(10) << 20,
		'fixed aggregate component bound refused')!
}

fn frozen_check(label string) ! {
	frozen_pins()!
	checked := original_check([frozen_verifier, '--verify-frozen'], label)!
	need(checked.actual_exit == 0, 'complete frozen old tool root changed')!
	frozen_pins()!
}

fn compiled_modules(phase string) ! {
	for path, expected in {
		repository + '/tests/software-hosted-x11/compactdiagnosis/compare.v': 'a4a3eac9206efd9d85887ba55529263acbd4b934ee405612be5a529fc44a0010'
		repository + '/tests/software-hosted-x11/compactdiagnosis/controls.v': '61f80faf63c787dffd98fb4105c6c02d8e19a8e44f3a718ccb4819b37c5bf941'
	} { need(digest(path)! == expected, 'reviewed pure diagnosis source differs')! }
	before_text := os.read_file(bootstrap + '/modules-before.json')!
	need(sha256.hexhash(before_text) == '7574aa941eeea3b7beb3dc58c14f6c23e57aea93bd5349a09f1aa8a51da9abce',
		'qualified before-bootstrap importedmodule map differs')!
	before := json2.decode[map[string]string](before_text, strict: true)!
	after := module_files()!
	need(before == after, 'importedmodule files changed across bootstrap')!
	compiled := {
		suite + '/compactproof/admit.v': sha256.hexhash(compactproof.source())
		suite + '/launchproof/admit.v': sha256.hexhash(launchproof.source())
		suite + '/proof/admit.v': sha256.hexhash(proof.source())
		suite + '/nativeguard/guard.v': sha256.hexhash($embed_file('/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/source/tests/software-hosted-x11/nativeguard/guard.v').to_string())
		suite + '/diagnostics/recoveryguard/recoveryguard.v': sha256.hexhash($embed_file('/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/source/tests/software-hosted-x11/diagnostics/recoveryguard/recoveryguard.v').to_string())
		repository + '/tests/software-hosted-x11/compactdiagnosis/compare.v': sha256.hexhash(compactdiagnosis.source())
		repository + '/tests/software-hosted-x11/compactdiagnosis/controls.v': sha256.hexhash($embed_file('/Users/alex/code/vinix/tests/software-hosted-x11/compactdiagnosis/controls.v').to_string())
	}
	for path, expected in compiled { need(digest(path)! == expected, 'compiled module differs from captured source: ' + path)! }
	os.write_file(bootstrap + '/' + phase + '-modules-after.json', json2.encode(after))!
	os.write_file(bootstrap + '/' + phase + '-compiled-modules.json', json2.encode(compiled))!
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

fn original_inputs() !map[string]string {
	mut pins := {
		original_checker: 'fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6'
		repository + '/tests/kernel-allocs/frame-page-seal.v': '8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4'
		compact_root + '/target-complete-seals01/targets01/inventory.json': '8da3c48959340c6f0d0f1aef0ac032a9f398e2ca43b0785cc8532402f5e35999'
		compact_root + '/target-complete-seals01/target-bootstrap01/inventory.json': '577d9f123d39d830d03111f0cabf2cf4128b16153f6975e0d18416173a2c0b99'
	}
	for path, hash in pins { need(digest(path)! == hash, 'original checker/source/complete inventory differs: ' + path)! }
	return pins
}

fn current_child() ! {
	need(os.args == [os.executable(), '--current-audit-child'] && !os.exists(current_audit),
		'requires fresh fixed current-audit child')!
	before := modules()!
	original_before := original_inputs()!
	os.mkdir(current_audit, mode: 0o700)!
	os.write_file(current_audit + '/modules-before.json', json2.encode(before))!
	os.write_file(current_audit + '/original-inputs-before.json', json2.encode(original_before))!
	audit_directory = current_audit
	frozen_check('frozen-tools-before')!
	// Exercise the pure reader before consuming retained evidence. These small
	// explicit controls create no process owner and remain active in-prod.
	compactdiagnosis.controls(consumer_tools + '/diagnosis-controls-01')!
	for role in ['targets01', 'target-bootstrap01'] {
		root := compact_root + '/' + role
		old := compact_root + '/target-complete-seals01/' + role + '/inventory.json'
		refused := original_check([original_checker, 'check', root, old], 'original-refusal-' + role)!
		need(refused.actual_exit == 1 && os.read_file(refused.log_path)! == 'state inventory mismatch\n',
			'expected original complete metadata refusal did not match exactly: ' + role)!
	}
	mut outputs := map[string]string{}
	for role in ['targets01', 'target-bootstrap01'] {
		root := compact_root + '/' + role
		old := compact_root + '/target-complete-seals01/' + role + '/inventory.json'
		out := current_audit + '/' + role
		sealed := original_check([original_checker, 'seal', root, out], 'current-seal-' + role)!
		need(sealed.actual_exit == 0, 'fresh unchanged complete seal failed: ' + role)!
		fresh := out + '/inventory.json'
		hash := digest(fresh)!
		need(os.read_file(sealed.log_path)! == 'FRAME-PAGE COMPLETE STATE PASS ' + hash + '\n'
			&& os.read_file(out + '/inventory.sha256')! == hash + '  inventory.json\n',
			'fresh complete seal marker or checksum differs: ' + role)!
		checked := original_check([original_checker, 'check', root, fresh], 'current-check-' + role)!
		need(checked.actual_exit == 0 && os.read_file(checked.log_path)! == 'FRAME-PAGE COMPLETE STATE CHECK PASS\n',
			'fresh separate original complete check differs: ' + role)!
		summary := compactdiagnosis.compare(old, fresh, current_audit + '/' + role + '-differences.json')!
		need(summary.accepted_metadata_only, 'current complete inventory has content/path/type drift')!
		outputs[role + '/inventory.json'] = hash
		outputs[role + '/inventory.sha256'] = digest(out + '/inventory.sha256')!
		outputs[role + '-differences.json'] = digest(current_audit + '/' + role + '-differences.json')!
	}
	frozen_check('frozen-tools-after')!
	after := modules()!
	original_after := original_inputs()!
	os.write_file(current_audit + '/modules-after.json', json2.encode(after))!
	os.write_file(current_audit + '/original-inputs-after.json', json2.encode(original_after))!
	need(before == after && original_before == original_after,
		'current diagnosis source or original manifest changed')!
	os.write_file(current_audit + '/result.json', json2.encode({'outcome': 'PASS',
		'outputs': json2.encode(outputs),
		'scope': 'Expected unchanged original complete refusals retained; same original auditor sealed and separately checked both complete current roots. Complete canonical field comparisons accepted only explicitly recorded metadata drift. Historical roots/manifests unchanged. No import or guest.'}) + '\n')!
	println('COMPACT CURRENT AUDIT original refusals, complete fresh seals/checks and metadata-only diagnosis PASS')
}

fn import_child() ! {
	need(os.args == [os.executable(), '--import-child'] && !os.exists(staging), 'requires fresh fixed staging child')!
	before := modules()!
	os.mkdir(staging, mode: 0o700)!
	os.write_file(staging + '/modules-before.json', json2.encode(before))!
	audit_directory = staging
	frozen_check('frozen-tools-before')!
	audit_directory = staging + '/audits-before'
	os.mkdir(audit_directory, mode: 0o700)!
	first := compactproof.check_audits(original_check)!
	first.write_record(staging + '/audits-before.json')!
	for arch in ['aarch64', 'x86_64'] {
		compactproof.import_build(arch, state + '/import-' + arch, first)!
		compactproof.assembled(state + '/import-' + arch,
			'/Users/alex/Library/Caches/vinix-codex/section14/package-hosted-launch-options-native-20261026/restored-stage-' + arch,
			arch, '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v', first)!
	}
	audit_directory = staging + '/audits-after'
	os.mkdir(audit_directory, mode: 0o700)!
	last := compactproof.check_audits(original_check)!
	last.write_record(staging + '/audits-after.json')!
	for arch in ['aarch64', 'x86_64'] {
		compactproof.assembled(state + '/import-' + arch,
			'/Users/alex/Library/Caches/vinix-codex/section14/package-hosted-launch-options-native-20261026/restored-stage-' + arch,
			arch, '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v', last)!
	}
	audit_directory = staging
	frozen_check('frozen-tools-after')!
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

fn run() ! {
	$if prod {} $else { return error('requires production source binding') }
	need(os.args.len == 2 && os.args[0] == os.executable()
		&& os.args[1] in ['--current-audit', '--prepare'], 'requires one fixed phase')!
	diagnose := os.args[1] == '--current-audit'
	phase := if diagnose { 'current-audit' } else { 'import' }
	phase_observer := if diagnose { current_observer } else { observer }
	phase_ms := if diagnose { 120000 } else { 780000 }
	admission_path := state + '/compact-' + phase + '-admission-df'
	need(digest(@FILE)! == sha256.hexhash($embed_file('compact-import.v').to_string()), 'staging profile source changed')!
	mut fresh := if diagnose { [current_audit, current_observer, consumer_tools + '/diagnosis-controls-01'] }
		else { [staging, observer, state + '/import-aarch64', state + '/import-x86_64'] }
	for path in fresh {
		need(!os.exists(path) && !os.is_link(path), 'requires fresh staging outputs: ' + path)!
	}
	for suffix in ['', '.barrier.json', '.cleanup.json', '.barrier-cleanup.json'] {
		path := admission_path + suffix
		need(!os.exists(path) && !os.is_link(path), 'requires fresh admission receipt: ' + path)!
	}
	for name in ['modules-after.json', 'compiled-modules.json'] {
		path := bootstrap + '/' + phase + '-' + name
		need(!os.exists(path) && !os.is_link(path), 'requires fresh bootstrap comparison receipt')!
	}
	compiled_modules(phase)!
	frozen_pins()!
	nativeguard.watch_interrupts()!
	admission := nativeguard.actual_df(state, admission_path)!
	need(admission.available >= u64(2) << 30, 'staging admission requires2GiB free')!
	os.mkdir(phase_observer, mode: 0o700)!
	os.mkdir(phase_observer + '/tmp', mode: 0o700)!
	os.write_file(phase_observer + '/admission.json', json2.encode(admission))!
	for name, _ in os.environ() { os.unsetenv(name) }
	for name, value in {'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex',
		'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'TMPDIR': phase_observer + '/tmp', 'VTMP': phase_observer + '/tmp'} {
		os.setenv(name, value, true)
	}
	before := modules()!
	os.write_file(phase_observer + '/modules-before.json', json2.encode(before))!
	mut charged := [staging, observer, current_audit, current_observer,
		state + '/import-aarch64', state + '/import-x86_64', bootstrap,
		old_tools, consumer_tools, projection, frozen_record, state + '/compact-stage-projection-01.json',
		state + '/compact-wrapper-binding-01', state + '/compact-supervisor-binding-01',
		suite + '/compactproof/current.v', suite + '/compactproof/current_controls.v',
		suite + '/compactproof/currentcheck', suite + '/compactproof-check.v', suite + '/check.v',
		suite + '/retain.v', suite + '/evidence-check.v']
	for role in ['import', 'current-audit'] {
		for suffix in ['', '.barrier.json', '.cleanup.json', '.barrier-cleanup.json'] {
			charged << state + '/compact-' + role + '-admission-df' + suffix
		}
	}
	child_mode := if diagnose { '--current-audit-child' } else { '--import-child' }
	argv := [os.executable(), child_mode]
	os.write_file(phase_observer + '/argv.json', json2.encode(argv))!
	os.write_file(phase_observer + '/environment.json', json2.encode(os.environ()))!
	started := time.sys_mono_now()
	result := nativeguard.supervise(argv, source_root, state, charged, phase_observer + '/output.log', phase_observer + '/df',
		nativeguard.Limits{start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30,
			cap_bytes: cap - reserve, wall_ms: phase_ms, sample_ms: 1000})!
	os.write_file(phase_observer + '/result.json', json2.encode(result))!
	after := modules()!
	os.write_file(phase_observer + '/modules-after.json', json2.encode(after))!
	need(result.reason == '' && result.group_observed && result.cleanup.reaped
		&& result.cleanup.group_empty && result.cleanup.exit_code == 0
		&& result.cleanup.final_wait == -1 && result.cleanup.final_errno == C.ECHILD
		&& before == after, 'staging child, source or cleanup refused')!
	final_df := nativeguard.actual_df(state, phase_observer + '/final-df')!
	allocated := nativeguard.allocated(charged, os.lstat(state)!.dev)!
	need(final_df.available >= u64(1) << 30 && allocated <= cap - 65536
		&& time.sys_mono_now() - started < i64(phase_ms) * time.millisecond, 'staging final resource checks refused')!
	os.write_file(phase_observer + '/qualification.json', json2.encode({'outcome': 'PASS',
		'allocated_bytes': allocated.str(), 'available_bytes': final_df.available.str(),
		'phase': phase, 'wall_ms': phase_ms.str(),
		'scope': 'Existing inherited-group owner; sampled256MiB cumulative cap and2GiB/1GiB floors; fixed120s current-diagnosis plus780s import phases, inclusive each child/final tail. Complete actual audits/maps; no guest.'}) + '\n')!
	need(nativeguard.allocated(charged, os.lstat(state)!.dev)! <= cap
		&& time.sys_mono_now() - started < i64(phase_ms) * time.millisecond, 'staging final receipt exceeds limits')!
	println('PASS bounded complete compact phase: ' + phase)
}

fn main() {
	if os.args == [os.executable(), '--import-child'] {
		import_child() or { eprintln(err); exit(1) }
	} else if os.args == [os.executable(), '--current-audit-child'] {
		current_child() or { eprintln(err); exit(1) }
	} else { run() or { eprintln(err); exit(1) } }
}
