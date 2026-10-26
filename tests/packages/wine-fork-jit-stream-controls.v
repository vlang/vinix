// SPDX-License-Identifier: GPL-2.0-or-later
// Native host plumbing controls. No translator, guest or target staging.
module main

import crypto.sha256
import json2
import os
import time
import tools.packages.winejitstream

#include <unistd.h>

fn C.write(int, voidptr, usize) isize
fn C.fork() int
fn C.getpid() int
fn C.kill(int, int) int

fn tree_bytes(directory string) !u64 {
	mut total := u64(0)
	for name in os.ls(directory)! {
		path := directory + '/' + name
		info := os.lstat(path)!
		if info.get_filetype() == .directory {
			total += tree_bytes(path)!
		} else if info.get_filetype() == .regular {
			total += info.size
		} else {
			return error('unexpected control artifact type')
		}
	}
	return total
}

fn require_free(directory string) ! {
	// V's macOS disk_usage currently multiplies by f_bsize instead of f_frsize.
	// Use the completed system df reading, in KiB, for this execution guard.
	mut process := os.new_process('/bin/df')
	defer { process.close() }
	process.set_args(['-k', directory])
	process.set_redirect_stdio_merged()
	process.run()
	C.close(process.stdio_fd[0])
	process.stdio_fd[0] = -1
	reading := process.stdout_slurp()
	process.wait()
	if process.code != 0 { return error('free-space reading failed') }
	lines := reading.trim_space().split_into_lines()
	if lines.len < 2 { return error('incomplete df reading') }
	fields := lines.last().split_any(' \t').filter(it != '')
	if fields.len < 6 || fields[3] == '' { return error('invalid df reading') }
	for digit in fields[3] {
		if digit < `0` || digit > `9` { return error('invalid df available field') }
	}
	if fields[3].u64() < 500 * 1024 { return error('requires at least 500MiB available') }
}

fn bounds(directory string) ! {
	require_free(directory)!
	if tree_bytes(directory)! > 20 * 1024 * 1024 { return error('observed state exceeds 20MiB') }
}

fn need(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn native_pid(log string, role string) !int {
	lines := log.split_into_lines()
	if lines.len != 2 { return error('native control requires only ready and arithmetic lines') }
	prefix := 'JITSTREAM READY ' + role + ' pid='
	if !lines[0].starts_with(prefix) { return error('missing native branch readiness') }
	text := lines[0][prefix.len..]
	pid := text.int()
	if pid <= 0 || pid.str() != text || lines[1] != 'JITSTREAM ARITHMETIC ' + role + ' PASS pid=' + text {
		return error('native branch PID or arithmetic marker differs')
	}
	return pid
}

fn checker_controls(checker string, directory string) !map[string]string {
	mut results := map[string]string{}
	parent := 'JITSTREAM READY parent pid=123\n0x1000:  d503201f  nop\nJITSTREAM ARITHMETIC parent PASS pid=123\n'
	child := 'JITSTREAM READY child pid=124\n0x1000:  d65f03c0  ret\nJITSTREAM ARITHMETIC child PASS pid=124\n'
	os.write_file(directory + '/parent.txt', parent)!
	os.write_file(directory + '/child.txt', child)!
	mut record := winejitstream.Run{
		leader_pid:  123
		wait_status: 0
		stopped:     true
		startup:     'JITSTREAM ORDINARY uid/gid=1000 groups=0 no-WX PASS\n'
		parent:      parent
		child:       child
	}
	for name in ['direct', 'serial', 'missing-ready', 'same-pid', 'cleanup', 'leader-pid'] {
		bounds(directory)!
		capture_dir := directory + '/' + name
		os.mkdir(capture_dir)!
		report := capture_dir + '/report.json'
		mut checker_arguments := []string{}
		if name == 'direct' {
			checker_arguments = [directory + '/parent.txt', directory + '/child.txt', report]
		} else {
			record = winejitstream.Run{
				...record
				stopped:    name != 'cleanup'
				leader_pid: if name == 'leader-pid' { 125 } else { 123 }
				parent:     if name == 'missing-ready' {
					'0x1000:  d503201f  nop\n'
				} else {
					parent
				}
				child:      if name == 'same-pid' {
					child.replace('pid=124', 'pid=123')
				} else {
					child
				}
			}
			serial := capture_dir + '/serial.txt'
			os.write_file(serial, 'JITSTREAM CAPTURE ' + json2.encode(record) + '\n')!
			checker_arguments = ['--serial', serial, report]
		}
		mut command := [checker]
		command << checker_arguments
		captured := winejitstream.capture(command, capture_dir, false, 1000)!
		need(captured.stopped && !captured.timed_out && !captured.size_limited, 'offline checker was not bounded')!
		if name in ['direct', 'serial'] {
			need(captured.wait_status == 0, 'offline checker refused valid fixed fixture')!
			summary := json2.decode[map[string]string](os.read_file(report)!)!
			comparison := json2.decode[winejitstream.Comparison](summary['comparison'])!
			need(comparison.overlapping_addresses == 1 && comparison.differing_addresses == 1
				&& summary['capture_incomplete'] == (name == 'direct').str(), 'offline comparison or completion scope differs')!
		} else {
			need(captured.wait_status != 0 && !os.exists(report), 'offline checker admitted invalid capture')!
		}
		results['offline-' + name] = 'PASS'
	}
	return results
}

fn controls() ! {
	if os.args.len != 4 {
		return error('usage: wine-fork-jit-stream-controls NATIVE_PROBE OFFLINE_CHECKER NEW_OUTPUT')
	}
	if sha256.hexhash(os.read_file(@FILE)!) != sha256.hexhash($embed_file('wine-fork-jit-stream-controls.v').to_string()) {
		return error('compiled controls source differs')
	}
	probe := os.real_path(os.args[1])
	checker := os.real_path(os.args[2])
	output := os.abs_path(os.args[3])
	if os.exists(output) || os.is_link(output) { return error('control output exists') }
	require_free(os.dir(output))!
	os.mkdir(output)!
	mut results := map[string]string{}
	for name in ['native', 'timeout', 'size', 'exec-refusal', 'existing-refusal'] {
		os.mkdir(output + '/' + name)!
	}
	native_dir := output + '/native'
	native := winejitstream.capture([probe, native_dir + '/parent.log', native_dir + '/child.log'], native_dir, false, 10000)!
	need(native.stopped && native.wait_status == 0 && !native.timed_out && !native.size_limited, 'native fork capture failed')!
	parent_pid := native_pid(native.parent, 'parent')!
	child_pid := native_pid(native.child, 'child')!
	need(parent_pid == native.leader_pid && child_pid != parent_pid, 'branches did not retain distinct process identities')!
	mut refused := false
	winejitstream.parse(native.parent, 'parent') or {
		refused = true
		winejitstream.Capture{}
	}
	need(refused, 'native markers without translator instructions were admitted')!
	results['native-fork-redirection-and-arithmetic'] = 'PASS'
	results['native-log-without-emitted-instructions-refused'] = 'PASS'
	os.write_file(output + '/native.json', json2.encode(native))!
	bounds(output)!
	timed := winejitstream.capture([os.executable(), '--hang'], output + '/timeout', false, 250)!
	need(timed.timed_out && timed.stopped && timed.wait_status != 0, 'runtime bound did not stop the process group')!
	prefix := 'JITSTREAM HANG descendant pid='
	need(timed.startup.starts_with(prefix), 'timeout control did not fork its descendant')!
	child_text := timed.startup[prefix.len..].trim_space()
	descendant := child_text.int()
	need(descendant > 0 && descendant.str() == child_text && descendant != timed.leader_pid
		&& C.kill(descendant, 0) < 0 && C.errno == C.ESRCH, 'timeout descendant survived cleanup')!
	results['runtime-group-bound'] = 'PASS'
	os.write_file(output + '/timeout.json', json2.encode(timed))!
	bounds(output)!
	limited := winejitstream.capture([os.executable(), '--flood'], output + '/size', false, 3000)!
	need(limited.stopped && limited.size_limited && limited.startup.len == winejitstream.log_limit
		&& limited.wait_status != 0, 'hard file-size bound failed')!
	results['hard-per-file-byte-bound'] = 'PASS'
	// Keep only the fixed-size file and a compact summary; avoid duplicating it.
	os.write_file(output + '/size.json', json2.encode({
		'wait_status':   limited.wait_status
		'startup_bytes': limited.startup.len
	}))!
	bounds(output)!
	failed := winejitstream.capture([output + '/does-not-exist'], output + '/exec-refusal', false, 1000)!
	need(failed.stopped && failed.wait_status == (125 << 8), 'exec refusal was not bounded and reaped')!
	results['exec-refusal-reaped'] = 'PASS'
	os.write_file(output + '/existing-refusal/parent.log', 'retain')!
	refused = false
	winejitstream.capture([probe], output + '/existing-refusal', false, 1000) or {
		refused = true
		winejitstream.Run{}
	}
	need(refused && os.read_file(output + '/existing-refusal/parent.log')! == 'retain', 'existing log refusal changed evidence')!
	results['existing-log-refused-without-mutation'] = 'PASS'
	os.mkdir(output + '/offline')!
	for name, result in checker_controls(checker, output + '/offline')! { results[name] = result }
	os.write_file(output + '/results.json', json2.encode({
		'results':                  json2.encode(results)
		'controller_source_sha256': sha256.hexhash(os.read_file(@FILE)!)
		'controller_binary_sha256': sha256.sum(os.read_bytes(os.executable())!).hex()
		'probe_binary_sha256':      sha256.sum(os.read_bytes(probe)!).hex()
		'checker_binary_sha256':    sha256.sum(os.read_bytes(checker)!).hex()
		'scope':                    'Native host fork/logging, arithmetic and supervisor controls only; no QEMU, ARM guest, shared JIT or Wine qualification.'
	}))!
	bounds(output)!
	println('PASS ' + results.len.str() + ' host JIT-stream controls')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--hang' {
		pid := C.fork()
		if pid < 0 { exit(92) }
		if pid == 0 {
			text := 'JITSTREAM HANG descendant pid=' + C.getpid().str() + '\n'
			if C.write(1, text.str, usize(text.len)) != text.len { exit(93) }
		}
		for { time.sleep(time.second) }
	}
	if os.args.len == 2 && os.args[1] == '--flood' {
		chunk := 'X'.repeat(4096)
		for { if C.write(2, chunk.str, usize(chunk.len)) <= 0 { exit(91) } }
	}
	controls() or {
		eprintln(err.msg())
		exit(1)
	}
}
