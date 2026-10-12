// SPDX-License-Identifier: GPL-2.0-or-later
module corevm

const core_pass_marker = 'VINIX QEMU CORE: PASS'
const core_persist_marker = 'VINIX QEMU CORE PERSIST: PASS'
const core_fail_markers = [
	'VINIX QEMU CORE: FAIL'
	'QEMU CORE FAIL line'
	'FATAL EXCEPTION'
	'KERNEL PANIC',
]
const core_feature_markers = [
	'QEMU CORE PASS: secure getrandom'
	'QEMU CORE PASS: sparse tmpfs shared mappings allocate on touch'
	'QEMU CORE PASS: copy-on-write fork'
	'QEMU CORE PASS: anonymous first touch, zero pages, fork and explicit population'
	'QEMU CORE PASS: syscalls page in untouched buffers'
	'QEMU CORE PASS: partial unmap reclaims pages and retains forked shares'
	'QEMU CORE PASS: a range split while a sharer unmaps it keeps its pages'
	'QEMU CORE PASS: madvise returns anonymous pages to the allocator'
	'QEMU CORE PASS: exit and exec reclaim process mappings'
	'QEMU CORE PASS: forked copy-on-write pages are reclaimed'
	'QEMU CORE PASS: default signal dispositions'
	'QEMU CORE PASS: signals reach a thread that makes no syscalls'
	'QEMU CORE PASS: SA_RESTART restarts an interrupted read'
	'QEMU CORE PASS: exit and exec take down threads blocked in the kernel'
	'QEMU CORE PASS: interrupted nanosleep returns a relative remainder'
	'QEMU CORE PASS: anonymous IPC buffers are reclaimed'
	'QEMU CORE PASS: socket interface boxes are reclaimed'
	'QEMU CORE PASS: full UNIX stream clears write readiness'
	'QEMU CORE PASS: futex wake-op updates and compares user words'
	'QEMU CORE PASS: alarm and ITIMER_REAL fire on time'
	'QEMU CORE PASS: mprotect and munmap refuse an address inside a page'
	'QEMU CORE PASS: more waiters than an event holds'
	'QEMU CORE PASS: fork keeps the program, auxv and directory'
	'QEMU CORE PASS: /proc/cpuinfo describes the machine'
	'QEMU CORE PASS: joined threads return their memory'
	'QEMU CORE PASS: the console controls a session'
	'QEMU CORE PASS: page table changes reach every CPU'
	'QEMU CORE PASS: a FIFO thread keeps its CPU'
	'QEMU CORE PASS: a frozen cgroup stops its threads'
	'QEMU CORE PASS: a wait ends for a signal already pending'
	'QEMU CORE PASS: ext2 cache, mmap, sync, namespace, timestamps'
	'QEMU CORE PASS: a shared mapping is visible to every reader'
	'QEMU CORE PASS: a released pid stays out of use while its group lives'
	'QEMU CORE PASS: fcntl and flock exclusion'
	'QEMU CORE PASS: permissions, umask, and resource limits'
	'QEMU CORE PASS: inotify events'
	'QEMU CORE PASS: priority, affinity, and accounting'
	'QEMU CORE PASS: concurrent wakeups enqueue one thread once'
	'QEMU CORE PASS: POSIX SIGEV_THREAD timer notification'
	'QEMU CORE PASS: anonymous descriptors are open both ways'
	'QEMU CORE PASS: Linux pollfd ABI'
	'QEMU CORE PASS: large blocking pipe transfer makes progress'
	'QEMU CORE PASS: empty pipes defer buffers and reclaim first-write storage'
	'QEMU CORE PASS: Linux epoll ABI and event count'
	'QEMU CORE PASS: syscall C-int truncation'
	'QEMU CORE PASS: abstract socket names are released'
	'QEMU CORE PASS: persistence markers synchronized',
]
const core_amd64_feature_markers = [
	'QEMU CORE PASS: x86-64 utime, utimes, futimesat and getdents'
	'QEMU CORE PASS: x86-64 TLS descriptors, LDT and 32-bit code',
]

pub fn required(verification bool, amd64 bool) []string {
	return if verification {
		[core_persist_marker]
	} else if amd64 {
		[...core_feature_markers, ...core_amd64_feature_markers, core_pass_marker]
	} else {
		[...core_feature_markers, core_pass_marker]
	}
}

pub fn results(run Run, verification bool, amd64 bool) ([]string, []string) {
	mut missing := []string{}
	for marker in required(verification, amd64) {
		if run.output.count(marker) != 1 { missing << marker }
	}
	mut failures := []string{}
	for marker in core_fail_markers { if run.output.contains(marker) { failures << marker } }
	if amd64 {
		if !run.finished { failures << 'the test did not finish before the timeout' }
	} else {
		if run.has_status && run.status != 0 {
			failures << 'VM runner exit status ' + run.status.str()
		}
		if run.forced { failures << 'VM did not exit after the test' }
	}
	return missing, failures
}
