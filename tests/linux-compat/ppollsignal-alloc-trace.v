// SPDX-License-Identifier: GPL-2.0-or-later
// Generate qualification-only small-group allocation tracing. Keep the
// production fixture and its original semantic/storage checks unchanged.
module main

import os

fn run() ! {
	if os.args.len != 3 { return error('Usage: ppollsignal-alloc-trace REPOSITORY FRESH-STATE') }
	repo := os.real_path(os.args[1])
	state := os.args[2]
	if os.exists(state) { return error('Fresh state required') }
	os.mkdir_all(state+'/probe-root/tests/linux-compat/ppollsignalfixture')!
	os.mkdir_all(state+'/probe-root/tests/linux-compat/ppollsignalreferenceinit')!
	procfs := os.read_file(repo+'/kernel/fs/procfs.v')!
	anchor := 'C.alloc_track_dump(unsafe { &char(buf) }, cap, 50)'
	if procfs.count(anchor) != 1 { return error('Different allocation diagnostic layout') }
	os.write_file(state+'/procfs.v',procfs.replace(anchor,anchor.replace('50','1')))!
	host := os.read_file(repo+'/tests/linux-compat/ppollsignal-host.v')!
	if host.count('ALLOC_TRACK=0') != 1 { return error('Different host build flags') }
	os.write_file(state+'/host.v',host.replace('ALLOC_TRACK=0','ALLOC_TRACK=1'))!
	base := repo+'/tests/linux-compat/ppollsignalfixture/'
	mut core := os.read_file(base+'core.v')!
	start := 'scratch := &State(C.alloca(usize(sizeof(State))))'
	if core.count(start) != 1 { return error('Different child entry frame') }
	core = core.replace(start,'trace_reset()\n\t\t\t\t'+start)
	core += '
fn trace_reset() {
 unsafe {
 if C.getuid() != 0 { return }
 fd := C.open(c\'/proc/allocstart\',C.O_RDONLY)
 if fd < 0 { fatal(40) }
 mut data := [16]u8{}
 if C.pread(fd,&data[0],sizeof(data),0) != 3 || C.close(fd) != 0 { fatal(41) }
 }
}
fn trace_sites(phase &char) {
 unsafe {
 if C.getuid() != 0 { return }
 fd := C.open(c\'/proc/allocsites\',C.O_RDONLY)
 if fd < 0 { fatal(42) }
 data := &u8(C.alloca(262145))
 n := C.pread(fd,data,262144,0)
 if n <= 0 || n >= 262144 || data[n-1] != 10 || C.close(fd) != 0 { fatal(43) }
 data[n] = 0
 mut start := 0
 for i in 0 .. int(n) {
 if data[i] != 10 { continue }
 data[i] = 0
 C.printf(c\'PERF-SITE ppollsignal phase=%s %s\\n\',phase,&data[start])
 start = i+1
 }
 C.fflush(nil)
 }
}
'
	mut storage := os.read_file(base+'storage.v')!
	before := 'if !snapshot(fd,before) { fatal(32) }'
	after := 'if !snapshot(fd,after) { fatal(33) }'
	if storage.count(before) != 1 || storage.count(after) != 1 { return error('Different storage snapshots') }
	storage = storage.replace(before,'trace_sites(c\'before\')\n if C.getuid() == 0 { C.usleep(13_000_000) }\n '+before)
	storage = storage.replace(after,after+'\n trace_sites(c\'after\')')
	output := state+'/probe-root/tests/linux-compat/'
	os.write_file(output+'ppollsignalfixture/core.v',core)!
	os.write_file(output+'ppollsignalfixture/storage.v',storage)!
	os.cp(base+'bounds.v',output+'ppollsignalfixture/bounds.v')!
	os.cp(repo+'/tests/linux-compat/ppollsignalreferenceinit/core.v',output+'ppollsignalreferenceinit/core.v')!
}

fn main() { run() or { eprintln(err.msg()); exit(1) } }
