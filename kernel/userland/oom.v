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

import kbudget
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

// How long one that has begun to exit is waited for. It is on its way, and
// what is left to choose by then may be the desktop.
const oom_exit_patience_ns = u64(30000000000)

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

// How many times in a row a choice is put off because a process' address
// space could not be looked at. A process holds its own for the whole of a
// fork; chosen without it, the kill falls on a smaller one, or on the desktop.
const oom_busy_rounds = 20

// A pass into the reserve is good for this many pages. Paging one in takes
// two at the most: the page of a file, and the process' own copy of it.
const oom_pass_pages = u32(4)

// How many passes a thread is given between two returns to userspace. A
// page-in that a pass does not get through is not one that memory was all
// that stood in the way of, and is given up on rather than tried for good.
const oom_pass_limit = u32(1024)

__global (
	// One thread chooses at a time; the rest wait for what it chose.
	oom_choosing   u32
	// The process killed and yet to give its memory back, or 0.
	oom_victim_pid int
	oom_victim_ns  u64
	oom_kill_count u64
	oom_busy_count int
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

// The process a thread asks for memory for, or 0 for a kernel thread.
fn oom_requester(t &proc.Thread) int {
	return if t.process != unsafe { nil } { t.process.pid } else { 0 }
}

// What killing a process would give back, as oom_badness() has it.
struct OomScore {
	// Weighed by oom_score_adj; 0 for a process that is not to be killed.
	score u64
	bytes u64
	// Its address space could not be looked at, and nothing is known.
	busy bool
}

// What killing a process would give back, weighed by its oom_score_adj as
// Linux weighs it: a point is a thousandth of the machine's memory, and
// -1000 exempts the process. 0 for one that is not to be killed: init, one
// already exiting, and one killed for memory before, which either is on its
// way or cannot be made to go. The caller holds the process table.
fn oom_badness(process &proc.Process) OomScore {
	if process.pid <= 1 || process.exiting || process.oom_killed
		|| unsafe { process.pagemap == nil } || process.oom_score_adj <= -1000 {
		return OomScore{}
	}
	resident := mmap.resident_bytes(process.pagemap) or {
		return OomScore{
			busy: true
		}
	}
	bytes := resident + kbudget.owned_bytes(process.kernel_owner)
	if bytes == 0 {
		return OomScore{}
	}
	weighed := i64(bytes) + i64(process.oom_score_adj) * i64(memory.total_bytes() / 1000)
	mut score := u64(1)
	if weighed > 1 {
		score = u64(weighed)
	}
	return OomScore{
		score: score
		bytes: bytes
	}
}

fn oom_badness_of(pid int) OomScore {
	proc.lock_table()
	process := proc.process_at(pid)
	mut found := OomScore{}
	if process != unsafe { nil } {
		found = oom_badness(process)
	}
	proc.unlock_table()
	return found
}

// The process to kill for memory `requester` asked for, and how much it holds;
// pid 0 when there is none, -1 when the choice is put off because a process
// could not be looked at. It is the one with the most to give back, with two
// exceptions.
//
// The process drawing the screen -- the desktop -- is chosen only when
// nothing else can be. Every window is its, so killing it ends the session
// whatever the other programs hold, and on a full RAM root with little else
// running it is often the largest process there is.
//
// The process asking is chosen over a larger one that holds less than twice
// as much. Its going ends the demand for certain, where a bystander's only
// feeds it: with 20 MiB left on a full RAM root, a program on its way to a
// gigabyte ran out while it was still the size of the file manager, which
// was killed for it, and then the program was too.
fn oom_select(requester int) (int, u64) {
	screen := term.graphics_owner()
	mut best := 0
	mut best_score := u64(0)
	mut best_bytes := u64(0)
	mut busy := false
	for pid := 2; pid < proc.max_pid; pid++ {
		if pid == screen {
			continue
		}
		found := oom_badness_of(pid)
		if found.busy {
			busy = true
		}
		if found.score > best_score {
			best = pid
			best_score = found.score
			best_bytes = found.bytes
		}
	}
	if busy && oom_busy_count < oom_busy_rounds {
		oom_busy_count++
		return -1, 0
	}
	oom_busy_count = 0
	if best == 0 && screen > 1 {
		found := oom_badness_of(screen)
		if found.score != 0 {
			return screen, found.bytes
		}
	}
	if requester > 1 && requester != screen && requester != best {
		found := oom_badness_of(requester)
		if found.score != 0 && found.score >= best_score / 2 {
			return requester, found.bytes
		}
	}
	return best, best_bytes
}

// Whether a process is in the middle of exiting.
fn oom_exiting(pid int) bool {
	proc.lock_table()
	process := proc.process_at(pid)
	exiting := process != unsafe { nil } && process.exiting
	proc.unlock_table()
	return exiting
}

fn oom_mark(pid int, killed bool) {
	proc.lock_table()
	mut process := proc.process_at(pid)
	if process != unsafe { nil } {
		process.oom_killed = killed
	}
	proc.unlock_table()
}

// Kill the process chosen. False when it turned out to be exiting on its own
// by now, or has no thread to take the signal yet, as a fork child has before
// its first is attached: neither is marked, and the choice is made again.
fn oom_kill(pid int, bytes u64) bool {
	// The name is the process', which may be gone by the time it is printed.
	mut name := [64]u8{}
	proc.lock_table()
	mut process := proc.process_at(pid)
	if process == unsafe { nil } || process.exiting {
		proc.unlock_table()
		return false
	}
	process.oom_killed = true
	for i := 0; i < process.name.len && i < name.len - 1; i++ {
		name[i] = unsafe { process.name.str[i] }
	}
	proc.unlock_table()

	mut target := proc.pin_process_at(pid)
	mut accepted := false
	if target != unsafe { nil } {
		accepted = signal_process(mut target, sigkill)
		proc.unpin_process(target)
	}
	if !accepted {
		oom_mark(pid, false)
		return false
	}
	katomic.inc(mut &oom_kill_count)
	C.kprintf(c'oom: out of memory: killed %s, which held %llu MiB\n', unsafe { &name[0] },
		bytes >> 20)
	return true
}

// The process being killed for memory, after choosing one if none is on its
// way out. 0 when nothing is left to kill, -1 when the caller should look
// again: another thread is choosing, or the choice could not be made yet.
// `requester` is the process that asked for the page.
fn oom_victim(requester int) int {
	if !katomic.cas(mut &oom_choosing, u32(0), u32(1)) {
		return -1
	}
	defer {
		katomic.store(mut &oom_choosing, u32(0))
	}
	now := time.monotonic_ns()
	previous := katomic.load(&oom_victim_pid)
	if previous != 0 {
		age := now - oom_victim_ns
		if age < oom_patience_ns || (age < oom_exit_patience_ns && oom_exiting(previous)) {
			return previous
		}
	}
	// One that outlasted its welcome stays marked, and is not chosen again.
	pid, bytes := oom_select(requester)
	if pid <= 0 {
		return pid
	}
	// Published before the process is marked, so that its exit, which looks
	// for the mark, finds its pid here to take away.
	oom_victim_ns = now
	katomic.store(mut &oom_victim_pid, pid)
	if !oom_kill(pid, bytes) {
		katomic.cas(mut &oom_victim_pid, pid, 0)
		return -1
	}
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

// Let a thread into the reserve for the page-in it is in the middle of.
// False once it has been let in too often since it last left for userspace.
fn oom_grant(mut t proc.Thread) bool {
	t.owes_memory = true
	if t.reserve_grants >= oom_pass_limit {
		return false
	}
	t.reserve_grants++
	t.reserve_pass = oom_pass_pages
	return true
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
		return oom_grant(mut t)
	}
	for round in 0 .. oom_pause_rounds {
		if oom_dying(t) {
			return false
		}
		// Not before one sleep: a caller told to try again at once, with the
		// page still not to be had, would spin on it.
		if round > 0 && memory.user_memory_available() {
			return true
		}
		if round >= oom_reclaim_rounds && oom_victim(oom_requester(t)) == 0 {
			return false
		}
		oom_pause()
	}
	return !oom_dying(t)
}

// On the way out of a syscall, which holds nothing by now: a page the thread
// could not wait for is waited for here, so that a process taking memory
// through syscalls alone is killed for it as one taking it by faults is.
// What is left of a pass into the reserve goes with it.
pub fn settle_owed_memory() {
	mut t := proc.current_thread()
	if t == unsafe { nil } || !t.owes_memory {
		return
	}
	t.owes_memory = false
	t.reserve_pass = 0
	t.reserve_grants = 0
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

// Let the calling thread's next pages come out of the reserve, for a fault
// the kernel itself took on a process' page and has to see through: it holds
// a lock and cannot wait for memory, or the process is the one being killed
// and is in the middle of a syscall. False when there is no page at all, or
// passes have not got the fault through, and it is the kernel's to report.
pub fn grant_reserve_page() bool {
	mut t := proc.current_thread()
	if t == unsafe { nil } || !memory.any_free() {
		return false
	}
	return oom_grant(mut t)
}

// memory's reserve pass: whether the calling thread has been let into the
// reserve for `count` more pages.
fn take_reserve_pass(count u64) bool {
	mut t := proc.current_thread()
	if t == unsafe { nil } || u64(t.reserve_pass) < count {
		return false
	}
	t.reserve_pass -= u32(count)
	return true
}
