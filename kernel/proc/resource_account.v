// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import katomic
import memory

// Scalars embedded in the existing task objects; no per-event allocation or
// pointer retained by a driver, fault handler or scheduler.
pub struct UsageCounters {
pub mut:
	minor_faults u64
	major_faults u64
	read_bytes u64
	write_bytes u64
	voluntary_switches u64
	involuntary_switches u64
}

// Native Linux LP64 rusage, identical on both supported architectures.
pub struct Rusage {
pub mut:
	utime_sec i64
	utime_usec i64
	stime_sec i64
	stime_usec i64
	maxrss i64
	ixrss i64
	idrss i64
	isrss i64
	minflt i64
	majflt i64
	nswap i64
	inblock i64
	oublock i64
	msgsnd i64
	msgrcv i64
	nsignals i64
	nvcsw i64
	nivcsw i64
}

fn maximum_counter(value &u64, candidate u64) {
	for {
		previous := katomic.load(value)
		if previous >= candidate { return }
		if katomic.cas(mut unsafe { value }, previous, candidate) { return }
	}
}

// Called before replacing/detaching the old page map, under the table lock.
// The page map's high-water mark survives unmapping and exec, while fork
// starts a fresh process mark from the child's own initial resident pages.
pub fn preserve_peak_rss(process &Process, pagemap &memory.Pagemap) {
	if pagemap != unsafe { nil } {
		maximum_counter(&process.peak_rss_bytes, katomic.load(&pagemap.peak_resident_bytes))
	}
}

fn peak_rss(process &Process) u64 {
	lock_table()
	mut peak := katomic.load(&process.peak_rss_bytes)
	if process.pagemap != unsafe { nil } {
		current := katomic.load(&process.pagemap.peak_resident_bytes)
		if current > peak { peak = current }
	}
	unlock_table()
	return peak
}

// Account completed device payloads once at the physical leaf, so partition
// forwarding and cache hits cannot charge the same bytes again. Background
// writeback is charged to its issuing kernel thread, not the earlier dirtier.
pub fn account_disk_io(bytes u64, write bool) {
	t := current_thread()
	if t == unsafe { nil } || t.process == unsafe { nil } { return }
	if write {
		add_cpu_counter(&t.usage.write_bytes, bytes)
		add_cpu_counter(&t.process.usage.write_bytes, bytes)
	} else {
		add_cpu_counter(&t.usage.read_bytes, bytes)
		add_cpu_counter(&t.process.usage.read_bytes, bytes)
	}
}

pub fn current_disk_read_bytes() u64 {
	t := current_thread()
	return if t == unsafe { nil } { u64(0) } else { katomic.load(&t.usage.read_bytes) }
}

// Successful demand-resolution/COW transactions are counted by the common
// resolver. An already-present fast path and failed faults count nothing.
pub fn account_page_fault(pagemap &memory.Pagemap, major bool) {
	t := current_thread()
	if t == unsafe { nil } || t.process == unsafe { nil }
		|| voidptr(t.process.pagemap) != voidptr(pagemap) { return }
	if major {
		add_cpu_counter(&t.usage.major_faults, 1)
		add_cpu_counter(&t.process.usage.major_faults, 1)
	} else {
		add_cpu_counter(&t.usage.minor_faults, 1)
		add_cpu_counter(&t.process.usage.minor_faults, 1)
	}
}

// Only the actual switch-away boundary calls this. A scheduler tick that
// keeps the CPU counts nothing. Like Linux, runnable yields/preemptions are
// involuntary; parking a dequeued task is voluntary.
pub fn account_context_switch(t &Thread, voluntary bool) {
	if t.process == unsafe { nil } { return }
	if voluntary {
		add_cpu_counter(&t.usage.voluntary_switches, 1)
		add_cpu_counter(&t.process.usage.voluntary_switches, 1)
	} else {
		add_cpu_counter(&t.usage.involuntary_switches, 1)
		add_cpu_counter(&t.process.usage.involuntary_switches, 1)
	}
}

fn add_usage(mut total UsageCounters, source &UsageCounters) {
	add_cpu_counter(&total.minor_faults, katomic.load(&source.minor_faults))
	add_cpu_counter(&total.major_faults, katomic.load(&source.major_faults))
	add_cpu_counter(&total.read_bytes, katomic.load(&source.read_bytes))
	add_cpu_counter(&total.write_bytes, katomic.load(&source.write_bytes))
	add_cpu_counter(&total.voluntary_switches, katomic.load(&source.voluntary_switches))
	add_cpu_counter(&total.involuntary_switches, katomic.load(&source.involuntary_switches))
}

fn fill_usage(mut result Rusage, counters &UsageCounters) {
	result.minflt = i64(katomic.load(&counters.minor_faults))
	result.majflt = i64(katomic.load(&counters.major_faults))
	result.inblock = i64(katomic.load(&counters.read_bytes) >> 9)
	result.oublock = i64(katomic.load(&counters.write_bytes) >> 9)
	result.nvcsw = i64(katomic.load(&counters.voluntary_switches))
	result.nivcsw = i64(katomic.load(&counters.involuntary_switches))
}

fn fill_times(mut result Rusage, user_ns u64, system_ns u64) {
	result.utime_sec = i64(user_ns / 1000000000)
	result.utime_usec = i64(user_ns % 1000000000 / 1000)
	result.stime_sec = i64(system_ns / 1000000000)
	result.stime_usec = i64(system_ns % 1000000000 / 1000)
}

// wait4/waitid report the child's lifetime plus descendants it has reaped.
// Max RSS is a maximum, unlike additive event and CPU counters.
pub fn fill_process_rusage(mut result Rusage, process &Process, now_ns u64, descendants bool) {
	user_ns, system_ns := process_cpu_times(process, now_ns)
	fill_times(mut result, user_ns, system_ns)
	fill_usage(mut result, &process.usage)
	result.maxrss = i64(peak_rss(process) / 1024)
	if descendants {
		mut p := unsafe { process }
		p.cpu_lock.acquire()
		fill_times(mut result, user_ns + katomic.load(&process.children_cpu_user_ns),
			system_ns + katomic.load(&process.children_cpu_system_ns))
		result.minflt += i64(katomic.load(&process.children_usage.minor_faults))
		result.majflt += i64(katomic.load(&process.children_usage.major_faults))
		result.inblock = i64((katomic.load(&process.usage.read_bytes)
			+ katomic.load(&process.children_usage.read_bytes)) >> 9)
		result.oublock = i64((katomic.load(&process.usage.write_bytes)
			+ katomic.load(&process.children_usage.write_bytes)) >> 9)
		result.nvcsw += i64(katomic.load(&process.children_usage.voluntary_switches))
		result.nivcsw += i64(katomic.load(&process.children_usage.involuntary_switches))
		child_peak := i64(katomic.load(&process.children_peak_rss_bytes) / 1024)
		if child_peak > result.maxrss { result.maxrss = child_peak }
		p.cpu_lock.release()
	}
}

pub fn fill_rusage(mut result Rusage, who int, now_ns u64) bool {
	t := current_thread()
	mut process := t.process
	match who {
		0 { fill_process_rusage(mut result, process, now_ns, false) }
		1 {
			user_ns, system_ns := thread_cpu_times(t, now_ns)
			fill_times(mut result, user_ns, system_ns)
			fill_usage(mut result, &t.usage)
			result.maxrss = i64(peak_rss(process) / 1024)
		}
		-1 {
			process.cpu_lock.acquire()
			fill_times(mut result, katomic.load(&process.children_cpu_user_ns),
				katomic.load(&process.children_cpu_system_ns))
			fill_usage(mut result, &process.children_usage)
			result.maxrss = i64(katomic.load(&process.children_peak_rss_bytes) / 1024)
			process.cpu_lock.release()
		}
		else { return false }
	}
	return true
}

pub fn account_reaped_usage(mut parent Process, child &Process) {
	add_usage(mut parent.children_usage, &child.usage)
	add_usage(mut parent.children_usage, &child.children_usage)
	maximum_counter(&parent.children_peak_rss_bytes, katomic.load(&child.peak_rss_bytes))
	maximum_counter(&parent.children_peak_rss_bytes, katomic.load(&child.children_peak_rss_bytes))
}
