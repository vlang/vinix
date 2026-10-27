// SPDX-License-Identifier: GPL-2.0-or-later
// Profile credential-free controller poll fixtures with a hard RSS/time guard.
module main

import crypto.sha256
import json2
import os
import time

#include <sys/resource.h>
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>

struct C.rusage {
	ru_maxrss i64
}

fn C.wait4(int, &int, int, &C.rusage) int

const rss_limit = u64(1024 * 1024 * 1024)
const duration_limit = 60 * time.second

struct Profile {
	mode string
	controller_sha256 string
	exit_status int
	peak_rss_bytes u64
	sampled_peak_rss_bytes u64
	samples int
	elapsed_ms i64
	output string
}

fn wait_child(pid int, status &int, flags int, usage &C.rusage) int {
	for {
		result := C.wait4(pid, status, flags, usage)
		if result < 0 && C.errno == C.EINTR { continue }
		return result
	}
	return -1
}

fn profile(controller string, pin string, mode string) !Profile {
	mut child := os.new_process(controller)
	child.set_args([mode])
	child.set_redirect_stdio_merged()
	child.set_stdin_path('/dev/null')
	child.run()
	if child.pid <= 0 { return error('cannot spawn poll fixture') }
	defer { child.close() }
	started := time.sys_mono_now()
	mut usage := C.rusage{}
	mut status := 0
	mut sampled_peak := u64(0)
	mut samples := 0
	mut failure := ''
	for {
		finished := wait_child(child.pid, &status, 1, &usage)
		if finished == child.pid { break }
		if finished < 0 { failure = 'wait4 failed'; break }
		if time.sys_mono_now() - started > duration_limit {
			failure = 'fixture exceeded 60 second guard'
			break
		}
		selected := os.exec(['/bin/ps', '-o', 'rss=', '-p', child.pid.str()])
		if selected.exit_code == 0 {
			text := selected.output.trim_space()
			if text != '' && text.bytes().all(it >= `0` && it <= `9`) {
				rss := text.u64() * 1024
				if rss > sampled_peak { sampled_peak = rss }
				samples++
				if rss > rss_limit { failure = 'fixture exceeded 1 GiB RSS guard'; break }
			}
		}
		time.sleep(20 * time.millisecond)
	}
	if failure != '' {
		C.kill(child.pid, 9)
		if wait_child(child.pid, &status, 0, &usage) != child.pid {
			return error('cannot reap guarded fixture: ' + mode)
		}
	}
	child.status = .exited
	output := child.stdout_slurp()
	mut peak := u64(usage.ru_maxrss)
	$if !macos { peak *= 1024 }
	if failure != '' { return error(failure + ': ' + mode) }
	if status != 0 || peak > rss_limit || output.len > 65536 {
		return error('poll fixture failed or exceeded its final bound: ' + mode)
	}
	return Profile{
		mode: mode
		controller_sha256: pin
		exit_status: status
		peak_rss_bytes: peak
		sampled_peak_rss_bytes: sampled_peak
		samples: samples
		elapsed_ms: (time.sys_mono_now() - started) / time.millisecond
		output: output
	}
}

fn run(controller string, destination string) ! {
	if os.real_path(controller) != controller || !os.is_file(controller)
		|| os.exists(destination) || os.is_link(destination) {
		return error('canonical controller and fresh result path required')
	}
	pin := sha256.sum256(os.read_bytes(controller)!).hex()
	baseline := profile(controller, pin, '--poll-memory-baseline')!
	fixed := profile(controller, pin, '--poll-memory-self-test')!
	if !baseline.output.starts_with('MAPS-ACCOUNT-POLL-MEMORY-BASELINE iterations=4096 ')
		|| !fixed.output.starts_with('MAPS-ACCOUNT-POLL-MEMORY-PASS iterations=18000 ') {
		return error('poll fixture completion evidence differs')
	}
	if sha256.sum256(os.read_bytes(controller)!).hex() != pin {
		return error('profiled executable changed')
	}
	os.write_file(destination, json2.encode([baseline, fixed], prettify: true) + '\n')!
	println('MAPS-ACCOUNT-POLL-PROFILE-PASS baseline_rss=${baseline.peak_rss_bytes} fixed_rss=${fixed.peak_rss_bytes} limit=${rss_limit}')
}

fn main() {
	if os.args.len != 3 {
		eprintln('usage: maps-account-poll-profile CANONICAL_CONTROLLER FRESH_RESULT_JSON')
		exit(2)
	}
	run(os.args[1], os.args[2]) or { eprintln(err); exit(1) }
}
