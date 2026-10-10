// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// CPU idle states: what a CPU with nothing to run does until it has.
//
// It used to do one thing, HLT on x86 and WFI on arm64. A processor has
// better to offer -- states that switch off more of the core the longer it
// will not be needed -- and which to use is a matter of how long the idle is
// going to be, which is what govern.v decides. This file keeps what the
// decision needs and what it led to: the table of states the driver for this
// machine found, and for every CPU the count and length of its stays in each.
//
// The pieces:
//
//	govern.v         the choice of a state, as functions of plain values
//	driver_amd64.v   HLT and MONITOR/MWAIT, and the x86 idle loop
//	driver_arm64.v   WFI
//	sysfs.v          /sys/devices/system/cpu/cpuN/cpuidle, as on Linux
//
// The scheduler's idle paths call in from sched.await(); see the driver for
// each architecture, where the order of instructions matters.
//
// Nothing here allocates or takes a lock: it runs on every idle, with
// interrupts off, on the CPU it is about.
@[has_globals]
module cpuidle

import katomic

// As many CPUs as the scheduler's own per-CPU tables have.
pub const max_cpus = 256

// One idle state, as its driver describes it.
pub struct State {
pub mut:
	name string
	desc string
	// How the driver enters it: an MWAIT hint on x86.
	hint u32
	// The driver's own notes on it; see the driver.
	flags u32
}

// What one CPU has done with the states, and what it is doing now. Written
// only by that CPU with its interrupts off; /sys reads it from anywhere, and
// a count that is one behind does no harm there.
struct CpuRecord {
mut:
	usage    [max_states]u64
	ticks    [max_states]u64
	above    [max_states]u64
	below    [max_states]u64
	rejected [max_states]u64
	// Bit n: state n is switched off for this CPU, through its `disable` file.
	disabled u32
	// The idle under way: the state's number plus one, and the counter when
	// it was entered. Zero when the CPU is not in one.
	open         u32
	entered_tick u64
	history      History
	// What MONITOR is armed on (x86). Nothing ever writes it: a CPU in MWAIT
	// is woken by its interrupts, as one in HLT is. The padding keeps every
	// other word, whoever writes that, out of the cache line being watched.
	pad_before [8]u64
	watched    u64
	pad_after  [7]u64
}

__global (
	cpuidle_states      [max_states]State
	cpuidle_costs       [max_states]StateCost
	cpuidle_state_count u32
	cpuidle_driver_name string
	// Set once the table is complete; until then, and for good when no
	// driver fits, the scheduler idles as it always has.
	cpuidle_ready u32
	cpuidle_cpus  [max_cpus]CpuRecord
	// The latency limit in microseconds, plus one. Zero is no limit, which is
	// also what a zero-filled global says before anything has run.
	cpuidle_latency_word u64
	// The rate of the counter the residencies are measured with.
	cpuidle_tick_hz u64
)

// Whether a driver's states are in use.
pub fn active() bool {
	return katomic.load(&cpuidle_ready) != 0
}

// Let no CPU enter a state it takes longer than `us` to leave. A CPU already
// idle keeps the state it is in; the limit applies from its next idle.
pub fn set_latency_limit_us(us u64) {
	katomic.store(mut &cpuidle_latency_word, if us >= no_limit - 1 { u64(0) } else { us + 1 })
}

pub fn clear_latency_limit() {
	katomic.store(mut &cpuidle_latency_word, u64(0))
}

pub fn latency_limit_us() u64 {
	word := katomic.load(&cpuidle_latency_word)
	return if word == 0 { no_limit } else { word - 1 }
}

// The state `cpu_number` should enter for an idle that a timer ends in
// `timer_us`, or no_state.
fn idle_pick(cpu_number u64, timer_us u64) int {
	me := unsafe { &cpuidle_cpus[cpu_number] }
	return choose_state(&cpuidle_costs[0], int(cpuidle_state_count), katomic.load(&me.disabled),
		predict_us(timer_us, &me.history), latency_limit_us())
}

// Note that `cpu_number` is entering `state` now.
@[inline]
fn idle_begin(cpu_number u64, state int, now_tick u64) {
	mut me := unsafe { &cpuidle_cpus[cpu_number] }
	me.entered_tick = now_tick
	me.open = u32(state) + 1
}

// Close the idle `cpu_number` has open, if it has one: count it, add its
// length, remember the length for the next prediction, and say whether the
// state was the right one.
fn idle_account(cpu_number u64, now_tick u64) {
	mut me := unsafe { &cpuidle_cpus[cpu_number] }
	if me.open == 0 {
		return
	}
	state := int(me.open - 1)
	me.open = 0
	ticks := now_tick - me.entered_tick
	me.usage[state]++
	me.ticks[state] += ticks
	us := ticks_to_us(ticks, cpuidle_tick_hz)
	me.history.record(us)
	match judge(&cpuidle_costs[0], int(cpuidle_state_count), katomic.load(&me.disabled),
		state, us) {
		.above { me.above[state]++ }
		.below { me.below[state]++ }
		.fitting {}
	}
}

// The state was chosen and then not entered: something to do turned up first.
@[inline]
fn idle_reject(cpu_number u64, state int) {
	mut me := unsafe { &cpuidle_cpus[cpu_number] }
	me.rejected[state]++
}

// Add a state to the table. For the driver, before the table is in use.
fn add_state(name string, desc string, exit_latency_us u32, target_residency_us u32, hint u32, flags u32) bool {
	n := cpuidle_state_count
	if n >= max_states {
		return false
	}
	cpuidle_states[n] = State{
		name:  name
		desc:  desc
		hint:  hint
		flags: flags
	}
	cpuidle_costs[n] = StateCost{
		exit_latency_us:     exit_latency_us
		target_residency_us: target_residency_us
	}
	cpuidle_state_count = n + 1
	return true
}
