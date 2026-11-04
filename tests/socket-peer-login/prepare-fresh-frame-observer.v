// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed frame-profile source generation only. No compiler, build or audit runs.
module main

import crypto.sha256
import json2
import os

const repository = '/Users/alex/code/vinix'
const donor = repository + '/build/peer-login-runtime-guarded-worktree'
const control_donor = repository + '/build/package-audio-peer-login-guarded-worktree'
const worktree = repository + '/build/package-peer-login-frame-fresh-worktree'
const raw = '/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-fresh-20261026'
const seal = raw + '-seal-01'
const output = seal + '/native-profiles-01'
const observer_source = repository + '/tests/socket-peer-login/fresh-atomic-observer.v'
const observer_sha = 'a473233234928cc68a5a6d87e432c2dc34ff5ecb6d5037dfe9bd1cc4e181a006'
const original_controller_sha = '20aa8efe95413e461a2cb95f1a0fd94331709fa79225029f334cc72103cc43dd'
const old_binding = "const frame_baseline_root = repository + '/build/package-alloc-track-frame-worktree'"
const new_binding = "const frame_baseline_root = repository + '/build/package-peer-login-frame-fresh-worktree'"
const controller_source = worktree + '/tests/socket-peer-login/guarded-build-check.v'
const controller_binary = raw + '/bootstrap-01/guarded-build-check'
const controller_pins = seal + '/controller-bootstrap-01-pins.json'

struct Edit {
	label string
	old string
	new string
	count int = 1
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn present(path string) bool { return os.exists(path) || os.is_link(path) }
fn sum(text string) string { return sha256.sum(text.bytes()).hex() }
fn ordinary_directory(path string) ! {
	require(os.real_path(path) == path && os.lstat(path)!.mode & 0o170000 == 0o040000,
		'canonical ordinary directory required: ' + path)!
}

fn read_stable(path string, limit u64) !string {
	require(os.real_path(path) == path, 'canonical input path required: ' + path)!
	before := os.lstat(path)!
	require(before.mode & 0o170000 == 0o100000 && before.size <= limit,
		'bounded ordinary input required: ' + path)!
	text := os.read_file(path)!
	after := os.lstat(path)!
	require(before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.size == after.size
		&& before.mtime == after.mtime && before.ctime == after.ctime && u64(text.len) == after.size,
		'input changed during read: ' + path)!
	return text
}

fn pin(path string, limit u64, expected string) !string {
	text := read_stable(path, limit)!
	require(sum(text) == expected, 'input hash differs: ' + path)!
	return text
}

fn change(text string, edit Edit) !string {
	require(edit.old != '' && edit.new != '' && edit.old != edit.new && edit.count > 0
		&& text.count(edit.old) == edit.count && text.count(edit.new) == 0,
		'exact replacement input differs: ' + edit.label)!
	changed := text.replace(edit.old, edit.new)
	require(changed.count(edit.new) == edit.count
		&& changed.len == text.len + edit.count * (edit.new.len - edit.old.len)
		&& changed.replace(edit.new, edit.old) == text,
		'replacement changed unrelated bytes: ' + edit.label)!
	return changed
}

fn edits(binary_sha string, source_sha string) []Edit {
	return [
		Edit{label: 'donor', old: "const donor = '/Users/alex/code/vinix/build/package-audio-peer-login-guarded-worktree'", new: "const donor = '${donor}'"},
		Edit{label: 'worktree', old: "const worktree = '/Users/alex/code/vinix/build/package-peer-login-atomic-fresh-worktree'", new: "const worktree = '${worktree}'"},
		Edit{label: 'raw', old: "const raw = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026'", new: "const raw = '${raw}'"},
		Edit{label: 'controller binary', old: "const controller_sha = '1e00428250ca71542a00b5d50de57f9bddfe2488c48db844ab3e3a234f1d45df'", new: "const controller_sha = '${binary_sha}'"},
		Edit{label: 'controller source', old: "const controller_source_sha = '${original_controller_sha}'", new: "const controller_source_sha = '${source_sha}'"},
		Edit{label: 'wall', old: 'const build_wall = u64(1320 * time.second)', new: 'const build_wall = u64(1100 * time.second)'},
		Edit{label: 'wall receipt', old: "'wall_seconds': '1320'", new: "'wall_seconds': '1100'"},
		Edit{label: 'build paths', old: '/build-03', new: '/build-01', count: 6},
		Edit{label: 'frame argv', old: "[controller, raw + '/build-01']", new: 'frame_build_argv()', count: 2},
		Edit{label: 'frame arches', old: "for arch in ['x86_64', 'aarch64'] {", new: 'for arch in frame_arches() {'},
		Edit{label: 'x86 required receipt', old: "\t\tif failure == '' && (!present(raw + '/build-01/qualification.json')\n\t\t\t|| inner['x86_64'].starts_with('unavailable') || inner['aarch64'].starts_with('unavailable')) {", new: "\t\tif failure == '' && (!present(raw + '/build-01/qualification.json')\n\t\t\t|| inner['x86_64'].starts_with('unavailable')) {"},
		Edit{label: 'production clock', old: 'fn production(retry bool) ! {\n\tstate := build_state(retry)', new: 'fn production(retry bool) ! {\n\tstarted := time.sys_mono_now()\n\tstate := build_state(retry)'},
		Edit{label: 'watch clock', old: 'mut watch := Watch{state: state, wall: build_wall, build: true, started: time.sys_mono_now()}', new: 'mut watch := Watch{state: state, wall: build_wall, build: true, started: started}'},
		Edit{label: 'frame markers', old: 'FRESH ATOMIC', new: 'FRESH FRAME', count: 4},
		Edit{label: 'build final guard', old: "\tprintln('FRESH FRAME NATIVE OBSERVATION PASS; REQUIRE ORIGINAL BUILD QUALIFICATION AND FULL AUDIT')", new: "\taudit_end_timing(watch.started, watch.previous, time.sys_mono_now(), watch.wall)!\n\tprintln('FRESH FRAME NATIVE OBSERVATION PASS; REQUIRE ORIGINAL BUILD QUALIFICATION AND FULL AUDIT')"},
		Edit{label: 'provisional build receipt', old: "'Observation only; original build qualification and complete audit remain required.'", new: "'PROVISIONAL: frame build status precedes final1100s/5s guards; require external actual exit0, native PASS, original qualification and full audit.'"},
		Edit{label: 'quiet clock', old: 'mut quiet := Watch{state: quiet_state, wall: 600 * u64(time.millisecond), audit: second}', new: 'mut quiet := Watch{state: quiet_state, wall: 900 * u64(time.millisecond), audit: second, started: time.sys_mono_now()}'},
		Edit{label: 'build mode', old: "'--build-03'", new: "'--build-frame-01'"},
		Edit{label: 'retry mode', old: "'--build-03-retry02'", new: "'--build-frame-01-retry02'"},
		Edit{label: 'audit live child log', old: "\t\trequire(!cancelled(), 'observer interrupted')!", new: "\t\trequire(!cancelled(), 'observer interrupted')!\n\t\tframe_audit_log(watch)!"},
		Edit{label: 'audit final child log', old: '\tcleanup := direct_cleanup(watch.pid) or { failure += \'; \' + err.msg(); map[string]string{} }', new: '\tcleanup := direct_cleanup(watch.pid) or { failure += \'; \' + err.msg(); map[string]string{} }\n\tframe_audit_log(&watch) or { failure += \'; audit log: \' + err.msg() }'},
		Edit{label: 'frame flood environment', old: "\t\tsecond_controls, second_controls + '/quiet', second_controls + '/flood']\n}", new: "\t\tsecond_controls, second_controls + '/quiet', second_controls + '/flood', second_controls + '/frame-flood']\n}"},
		Edit{label: 'frame flood probe route', old: "\t\tsecond_controls + '/flood' { 'flood2' }", new: "\t\tsecond_controls + '/flood' { 'flood2' }\n\t\tsecond_controls + '/frame-flood' { 'frameflood' }"},
		Edit{label: 'frame flood probe state', old: "\t\t'flood2' { second_controls + '/flood' }", new: "\t\t'flood2' { second_controls + '/flood' }\n\t\t'frameflood' { second_controls + '/frame-flood' }"},
		Edit{label: 'frame flood probe admission', old: "'quiet2', 'flood2'],", new: "'quiet2', 'flood2', 'frameflood'],"},
		Edit{label: 'closed frame flood child', old: "\tif os.args[1] == '--control-flood' { control_flood(); return }", new: "\tif os.args[1] == '--control-flood' { control_flood(); return }\n\tif os.args[1] == '--frame-audit-flood' { for _ in 0 .. 2049 { println('x'.repeat(1024)) }; return }"},
		Edit{label: 'frame helpers and controls', old: '\treturn count\n}\n\nfn run() ! {', new: frame_helpers()},
	]
}

fn frame_helpers() string {
	return [
		'\tcount += frame_profile_controls()!',
		'\treturn count',
		'}', '',
		"fn frame_build_argv() []string { return [controller, '--frame-baseline', raw + '/build-01'] }",
		"fn frame_arches() []string { return ['x86_64'] }",
		"fn frame_audit_size(size u64) ! { require(size <= 2 * 1024 * 1024, 'frame audit child log cap')! }",
		'fn frame_audit_log(watch &Watch) ! {',
		'\tif !watch.audit || watch.pid <= 1 { return }',
		"\tinfo := os.lstat(watch.state + '/child.log')!",
		"\trequire(info.mode & 0o170000 == 0o100000, 'ordinary frame audit child log required')!",
		'\tframe_audit_size(info.size)!',
		'}',
		'fn frame_profile_controls() !int {',
		"\trequire(frame_build_argv() == [controller, '--frame-baseline', raw + '/build-01'], 'frame build argv differs')!",
		"\trequire(frame_arches() == ['x86_64'], 'frame receipt scope differs')!",
		"\trequire(build_wall == 1100 * u64(time.second), 'frame total wall differs')!",
		'\tframe_audit_size(2 * 1024 * 1024)!',
		'\tmut refused := false',
		'\tframe_audit_size(2 * 1024 * 1024 + 1) or { refused = true }',
		"\trequire(refused, 'frame audit child log overflow accepted')!",
		"\tstate := second_controls + '/frame-flood'",
		'\trequire_fresh(state)!',
		'\tos.mkdir(state)!',
		"\tos.write_file(state + '/child.log', '')!",
		'\tmut flood := Watch{state: state, audit: true, wall: 5 * u64(time.second)}',
		'\tsample(true, mut flood)!',
		'\tmut overflow := false',
		"\trun_observed([os.executable(), '--frame-audit-flood'], mut flood) or { overflow = err.msg().contains('frame audit child log cap') }",
		"\trequire(overflow && flood.pid > 1 && (!flood.observed_exit || flood.observed_status == 0), 'actual frame audit overflow did not refuse')!",
		"\tstatus := json2.decode[map[string]string](small_text(state + '/status.json')!)!",
		"\trequire(status['error'] in ['frame audit child log cap; audit log: frame audit child log cap', '; audit log: frame audit child log cap'], 'unexpected frame flood refusal')!",
		"\tcleanup := json2.decode[map[string]string](status['direct_cleanup'])!",
		"\trequire(cleanup['pid'] == flood.pid.str() && cleanup['waitpid_result'] == '-1' && cleanup['waitpid_errno'] == int(C.ECHILD).str()",
		"\t\t&& cleanup['group_probe_result'] == '-1' && cleanup['group_probe_errno'] == int(C.ESRCH).str(), 'frame flood cleanup differs')!",
		'\treturn 6',
		'}', '',
		'fn run() ! {',
	].join('\n')
}

fn actual_controller() !(string, string, string) {
	donor_source := pin(control_donor + '/tests/socket-peer-login/guarded-build-check.v', 4 * 1024 * 1024, original_controller_sha)!
	require(donor_source.count(old_binding) == 1 && donor_source.count(new_binding) == 0,
		'one frame controller binding required')!
	source_sha := sum(donor_source.replace(old_binding, new_binding))
	pin(controller_source, 4 * 1024 * 1024, source_sha)!
	pins_text := read_stable(controller_pins, 16384)!
	pins := json2.decode[map[string]string](pins_text)!
	require(json2.encode(pins) + '\n' == pins_text, 'canonical controller receipt required')!
	keys := ['format', 'controller_source', 'controller_source_sha256', 'controller_binary',
		'controller_binary_sha256', 'bootstrap_actual_exit', 'source_tool_maps_cmp_actual_exit',
		'host_controls_actual_exit', 'closure_controls_actual_exit',
		'host_controls_sha256', 'closure_controls_sha256']
	require(pins.len == keys.len && keys.all(it in pins), 'complete fixed controller receipt required')!
	require(pins['format'] == 'fresh-frame-controller-v1' && pins['controller_source'] == controller_source
		&& pins['controller_source_sha256'] == source_sha && pins['controller_binary'] == controller_binary,
		'frame controller receipt bindings differ')!
	for key in ['bootstrap_actual_exit', 'source_tool_maps_cmp_actual_exit',
		'host_controls_actual_exit', 'closure_controls_actual_exit'] {
		require(pins[key] == '0', 'controller stage did not actually pass: ' + key)!
	}
	pin(raw + '/host-controls-01/host-controls.json', 65536, pins['host_controls_sha256'])!
	pin(raw + '/closure-controls-01/closure.json', 4 * 1024 * 1024, pins['closure_controls_sha256'])!
	binary_sha := sum(read_stable(controller_binary, 8 * 1024 * 1024)!)
	require(binary_sha == pins['controller_binary_sha256'], 'actual controller binary pin differs')!
	return binary_sha, source_sha, sum(pins_text)
}

fn write_profile(base string, body string, name string) !string {
	path := output + '/' + name
	os.mkdir(path)!
	os.mkdir(path + '/source')!
	destination := path + '/source/fresh-frame-observer.v'
	os.write_file(destination, body)!
	digest := sum(body)
	pin(destination, 1024 * 1024, digest)!
	pin(observer_source, 1024 * 1024, sum(base))!
	return digest
}

fn run() ! {
	require(os.args.len == 1, 'fixed frame observer preparation takes no operands')!
	for path in [donor, control_donor, worktree, raw, seal] { ordinary_directory(path)! }
	require(!present(output), 'fresh fixed native profile output required')!
	base := pin(observer_source, 1024 * 1024, observer_sha)!
	binary_sha, source_sha, pins_sha := actual_controller()!
	changes := edits(binary_sha, source_sha)
	mut body := base
	for edit in changes { body = change(body, edit)! }
	mut reversed := body
	for i := changes.len - 1; i >= 0; i-- { reversed = reversed.replace(changes[i].new, changes[i].old) }
	require(reversed == base, 'complete inverse frame source differs')!
	independent := change(body, Edit{label: 'independent controls', old: "'/native-controls-02'", new: "'/native-controls-03'"})!
	separate := change(independent, Edit{label: 'independent check', old: "'/native-check-01'", new: "'/native-check-02'", count: 6})!
	os.mkdir(output)!
	primary_sha := write_profile(base, body, 'primary')!
	independent_sha := write_profile(base, separate, 'independent')!
	pin(observer_source, 1024 * 1024, observer_sha)!
	pin(controller_source, 4 * 1024 * 1024, source_sha)!
	pin(controller_binary, 8 * 1024 * 1024, binary_sha)!
	pin(controller_pins, 16384, pins_sha)!
	os.write_file(output + '/source-derivation.json', json2.encode({'format': '1',
		'base_source': observer_source, 'base_sha256': observer_sha,
		'controller_binary_sha256': binary_sha, 'controller_source_sha256': source_sha,
		'controller_receipt_sha256': pins_sha, 'primary_source_sha256': primary_sha,
		'independent_source_sha256': independent_sha, 'expected_native_controls': '67',
		'build_argv': json2.encode([controller_binary, '--frame-baseline', raw + '/build-01']),
		'build_total_wall_seconds': '1100', 'build_term_grace_seconds': '10',
		'audit_total_wall_seconds': '600/300', 'audit_term_grace_seconds': '0',
		'audit_child_log_bytes': '2097152',
		'scope': 'Fixed generated frame source only. No compiler/build/audit/qualification. Require full generated diff review, strict bootstraps and fresh67 controls per profile before use.'}) + '\n')!
	println('FRESH FRAME NATIVE PROFILE SOURCES COMPLETE; NO QUALIFICATION')
}

fn main() { run() or { eprintln(err); exit(1) } }
