// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed fresh-atomic build observer. It does not qualify a build or its descendants.
@[has_globals]
module main

import crypto.sha256
import json2
import os
import sourcecommand
import time

#include <errno.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
fn C.getpgid(i32) i32
fn C.waitpid(i32, &i32, i32) i32

const donor = '/Users/alex/code/vinix/build/package-audio-peer-login-guarded-worktree'
const worktree = '/Users/alex/code/vinix/build/package-peer-login-atomic-fresh-worktree'
const raw = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026'
const seal = raw + '-seal-01'
const observer = raw + '/native-observer-01'
const controller = raw + '/bootstrap-01/guarded-build-check'
const controller_sha = '1e00428250ca71542a00b5d50de57f9bddfe2488c48db844ab3e3a234f1d45df'
const controller_source_sha = '20aa8efe95413e461a2cb95f1a0fd94331709fa79225029f334cc72103cc43dd'
const compiler = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const kib_cap = i64(524288)
// Covers three worst-case doubly escaped retry records following the last du,
// plus scratch streams, allocation rounding and the separate64KiB status.
const observer_tail_kib = i64(1024)
const admission_kib = i64(2097152)
const live_kib = i64(1048576)
const log_cap = i64(32 * 1024 * 1024)
const journal_cap = i64(4 * 1024 * 1024)
const sample_window = u64(5000 * time.millisecond)
const build_wall = u64(1320 * time.second)
const moving_log_entry = 18026

__global interrupted = i32(0)
fn interrupt(signal os.Signal) { interrupted = i32(signal) }
fn cancelled() bool { return interrupted != 0 }
fn never() bool { return false }
fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn present(path string) bool { return os.exists(path) || os.is_link(path) }

struct Metrics {
	free_kib i64
	allocated_kib i64
	apparent_kib i64
	log_bytes i64
}

struct WalkCount {
mut:
	entries int
}

struct Watch {
	state string
	wall u64
	build bool
	log_limit i64 = log_cap
	log_roots []string
mut:
	pid int
	started u64
	previous u64
	samples int
	journal_bytes i64
	max_gap_ms u64
	max_sample_ms u64
	max_allocated_kib i64
	max_apparent_kib i64
	min_free_kib i64 = 9223372036854775807
	observed_exit bool
	observed_status int
	reason string
}

fn roots() []string { return [donor, worktree, raw, seal] }

fn child_environment() map[string]string {
	p := raw + '/bootstrap-01'
	return {'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex',
		'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'V': compiler, 'VEXE': compiler,
		'V_MACOS_V3_CALLER_VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE_PRESENT': '1',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0', 'V_MACOS_V3_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1',
		'VMODULES': p + '/modules', 'V3CACHE': p + '/cache', 'XDG_CACHE_HOME': p + '/cache',
		'VTMP': p + '/tmp', 'TMPDIR': p + '/tmp',
		'SDKROOT': '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk',
		'DEVELOPER_DIR': '/Library/Developer/CommandLineTools'}
}

fn ordinary_directory(path string) ! {
	require(os.real_path(path) == path && os.lstat(path)!.mode & 0o170000 == 0o040000,
		'canonical ordinary directory required: ' + path)!
}

fn regular_hash(path string, limit u64) !string {
	a := os.lstat(path)!
	require(a.mode & 0o170000 == 0o100000 && a.size <= limit, 'bounded regular input required')!
	bytes := os.read_bytes(path)!
	b := os.lstat(path)!
	require(a.dev == b.dev && a.inode == b.inode && a.mode == b.mode && a.uid == b.uid
		&& a.gid == b.gid && a.size == b.size && a.mtime == b.mtime && a.ctime == b.ctime
		&& u64(bytes.len) == b.size, 'input changed during read: ' + path)!
	return sha256.sum(bytes).hex()
}

// Decimal conversion is bounded before arithmetic, including hostile probe text.
fn number(text string) !i64 {
	require(text.len > 0 && text.len <= 15 && text.bytes().all(it >= `0` && it <= `9`),
		'invalid nonnegative probe integer')!
	return text.i64()
}

fn du_total(text string, expected []string) !i64 {
	mut seen := map[string]bool{}
	mut total := i64(0)
	for line in text.split_into_lines() {
		if line == '' { continue }
		fields := line.split('\t')
		require(fields.len == 2 && fields[1] in expected && !seen[fields[1]], 'du rows/paths differ')!
		total += number(fields[0])!
		seen[fields[1]] = true
	}
	require(seen.len == expected.len, 'du omitted charged root')!
	return total
}

fn df_free(text string) !i64 {
	lines := text.split_into_lines().filter(it.trim_space() != '')
	require(lines.len == 2 && lines[0].starts_with('Filesystem'), 'df rows differ')!
	fields := lines[1].fields()
	require(fields.len >= 6, 'df fields differ')!
	return number(fields[3])
}

fn policy(m Metrics, admission bool) ! {
	require(m.free_kib >= if admission { admission_kib } else { live_kib }, 'free space floor')!
	require(m.allocated_kib <= kib_cap - observer_tail_kib && m.apparent_kib <= kib_cap - observer_tail_kib,
		'inclusive storage cap with observer output reservation')!
	require(m.log_bytes <= log_cap, 'combined log cap')!
}

fn timing(gap u64, duration u64) ! {
	require(gap <= sample_window && duration <= sample_window, 'native sample interval/window exceeds 5s')!
}

fn retry_allowed(attempt int, now u64, deadline u64) bool {
	return attempt < 3 && now < deadline && deadline - now >= 250 * u64(time.millisecond)
}

fn journal(mut watch Watch, name string, text string) ! {
	require(name.len > 0 && !name.contains('/'), 'observation record name required')!
	// A full/failed raw journal must not prevent the final refusal/cleanup
	// receipt. This separate 64KiB allowance is charged by both du probes.
	if name == 'status.json' {
		require(!present(watch.state + '/' + name) && text.len <= 65536, 'fresh bounded final receipt required')!
		os.write_file(watch.state + '/' + name, text)!
		return
	}
	path := watch.state + '/observations.jsonl'
	if present(path) {
		require(os.lstat(path)!.mode & 0o170000 == 0o100000 && os.file_size(path) == u64(watch.journal_bytes),
			'observation journal changed')!
	}
	record := json2.encode({'name': name, 'record': text}) + '\n'
	// Keep fixed final status/control receipts outside the raw-record allowance.
	require(i64(record.len) <= journal_cap - 65536 - watch.journal_bytes, 'observation journal cap')!
	mut file := os.open_append(path)!
	n := file.write_string(record)!
	file.close()
	require(n == record.len && os.file_size(path) == u64(watch.journal_bytes + i64(record.len)), 'short observation journal write')!
	watch.journal_bytes += i64(record.len)
	if name in ['plan.json', 'controls.json'] {
		require(!present(watch.state + '/' + name) && text.len <= 16384, 'fresh bounded fixed receipt required')!
		os.write_file(watch.state + '/' + name, text)!
	}
}

struct ProbeWatch {
	state string
	deadline u64
mut:
	pid int
	observed_exit bool
	status int
}

fn small_text(path string) !string {
	info := os.lstat(path)!
	require(info.mode & 0o170000 == 0o100000 && info.size <= 8192, 'bounded ordinary probe stream required')!
	return os.read_file(path)
}

fn probe_observe(pid int, pointer voidptr) ! {
	mut probe := unsafe { &ProbeWatch(pointer) }
	probe.pid = pid
	for {
		require(!cancelled(), 'probe interrupted')!
		for suffix in ['stdout', 'stderr', 'owner'] {
			require(os.lstat(probe.state + '/probe.' + suffix)!.size <= 8192, 'probe stream limit')!
		}
		require(time.sys_mono_now() < probe.deadline, 'probe owner deadline')!
		status := sourcecommand.child_exit(pid)!
		if status.exited {
			require(time.sys_mono_now() <= probe.deadline, 'probe exit observation after deadline')!
			probe.observed_exit = true; probe.status = status.return_code; return
		}
		require(time.sys_mono_now() < probe.deadline, 'probe owner deadline')!
		time.sleep(time.millisecond)
	}
}

fn probe_command(kind string) ![]string {
	if kind == 'allocated' || kind == 'apparent' {
		mut argv := ['/usr/bin/du', '-P', if kind == 'allocated' { '-skl' } else { '-skAl' }]
		argv << charged_roots()!
		return argv
	}
	return match kind {
		'df' { ['/bin/df', '-k', raw] }
		'transient', 'failure' { [os.executable(), '--control-probe-' + kind] }
		else { return error('unknown closed probe') }
	}
}

fn probe_route(state string) !string {
	return match state {
		observer + '/run-01' { 'run' }
		observer + '/controls-01' { 'controls' }
		observer + '/controls-01/quiet' { 'quiet' }
		observer + '/controls-01/flood' { 'flood' }
		else { return error('unknown closed probe state') }
	}
}

fn probe_state(route string) !string {
	return match route {
		'run' { observer + '/run-01' }
		'controls' { observer + '/controls-01' }
		'quiet' { observer + '/controls-01/quiet' }
		'flood' { observer + '/controls-01/flood' }
		else { return error('unknown closed probe route') }
	}
}

// A fixed self mode redirects both streams before exec of the exact probe.
// Files survive interruption and ownership errors, unlike capture's in-memory
// output. Reuse occurs only after the prior raw streams have been journaled.
fn probe_child(mode string) ! {
	parts := mode.split('-')
	require(parts.len == 5 && parts[0] == '' && parts[1] == '' && parts[2] == 'probe'
		&& parts[4] in ['run', 'controls', 'quiet', 'flood'], 'unknown closed probe mode')!
	state := probe_state(parts[4])!
	ordinary_directory(state)!
	require(!present(state + '/status.json') && !present(state + '/controls.json'), 'completed observation is immutable')!
	command := probe_command(parts[3])!
	mut out := os.open_file(state + '/probe.stdout', 'w')!
	mut err := os.open_file(state + '/probe.stderr', 'w')!
	require(os.fd_dup2(out.fd, 1) == 1 && os.fd_dup2(err.fd, 2) == 2, 'probe stream redirection')!
	out.close(); err.close()
	mut environment := []string{}
	for key, value in child_environment() { environment << key + '=' + value }
	os.execve(command[0], command[1..], environment)!
}

fn probe(kind string, deadline u64, label string, mut watch Watch) !string {
	for attempt in 0 .. 3 {
		now := time.sys_mono_now()
		require(retry_allowed(attempt, now, deadline), 'probe retry has no remaining sample window')!
		remaining_ms := (deadline - now) / u64(time.millisecond)
		budget_ms := if remaining_ms > 1200 { u64(1000) } else { remaining_ms - 200 }
		mode := '--probe-' + kind + '-' + probe_route(watch.state)!
		command := ['/opt/homebrew/bin/gtimeout', '--signal=KILL', '${f64(budget_ms) / 1000.0}s', os.executable(), mode]
		actual_probe := probe_command(kind)!
		for suffix in ['stdout', 'stderr', 'owner'] {
			path := watch.state + '/probe.' + suffix
			if present(path) { require(os.lstat(path)!.mode & 0o170000 == 0o100000, 'ordinary probe scratch file required')! }
			os.write_file(path, '')!
		}
		started := time.sys_mono_now()
		mut child := ProbeWatch{state: watch.state, deadline: started + (budget_ms + 150) * u64(time.millisecond)}
		mut failure := ''
		result := sourcecommand.run_logged_owned(command, child_environment(), never, watch.state + '/probe.owner',
			false, '', probe_observe, &child, 0) or {
			failure = err.msg()
			sourcecommand.Output{status: -999}
		}
		stdout := small_text(watch.state + '/probe.stdout')!
		stderr := small_text(watch.state + '/probe.stderr')!
		owner := small_text(watch.state + '/probe.owner')!
		journal(mut watch, label + '-${attempt}.json', json2.encode({'argv': json2.encode(command),
			'probe_argv': json2.encode(actual_probe), 'error': failure,
			'status': if failure == '' { result.status.str() } else { 'unavailable' },
			'observed_exit': child.observed_exit.str(), 'observed_status': child.status.str(),
			'stdout': stdout, 'stderr': stderr, 'owner_output': owner,
			'elapsed_ms': ((time.sys_mono_now() - started) / u64(time.millisecond)).str()}) + '\n')!
		require(failure == '', 'probe owner failed; retained raw streams: ' + failure)!
		require(child.observed_exit && child.status == result.status, 'probe WNOWAIT/result status differs')!
		require(time.sys_mono_now() <= deadline, 'probe finished after sample deadline')!
		if result.status == 0 { return stdout }
	}
	return error('probe failed after initial attempt and two immediate retries')
}

// lstat and du -P both leave dependency symlinks untraversed. Count every hard
// link in each charged root (-l), and both allocated and apparent bytes (-A).
fn charged_roots() ![]string {
	mut paths := []string{}
	for path in roots() {
		if path == seal && !present(path) { continue }
		ordinary_directory(path)!
		paths << path
	}
	return paths
}

fn log_bytes(path string, depth int, deadline u64, mut count WalkCount) !i64 {
	count.entries++
	require(count.entries <= 50000 && depth <= 96 && time.sys_mono_now() <= deadline, 'bounded no-follow log walk')!
	info := os.lstat(path) or {
		if err.code() == C.ENOENT { return error_with_code('log entry moved: ' + path, moving_log_entry) }
		return err
	}
	kind := info.mode & 0o170000
	if kind == 0o120000 { return 0 }
	if kind == 0o100000 {
		if !path.ends_with('.log') { return 0 }
		require(info.size <= u64(log_cap), 'individual log cap')!
		return i64(info.size)
	}
	require(kind == 0o040000, 'unsupported charged entry')!
	mut total := i64(0)
	names := os.ls(path) or {
		if err.code() == C.ENOENT { return error_with_code('log directory moved: ' + path, moving_log_entry) }
		return err
	}
	for name in names {
		total += log_bytes(path + '/' + name, depth + 1, deadline, mut count)!
		require(total <= log_cap, 'combined log cap')!
	}
	return total
}

fn sample(admission bool, mut watch Watch) ! {
	started := time.sys_mono_now()
	gap := if watch.previous == 0 { u64(0) } else { started - watch.previous }
	watch.previous = started
	watch.max_gap_ms = u64_max(watch.max_gap_ms, gap / u64(time.millisecond))
	timing(gap, 0)!
	phase_deadline := if watch.started == 0 { started + sample_window } else { watch.started + watch.wall }
	deadline := if phase_deadline < started + sample_window { phase_deadline } else { started + sample_window }
	require(deadline > started, 'observer absolute phase deadline')!
	paths := charged_roots()!
	label := 'sample-${watch.samples}'
	free := df_free(probe('df', deadline, label + '-df', mut watch)!)!
	allocated := du_total(probe('allocated', deadline, label + '-allocated', mut watch)!, paths)!
	apparent := du_total(probe('apparent', deadline, label + '-apparent', mut watch)!, paths)!
	log_paths := if watch.log_roots.len == 0 { paths } else { watch.log_roots }
	mut count := WalkCount{}
	mut logs := i64(0)
	mut walked := false
	for attempt in 0 .. 3 {
		require(retry_allowed(attempt, time.sys_mono_now(), deadline), 'log walk retry window')!
		count.entries = 0; logs = 0
		mut failure := ''
		mut failure_code := 0
		for path in log_paths {
			logs += log_bytes(path, 0, deadline, mut count) or { failure = err.msg(); failure_code = err.code(); break }
			require(logs <= log_cap, 'observed combined log cap across charged roots')!
		}
		if failure == '' { walked = true; break }
		journal(mut watch, label + '-logwalk-${attempt}.json', json2.encode({'error': failure, 'error_code': failure_code.str(),
			'entries': count.entries.str(), 'elapsed_ms': ((time.sys_mono_now() - started) / u64(time.millisecond)).str()}) + '\n')!
		require(failure_code == moving_log_entry, 'log walk policy/type/deadline refusal: ' + failure)!
	}
	require(walked, 'log walk failed after initial attempt and two immediate retries')!
	m := Metrics{free, allocated, apparent, logs}
	duration := time.sys_mono_now() - started
	watch.max_sample_ms = u64_max(watch.max_sample_ms, duration / u64(time.millisecond))
	watch.max_allocated_kib = i64_max(watch.max_allocated_kib, allocated)
	watch.max_apparent_kib = i64_max(watch.max_apparent_kib, apparent)
	if free < watch.min_free_kib { watch.min_free_kib = free }
	journal(mut watch, label + '.json', json2.encode({'metrics': json2.encode(m), 'admission': admission.str(),
		'monotonic_ns': started.str(), 'gap_ms': (gap / u64(time.millisecond)).str(),
		'duration_ms': (duration / u64(time.millisecond)).str(), 'entries': count.entries.str()}) + '\n')!
	watch.samples++
	// Include the last journal write and policy checks in the measured window.
	policy(m, admission)!
	require(logs <= watch.log_limit, 'closed control log cap')!
	finished := time.sys_mono_now()
	watch.max_sample_ms = u64_max(watch.max_sample_ms, (finished - started) / u64(time.millisecond))
	timing(gap, finished - started)!
	require(finished <= deadline, 'sample exceeded absolute phase deadline')!
}

fn u64_max(a u64, b u64) u64 { return if a > b { a } else { b } }
fn i64_max(a i64, b i64) i64 { return if a > b { a } else { b } }

fn observe(pid int, pointer voidptr) ! {
	mut watch := unsafe { &Watch(pointer) }
	watch.pid = pid
	for {
		require(!cancelled(), 'observer interrupted')!
		now := time.sys_mono_now()
		require(now - watch.started <= watch.wall, 'observer wall deadline')!
		if now - watch.previous >= u64(time.second) { sample(false, mut watch)! }
		status := sourcecommand.child_exit(pid)!
		if status.exited {
			watch.observed_exit = true
			watch.observed_status = status.return_code
			// Even a child exiting before the first periodic sample must have its
			// final log/storage state checked while its leader is still reserved.
			sample(false, mut watch)!
			return
		}
		time.sleep(10 * time.millisecond)
	}
}

// These probes follow the owner's completed sole-reap mechanism. No signal is
// sent to a positive PID after reap. This says nothing about escaped groups.
fn direct_cleanup(pid int) !map[string]string {
	require(pid > 1, 'no direct leader was started')!
	mut status := i32(0)
	waited := C.waitpid(i32(pid), &status, C.WNOHANG)
	wait_errno := int(C.errno)
	deadline := time.sys_mono_now() + 2 * u64(time.second)
	mut group_result := i32(0)
	mut group_errno := 0
	for {
		group_result = C.kill(-i32(pid), 0)
		group_errno = int(C.errno)
		if group_result == -1 && group_errno == C.ESRCH { break }
		if time.sys_mono_now() >= deadline { break }
		time.sleep(10 * time.millisecond)
	}
	result := {'pid': pid.str(), 'waitpid_result': waited.str(), 'waitpid_errno': wait_errno.str(),
		'group_probe_result': group_result.str(), 'group_probe_errno': group_errno.str(),
		'scope': 'Direct owned leader and its original PGID only; separate inner controller groups require their own receipts.'}
	require(waited == -1 && wait_errno == C.ECHILD && group_result == -1 && group_errno == C.ESRCH,
		'direct cleanup observation differs: ' + json2.encode(result))!
	return result
}

fn run_observed(argv []string, mut watch Watch) ! {
	if watch.started == 0 { watch.started = time.sys_mono_now() }
	mut failure := ''
	result := sourcecommand.run_logged_owned(argv, child_environment(), cancelled,
		watch.state + '/child.log', false, '', observe, &watch, 10) or {
		failure = err.msg()
		sourcecommand.Output{status: -999}
	}
	cleanup := direct_cleanup(watch.pid) or { failure += '; ' + err.msg(); map[string]string{} }
	// Postflight sampling is required even after a policy refusal; preserve its
	// independent error without manufacturing a completed controller postflight.
	sample(false, mut watch) or { failure += '; postflight: ' + err.msg() }
	if failure == '' && (!watch.observed_exit || result.status != watch.observed_status || result.status != 0) {
		failure = 'owned command exit/status differs: returned=' + result.status.str() + ', observed=' + watch.observed_status.str()
	}
	mut inner := map[string]string{}
	if watch.build {
		for arch in ['x86_64', 'aarch64'] {
			path := raw + '/build-03/' + arch + '/build.status.json'
			if !present(path) { inner[arch] = 'unavailable; no separate group cleanup claim'; continue }
			text := small_text(path) or { inner[arch] = 'unavailable: ' + err.msg(); continue }
			inner[arch] = json2.encode({'path': path, 'sha256': sha256.sum(text.bytes()).hex(), 'raw': text,
				'scope': 'Unchanged controller receipt; outer observer did not independently own/reap this separate group.'})
			parsed := json2.decode[map[string]string](text) or { failure += '; invalid inner receipt'; continue }
			if failure == '' && (parsed['exit_code'] != '0' || parsed['reason'] != '' || parsed['cleanup'] != 'leader reaped; group absent') {
				failure += '; successful inner cleanup receipt differs'
			}
		}
		if failure == '' && (!present(raw + '/build-03/qualification.json')
			|| inner['x86_64'].starts_with('unavailable') || inner['aarch64'].starts_with('unavailable')) {
			failure += '; successful original controller qualification/inner receipts unavailable'
		}
	}
	watch.reason = failure
	journal(mut watch, 'status.json', json2.encode({'return_status': result.status.str(),
		'error': failure, 'watch': json2.encode(watch), 'direct_cleanup': json2.encode(cleanup),
		'inner_controller_receipts': json2.encode(inner),
		'scope': 'Observation only. Build qualification and separate descendant cleanup remain the unchanged controller authority.'}) + '\n')!
	require(failure == '' && result.status == 0 && watch.observed_exit && result.status == watch.observed_status,
		'observed command refused: ' + failure)!
}

fn production() ! {
	require(!present(observer + '/run-01') && !present(raw + '/build-03'), 'fresh fixed build/observer attempt required')!
	for path in [donor, worktree, raw, observer] { ordinary_directory(path)! }
	for relative in ['kernel/obj', 'kernel/bin', 'kernel/cc-runtime-x86_64', 'kernel/cc-runtime-aarch64'] {
		require(!present(worktree + '/' + relative), 'prior kernel transient output remains')!
	}
	require(regular_hash(controller, 8 * 1024 * 1024)! == controller_sha
		&& regular_hash(worktree + '/tests/socket-peer-login/guarded-build-check.v', 1024 * 1024)! == controller_source_sha,
		'fixed guarded controller changed')!
	os.mkdir(observer + '/run-01')!
	mut watch := Watch{state: observer + '/run-01', wall: build_wall, build: true, started: time.sys_mono_now()}
	journal(mut watch, 'plan.json', json2.encode({'argv': json2.encode([controller, raw + '/build-03']),
		'environment': json2.encode(child_environment()), 'controller_sha256': controller_sha,
		'controller_source_sha256': controller_source_sha, 'roots': json2.encode(roots()),
		'wall_seconds': '1320', 'term_grace_seconds': '10', 'sample_nominal_ms': '1000',
		'max_sample_gap_ms': '5000', 'max_sample_window_ms': '5000', 'cap_kib': kib_cap.str(),
		'observer_tail_kib': observer_tail_kib.str(), 'admission_kib': admission_kib.str(),
		'live_kib': live_kib.str(), 'journal_cap': journal_cap.str()}) + '\n')!
	sample(true, mut watch)!
	run_observed([controller, raw + '/build-03'], mut watch)!
	println('FRESH ATOMIC NATIVE OBSERVATION PASS; REQUIRE ORIGINAL BUILD QUALIFICATION AND FULL AUDIT')
}

// Closed child modes are used only by --controls. They run no compiler/build.
fn control_worker() {
	for _ in 0 .. 64 { println('0123456789abcdef'.repeat(256)); eprintln('fedcba9876543210'.repeat(256)) }
	time.sleep(2200 * time.millisecond)
}

fn control_flood() { for _ in 0 .. 256 { println('0123456789abcdef'.repeat(64)) } }

fn inner_observe(pid int, pointer voidptr) ! {
	mut watch := unsafe { &Watch(pointer) }
	watch.pid = pid
	os.write_file(watch.state + '/inner-ready.json', json2.encode({'pid': pid.str(), 'pgid': C.getpgid(i32(pid)).str()}))!
	for {
		if cancelled() { return error('control inner interrupted') }
		require(time.sys_mono_now() - watch.started < 5 * u64(time.second), 'control inner deadline')!
		if sourcecommand.child_exited(pid)! { return error('control worker exited before interruption') }
		time.sleep(10 * time.millisecond)
	}
}

fn control_controller() ! {
	mut watch := Watch{state: observer + '/controls-01', started: time.sys_mono_now()}
	mut interrupted_inner := false
	sourcecommand.run_logged_owned([os.executable(), '--control-worker'], child_environment(), never,
		watch.state + '/inner.log', false, '', inner_observe, &watch, 1) or { interrupted_inner = err.msg() == 'control inner interrupted' }
	cleanup := direct_cleanup(watch.pid)!
	require(interrupted_inner, 'nested control did not observe controller interruption')!
	os.write_file(watch.state + '/inner-cleanup.json', json2.encode(cleanup))!
}

fn interrupt_nested(pid int, pointer voidptr) ! {
	mut watch := unsafe { &Watch(pointer) }
	watch.pid = pid
	deadline := time.sys_mono_now() + 3 * u64(time.second)
	for !present(watch.state + '/inner-ready.json') {
		require(time.sys_mono_now() < deadline && !sourcecommand.child_exited(pid)!, 'nested control readiness failed')!
		time.sleep(10 * time.millisecond)
	}
	return error('deliberate outer control refusal')
}

fn verify_inner(text string, outer_pid int) ! {
	result := json2.decode[map[string]string](text)!
	pid := number(result['pid'])!
	require(pid > 1 && pid != outer_pid && result['waitpid_result'] == '-1'
		&& result['waitpid_errno'] == int(C.ECHILD).str() && result['group_probe_result'] == '-1'
		&& result['group_probe_errno'] == int(C.ESRCH).str(), 'separate inner cleanup receipt differs')!
}

fn controls() ! {
	ordinary_directory(observer)!
	require(!present(observer + '/controls-01'), 'fresh controls state required')!
	os.mkdir(observer + '/controls-01')!
	mut watch := Watch{state: observer + '/controls-01', wall: 5 * u64(time.second)}
	mut count := 0
	good := '1\t' + donor + '\n2\t' + worktree + '\n'
	require(du_total(good, [donor, worktree])! == 3, 'valid du parser control')!; count++
	for bad in [good + '1\t' + donor + '\n', '1\t' + donor + '\n', good + '1\t/foreign\n',
		'-1\t' + donor + '\n2\t' + worktree + '\n', '99999999999999999999\t' + donor + '\n2\t' + worktree + '\n'] {
		mut refused := false
		du_total(bad, [donor, worktree]) or { refused = true }
		require(refused, 'malformed du accepted')!; count++
	}
	require(df_free('Filesystem 1024-blocks Used Available Capacity Mounted on\ndisk 3 1 2 1% /\n')! == 2, 'df parser control')!; count++
	for bad in ['disk 3 1 2 1% /\n', 'Filesystem x\ndisk 3 1 -2 1% /\n', 'Filesystem x\ndisk 3 1 9999999999999999 1% /\n'] {
		mut refused := false
		df_free(bad) or { refused = true }
		require(refused, 'malformed df accepted')!; count++
	}
	for m in [Metrics{live_kib - 1, 0, 0, 0}, Metrics{live_kib, kib_cap - observer_tail_kib + 1, 0, 0},
		Metrics{live_kib, 0, kib_cap - observer_tail_kib + 1, 0}, Metrics{live_kib, 0, 0, log_cap + 1}] {
		mut refused := false
		policy(m, false) or { refused = true }
		require(refused, 'resource boundary accepted')!; count++
	}
	policy(Metrics{live_kib, kib_cap - observer_tail_kib, kib_cap - observer_tail_kib, log_cap}, false)!; count++
	mut floor_refused := false
	policy(Metrics{admission_kib - 1, 0, 0, 0}, true) or { floor_refused = true }
	require(floor_refused, 'admission floor accepted')!; count++
	policy(Metrics{admission_kib, 0, 0, 0}, true)!; count++
	timing(sample_window, sample_window)!; count++
	for values in [[sample_window + 1, u64(0)]!, [u64(0), sample_window + 1]!] {
		mut refused := false
		timing(values[0], values[1]) or { refused = true }
		require(refused, 'timing boundary accepted')!; count++
	}
	require(retry_allowed(2, 0, sample_window) && !retry_allowed(3, 0, sample_window)
		&& !retry_allowed(1, sample_window, sample_window) && !retry_allowed(1, sample_window - 1, sample_window), 'retry boundary')!; count++
	deadline := time.sys_mono_now() + sample_window
	require(probe('transient', deadline, 'transient', mut watch)! == 'eventual\n', 'transient probe retry')!; count++
	mut persistent_refused := false
	probe('failure', time.sys_mono_now() + sample_window, 'persistent', mut watch) or { persistent_refused = true }
	probe_journal := os.read_file(watch.state + '/observations.jsonl')!
	require(persistent_refused && probe_journal.contains('persistent-2.json') && !probe_journal.contains('persistent-3.json')
		&& probe_journal.contains('raw failing stdout') && probe_journal.contains('raw failing stderr'), 'persistent probe retry/raw stream bound')!; count++
	sample(true, mut watch)!
	run_observed([os.executable(), '--control-worker'], mut watch)!
	require(watch.samples >= 4 && watch.max_gap_ms <= 5000 && os.file_size(watch.state + '/child.log') >= 512 * 1024,
		'native sampled direct-file output control')!; count++
	// The quiet child outlives the closed600ms control deadline. The same owner
	// must interrupt, retire/reap, preserve refusal and observe direct cleanup.
	quiet_state := watch.state + '/quiet'
	os.mkdir(quiet_state)!
	mut quiet := Watch{state: quiet_state, wall: 600 * u64(time.millisecond)}
	sample(true, mut quiet)!
	mut quiet_refused := false
	run_observed([os.executable(), '--control-quiet'], mut quiet) or { quiet_refused = err.msg().contains('wall deadline') }
	require(quiet_refused && quiet.pid > 1 && present(quiet_state + '/status.json'), 'actual quiet deadline refusal')!; count++
	// A fast child writes256KiB then exits before the first periodic sample.
	// Closed controls-only128KiB/path settings exercise final-sample refusal;
	// production keeps the four fixed roots and32MiB combined log cap.
	flood_state := watch.state + '/flood'
	os.mkdir(flood_state)!; os.write_file(flood_state + '/child.log', '')!
	mut flood := Watch{state: flood_state, wall: 5 * u64(time.second), log_limit: 128 * 1024,
		log_roots: [flood_state + '/child.log']}
	sample(true, mut flood)!
	mut flood_refused := false
	run_observed([os.executable(), '--control-flood'], mut flood) or { flood_refused = err.msg().contains('closed control log cap') }
	require(flood_refused && flood.observed_exit && flood.observed_status == 0 && present(flood_state + '/status.json'),
		'actual fast-exit final-sample log refusal')!; count++
	mut nested := Watch{state: watch.state}
	mut nested_refused := false
	sourcecommand.run_logged_owned([os.executable(), '--control-controller'], child_environment(), never,
		watch.state + '/nested.log', false, '', interrupt_nested, &nested, 10) or { nested_refused = err.msg() == 'deliberate outer control refusal' }
	cleanup := direct_cleanup(nested.pid)!
	require(nested_refused, 'outer nested interruption control')!
	verify_inner(os.read_file(watch.state + '/inner-cleanup.json')!, nested.pid)!
	ready := json2.decode[map[string]string](os.read_file(watch.state + '/inner-ready.json')!)!
	require(ready['pid'] == ready['pgid'] && ready['pgid'] != nested.pid.str(), 'nested child must own separate PGID')!; count++
	mut absent_refused := false
	verify_inner('{}', nested.pid) or { absent_refused = true }
	require(absent_refused, 'missing inner cleanup receipt accepted')!; count++
	mut forged_refused := false
	verify_inner(json2.encode({'pid': nested.pid.str(), 'waitpid_result': '-1', 'waitpid_errno': int(C.ECHILD).str(),
		'group_probe_result': '-1', 'group_probe_errno': int(C.ESRCH).str()}), nested.pid) or { forged_refused = true }
	require(forged_refused, 'outer-only receipt accepted as separate inner cleanup')!; count++
	// Journal exhaustion still permits its independent fixed final receipt.
	full_state := watch.state + '/journal-boundary'
	os.mkdir(full_state)!
	mut full := Watch{state: full_state, journal_bytes: journal_cap}
	mut journal_refused := false
	journal(mut full, 'too-large', 'x') or { journal_refused = true }
	require(journal_refused, 'journal byte boundary accepted')!
	journal(mut full, 'status.json', '{"error":"control journal cap","cleanup":"no child launched"}\n')!
	require(present(full_state + '/status.json'), 'journal cap erased final refusal')!; count++
	journal(mut watch, 'controls.json', json2.encode({'controls': count.str(), 'status': 'PASS',
		'outer_direct_cleanup': json2.encode(cleanup), 'nested_scope': 'Explicit cooperative inner owner receipt required; outer PGID alone supplies no descendant cleanup claim.'}) + '\n')!
	println('FRESH ATOMIC NATIVE OBSERVER CONTROLS PASS ${count}')
}

fn run() ! {
	require(os.args.len == 2, 'one fixed mode required')!
	if os.args[1].starts_with('--probe-') { probe_child(os.args[1])!; return }
	if os.args[1] == '--control-worker' { control_worker(); return }
	if os.args[1] == '--control-quiet' { time.sleep(5 * time.second); return }
	if os.args[1] == '--control-flood' { control_flood(); return }
	if os.args[1] in ['--control-probe-transient', '--control-probe-failure'] {
		if os.args[1] == '--control-probe-transient' && present(observer + '/controls-01/probe-count') { println('eventual'); return }
		if os.args[1] == '--control-probe-transient' { os.write_file(observer + '/controls-01/probe-count', '1')! }
		println('raw failing stdout'); eprintln('raw failing stderr'); exit(7)
	}
	for signal in [os.Signal.int, .term, .hup] { os.signal_opt(signal, interrupt)! }
	match os.args[1] {
		'--controls' { controls()! }
		'--control-controller' { control_controller()! }
		'--build-03' { production()! }
		else { return error('unknown fixed mode') }
	}
}

fn main() { run() or { eprintln(err); exit(1) } }
