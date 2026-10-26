// SPDX-License-Identifier: GPL-2.0-or-later
module probebudget

import os

#include <sys/mount.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>

fn C.mount(&char, &char, &char, usize, voidptr) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.fflush(voidptr) i32

const mountpoint = '/ios-probe-cgroup'

fn amount(group string, name string) !u64 {
	text := os.read_file(group + '/' + name)!
	value := text.trim_space()
	if value == '' || value.bytes().any(it < `0` || it > `9`) { return error('invalid ' + name) }
	return value.u64()
}

fn create(name string, bytes u64) !string {
	group := mountpoint + '/' + name
	os.mkdir(group)!
	os.write_file(group + '/memory.max', bytes.str())!
	if amount(group, 'memory.max')! != bytes { return error('memory.max readback mismatch') }
	return group
}

// The supervisor stays outside the finite group, including during OOM checks.
pub fn enter(group string) ! {
	if group == '' { return }
	pid := os.getpid().str()
	os.write_file(group + '/cgroup.procs', pid)!
	membership := os.read_file('/proc/self/cgroup')!
	expected := '0::/' + os.file_name(group) + '\n'
	if membership != expected { return error('child cgroup membership mismatch: ' + membership) }
	if pid !in os.read_file(group + '/cgroup.procs')!.split_into_lines() {
		return error('child absent from cgroup.procs')
	}
	limit := amount(group, 'memory.max')!
	current := amount(group, 'memory.current')!
	if current >= limit { return error('child has no memory headroom') }
	println('IOS-PROBE-BUDGET: child pid=${pid} max=${limit} current=${current} headroom=${limit - current}')
	C.fflush(unsafe { nil })
}

fn empty(group string) ! {
	if os.read_file(group + '/cgroup.procs')!.trim_space() != '' {
		return error('budget group still populated')
	}
}

fn allocation_check(group string, exceed bool) ! {
	enter(group)!
	before := amount(group, 'memory.current')!
	size := if exceed { 128 * 1024 * 1024 } else { 8 * 1024 * 1024 }
	area := unsafe { C.mmap(nil, usize(size), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0) }
	if area == voidptr(-1) { return error('budget check mmap failed') }
	unsafe { C.memset(area, 0x5a, size) }
	if exceed { return error('memory.max failed to stop a 128 MiB touch under 64 MiB') }
	touched := amount(group, 'memory.current')!
	if touched < before + u64(size) - 131072 { return error('anonymous touch was not charged') }
	if unsafe { C.munmap(area, usize(size)) } != 0 { return error('budget check munmap failed') }
	released := amount(group, 'memory.current')!
	if released + u64(size) > touched + 131072 { return error('anonymous release was not uncharged') }
	println('IOS-PROBE-BUDGET: charge check before=${before} touched=${touched} released=${released}')
	C.fflush(unsafe { nil })
}

fn verify_enforcement() ! {
	parent := os.read_file('/proc/self/cgroup')!
	for exceed in [false, true] {
		group := create('check', 64 * 1024 * 1024)!
		C.fflush(unsafe { nil })
		child := C.fork()
		if child < 0 { return error('budget check fork failed') }
		if child == 0 {
			allocation_check(group, exceed) or {
				eprintln('IOS-NATIVE: FAIL budget check: ' + err.msg())
				exit(125)
			}
			exit(0)
		}
		mut status := i32(0)
		if C.waitpid(child, &status, 0) != child { return error('budget check waitpid failed') }
		if (!exceed && status != 0) || (exceed && status & 127 != 9) {
			return error('budget check unexpected wait status ${status}, exceed=${exceed}')
		}
		events := os.read_file(group + '/memory.events')!
		if exceed && 'oom_kill 1' !in events.split_into_lines() { return error('missing cgroup OOM event') }
		empty(group)!
		if os.read_file('/proc/self/cgroup')! != parent { return error('supervisor changed cgroup') }
		println('IOS-PROBE-BUDGET: check exceed=${exceed} wait=${status} events=' + events.replace('\n', ';'))
		os.rmdir(group)!
	}
	println('IOS-PROBE-BUDGET: enforcement and supervisor isolation PASS')
	C.fflush(unsafe { nil })
}

pub fn prepare(text string) !string {
	if text == '' { return '' }
	bytes := parse(text)!
	os.mkdir(mountpoint)!
	if C.mount(c'none', mountpoint.str, c'cgroup2', 0, unsafe { nil }) != 0 {
		return error('cannot mount cgroup2')
	}
	verify_enforcement()!
	return create('probe', bytes)
}

pub fn finish(group string) ! {
	if group == '' { return }
	empty(group)!
	println('IOS-PROBE-BUDGET: final current=' + amount(group, 'memory.current')!.str()
		+ ' events=' + os.read_file(group + '/memory.events')!.replace('\n', ';'))
	os.rmdir(group)!
	C.fflush(unsafe { nil })
}
