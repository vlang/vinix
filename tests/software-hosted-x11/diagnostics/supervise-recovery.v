module main

// Fixed failed diagnostic scopes; source and build pins are reviewed separately.
import os
import json2
import crypto.sha256
import strconv
import time
import recoveryguard

fn C.getpgid(pid i32) i32

const state = '/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a'
const source_dir = '/Users/alex/code/vinix/build/package-hosted-launch-options-guest-worktree/tests/software-hosted-x11/diagnostics'

struct Observation {
	mono_ns i64
	available_bytes u64
	archive_bytes u64
	df_output string
}

struct FixedScope {
	name string
	stem string
	flag string
}

fn sha(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut h := sha256.new()
	defer { unsafe { h.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := f.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		h.write(buffer[..n])!
	}
	return h.sum([]u8{}).hex()
}

fn actual_df() !(u64, string) {
	mut p := os.new_process('/bin/df')
	defer { p.close() }
	p.set_args(['-k', state]); p.set_redirect_stdio_merged(); p.use_pgroup = true; p.run()
	C.close(p.stdio_fd[0]); p.stdio_fd[0] = -1
	start := time.sys_mono_now()
	for p.is_alive() {
		if recoveryguard.deadline_expired(start, 5000) {
			recoveryguard.terminate_group(mut p, 5000)!
			return error('actual df deadline exceeded')
		}
		time.sleep(10 * time.millisecond)
	}
	p.wait()
	text := p.stdout_slurp()
	lines := text.trim_space().split_into_lines()
	if p.code != 0 || lines.len != 2 || !lines[0].contains('1024-blocks') { return error('actual df failed or format differs: ' + text) }
	fields := lines[1].fields()
	if fields.len != 9 || fields[0] != '/dev/disk3s5' || fields[8] != '/System/Volumes/Data' { return error('actual df volume or columns differ: ' + text) }
	kib := strconv.parse_uint(fields[3], 10, 64)!
	if kib > u64(18446744073709551615) / 1024 { return error('df overflow') }
	return kib * 1024, text
}

fn sample(archive string) !Observation {
	available, text := actual_df()!
	bytes := if os.exists(archive) { u64(os.lstat(archive)!.size) } else { u64(0) }
	return Observation{time.sys_mono_now(), available, bytes, text}
}

fn drain_stdout(mut p os.Process, mut log os.File) ! {
	// Bound each monitoring step even if an unexpected producer floods output.
	for _ in 0 .. 16 {
		chunk := p.stdout_read()
		if chunk.len == 0 { break }
		log.write_string(chunk)!
	}
}

fn run() ! {
	if os.args.len != 2 { return error('expected exact native02 or arm03 scope') }
	scope := match os.args[1] {
		'--native02' { FixedScope{'native-x86_64-02', 'archive-native02', '--reclaim-reviewed-native02'} }
		'--arm03' { FixedScope{'native-aarch64-03', 'archive-arm03', '--reclaim-reviewed-arm03'} }
		else { return error('unreviewed scope') }
	}
	prefix := state + '/failed-diagnostics/' + scope.name
	binary := state + '/' + scope.stem + '-01'
	source := source_dir + '/' + scope.stem + '.v'
	expected := if scope.stem == 'archive-native02' {
		map[string]string{source: '8f633f855c8470d415c39958d5ab27d913f323008eb17329257360f24b4092ba', binary: 'e449ead64359a1929e81816cf2934b41425a0d8d212ee5965178d3d432f67859', state + '/archive-native02-build-01.json': '63b0a776420146dc69da5c0014716ad61414d15429bb6313948fce5eea6ceeb9'}
	} else {
		map[string]string{source: '18dacd1796e44cb4c9cf541cb9d1c20e41f55966a34f65755a2712e5087b5be9', binary: '79cf22ebd4ac39527dd4768dd3d629ca65fe1ec85b5d82226ab0a50079e2de31', state + '/archive-arm03-build-01.json': '84388776863d8606c318442a02bd04b300081d6d579ece6f4cb6615c470cc5cf'}
	}
	for path, wanted in expected { if sha(path)! != wanted { return error('reviewed binding unavailable or changed: ' + path) } }
	guard_source := source_dir + '/recoveryguard/recoveryguard.v'
	guard_hash := sha(guard_source)!
	if guard_hash != '85859c002c42ba44e944ca7b80d1894c27150669e89fa98bd0f4438ae5fa8517' { return error('reviewed shared guard source changed') }
	if os.exists(prefix + '-supervision-01.json') || os.exists(prefix + '-supervision-01.log') || os.exists(prefix + '-supervision-01.argv.json') { return error('requires new supervision outputs') }
	initial := sample(prefix + '.tar.gz')!
	if initial.available_bytes < (u64(550) << 20) { return error('fresh actual df below550MiB gate') }
	if initial.archive_bytes != 0 { return error('archive already exists') }
	args := [binary, scope.flag]
	os.write_file(prefix + '-supervision-01.argv.json', json2.encode(args))!
	os.setenv('VINIX_FAILED_RECOVERY_SUPERVISION', 'actual-df-k-256MiB-v1', true)
	mut p := os.new_process(binary)
	mut cleaned := false
	mut group_confirmed := false
	defer {
		if !cleaned { recoveryguard.terminate_group(mut p, 5000) or { eprintln(recoveryguard.bounded_message(err.msg())) } }
		p.close()
	}
	mut log := os.create(prefix + '-supervision-01.log')!
	defer { log.close() }
	started := time.sys_mono_now()
	p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.use_pgroup = true; p.run()
	C.close(p.stdio_fd[0]); p.stdio_fd[0] = -1
	for _ in 0 .. 100 {
		if C.getpgid(i32(p.pid)) == i32(p.pid) { group_confirmed = true; break }
		if !p.is_alive() { break }
		time.sleep(10 * time.millisecond)
	}
	mut reason := if group_confirmed { '' } else { 'process group establishment was not observed' }
	mut observations := [initial]
	for reason == '' {
		drain_stdout(mut p, mut log) or { reason = err.msg(); break }
		if recoveryguard.deadline_expired(started, 30 * 60 * 1000) {
			reason = 'bounded30minute recovery wall deadline exceeded'
			break
		}
		current := sample(prefix + '.tar.gz') or { reason = err.msg(); break }
		observations << current
		if current.available_bytes < (u64(256) << 20) || current.archive_bytes > (u64(210) << 20) {
			reason = 'observed actual df floor or archive bound breached'
			break
		}
		if !p.is_alive() {
			remaining := recoveryguard.group_present(p.pid) or { reason = err.msg(); break }
			if remaining { reason = 'leader exited with remaining process-group members' }
			break
		}
		time.sleep(200 * time.millisecond)
	}
	// Raw PGID cleanup is effective even after is_alive() reaps the leader.
	mut cleanup_error := ''
	recoveryguard.terminate_group(mut p, 5000) or { cleanup_error = err.msg() }
	if cleanup_error == '' {
		cleaned = true
		log.write_string(p.stdout_slurp())!
	} else { reason += '; ' + cleanup_error }
	log.close()
	// Final binding refusal is part of the retained receipt, not a later error.
	for path, wanted in expected {
		actual := sha(path) or { reason += '; final binding unreadable: ' + path; continue }
		if actual != wanted { reason += '; final binding changed: ' + path }
	}
	if (sha(guard_source) or { '' }) != guard_hash { reason += '; shared guard source changed' }
	mut pins := expected.clone()
	pins[guard_source] = guard_hash
	for path in [@FILE, os.executable(), prefix + '-supervision-01.argv.json', prefix + '-supervision-01.log'] { pins[path] = sha(path)! }
	os.write_file(prefix + '-supervision-01.json', json2.encode({
		'code': p.code.str(), 'guard_refusal': reason, 'process_group_observed': group_confirmed.str(),
		'group_empty_and_leader_reaped': cleaned.str(),
		'pins': json2.encode(pins), 'observations': json2.encode(observations),
		'scope': 'Exact failed diagnostic only; actual df-k samples,550MiB start,256MiB abort floor,210MiB archive bound,30minute wall deadline. Discrete observations, not continuous enforcement. No native staging.'
	}))!
	if p.code != 0 || reason != '' { return error('recovery refused; failure outputs retained') }
	println('PASS fixed failed diagnostic supervisor completed: ' + scope.name)
}

fn main() { run() or { eprintln(recoveryguard.bounded_message(err.msg())); exit(1) } }
