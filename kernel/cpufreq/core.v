// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// CPU frequency and performance control: the policies, and the worker that
// keeps the hardware to them.
//
// The pieces:
//
//	limit.v            the thermal limit, shared with thermal management
//	policy.v           governors, preferences, profiles and their arithmetic,
//	                   as functions of plain values
//	core.v             this: one policy per CPU or per cluster, the driver's
//	                   entry points, the sampling worker, set_profile()
//	sysfs.v            /sys/devices/system/cpu/cpuN/cpufreq, as on Linux
//	driver_amd64.v     Intel HWP, Intel Enhanced SpeedStep, AMD CPPC
//	driver_arm64.v     Apple cluster DVFS
//
// A driver fills in the policies and four functions. When none fits the
// machine -- every virtual machine, where the host owns the clock -- the
// driver is "none": the policies say what frequency the CPUs run at, as far
// as that is known, nothing can be changed, and no worker runs.
//
// With a driver, one kernel thread wakes ten times a second. For each policy
// it works out how busy the CPUs were (proc.machine_cpu_times), and hands the
// policy to the driver, which turns the governor, the allowed range and the
// preference into what its hardware takes. A change made through /sys or
// set_profile(), or a new thermal limit, goes the same way at once.
@[has_globals]
module cpufreq

import devcore
import klock
import numa
import proc
import sched

// The CPUs a policy can speak for, and so at most as many policies: the
// scheduler's affinity masks are 64 bits wide, and /sys has directories for
// that many CPUs.
pub const max_cpus = 64

// How often the worker looks at the load. Linux's governors sample between
// every 10 ms and every 100 ms; the coarse end is enough to follow a load and
// costs an idle machine ten wake-ups a second.
const sample_ms = u64(100)

// What is wanted of one CPU, or of the CPUs that share a clock.
pub struct Policy {
pub mut:
	// The CPUs it speaks for: the lowest, and all of them as a mask.
	first_cpu u32
	cpus      u64
	limits    Limits
	governor   Governor
	preference Preference
	// How busy its busiest CPU was over the last interval, in thousandths.
	utilisation u32
	// What the governor last asked for, in kHz.
	wanted_khz u64
	// The driver's own word for this policy: a cluster's number.
	unit u32
}

// What a driver provides. Set once, before the policies are published.
struct Driver {
mut:
	name string
	// Whether anything can be changed. False for "none".
	settable bool
	// Whether the hardware takes an energy/performance preference.
	has_preference bool
	// Put the policy as it now stands into effect. Called with cpufreq_lock
	// held, from the worker or from whoever changed the policy.
	apply fn (index int, mut policy Policy) = unsafe { nil }
	// The frequency the policy's CPUs are running at, in kHz, or 0 when the
	// hardware does not say.
	current fn (index int, policy &Policy) u64 = unsafe { nil }
}

__global (
	cpufreq_driver       Driver
	cpufreq_policies     [max_cpus]Policy
	cpufreq_policy_count int
	// The policy of each CPU, plus one. Zero for a CPU that has none.
	cpufreq_policy_of [max_cpus]u16
	// Serializes changes to the policies and the driver's apply().
	cpufreq_lock          klock.Lock
	cpufreq_profile_value Profile
	cpufreq_started       bool
	// What the worker last saw of each CPU, for the next difference.
	cpufreq_busy_ns [max_cpus]u64
	cpufreq_seen_ns [max_cpus]u64
	// The thermal limit's generation the policies were last applied under.
	cpufreq_applied_generation u64
)

// The machine-wide profile in force.
pub fn profile() Profile {
	return cpufreq_profile_value
}

// Set the governor and preference of every policy from one word. This is the
// entry point for power management: balanced on mains, power_saver on
// battery. False when the machine has no frequency control to set.
pub fn set_profile(wanted Profile) bool {
	if !cpufreq_driver.settable {
		return false
	}
	cpufreq_lock.acquire()
	cpufreq_profile_value = wanted
	for i in 0 .. cpufreq_policy_count {
		mut policy := unsafe { &cpufreq_policies[i] }
		policy.governor = profile_governor(wanted)
		policy.preference = profile_preference(wanted)
		apply_policy(i, mut policy)
	}
	cpufreq_lock.release()
	return true
}

// The policy that covers `cpu_number`, or nil.
fn policy_for(cpu_number u64) (&Policy, int) {
	if cpu_number >= max_cpus || cpufreq_policy_of[cpu_number] == 0 {
		return unsafe { nil }, -1
	}
	index := int(cpufreq_policy_of[cpu_number]) - 1
	return unsafe { &cpufreq_policies[index] }, index
}

// Add a policy for the CPUs in `cpus`. For the driver, while it starts.
fn add_policy(cpus u64, limits Limits, governor Governor, preference Preference, unit u32) int {
	if cpus == 0 || cpufreq_policy_count >= max_cpus {
		return -1
	}
	index := cpufreq_policy_count
	mut first := u32(0)
	for first < 64 && cpus & (u64(1) << first) == 0 {
		first++
	}
	mut filled := limits
	filled.user_min_khz = limits.hw_min_khz
	filled.user_max_khz = limits.hw_max_khz
	cpufreq_policies[index] = Policy{
		first_cpu:  first
		cpus:       cpus
		limits:     filled
		governor:   governor
		preference: preference
		wanted_khz: limits.hw_max_khz
		unit:       unit
	}
	for cpu_number in 0 .. 64 {
		if cpus & (u64(1) << u32(cpu_number)) != 0 {
			cpufreq_policy_of[cpu_number] = u16(index + 1)
		}
	}
	cpufreq_policy_count = index + 1
	return index
}

// Work out what the governor asks for and hand the policy to the driver.
// With cpufreq_lock held.
fn apply_policy(index int, mut policy Policy) {
	lowest, highest := allowed_range(policy.limits, thermal_limit())
	policy.wanted_khz = target_khz(policy.governor, policy.preference, policy.utilisation,
		lowest, highest)
	if cpufreq_driver.apply != unsafe { nil } {
		cpufreq_driver.apply(index, mut policy)
	}
}

// How busy the policy's busiest CPU has been since the last look, in
// thousandths. One CPU of a cluster at full load needs the cluster's clock
// however idle the others are.
fn sample_utilisation(policy &Policy) u32 {
	now := proc.cpu_time_now_ns()
	mut busiest := u32(0)
	for cpu_number in 0 .. 64 {
		if policy.cpus & (u64(1) << u32(cpu_number)) == 0 {
			continue
		}
		user, system, _ := proc.machine_cpu_times(cpu_number, now)
		busy := user + system
		before_busy := cpufreq_busy_ns[cpu_number]
		before_seen := cpufreq_seen_ns[cpu_number]
		cpufreq_busy_ns[cpu_number] = busy
		cpufreq_seen_ns[cpu_number] = now
		if before_seen == 0 || now <= before_seen || busy < before_busy {
			continue
		}
		share := utilisation_permille(busy - before_busy, now - before_seen)
		if share > busiest {
			busiest = share
		}
	}
	return busiest
}

fn worker() {
	for {
		devcore.sleep_ms(sample_ms)
		cpufreq_lock.acquire()
		cpufreq_applied_generation = limit_generation()
		for i in 0 .. cpufreq_policy_count {
			mut policy := unsafe { &cpufreq_policies[i] }
			policy.utilisation = sample_utilisation(policy)
			apply_policy(i, mut policy)
		}
		cpufreq_lock.release()
	}
}

// Find the machine's frequency control and start keeping to the policies.
// Once, from publish().
fn start() {
	if cpufreq_started {
		return
	}
	cpufreq_started = true
	cpufreq_profile_value = .balanced
	mut count := numa.cpu_count()
	if count > max_cpus {
		count = max_cpus
	}
	driver_start(count)
	if !cpufreq_driver.settable {
		// Nothing to set: the CPUs run as fast as they run.
		cpufreq_profile_value = .performance
		return
	}
	cpufreq_lock.acquire()
	for i in 0 .. cpufreq_policy_count {
		mut policy := unsafe { &cpufreq_policies[i] }
		apply_policy(i, mut policy)
	}
	cpufreq_lock.release()
	sched.new_kernel_thread(voidptr(worker), unsafe { nil }, true)
}
