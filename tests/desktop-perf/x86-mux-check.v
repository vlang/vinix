// SPDX-License-Identifier: GPL-2.0-or-later
// Host-only QEMU monitor control: no kernel, disk, firmware or guest workload.
module main

import crypto.sha256
import json2
import os
import perfconsole
import sourcecommand
import time

fn never() bool { return false }
fn line(_ string, _ voidptr) !bool { return false }
fn require(ok bool, text string) ! { if !ok { return error(text) } }
fn command(argv []string) !string {
	r := sourcecommand.capture(argv, os.environ(), 10, 1024 * 1024, never)!
	if r.status != 0 { return error('observation failed: ' + argv.str() + r.stderr) }
	return r.stdout
}
fn size(text string, index int) !i64 {
	f := text.fields()
	if index >= f.len || f[index] == '' || f[index].len > 15 || !f[index].bytes().all(it >= `0` && it <= `9`) { return error('invalid size output') }
	return f[index].i64()
}
fn budget(state string, admission bool) !string {
	df := command(['/bin/df', '-k', os.dir(state)])!
	rows := df.trim_space().split_into_lines()
	if rows.len != 2 { return error('unexpected df rows') }
	free := size(rows[1], 3)!
	minimum := if admission { i64(2097152) } else { i64(1048576) }
	if free < minimum { return error('actual df below required floor') }
	mut du := ''
	if os.exists(state) {
		du = command(['/usr/bin/du', '-sk', state])!
		if size(du, 0)! > 65536 { return error('all-state charged size exceeds 64 MiB') }
	}
	return df + '\n' + du
}
fn hash(path string) !string {
	mut f := os.open(path)!; defer { f.close() }
	mut h := sha256.new(); defer { unsafe { h.free() } }
	mut b := []u8{len: 1024 * 1024}; defer { unsafe { b.free() } }
	for {
		n := f.read(mut b) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }; h.write(b[..n])!
	}
	return h.sum([]u8{}).hex()
}
fn inventory(path string, ancestors []string, mut values map[string]string) ! {
	if ancestors.len > 128 { return error('input nesting limit') }
	i := os.lstat(path)!
	values['mode:' + path] = i.mode.str()
	if i.get_filetype() == .regular { values[path] = hash(path)!; return }
	if i.get_filetype() == .symbolic_link {
		values['link:' + path] = os.readlink(path)!
		r := os.real_path(path)
		if r == '' || r == path || r in ancestors { return error('dangling/cyclic input') }
		values['resolved:' + path] = r
		inventory(r, ancestors, mut values)!; return
	}
	if i.get_filetype() != .directory { return error('special input') }
	r := os.real_path(path)
	if r in ancestors { return error('directory cycle') }
	mut next := ancestors.clone(); next << r
	mut names := os.ls(path)!; names.sort()
	for name in names { inventory(path + '/' + name, next, mut values)! }
}
fn no_children() !string {
	mut raw := i32(0)
	r := C.waitpid(-1, &raw, C.WNOHANG); saved := C.errno
	if r != -1 || saved != C.ECHILD { return error('child remains: ' + r.str()) }
	return 'waitpid(-1,WNOHANG)=-1;errno=ECHILD'
}
fn run() ! {
	if os.args.len != 5 { return error('usage: x86-mux-check NEW-STATE QEMU SOURCE-ROOT COMPLETE-V') }
	state := os.args[1]; qemu := os.real_path(os.args[2]); root := os.real_path(os.args[3]); compiler := os.real_path(os.args[4])
	if !state.starts_with('/') || os.real_path(os.dir(state)) != os.dir(state) || os.exists(state) || os.is_link(state) { return error('fresh canonical state required') }
	admission := budget(state, true)!
	os.mkdir(state)!
	os.write_file(state + '/budget-before.log', admission)!
	mut before := map[string]string{}
	for path in [qemu, os.executable(), os.dir(compiler), root + '/tests/desktop-perf/run-x86.v',
		root + '/tests/desktop-perf/x86-mux-check.v', root + '/tests/desktop-perf/perfconsole',
		root + '/tools/sourcecommand'] { inventory(path, [], mut before)! }
	os.write_file(state + '/inputs-before.json', json2.encode(before) + '\n')!
	os.write_file(state + '/environment.json', json2.encode(os.environ()) + '\n')!
	owner := perfconsole.own_commands(); defer { owner.close() }
	mut results := map[string]string{}
	for serial in ['mon:stdio', 'stdio'] {
		argv := [qemu, '-machine', 'none', '-nodefaults', '-display', 'none', '-serial', serial, '-S']
		name := if serial == 'stdio' { 'negative' } else { 'positive' }
		os.write_file(state + '/' + name + '.argv.json', json2.encode(argv) + '\n')!
		started := time.sys_mono_now()
		output := perfconsole.capture(argv, os.environ(), state, 0.5, 10, false, line, unsafe { nil })!
		elapsed := time.sys_mono_now() - started
		os.write_file_array(state + '/' + name + '.log', output.data)!
		results[name + ':status'] = output.status.str()
		results[name + ':elapsed_ns'] = elapsed.str()
		results[name + ':failure'] = output.failure
		results[name + ':timed_out'] = output.timed_out.str()
		results[name + ':drained'] = output.drained.str()
		// Retain the actual exit and capture result even when the next assertion
		// refuses this case. Never turn a failed control into a missing receipt.
		os.write_file(state + '/' + name + '.status.json', json2.encode(results) + '\n')!
		results[name + ':cleanup'] = no_children()!
		os.write_file(state + '/' + name + '.status.json', json2.encode(results) + '\n')!
		require(output.failure == '' && output.timed_out && output.drained, name + ' capture/drain')!
		require(output.status == if name == 'positive' { 0 } else { -9 }, name + ' actual status')!
		require(elapsed < 15 * u64(time.second), name + ' wall bound')!
		os.write_file(state + '/' + name + '.budget.log', budget(state, false)!)!
	}
	mut after := map[string]string{}
	for path in [qemu, os.executable(), os.dir(compiler), root + '/tests/desktop-perf/run-x86.v',
		root + '/tests/desktop-perf/x86-mux-check.v', root + '/tests/desktop-perf/perfconsole',
		root + '/tools/sourcecommand'] { inventory(path, [], mut after)! }
	os.write_file(state + '/inputs-after.json', json2.encode(after) + '\n')!
	require(before == after, 'input identity changed')!
	results['scope'] = 'host-only machine-none QEMU; no target media/kernel/workload; installed host loader/SDK dependencies are not hermetic'
	results['inputs'] = hash(state + '/inputs-before.json')!
	results['verdict'] = 'PASS'
	os.write_file(state + '/qualification.json', json2.encode(results) + '\n')!
	println('PERF X86 MUX HOST PASS ' + hash(state + '/qualification.json')!)
}
fn main() { run() or {
	if os.args.len >= 2 && os.is_dir(os.args[1]) { os.write_file(os.args[1] + '/failure.txt', err.msg() + '\n') or {} }
	eprintln(err); exit(1)
} }
