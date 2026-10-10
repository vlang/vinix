// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The other processors: parked before a suspend to RAM, started again after.
//
// Firmware brings one processor back from S3, the one the machine boots on.
// The others are as they are after power-on: stopped, waiting for a startup
// IPI, with nothing of what the kernel programmed into them. So none of them
// may hold anything when the machine goes down. This scheduler makes that
// easy to arrange: a processor that is idle holds no thread, no lock and no
// stack contents (sched/park_amd64.v), so each is made idle and kept there,
// and what is saved for it is only what is the processor's own and not in
// memory -- its local APIC -- which it reads out itself as it parks.
//
// It is not given a saved register context to come back to, as the sleeping
// processor is. There would be nothing in one: an idle processor's next
// instruction is always "start the idle loop from the top of the idle stack",
// which is what a processor does at boot once it has been set up. So a
// processor that is started again is set up again, by the same code that set
// it up at boot (x86.cpu.initialisation.reinitialise()), and enters the idle
// loop the way it did then. The scheduler's record of it -- its queue, its
// number, its stacks, its TSS -- was in memory all along.
//
// Starting is INIT, then a startup IPI naming the trampoline page, as the
// MultiProcessor specification has it. It is done the same way whether or
// not the machine lost power: a parked processor sits halted with interrupts
// off, and INIT is what gets it out of that, too. That keeps one path, and
// has a sleep that firmware refused exercise the same code as one that
// happened.
@[has_globals]
module wake

import cpufreq
import devcore
import katomic
import sched
import x86.apic
import x86.cpu.initialisation as cpuinit
import x86.cpu.local as cpulocal
import x86.hypervisor

fn C.x86_wake_secondary()

// How long the processors are given to reach the idle loop and park: each
// does at its next scheduler interrupt, a time slice away at most, unless it
// is in a long stretch with interrupts off.
const park_timeout_ns = 2 * devcore.second
// INIT to startup, and startup to startup, by the specification.
const init_settle_ns = 10 * devcore.millisecond
const startup_settle_ns = 200 * devcore.microsecond
// How long a started processor may take to set itself up and say so. It is
// waited for with interrupts off, on the only processor running.
const start_timeout_ns = 2 * devcore.second
// How long a processor that has gone offline may take to say it has parked:
// there is nothing between the two but reading out its APIC.
const commit_timeout_ns = devcore.second

const max_cpus = 256

// Where a processor is in being parked and started again.
const state_running = u32(0)
// Online when parking began, and asked to park.
const state_asked = u32(1)
// Parked: offline, its APIC read out, halted.
const state_parked = u32(2)
// It parked and did not start again. It is not asked or started a second
// time: nothing is known about what it is doing.
const state_lost = u32(3)

__global (
	x86wake_state [max_cpus]u32
	// Each processor's local APIC as it read it out when it parked.
	x86wake_lapics      &apic.LocalState
	x86wake_lapic_count u64
	// Processors that did not come back, over the life of the machine.
	x86wake_lost u64
)

// Runs on a processor as it parks: offline, interrupts off, about to halt.
fn parking_processor(cpu_number u64) {
	if cpu_number < x86wake_lapic_count {
		unsafe {
			x86wake_lapics[cpu_number] = apic.lapic_save()
		}
	}
	hypervisor.leave_cpu(cpu_number)
	if cpu_number < max_cpus {
		katomic.store(mut &x86wake_state[cpu_number], state_parked)
	}
}

// Room for every processor's APIC state, and the hook that fills it. Called
// once, when every processor is known. False without the memory.
fn prepare_secondaries() bool {
	if x86wake_lapics != unsafe { nil } {
		return true
	}
	count := u64(cpu_locals.len)
	if count > max_cpus {
		return false
	}
	x86wake_lapics = unsafe { &apic.LocalState(malloc(count * sizeof(apic.LocalState))) }
	if x86wake_lapics == unsafe { nil } {
		return false
	}
	unsafe { C.memset(voidptr(x86wake_lapics), 0, count * sizeof(apic.LocalState)) }
	x86wake_lapic_count = count
	sched.set_park_hook(voidptr(parking_processor))
	return true
}

fn all_parked(_ voidptr) bool {
	for entry in cpu_locals {
		if katomic.load(&x86wake_state[entry.cpu_number]) == state_asked {
			return false
		}
	}
	return true
}

// Park every processor but this one, the boot processor, that is running: one
// that was lost in an earlier sleep is not waited for. False if one would not
// within the time allowed; the ones that did are parked all the same and
// start_secondaries() is what brings them back.
pub fn park_secondaries() bool {
	for entry in cpu_locals {
		number := entry.cpu_number
		if number == 0 || katomic.load(&x86wake_state[number]) == state_lost {
			continue
		}
		katomic.store(mut &x86wake_state[number], if katomic.load(&entry.online) != 0 {
			state_asked
		} else {
			state_running
		})
	}
	sched.park_others(0)
	// Sleeping, not spinning: this processor has the threads the others put
	// down to run.
	return devcore.sleep_until(all_parked, unsafe { nil }, park_timeout_ns, 1)
}

fn is_online(context voidptr) bool {
	cpu_local := unsafe { &cpulocal.Local(context) }
	return katomic.load(&cpu_local.online) != 0
}

fn has_parked(context voidptr) bool {
	cpu_local := unsafe { &cpulocal.Local(context) }
	return katomic.load(&x86wake_state[cpu_local.cpu_number]) == state_parked
}

// Start one parked processor and wait for it to be scheduling again.
fn start_secondary(mut cpu_local cpulocal.Local) bool {
	arm(u64(voidptr(C.x86_wake_secondary)), cpu_local.idle_int_stack, u64(voidptr(cpu_local)))
	apic.lapic_send_init(cpu_local.lapic_id)
	devcore.stall(init_settle_ns)
	page := u8(entry_address() >> 12)
	apic.lapic_send_startup(cpu_local.lapic_id, page)
	devcore.stall(startup_settle_ns)
	mut started := is_online(voidptr(cpu_local))
	if !started {
		// The second one is ignored by a processor the first one started.
		apic.lapic_send_startup(cpu_local.lapic_id, page)
		started = devcore.spin_until(is_online, voidptr(cpu_local), start_timeout_ns)
	}
	disarm()
	return started
}

// End the parking and start every processor that parked, one after another:
// the trampoline has one stack and one argument to hand over at a time.
// Returns how many did not come back. Called on the boot processor; it does
// not need interrupts. Calling it again when all are back does nothing.
pub fn start_secondaries() int {
	// From here no processor goes offline that has not already.
	sched.end_parking()
	mut missing := 0
	for mut entry in cpu_locals {
		number := entry.cpu_number
		if number == 0 {
			continue
		}
		if katomic.load(&x86wake_state[number]) == state_asked {
			if katomic.load(&entry.online) != 0 {
				// It never got as far as parking, and now will not.
				katomic.store(mut &x86wake_state[number], state_running)
				continue
			}
			// Offline and not yet parked: between the two, with only its
			// APIC to read out in between.
			devcore.spin_until(has_parked, voidptr(entry), commit_timeout_ns)
		}
		state := katomic.load(&x86wake_state[number])
		if state != state_parked && state != state_asked {
			continue
		}
		if state == state_parked && start_secondary(mut entry) {
			katomic.store(mut &x86wake_state[number], state_running)
			continue
		}
		// It parked and did not start, or went offline and never said it
		// had parked. Either way it is gone, and is counted once.
		katomic.store(mut &x86wake_state[number], state_lost)
		missing++
		katomic.inc(mut &x86wake_lost)
		C.kprintf(c'wake: CPU %llu did not start again\n', number)
	}
	return missing
}

// How many processors have failed to come back from a sleep.
pub fn lost_processors() u64 {
	return katomic.load(&x86wake_lost)
}

// Where the trampoline sends a processor that is being started again, by way
// of x86_wake_secondary: long mode, the trampoline's page table and GDT, the
// processor's idle stack.
@[export: 'x86_wake_secondary_entry']
fn secondary_entry(context voidptr) {
	mut cpu_local := unsafe { &cpulocal.Local(context) }
	cpuinit.reinitialise(mut cpu_local)
	number := cpu_local.cpu_number
	if number < x86wake_lapic_count {
		apic.lapic_restore(unsafe { &x86wake_lapics[number] })
	} else {
		apic.lapic_enable(0xff)
	}
	apic.lapic_timer_stop()
	// Its frequency registers are as power-on left them.
	cpufreq.cpu_lost_power(number)
	katomic.store(mut &cpu_local.online, u64(1))
	sched.enter_idle()
}

// Everything that has to be in place before a sleep can be offered: the
// trampoline in its page, and room for what is saved. Called once at boot,
// when every processor is running.
pub fn initialise() bool {
	if !available() {
		return false
	}
	if !prepare_context() || !prepare_secondaries() {
		x86wake_unavailable = 'no memory to save the processors in'
		x86wake_page = 0
		return false
	}
	return true
}
