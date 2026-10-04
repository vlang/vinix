// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module userland

// What a process needing a page it cannot have costs, the same on both
// architectures. Memory below the reserve the kernel keeps for itself
// (memory/reserve.v) is not handed to processes: the one holding the most
// memory is killed instead, and whoever needed the page waits for that memory
// and tries again. This is Linux's OOM killer, oom_score_adj included.
//
// The alternative was the machine. Page tables, slab pages and kernel stacks
// cannot fail, and with nothing left for them the kernel stopped with "Out of
// memory after reclaim", whichever program had used the memory up.

import event
import katomic
import memory
import memory.mmap
import proc
import term
import time

// How long a process that was killed is waited for before another is chosen
// in its place. It gives its memory back at the end of its exit, after its
// threads have left and its files are closed, and may be in a syscall that
// cannot be interrupted before it starts.
const oom_patience_ns = u64(5000000000)

// How long a thread sleeps between looks at whether the memory has come, and
// how many of those sleeps one call sits out before handing back to its
// caller, which tries its allocation again and comes back if it must.
const oom_pause_ns = i64(10000000)
const oom_pause_rounds = 100

// How many of them go by before a process is killed. A reclaimer another CPU
// is in the middle of gives nothing back to this one, and a cache whose lock
// is taken is passed over: a page that cannot be had this instant is often
// there a moment later, with nothing killed for it.
const oom_reclaim_rounds = 3

__global (
	// One thread chooses at a time; the rest wait for what it chose.
	oom_choosing   u32
	// The process killed and yet to give its memory back, or 0.
	oom_victim_pid int
	oom_victim_ns  u64
	oom_kill_count u64
)

pub fn initialise_oom() {
	memory.register_exhaustion_handler(recover_memory)
	memory.register_reserve_pass(take_reserve_pass)
}

// How many processes have been killed for memory since boot.
pub fn oom_kills() u64 {
	return katomic.load(&oom_kill_count)
}

// Whether the calling thread is on its way out: killed, or told to leave by
// a sibling that was. It has no use for the page it wanted.
fn oom_dying(t &proc.Thread) bool {
	return katomic.load(&t.must_exit) || katomic.load(&t.pending_signals) & signal_bit(sigkill) != 0
		|| (t.process != unsafe { nil } && t.process.exiting)
}

// What killing a process would give back, weighed by its oom_score_adj as
// Linux weighs it: a point is a thousandth of the machine's memory, and
// -1000 exempts the process. 0 for one that is not to be killed: init, one
// already exiting, and one killed for memory before, which either is on its
// way or cannot be made to go. The caller holds the process table.
fn oom_badness(process &proc.Process) (u64, u64) {
	if process.pid <= 1 || process.exiting || process.oom_killed
		|| unsafe { process.pagemap == nil } || process.oom_score_adj <= -1000 {
		return 0, 0
	}
	bytes := mmap.resident_bytes(process.pagemap)
	if bytes == 0 {
		return 0, 0
	}
	score := i64(bytes) + i64(process.oom_score_adj) * i64(memory.total_bytes() / 1000)
	if score < 1 {
		return 1, bytes
	}
	return u64(score), bytes
}

fn oom_badness_of(pid int) (u64, u64) {
	proc.lock_table()
	defer {
		proc.unlock_table()
	}
	process := proc.process_at(pid)
	if process == unsafe { nil } {
		return 0, 0
	}
	return oom_badness(process)
}

// The process with the most to give back, and how much; pid 0 when there is
// none.
//
// The process drawing the screen -- the desktop -- is chosen only when
// nothing else can be. Every window is its, so killing it ends the session
// whatever the other programs hold, and on a full RAM root with little else
// running it is often the largest process there is.
fn oom_select() (int, u64) {
	screen := term.graphics_owner()
	mut best := 0
	mut best_score := u64(0)
	mut best_bytes := u64(0)
	for pid := 2; pid < proc.max_pid; pid++ {
		if pid == screen {
			continue
		}
		score, bytes := oom_badness_of(pid)
		if score > best_score {
			best = pid
			best_score = score
			best_bytes = bytes
		}
	}
	if best == 0 && screen > 1 {
		score, bytes := oom_badness_of(screen)
		if score != 0 {
			return screen, bytes
		}
	}
	return best, best_bytes
}

fn oom_kill(pid int, bytes u64) {
	// The name is the process', which may be gone by the time it is printed.
	mut name := [64]u8{}
	proc.lock_table()
	mut process := proc.process_at(pid)
	if process != unsafe { nil } {
		process.oom_killed = true
		for i := 0; i < process.name.len && i < name.len - 1; i++ {
			name[i] = unsafe { process.name.str[i] }
		}
	}
	proc.unlock_table()
	katomic.inc(mut &oom_kill_count)
	signal_pid(pid, sigkill)
	C.kprintf(c'oom: out of memory: killed %s, which held %llu MiB\n', unsafe { &name[0] },
		bytes >> 20)
}

// The process being killed for memory, after choosing one if none is on its
// way out. 0 when nothing is left to kill, -1 while another thread chooses.
fn oom_victim() int {
	if !katomic.cas(mut &oom_choosing, u32(0), u32(1)) {
		return -1
	}
	defer {
		katomic.store(mut &oom_choosing, u32(0))
	}
	now := time.monotonic_ns()
	previous := katomic.load(&oom_victim_pid)
	if previous != 0 && now - oom_victim_ns < oom_patience_ns {
		return previous
	}
	// One that outlasted its welcome stays marked, and is not chosen again.
	pid, bytes := oom_select()
	if pid == 0 {
		return 0
	}
	oom_victim_ns = now
	katomic.store(mut &oom_victim_pid, pid)
	oom_kill(pid, bytes)
	return pid
}

// exit_process(), once a process' address space has been given back. When it
// was killed for memory and that is still short, the next may be chosen at
// once: there is nothing more of this one to wait for.
fn oom_victim_gone(process &proc.Process) {
	if process.oom_killed {
		katomic.cas(mut &oom_victim_pid, process.pid, 0)
	}
}

// Sleep, to be woken early only by being killed or told to exit.
fn oom_pause() {
	mut timer := time.new_timer(time.TimeSpec{
		tv_sec:  0
		tv_nsec: oom_pause_ns
	})
	event.await_one_masked(mut timer.event, signal_bit(sigkill)) or {}
	timer.disarm()
	unsafe { free(timer) }
}

// memory.recover_from_exhaustion(): the calling thread needed a page for its
// process and there was none. True once there may be one, and the caller
// tries again; false when the caller's own process is the one being killed,
// or when nothing is left to kill.
//
// It sleeps. A caller that does not know it may -- the kernel copying to or
// from a process' page in the middle of a syscall, which may hold a lock --
// is only made to wait with interrupts on, which no lock holder has. With
// them off, as they are throughout an arm64 syscall, the page comes out of
// the upper half of the reserve instead, and what is to be killed for the
// memory is settled on the way out of the syscall: settle_owed_memory().
fn recover_memory(sleepable bool) bool {
	mut t := proc.current_thread()
	if t == unsafe { nil } {
		return false
	}
	if !sleepable && !event.may_wait() {
		t.owes_memory = true
		if oom_dying(t) || !memory.reserve_half_left() {
			return false
		}
		t.reserve_pass = true
		return true
	}
	for round in 0 .. oom_pause_rounds {
		if oom_dying(t) {
			return false
		}
		if memory.user_memory_available() {
			return true
		}
		if round >= oom_reclaim_rounds && oom_victim() == 0 {
			return false
		}
		oom_pause()
	}
	return !oom_dying(t)
}

// On the way out of a syscall, which holds nothing by now: a page the thread
// could not wait for is waited for here, so that a process taking memory
// through syscalls alone is killed for it as one taking it by faults is.
pub fn settle_owed_memory() {
	mut t := proc.current_thread()
	if t == unsafe { nil } || !t.owes_memory {
		return
	}
	t.owes_memory = false
	recover_memory(true)
}

// A fault the calling thread took in userspace could not be resolved for lack
// of memory, and recover_from_exhaustion() said not to try again. When that
// is because its own process is the one killed, the thread ends here: there
// is nothing of its own it could go back to. Otherwise nothing was left to
// kill, and the fault is the thread's to take as any other.
pub fn exit_if_killed_for_memory() {
	t := proc.current_thread()
	if t == unsafe { nil } || !oom_dying(t) {
		return
	}
	exit_if_told_to()
	exit_with_fatal_signal(u8(sigkill))
}

// Let the calling thread's next page come out of the reserve, for a fault the
// kernel itself took on a process' page and has to see through: it holds a
// lock and cannot wait for memory, or the process is the one being killed and
// is in the middle of a syscall. False when there is no page at all, and the
// fault is the kernel's to report.
pub fn grant_reserve_page() bool {
	mut t := proc.current_thread()
	if t == unsafe { nil } || !memory.any_free() {
		return false
	}
	t.reserve_pass = true
	t.owes_memory = true
	return true
}

// memory's reserve pass: whether the calling thread has been let into the
// reserve, which is good for the one page.
fn take_reserve_pass() bool {
	mut t := proc.current_thread()
	if t == unsafe { nil } || !t.reserve_pass {
		return false
	}
	t.reserve_pass = false
	return true
}
