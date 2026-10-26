// SPDX-License-Identifier: GPL-2.0-or-later
// Offline comparison only: no guest launch, target staging or qualification.
module main

import crypto.sha256
import json2
import os
import tools.packages.winejitstream

fn bounded_read(path string, limit int) !string {
	before := os.lstat(path)!
	if before.get_filetype() != .regular || before.size > u64(limit) {
		return error('requires bounded ordinary input')
	}
	text := os.read_file(path)!
	after := os.lstat(path)!
	if after.get_filetype() != .regular || after.dev != before.dev || after.inode != before.inode
		|| after.size != before.size || text.len > limit {
		return error('input changed while reading')
	}
	return text
}

fn check() ! {
	if os.args.len != 4 {
		return error('usage: wine-fork-jit-stream-check PARENT_LOG CHILD_LOG NEW_REPORT or --serial SERIAL_LOG NEW_REPORT')
	}
	output := os.args[3]
	if os.exists(output) || os.is_link(output) { return error('report already exists') }
	mut parent := ''
	mut child := ''
	mut status := -1
	mut incomplete := true
	mut leader_pid := 0
	mut input_pins := map[string]string{}
	if os.args[1] == '--serial' {
		// Three bounded logs can each expand sixfold through JSON escaping.
		serial := bounded_read(os.args[2], 24 * winejitstream.log_limit)!
		input_pins[os.args[2]] = sha256.hexhash(serial)
		mut records := []string{}
		for line in serial.split_into_lines() {
			if line.starts_with('JITSTREAM CAPTURE ') {
				records << line['JITSTREAM CAPTURE '.len..]
			}
		}
		if records.len != 1 { return error('requires exactly one complete capture record') }
		result := json2.decode[winejitstream.Run](records[0])!
		if !result.stopped || result.leader_pid <= 0 || result.wait_status < 0
			|| result.startup.len > winejitstream.log_limit
			|| result.parent.len > winejitstream.log_limit || result.child.len > winejitstream.log_limit {
			return error('unconfirmed cleanup or oversized capture')
		}
		if !result.startup.contains('JITSTREAM ORDINARY uid/gid=1000 groups=0 no-WX PASS\n') {
			return error('missing ordinary identity marker')
		}
		parent = result.parent
		child = result.child
		status = result.wait_status
		leader_pid = result.leader_pid
		incomplete = result.timed_out || result.size_limited || result.wait_status != 0
	} else {
		parent = bounded_read(os.args[1], winejitstream.log_limit)!
		child = bounded_read(os.args[2], winejitstream.log_limit)!
		input_pins[os.args[1]] = sha256.hexhash(parent)
		input_pins[os.args[2]] = sha256.hexhash(child)
	}
	parsed_parent := winejitstream.parse(parent, 'parent')!
	parsed_child := winejitstream.parse(child, 'child')!
	if os.args[1] == '--serial' && parsed_parent.pid != leader_pid {
		return error('parent readiness PID differs from captured translator leader')
	}
	comparison := winejitstream.compare(parsed_parent, parsed_child)!
	os.write_file(output, json2.encode({
		'format':                 '1'
		'comparison':             json2.encode(comparison)
		'input_sha256':           json2.encode(input_pins)
		'parent_log_sha256':      sha256.hexhash(parent)
		'child_log_sha256':       sha256.hexhash(child)
		'parent_arithmetic_pass': parsed_parent.arithmetic_pass.str()
		'child_arithmetic_pass':  parsed_child.arithmetic_pass.str()
		'wait_status':            status.str()
		'capture_incomplete':     incomplete.str()
		'scope':                  'PID-attributed emitted instruction words at RX virtual addresses only; no shared physical backing, temporal collision, failure cause, canonical fork, ARM or Wine qualification.'
	}))!
	println('JITSTREAM COMPARISON AVAILABLE (not workload qualification)')
}

fn main() {
	check() or {
		eprintln(err.msg())
		exit(1)
	}
}
