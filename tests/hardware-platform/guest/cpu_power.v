// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// cpu-power and cpu-power-simulated: the idle states CPUs wait in, and the
// control of their speed.
//
// Idle. Every CPU must have its states in /sys, and waiting must be counted:
// across a second in which this program sleeps, each CPU enters a state and
// the time it spent there grows. Switching the deepest state off must stop it
// being used, and switching it on again must bring it back. Above all, work
// that depends on being woken must still get done: threads that sleep on
// timers and hand a byte back and forth through pipes, beside threads that
// only compute, finish with the right totals. A CPU that slept through a
// wake-up would leave them waiting, and the scenario would end by its
// deadline instead.
//
// Speed. A virtual machine has nothing to set, and must say so: the driver is
// `none`, the frequencies are what the processor reports, and a write that
// cannot be honoured fails. cpu-power-simulated boots with a made-up driver
// (vinix.cpufreq=simulate) so that the path from a governor to each CPU's own
// register write runs: `performance` puts every CPU at its highest frequency,
// `powersave` at its lowest, and a profile sets both for all of them.
module main

import os
import time

const cpu_root = '/sys/devices/system/cpu'

fn cpu_count() int {
	mut count := 0
	for os.exists('${cpu_root}/cpu${count}') {
		count++
	}
	return count
}

fn state_count(cpu int) int {
	mut count := 0
	for os.exists('${cpu_root}/cpu${cpu}/cpuidle/state${count}') {
		count++
	}
	return count
}

fn idle_number(cpu int, state int, file string) i64 {
	return read_word('${cpu_root}/cpu${cpu}/cpuidle/state${state}/${file}').i64()
}

// Threads that only get their work done if they are woken on time.
fn sleeper(rounds int, done chan int) {
	mut completed := 0
	for _ in 0 .. rounds {
		time.sleep(2 * time.millisecond)
		completed++
	}
	done <- completed
}

fn spinner(rounds u64, done chan u64) {
	mut value := u64(0x9e3779b97f4a7c15)
	for i in u64(0) .. rounds {
		value = (value ^ (value >> 29)) * 0xbf58476d1ce4e5b9 + i
	}
	done <- value
}

fn spinner_expected(rounds u64) u64 {
	mut value := u64(0x9e3779b97f4a7c15)
	for i in u64(0) .. rounds {
		value = (value ^ (value >> 29)) * 0xbf58476d1ce4e5b9 + i
	}
	return value
}

fn check_idle(mut t Test) {
	cpus := cpu_count()
	driver := read_word('${cpu_root}/cpuidle/current_driver')
	t.check(cpus > 0, 'no CPUs in ${cpu_root}')
	t.check(driver != '', 'no idle driver named in cpuidle/current_driver')
	states := state_count(0)
	t.check(states > 0, 'cpu0 has no idle states')
	if cpus == 0 || states == 0 {
		return
	}
	deepest := states - 1
	// Waiting is counted on every CPU.
	mut usage := []i64{len: cpus}
	mut spent := []i64{len: cpus}
	for cpu in 0 .. cpus {
		for state in 0 .. states {
			usage[cpu] += idle_number(cpu, state, 'usage')
			spent[cpu] += idle_number(cpu, state, 'time')
		}
	}
	sleep_ms(1000)
	mut least := i64(1000000)
	for cpu in 0 .. cpus {
		mut now_usage := i64(0)
		mut now_spent := i64(0)
		for state in 0 .. states {
			now_usage += idle_number(cpu, state, 'usage')
			now_spent += idle_number(cpu, state, 'time')
		}
		t.check(now_usage > usage[cpu], 'cpu${cpu} entered no idle state in a second')
		t.check(now_spent > spent[cpu], 'cpu${cpu} counted no idle time in a second')
		if now_spent - spent[cpu] < least {
			least = now_spent - spent[cpu]
		}
	}
	t.info('idle: driver ${driver}, ${states} state(s) on ${cpus} CPUs; the busiest CPU waited ${least / 1000} ms of a second')
	// With nothing to run, a CPU spends most of a second waiting.
	t.check(least >= 500000, 'a CPU counted only ${least} us of waiting in an idle second')

	// A state that is switched off is not used.
	state_dir := '${cpu_root}/cpu0/cpuidle/state${deepest}/'
	write_text(state_dir + 'disable', '1') or { t.check(false, 'disabling state${deepest}: ${err.msg()}') }
	before := idle_number(0, deepest, 'usage')
	sleep_ms(500)
	t.check(idle_number(0, deepest, 'usage') == before, 'a disabled state was entered ${idle_number(0,
		deepest, 'usage') - before} times')
	if _ := write_text(state_dir + 'disable', '2') {
		t.check(false, 'disable accepted 2')
	}
	if _ := write_text(state_dir + 'usage', '0') {
		t.check(false, 'usage is writable')
	}
	write_text(state_dir + 'disable', '0') or { t.check(false, 'enabling state${deepest}: ${err.msg()}') }
	sleep_ms(500)
	t.check(idle_number(0, deepest, 'usage') > before, 'the state was not used again once enabled')
}

fn check_wakeups(mut t Test) {
	rounds := u64(20000000)
	sleeps := chan int{cap: 8}
	spins := chan u64{cap: 8}
	started := time.sys_mono_now()
	for _ in 0 .. 4 {
		spawn sleeper(400, sleeps)
	}
	for _ in 0 .. 2 {
		spawn spinner(rounds, spins)
	}
	// A byte handed back and forth: each read waits for the other end's write.
	// C's int: `int` here is wider.
	mut there := [2]i32{}
	mut back := [2]i32{}
	C.pipe(voidptr(&there[0]))
	C.pipe(voidptr(&back[0]))
	child := os.fork()
	if child == 0 {
		mut b := [1]u8{}
		for C.read(there[0], &b[0], 1) == 1 {
			C.write(back[1], &b[0], 1)
		}
		exit(0)
	}
	mut trips := 0
	mut b := [u8(7)]!
	for _ in 0 .. 2000 {
		if C.write(there[1], &b[0], 1) != 1 || C.read(back[0], &b[0], 1) != 1 {
			break
		}
		trips++
	}
	C.close(there[1])
	mut slept := 0
	for _ in 0 .. 4 {
		slept += <-sleeps
	}
	expected := spinner_expected(rounds)
	for _ in 0 .. 2 {
		t.check(<-spins == expected, 'a computing thread came back with the wrong result')
	}
	took := (time.sys_mono_now() - started) / 1000000
	t.check(slept == 1600, 'the sleeping threads finished ${slept} of 1600 sleeps')
	t.check(trips == 2000, 'the pipe made ${trips} of 2000 round trips')
	t.info('wake-ups: 1600 timed sleeps, 2000 pipe round trips and two computing threads done in ${took} ms')
}

fn scenario_cpu_power(mut t Test) {
	check_idle(mut t)
	check_wakeups(mut t)
	// A machine with no frequency control says so, and refuses what it
	// cannot do.
	freq := '${cpu_root}/cpu0/cpufreq/'
	t.check(read_word(freq + 'scaling_driver') == 'none', 'scaling_driver is "${read_word(freq +
		'scaling_driver')}" in a machine with nothing to drive')
	t.check(read_word(freq + 'scaling_min_freq') == read_word(freq + 'scaling_max_freq'), 'min and max differ with no driver')
	if _ := write_text(freq + 'scaling_governor', 'performance') {
		t.check(false, 'a governor was accepted with no driver')
	}
	if _ := write_text('${cpu_root}/cpufreq/profile', 'power_saver') {
		t.check(false, 'a profile was accepted with no driver')
	}
	t.check(read_word('${cpu_root}/cpufreq/thermal_limit') == '100', 'thermal_limit is ${read_word('${cpu_root}/cpufreq/thermal_limit')}')
}

// Every CPU's current frequency, once they agree on `wanted` ('max' or
// 'min'); false if they do not within two seconds.
fn all_at(cpus int, wanted string) bool {
	for _ in 0 .. 20 {
		mut agree := true
		for cpu in 0 .. cpus {
			freq := '${cpu_root}/cpu${cpu}/cpufreq/'
			target := if wanted == 'max' {
				read_word(freq + 'cpuinfo_max_freq')
			} else {
				read_word(freq + 'cpuinfo_min_freq')
			}
			if read_word(freq + 'scaling_cur_freq') != target {
				agree = false
			}
		}
		if agree {
			return true
		}
		sleep_ms(100)
	}
	return false
}

fn scenario_cpu_power_simulated(mut t Test) {
	cpus := cpu_count()
	freq := '${cpu_root}/cpu0/cpufreq/'
	t.check(read_word(freq + 'scaling_driver') != 'none', 'the simulated driver did not start')
	t.check(read_word(freq + 'cpuinfo_min_freq') != read_word(freq + 'cpuinfo_max_freq'), 'the simulated driver has one frequency')
	for cpu in 0 .. cpus {
		write_text('${cpu_root}/cpu${cpu}/cpufreq/scaling_governor', 'performance') or {
			t.check(false, 'performance on cpu${cpu}: ${err.msg()}')
		}
	}
	t.check(all_at(cpus, 'max'), 'performance did not put every CPU at its highest frequency')
	for cpu in 0 .. cpus {
		write_text('${cpu_root}/cpu${cpu}/cpufreq/scaling_governor', 'powersave') or {
			t.check(false, 'powersave on cpu${cpu}: ${err.msg()}')
		}
	}
	t.check(all_at(cpus, 'min'), 'powersave did not put every CPU at its lowest frequency')
	write_text('${cpu_root}/cpufreq/profile', 'performance') or { t.check(false, 'profile: ${err.msg()}') }
	t.check(read_word(freq + 'scaling_governor') == 'performance', 'the performance profile left the governor at ${read_word(freq +
		'scaling_governor')}')
	t.check(all_at(cpus, 'max'), 'the performance profile did not put every CPU at its highest frequency')
	if _ := write_text(freq + 'scaling_governor', 'nonesuch') {
		t.check(false, 'an unknown governor was accepted')
	}
	t.info('simulated driver: ${cpus} CPUs between ${read_word(freq + 'cpuinfo_min_freq')} and ${read_word(freq +
		'cpuinfo_max_freq')} kHz followed performance, powersave and the profile')
}
