// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// suspend-deep and suspend-deep-iommu: the machine is suspended to RAM (ACPI
// S3) and comes back whole.
//
// In a suspend to RAM the processors, the interrupt controllers, the timers
// and every device lose power; only memory keeps it. Whether the kernel put
// all of that back shows in whether the machine still does everything it did
// before, so this is mostly a list of things done before a sleep and done
// again after it:
//
//   - memory: 32 MiB of a sequence that is checked word for word afterwards;
//   - processors: a thread pinned to each one must run there again, the
//     kernel's own per-CPU accounting in /proc/stat must show user time on
//     each, and the protection registers must have been compared on all;
//   - the disk: a pattern written before must read back, a part of the disk
//     never read before must read as the host filled it, and a new pattern
//     must go out and come back;
//   - the network: a file fetched from QEMU's TFTP server;
//   - the clocks: neither may run backwards, and both must have moved on by
//     about as long as the machine was away;
//   - the screen: what was drawn on it must be there again;
//   - with an IOMMU: both devices still confined, and no fault recorded.
//
// Three sleeps are ended in the three ways QEMU can end one -- its
// `system_wakeup` command, the clock's alarm, a key -- and five more follow
// one after another. Before them, two rehearsals (pm_test = platform) take
// the whole way down and back without asking firmware for the sleep: one
// undisturbed, and one a key interrupts, which must be counted as a sleep
// that failed.
//
// That the machine really slept is not for this program to say: it would
// read the same if the kernel had only waited. The host counts QEMU's own
// SUSPEND and WAKEUP events.
@[has_globals]
module main

import sync.stdatomic
import time

#include <time.h>
#include <unistd.h>

fn C.clock_gettime(clock i32, value voidptr) i32
fn C.syscall(number i64, a voidptr, b voidptr, c voidptr) i64

const sys_sched_setaffinity = i64(203)
const sys_getcpu = i64(309)
const clock_realtime = i32(0)

const deep_stats = '/sys/power/suspend_stats/'
const deep_memory_bytes = 32 << 20
const deep_disk = '/dev/sd0'
const deep_pattern_bytes = 65536
// Where the host filled the disk before the boot, a megabyte apart, each
// part read once: hwhost's deep_disk has the same.
const deep_prefill_base = i64(16) << 20
const deep_max_cpus = 16

__global (
	// One counter for each pinned thread, the CPU it last found itself on,
	// and whether they are to count at all just now.
	deep_counts  [deep_max_cpus]u64
	deep_seen_on [deep_max_cpus]i64
	deep_running u64
	// A thread that counts whenever it is allowed to run.
	deep_free_count u64
)

struct TimeSpec {
mut:
	seconds     i64
	nanoseconds i64
}

fn realtime_ms() i64 {
	mut now := TimeSpec{}
	C.clock_gettime(clock_realtime, voidptr(&now))
	return now.seconds * 1000 + now.nanoseconds / 1000000
}

fn monotonic_ms() i64 {
	return i64(time.sys_mono_now() / 1000000)
}

fn deep_stat(name string) string {
	return read_word(deep_stats + name)
}

fn count_freely() {
	for {
		stdatomic.add_u64(&deep_free_count, 1)
	}
}

// Stays on one CPU and counts while deep_running says so.
fn count_on_cpu(cpu int) {
	mask := u64(1) << u64(cpu)
	if C.syscall(sys_sched_setaffinity, unsafe { nil }, voidptr(u64(8)), voidptr(&mask)) != 0 {
		stdatomic.store_i64(&deep_seen_on[cpu], -2)
		return
	}
	mut turns := u64(0)
	for {
		if stdatomic.load_u64(&deep_running) == 0 {
			sleep_ms(5)
			continue
		}
		stdatomic.add_u64(&deep_counts[cpu], 1)
		turns++
		if turns % 20000 == 1 {
			mut here := u32(0xffff)
			C.syscall(sys_getcpu, voidptr(&here), unsafe { nil }, unsafe { nil })
			stdatomic.store_i64(&deep_seen_on[cpu], i64(here))
		}
	}
}

// The user time /proc/stat has for each CPU, in hundredths of a second.
fn cpu_user_ticks(cpus int) []i64 {
	mut ticks := []i64{len: cpus}
	text := read_text('/proc/stat') or { return ticks }
	for line in text.split_into_lines() {
		words := line.fields()
		if words.len < 2 || !words[0].starts_with('cpu') || words[0] == 'cpu' {
			continue
		}
		number := words[0][3..].int()
		if number >= 0 && number < cpus {
			ticks[number] = words[1].i64()
		}
	}
	return ticks
}

// Every CPU must run its pinned thread, on that CPU, and be billed for it.
fn check_every_cpu(mut t Test, cpus int, when string) {
	before_ticks := cpu_user_ticks(cpus)
	mut before := []u64{len: cpus}
	for cpu in 0 .. cpus {
		before[cpu] = stdatomic.load_u64(&deep_counts[cpu])
		stdatomic.store_i64(&deep_seen_on[cpu], -1)
	}
	stdatomic.store_u64(&deep_running, 1)
	sleep_ms(800)
	stdatomic.store_u64(&deep_running, 0)
	sleep_ms(50)
	after_ticks := cpu_user_ticks(cpus)
	mut summary := []string{}
	for cpu in 0 .. cpus {
		counted := stdatomic.load_u64(&deep_counts[cpu]) - before[cpu]
		seen := stdatomic.load_i64(&deep_seen_on[cpu])
		billed := after_ticks[cpu] - before_ticks[cpu]
		t.check(counted > 0, '${when}: the thread pinned to CPU ${cpu} did not run')
		t.check(seen == cpu, '${when}: the thread pinned to CPU ${cpu} found itself on CPU ${seen}')
		t.check(billed >= 2, '${when}: /proc/stat billed CPU ${cpu} ${billed} ticks of user time in 0.8 s of a thread spinning on it')
		summary << '${counted}/${billed}'
	}
	t.info('${when}: counts/ticks on each CPU: ${summary.join(' ')}')
}

// The sequence memory and its check are made of: xorshift64.
fn next_word(previous u64) u64 {
	mut x := previous
	x ^= x << 13
	x ^= x >> 7
	x ^= x << 17
	return x
}

fn fill_memory(mut words []u64) {
	mut value := u64(0x9e3779b97f4a7c15)
	for i in 0 .. words.len {
		value = next_word(value)
		words[i] = value
	}
}

// The index of the first word that is not what fill_memory() put there.
fn memory_damage(words []u64) int {
	mut value := u64(0x9e3779b97f4a7c15)
	for i in 0 .. words.len {
		value = next_word(value)
		if words[i] != value {
			return i
		}
	}
	return -1
}

// Reads a pattern that is expected to be on a device already.
fn read_pattern(path string, offset i64, seed u8, length int) ! {
	expected := pattern_bytes(seed, length)
	fd := C.open(&char(path.str), C.O_RDONLY)
	if fd < 0 {
		return errno_error(path)
	}
	defer {
		C.close(fd)
	}
	mut found := []u8{len: length}
	if C.pread(fd, found.data, usize(length), offset) != length {
		return errno_error('${path}: read at ${offset}')
	}
	for i in 0 .. length {
		if found[i] != expected[i] {
			return error('byte ${i} at ${offset} is 0x${found[i].hex()}, not 0x${expected[i].hex()}')
		}
	}
}

struct DeepRun {
mut:
	cpus    int
	memory  []u64
	screen  Screen
	drawn   bool
	sleeps  int // suspends to RAM that worked
	iommu   bool
	card    string
	controller string
}

// What must hold after every sleep, whichever way it ended.
fn (mut run DeepRun) check_machine(mut t Test, when string, thorough bool) {
	check_every_cpu(mut t, run.cpus, when)
	t.check(network_works(20), '${when}: the network does not work')
	// The pattern written before the first sleep, which may come from the
	// kernel's cache; a megabyte of disk nothing has read yet, which cannot;
	// and a new pattern, out and back.
	read_pattern(deep_disk, 1 << 20, 0x31, deep_pattern_bytes) or {
		t.check(false, '${when}: the pattern from before the sleep: ${err.msg()}')
	}
	fresh := deep_prefill_base + (i64(run.sleeps) << 20)
	read_pattern(deep_disk, fresh, u8(0x40 + run.sleeps), deep_pattern_bytes) or {
		t.check(false, '${when}: disk never read before: ${err.msg()}')
	}
	write_pattern(deep_disk, i64(2 + run.sleeps) << 20, u8(0x70 + run.sleeps), deep_pattern_bytes) or {
		t.check(false, '${when}: a new pattern: ${err.msg()}')
	}
	if run.drawn {
		wrong := run.screen.pattern_errors()
		t.check(wrong == 0, "${when}: ${wrong} pixels of what was drawn on the screen are gone; ${run.screen.first_error()}; ${run.screen.error_map()}")
	}
	if run.iommu {
		t.check(dma_line(run.card) == 'domain: dmar0 isolated', '${when}: the card says "${dma_line(run.card)}"')
		t.check(dma_line(run.controller) == 'domain: dmar0 isolated', '${when}: the disk controller says "${dma_line(run.controller)}"')
		state := read_text('/sys/class/iommu/dmar0/state') or { '' }
		t.check(state.contains('on'), '${when}: dmar0 is not on: "${state.replace('\n', ' | ')}"')
	}
	if thorough {
		damaged := memory_damage(run.memory)
		t.check(damaged < 0, '${when}: memory differs from what was written at word ${damaged} of ${run.memory.len}')
	}
}

// One suspend to RAM: writes `mem`, and checks what the clocks and the
// kernel's account say about it. `least_ms` and `most_ms` bound how long the
// machine may have been away by the wall clock.
fn (mut run DeepRun) sleep(mut t Test, what string, wake string, least_ms i64, most_ms i64) {
	frozen_from := stdatomic.load_u64(&deep_free_count)
	mono_before := monotonic_ms()
	real_before := realtime_ms()
	write_text('/sys/power/state', 'mem') or { t.check(false, '${what}: writing mem to state: ${err.msg()}') }
	mono_after := monotonic_ms()
	real_after := realtime_ms()
	frozen := stdatomic.load_u64(&deep_free_count) - frozen_from
	run.sleeps++

	mono := mono_after - mono_before
	real := real_after - real_before
	t.check(mono >= 0, '${what}: the monotonic clock went back ${-mono} ms')
	t.check(real >= least_ms && real <= most_ms, '${what}: the wall clock moved on ${real} ms; between ${least_ms} and ${most_ms} was expected')
	// Both clocks are moved on by the same amount; they are read a moment
	// apart.
	t.check(real - mono > -200 && real - mono < 200, '${what}: the wall clock moved ${real} ms and the monotonic clock ${mono} ms')
	t.check(deep_stat('last_depth') == 'deep', '${what}: last_depth is ${deep_stat('last_depth')}, not deep')
	t.check(deep_stat('last_wake') == wake, '${what}: last_wake is ${deep_stat('last_wake')}, not ${wake}')
	t.check(deep_stat('deep') == run.sleeps.str(), '${what}: ${deep_stat('deep')} suspends to RAM counted, not ${run.sleeps}')
	t.check(deep_stat('security_changes') == '0', '${what}: CPU protections changed across the sleep')
	t.check(deep_stat('security_cpus') == run.cpus.str(), '${what}: the protections of ${deep_stat('security_cpus')} CPUs were compared, not of ${run.cpus}')
	asleep := deep_stat('last_sleep_ms').i64()
	// Awake, the free thread counts about this much in the time the machine
	// was down; frozen and then powered off, a small part of it.
	rate := free_rate()
	t.check(frozen < u64(rate) * u64(asleep) / 300 / 4 || asleep < 300, '${what}: userspace ran while asleep: ${frozen} counts in ${asleep} ms, ${rate} per 300 ms awake')
	t.info('${what}: woke by ${deep_stat('last_wake')} after ${asleep} ms; wall clock +${real} ms; down in ${deep_stat('last_suspend_ms')} ms, back in ${deep_stat('last_resume_ms')} ms')
}

// How far the free thread counts in 300 ms awake.
fn free_rate() i64 {
	from := stdatomic.load_u64(&deep_free_count)
	sleep_ms(300)
	return i64(stdatomic.load_u64(&deep_free_count) - from)
}

fn deep_scenario(mut t Test, iommu bool) {
	mut run := DeepRun{
		cpus:  cpu_count()
		iommu: iommu
	}
	t.check(run.cpus == 4, 'the machine has ${run.cpus} CPUs, not the 4 the scenario asks QEMU for')
	if run.cpus > deep_max_cpus {
		run.cpus = deep_max_cpus
	}
	offered := read_word('/sys/power/mem_sleep')
	t.info('mem_sleep: ${offered}; deep_sleep: ${read_word('/sys/power/deep_sleep')}')
	if !t.check(offered.contains('deep'), 'mem_sleep does not offer deep: "${offered}"') {
		return
	}
	t.check(offered.contains('[s2idle]'), 'mem_sleep does not start at s2idle: "${offered}"')
	write_text('/sys/power/mem_sleep', 'deep') or { t.check(false, 'selecting deep: ${err.msg()}') }
	t.check(read_word('/sys/power/mem_sleep') == 's2idle [deep]', 'deep did not stick: "${read_word('/sys/power/mem_sleep')}"')

	if iommu {
		run.card = bound_device('e1000')
		run.controller = bound_device('ahci')
		t.check(run.card != '' && run.controller != '', 'the card or the disk controller is not bound')
	}

	// What is to be found again afterwards.
	run.memory = []u64{len: deep_memory_bytes / 8}
	fill_memory(mut run.memory)
	write_pattern(deep_disk, 1 << 20, 0x31, deep_pattern_bytes) or { t.check(false, 'disk before the sleep: ${err.msg()}') }
	t.check(network_works(20), 'the network does not work before any sleep')
	if screen := open_screen() {
		run.screen = screen
		run.screen.draw_pattern()
		run.drawn = true
		t.check(run.screen.pattern_errors() == 0, "what was drawn on the screen does not read back: ${run.screen.pattern_errors()} pixels differ")
		t.info("screen: ${screen.width} by ${screen.height}, pattern drawn")
	} else {
		t.check(false, 'the screen: ${err.msg()}')
	}
	for cpu in 0 .. run.cpus {
		spawn count_on_cpu(cpu)
	}
	spawn count_freely()
	sleep_ms(200)
	check_every_cpu(mut t, run.cpus, 'before any sleep')
	t.step('screen drawn')
	sleep_ms(1000)

	// Ended by the host, once QEMU says the machine is suspended. QEMU's
	// ACPI reports that as the power button.
	t.step('deep sleep for a wakeup')
	run.sleep(mut t, 'wakeup', 'power-button', 1000, 60000)
	run.check_machine(mut t, 'after the wakeup', true)

	// Ended by the clock's alarm.
	write_text('/sys/class/rtc/rtc0/wakealarm', '+4') or { t.check(false, 'wakealarm: ${err.msg()}') }
	run.sleep(mut t, 'alarm', 'alarm', 2500, 60000)
	t.check(read_word('/sys/class/rtc/rtc0/wakealarm') == '', 'the alarm that went off still reads back')
	run.check_machine(mut t, 'after the alarm', true)

	// Ended by a key.
	t.step('deep sleep for a key')
	run.sleep(mut t, 'key', 'keyboard', 1000, 60000)
	run.check_machine(mut t, 'after the key', true)

	// And five more, one after another.
	for cycle in 0 .. 5 {
		write_text('/sys/class/rtc/rtc0/wakealarm', '+2') or { t.check(false, 'wakealarm: ${err.msg()}') }
		run.sleep(mut t, 'cycle ${cycle + 1}', 'alarm', 500, 60000)
	}
	run.check_machine(mut t, 'after five more sleeps', true)

	t.check(deep_stat('success') == run.sleeps.str(), 'success is ${deep_stat('success')}, not ${run.sleeps}')
	t.check(deep_stat('fail') == '0', 'fail is ${deep_stat('fail')}')
	t.check(deep_stat('security_changes') == '0', 'CPU protections changed across a sleep')
	if iommu {
		caught := read_text('/sys/class/iommu/dmar0/faults') or { 'unreadable' }
		t.check(caught.contains('count: 0'), 'dmar0 recorded a fault: "${caught.replace('\n', ' | ')}"')
		t.info('dmar0: card and disk controller isolated after ${run.sleeps} suspends to RAM; faults says count: 0')
	}
	t.step('screen after the sleeps')
	sleep_ms(1500)
}

fn scenario_suspend_deep(mut t Test) {
	deep_scenario(mut t, false)
}

fn scenario_suspend_deep_iommu(mut t Test) {
	deep_scenario(mut t, true)
}
