module main

import crypto.sha256
import json2
import nativeguard
import os
import time

#include <errno.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.alarm(seconds u32) u32
fn C.fork() int
fn C.getpgid(pid i32) i32
fn C.getppid() int

struct Passed {
	name string
	detail string
}

fn sha(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn child(mode string, out string) ! {
	C.alarm(15)
	if mode == '--child-fast' { print(json2.encode(os.args[3..])); return }
	if mode == '--child-loud' {
		text := 'LITERAL λ ' + 'x'.repeat(512 * 1024)
		mut sent := 0
		for sent < text.len {
			n := C.write(1, unsafe { text.str + sent }, usize(text.len - sent))
			if n < 0 && C.errno == C.EINTR { continue }
			if n <= 0 { return error('loud child write failed') }
			sent += int(n)
		}
		return
	}
	if mode == '--child-descendant' {
		pid := C.fork()
		if pid < 0 { return error('descendant fork failed') }
		if pid == 0 {
			C.alarm(15)
			os.write_file(out + '/descendant.pending', json2.encode({'pid': os.getpid(), 'pgid': int(C.getpgid(0))})) or { C._exit(73) }
			os.rename(out + '/descendant.pending', out + '/descendant.json') or { C._exit(74) }
			for { time.sleep(time.second) }
		}
		start := time.sys_mono_now()
		for !os.exists(out + '/descendant.json') {
			if time.sys_mono_now() - start > time.second { return error('descendant publication timed out') }
			time.sleep(time.millisecond)
		}
		if C.kill(pid, 0) != 0 || C.getpgid(i32(pid)) != C.getpgid(0) { return error('published descendant is not live in leader group') }
		return
	}
	if mode == '--child-cap' { os.write_file(out + '/payload', 'c'.repeat(256 * 1024))! }
	if mode == '--child-interrupt' { C.kill(C.getppid(), C.SIGTERM) }
	if mode !in ['--child-cap', '--child-interrupt', '--child-sleep'] { return error('unknown control child') }
	os.write_file(out + '/started', json2.encode({'pid': os.getpid(), 'ppid': int(C.getppid()),
		'uid': int(C.getuid()), 'euid': int(C.geteuid()), 'pgid': int(C.getpgid(0))}))!
	for { time.sleep(time.second) }
}

fn check_result(result nativeguard.Result, out string) ! {
	if !result.group_observed || !result.cleanup.reaped || !result.cleanup.group_empty ||
		result.cleanup.final_wait != -1 || result.cleanup.final_errno != C.ECHILD {
		return error('real cleanup/group barrier proof differs: ' + out)
	}
	for sample in result.samples {
		if !sample.df.cleanup.reaped || !sample.df.cleanup.group_empty || sample.df.cleanup.exit_code != 0 ||
			sample.df.cleanup.final_wait != -1 || sample.df.cleanup.final_errno != C.ECHILD {
			return error('separate actual df helper cleanup differs')
		}
	}
	os.write_file(out + '/result.json', json2.encode(result))!
}

fn observe(mode string, out string, wall int, cap u64, extra []string) !nativeguard.Result {
	os.mkdir(out)!
	nativeguard.watch_interrupts()!
	result := nativeguard.supervise([os.executable(), mode, out, ...extra], os.getwd(), out, [out], out + '/output.log', out + '/df',
		nativeguard.Limits{start_bytes: u64(550) << 20, floor_bytes: u64(256) << 20, cap_bytes: cap, wall_ms: wall, sample_ms: 20})!
	check_result(result, out)!
	return result
}

fn blocks(path string) !u64 {
	mut stat := C.stat{}
	if unsafe { C.lstat(&char(path.str), &stat) } != 0 || stat.st_blocks < 0 { return error('control lstat failed') }
	return u64(stat.st_blocks) * 512
}

fn run() ! {
	$if prod {} $else { return error('controls require -prod') }
	if os.args.len != 3 || !os.args[1].starts_with('--out=') || !os.args[2].starts_with('--supervisor=') { return error('use --out=ABS_NEW --supervisor=ABS_BINARY') }
	out := os.args[1].all_after('=')
	supervisor := os.args[2].all_after('=')
	if out != os.abs_path(out) || os.exists(out) || os.is_link(out) || supervisor != os.abs_path(supervisor) { return error('control paths differ') }
	os.mkdir(out)!
	mut pins := map[string]string{}
	for path in [@FILE, os.dir(@FILE) + '/nativeguard/guard.v', os.executable(), supervisor] { pins[path] = sha(path)! }
	os.write_file(out + '/pins-before.json', json2.encode(pins))!
	mut passed := []Passed{}
	nativeguard.watch_interrupts()!
	df := nativeguard.actual_df(out, out + '/admission-df.log')!
	if df.available < u64(550) << 20 || !df.cleanup.reaped || !df.cleanup.group_empty || df.cleanup.final_errno != C.ECHILD { return error('actual df start or cleanup differs') }
	os.write_file(out + '/admission.json', json2.encode(df))!
	passed << Passed{'real-direct-df-cleanup', 'actual volume parse and independent group barrier, raw wait/ECHILD, group absence'}
	valid := 'Filesystem 1024-blocks Used Available Capacity iused ifree %iused Mounted on\n/dev/disk3s5 9000 1000 8000 10% 1 2 1% /System/Volumes/Data\n'
	if nativeguard.parse_df(valid)! != 8000 * 1024 { return error('df KiB conversion differs') }
	for bad in [valid.replace('1024-blocks', '512-blocks'), valid.replace('/dev/disk3s5', '/dev/other'),
		valid.replace('8000', '-1'), valid.replace('8000', '18446744073709551615'), valid + valid] {
		mut refused := false
		nativeguard.parse_df(bad) or { refused = true }
		if !refused { return error('invalid actual df accepted') }
	}
	passed << Passed{'df-format-volume-overflow-refusals', 'exact byte conversion; five malformed or other-volume observations refused'}
	limits := nativeguard.Limits{start_bytes: 100, floor_bytes: 80, cap_bytes: 200, wall_ms: 10}
	if nativeguard.refusal(80, 200, 9, limits) != '' || nativeguard.refusal(79, 200, 9, limits) != 'actual df below shared floor' ||
		nativeguard.refusal(80, 201, 9, limits) != 'namespace allocation cap exceeded' || nativeguard.refusal(80, 200, 10, limits) != 'outer wall deadline exceeded' { return error('boundary decisions differ') }
	passed << Passed{'budget-and-deadline-boundaries', 'floor and cap exact equality accepts, one-byte violation refuses; exact deadline expires'}
	for mode in ['space', 'allocation'] {
		admission_out := out + '/refuse-' + mode
		os.mkdir(admission_out)!
		os.write_file(admission_out + '/existing', 'x'.repeat(8192))!
		mut reason := ''
		nativeguard.supervise([os.executable(), '--child-sleep', admission_out], os.getwd(), admission_out, [admission_out], admission_out + '/output.log', admission_out + '/df',
			nativeguard.Limits{start_bytes: if mode == 'space' { ~u64(0) } else { u64(550) << 20 }, floor_bytes: u64(256) << 20,
				cap_bytes: if mode == 'allocation' { u64(1) } else { u64(2) << 20 }, wall_ms: 5000}) or { reason = err.msg() }
		expected_reason := if mode == 'space' { 'fresh actual df below start admission' } else { 'initial namespace exceeds cap' }
		if reason != expected_reason || os.exists(admission_out + '/started') || os.exists(admission_out + '/output.log') || os.exists(admission_out + '/output.log.barrier.json') { return error('prelaunch admission did not refuse without main child') }
		os.write_file(admission_out + '/refusal.json', json2.encode({'reason': reason, 'main_child_artifacts_absent': 'true'}))!
		passed << Passed{'prelaunch-' + mode + '-refusal', 'real df helper cleaned; main child log/barrier/marker absent after exact admission refusal'}
	}
	inside := out + '/allocated'
	os.mkdir(inside)!
	os.write_file(out + '/outside', 'o'.repeat(64 * 1024))!
	os.write_file(inside + '/small', 'x')!
	mut sparse := os.create(inside + '/sparse')!
	if C.ftruncate(sparse.fd, 8 * 1024 * 1024) != 0 { return error('sparse truncate failed') }
	sparse.close()
	os.symlink(out + '/outside', inside + '/external-link')!
	expected := blocks(inside)! + blocks(inside + '/small')! + blocks(inside + '/sparse')! + blocks(inside + '/external-link')!
	if nativeguard.allocated([inside], os.lstat(out)!.dev)! != expected || expected >= 8 * 1024 * 1024 { return error('nofollow sparse allocation differs') }
	passed << Passed{'sparse-and-external-symlink-allocation', 'exact lstat block sum includes directory/link, follows no external referent, ignores sparse logical zeros'}
	for i in 0 .. 10 {
		extra := ['', 'λ;$(literal)', '--file', 'space value']
		result := observe('--child-fast', out + '/fast-' + i.str(), 5000, u64(2) << 20, extra)!
		if result.reason != '' || result.cleanup.exit_code != 0 || os.read_file(out + '/fast-' + i.str() + '/output.log')! != json2.encode(extra) { return error('fast exact-vector child differs') }
	}
	passed << Passed{'ten-fast-gated-literal-executions', 'every child observed its own group before release; exact empty/Unicode/metacharacter/flag/space argv retained'}
	loud := observe('--child-loud', out + '/loud', 5000, u64(2) << 20, [])!
	if loud.reason != '' || loud.cleanup.exit_code != 0 || os.read_file(out + '/loud/output.log')! != 'LITERAL λ ' + 'x'.repeat(512 * 1024) { return error('loud draining differs') }
	passed << Passed{'loud-nonblocking-output', '512KiB payload retained byte-for-byte without pipe deadlock'}
	deadline := observe('--child-sleep', out + '/deadline', 100, u64(2) << 20, [])!
	if deadline.reason != 'outer wall deadline exceeded' || deadline.cleanup.exit_code != 137 || !os.exists(out + '/deadline/started') { return error('actual deadline termination differs') }
	deadline_identity := json2.decode[map[string]int](os.read_file(out + '/deadline/started')!)!
	if deadline_identity['pid'] != deadline.cleanup.pid || deadline_identity['pgid'] != deadline.cleanup.pid ||
		deadline_identity['uid'] != os.getuid() || deadline_identity['euid'] != os.geteuid() { return error('deadline child credentials/group differ') }
	passed << Passed{'real-wall-timeout', 'live started child killed, actual leader reaped and group absent'}
	cap := observe('--child-cap', out + '/cap', 3000, u64(64) << 10, [])!
	if cap.reason != 'namespace allocation cap exceeded' || cap.cleanup.exit_code != 137 || os.file_size(out + '/cap/payload') != 256 * 1024 { return error('actual allocation refusal differs') }
	passed << Passed{'real-allocation-cap', 'child wrote256KiB; sampled64KiB cap refused and cleaned actual process'}
	descendant := observe('--child-descendant', out + '/descendant', 5000, u64(2) << 20, [])!
	identity := json2.decode[map[string]int](os.read_file(out + '/descendant/descendant.json')!)!
	if descendant.reason != 'leader exited with remaining inherited-group members' || !descendant.held_pipe_after_leader_exit || descendant.cleanup.exit_code != 0 || identity['pgid'] != descendant.cleanup.pid || C.kill(identity['pid'], 0) != -1 || C.errno != C.ESRCH { return error('early leader descendant cleanup differs') }
	passed << Passed{'early-leader-held-pipe-descendant', 'leader exited0; intended inherited-group live descendant held pipe; refusal then ESRCH without hanging'}
	interruption := observe('--child-interrupt', out + '/interrupt', 5000, u64(2) << 20, [])!
	if !interruption.reason.starts_with('outer interruption signal=') || interruption.cleanup.exit_code != 137 { return error('actual signal cleanup differs') }
	for suffix in ['', '.barrier.json', '.barrier-cleanup.json', '.cleanup.json'] { if os.exists(out + '/interrupt/df.final' + suffix) { return error('sticky cancellation released final df helper') } }
	passed << Passed{'real-parent-sigterm', 'signal handler caused bounded child/group termination; sticky cancellation released no final df helper'}
	nativeguard.watch_interrupts()!
	refusal := nativeguard.supervise([supervisor, '--arbitrary-command'], os.getwd(), out, [out + '/profile'], out + '/profile.log', out + '/profile-df', nativeguard.Limits{start_bytes: u64(550) << 20, floor_bytes: u64(256) << 20, cap_bytes: u64(2) << 20, wall_ms: 5000})!
	if refusal.cleanup.exit_code != 1 || !os.read_file(out + '/profile.log')!.contains('arbitrary commands refused') { return error('arbitrary supervisor command accepted') }
	os.write_file(out + '/profile-result.json', json2.encode(refusal))!
	passed << Passed{'fixed-command-profile-refusal', 'real supervisor rejected arbitrary mode before native work'}
	for path, wanted in pins { if sha(path)! != wanted { return error('control source/tool changed') } }
	if passed.len != 13 { return error('control count differs') }
	os.write_file(out + '/results.json', json2.encode({'passed': 'true', 'count': passed.len.str(), 'controls': json2.encode(passed), 'pins': json2.encode(pins),
		'scope': 'Small host controls only, default host collector, no ASan/tracking/manualfree, no images/VM/native acceptance. Trusted numeric PGIDs; no detached-daemon guarantee.'}))!
	println('PASS13 bounded native supervisor host controls')
}

fn main() {
	if os.args.len >= 3 && os.args[1].starts_with('--child-') { child(os.args[1], os.args[2]) or { eprintln(err); exit(1) }; return }
	C.alarm(90)
	run() or { eprintln(err); exit(1) }
}
