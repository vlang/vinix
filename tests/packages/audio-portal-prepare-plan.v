// SPDX-License-Identifier: GPL-2.0-or-later
// Encode the maintained preparation runner's typed plan; never run a producer.
module main

import crypto.sha256
import json2
import os

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

fn C.open(&char, i32, ...int) i32
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32

// Keep this field order and these types identical to audio-portal-prepare-run.v.
struct Plan {
	format int
	profile string
	source_revision string
	state_root string
	audit_root string
	kernel_seal_sha256 string
	kernel_sha256 string
	roots map[string]string
	files map[string]string
mut:
	inputs map[string]map[string]string
	charged_roots []string
	cap_bytes u64
	prepare_wall_ms int
}

fn bounded(path string, expected string) !string {
	before := os.lstat(path)!
	if before.mode & 0o170000 != 0o100000 || before.size > u64(32) << 20 {
		return error('requires a regular input of at most32MiB')
	}
	text := os.read_file(path)!
	after := os.lstat(path)!
	if before.dev != after.dev || before.inode != after.inode || before.mode != after.mode
		|| before.uid != after.uid || before.gid != after.gid || before.size != after.size
		|| before.nlink != after.nlink || before.mtime != after.mtime
		|| before.ctime != after.ctime || sha256.hexhash(text) != expected {
		return error('input changed or SHA256 differs')
	}
	return text
}

fn encode() ! {
	if os.args.len != 6 { return error('use TEMPLATE SHA256 INPUTS|- SHA256|- NEW_PLAN') }
	text := bounded(os.args[1], os.args[2])!
	mut plan := json2.decode[Plan](text, strict: true)!
	if text != json2.encode(plan) + '\n' || plan.inputs.len != 0 {
		return error('template must be the exact canonical typed Plan with empty inputs')
	}
	if os.args[3] == '-' {
		if os.args[4] != '-' { return error('empty inputs require both dash arguments') }
	} else {
		input_text := bounded(os.args[3], os.args[4])!
		inputs := json2.decode[map[string]map[string]string](input_text, strict: true)!
		canonical := json2.encode(inputs)
		if input_text != canonical && input_text != canonical + '\n' {
			return error('inspection inputs must retain their exact canonical representation')
		}
		mut expected := []string{}
		for role, _ in plan.roots { expected << 'tree:' + role }
		for role, _ in plan.files { expected << 'file:' + role }
		mut actual := inputs.keys()
		expected.sort()
		actual.sort()
		if expected != actual { return error('inspection input roles differ from template') }
		plan.inputs = inputs
	}
	output := json2.encode(plan) + '\n'
	if output.len > 32 * 1024 * 1024 { return error('encoded Plan exceeds32MiB') }
	path := os.args[5]
	if !os.is_abs_path(path) || path.bytes().any(it < 32 || it == 127)
		|| os.real_path(os.dir(path)) != os.dir(path)
		|| os.lstat(os.dir(path))!.mode & 0o170000 != 0o040000 {
		return error('output requires an existing canonical ordinary parent')
	}
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, 0o600)
	if fd < 0 { return error('cannot exclusively create new Plan') }
	mut closed := false
	defer { if !closed { C.close(fd) } }
	mut offset := 0
	for offset < output.len {
		remaining := output.len - offset
		written := C.write(fd, unsafe { output.str + offset }, usize(remaining))
		if written < 0 && C.errno == C.EINTR { continue }
		if written <= 0 || written > isize(remaining) {
			return error('Plan write failed; preserve partial output')
		}
		offset += int(written)
	}
	closed = true
	if C.close(fd) != 0 { return error('Plan close failed; preserve output') }
	if os.read_file(path)! != output { return error('written Plan differs') }
	println(sha256.hexhash(output))
}

fn main() { encode() or { eprintln('audio-portal-prepare-plan: ' + err.msg()); exit(1) } }
