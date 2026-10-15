// SPDX-License-Identifier: GPL-2.0-or-later
// Actual staged worker-priority V body; explicit host observation transport.
@[has_globals; translated]
module workerpriorityfixture

#include "contract.h"

fn C.printf(&char, ...)

@[noreturn]
fn C.exit(int)

fn C.memset(voidptr, int, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) int
fn C.vinix_linuxkpi_worker_set_nice(i32) int
fn C.wph_historical_identity(i32) int
fn C.wph_historical_irq(i32) int
fn C.wph_set_preempt(u32, u32)
fn C.wph_get_preempt(u32) u32

pub struct Process {
pub mut:
	nice     int
	identity u64
}

pub struct Thread {
pub mut:
	process                 &Process = unsafe { nil }
	is_dead                 bool
	sched_nice_override     int
	sched_has_nice_override bool
	affinity_mask           u64
	linuxkpi_migration_pin  u64
	numa_node               int
	cookie                  [4]u64
}

pub struct Local {
pub mut:
	cpu_number         u64
	maskable_irq_depth u32
	cookie             u64
}

__global (
	owner            Process
	other_owner      Process
	task             Thread
	current_task     &Thread
	cpu_state        Local
	irq_enabled      bool
	preempt_value    u32
	toggle_count     u32
	task_queries     u32
	store_count      u32
	reschedules      u32
	assertions       u32
	cases            u32
	historical_cases u32
	expected_nice    int
	before_task      Thread
	before_owner     Process
	before_other     Process
	before_local     Local
)

pub fn check(ok bool, code int) {
	assertions++
	if !ok {
		C.printf(c'FAIL: worker priority condition %d case=%u\n', code, cases)
		C.exit(1)
	}
}

pub fn current() &Thread {
	task_queries++
	return current_task
}

pub fn cpu_local() &Local { return unsafe { &cpu_state } }

pub fn kernel_owner() &Process { return unsafe { &owner } }

pub fn interrupt_toggle(next bool) bool {
	prior := irq_enabled
	irq_enabled = next
	toggle_count++
	return prior
}

pub fn load[T](value &T) T { return unsafe { *value } }

pub fn store[T](value &T, item T) {
	check(!irq_enabled, 1)
	if sizeof(T) == 1 {
		check(store_count == 1 && voidptr(value) == unsafe { voidptr(&task.sched_has_nice_override) } && bool(item), 2)
		unsafe { *value = item }
	} else {
		check(store_count == 0 && voidptr(value) == unsafe { voidptr(&task.sched_nice_override) } && int(item) == expected_nice, 3)
		unsafe { *value = item }
	}
	store_count++
}

pub fn reschedule() {
	check(irq_enabled && preempt_value == 0 && store_count == 2 && task.sched_has_nice_override && task.sched_nice_override == expected_nice, 4)
	reschedules++
}

@[export:'wph_fixed_index']
pub fn fixed_index(index i64, length i64) i64 {
	check(index >= 0 && index < length, 5)
	return index
}

@[export:'wph_fixed_index_u64']
pub fn fixed_index_unsigned(index u64, length i64) i64 {
	check(length >= 0 && index < u64(length), 6)
	return i64(index)
}

fn configure(cpu u32, nice int, flag bool) {
	unsafe { C.memset(&task, 0, sizeof(Thread)) }
	owner = Process{ nice: 7, identity: 0x1234 }
	other_owner = owner
	task.process = kernel_owner()
	task.sched_nice_override = nice
	task.sched_has_nice_override = flag
	task.affinity_mask = 0x1111222233334444
	task.linuxkpi_migration_pin = (u64(3) << 32) | u64(cpu + 1)
	task.numa_node = 41
	task.cookie = [u64(1), u64(17), u64(0x12345678), ~u64(0)]!
	current_task = unsafe { &task }
	cpu_state = Local{ cpu_number: u64(cpu), cookie: 0x5678 }
	irq_enabled = true
	preempt_value = 0
	C.wph_set_preempt(cpu, 0)
	toggle_count = 0
	task_queries = 0
	store_count = 0
	reschedules = 0
}

fn capture() {
	unsafe {
		C.memcpy(&before_task, &task, sizeof(Thread))
		C.memcpy(&before_owner, &owner, sizeof(Process))
		C.memcpy(&before_other, &other_owner, sizeof(Process))
		C.memcpy(&before_local, &cpu_state, sizeof(Local))
	}
}

fn unchanged(success bool) bool {
	if success {
		before_task.sched_nice_override = expected_nice
		before_task.sched_has_nice_override = true
	}
	return unsafe { C.memcmp(&before_task, &task, sizeof(Thread)) } == 0 && unsafe { C.memcmp(&before_owner, &owner, sizeof(Process)) } == 0
		&& unsafe { C.memcmp(&before_other, &other_owner, sizeof(Process)) } == 0 && unsafe { C.memcmp(&before_local, &cpu_state, sizeof(Local)) } == 0
}

fn invoke(nice i32, expected int, initial_if bool, toggles u32, queries u32) {
	expected_nice = int(nice)
	capture()
	check(C.vinix_linuxkpi_worker_set_nice(nice) == expected, 7)
	check(irq_enabled == initial_if && toggle_count == toggles && task_queries == queries && unchanged(expected == 0) && C.wph_get_preempt(u32(cpu_state.cpu_number)) == preempt_value, 8)
	check(store_count == if expected == 0 { 2 } else { 0 }, 9)
	check(reschedules == if expected == 0 { 1 } else { 0 }, 10)
	cases++
}

fn valid_matrix() {
	for cpu in u32(0) .. u32(256) {
		for prior in [-20, 0, 19]! {
			for flag in [false, true]! {
				for nice in -20 .. 20 {
					configure(cpu, prior, flag)
					invoke(i32(nice), 0, true, 2, 1)
				}
			}
		}
	}
}

fn refusal_matrix() {
	for cpu in [u32(0), u32(1), u32(63), u32(64), u32(255)]! {
		for nice in [i32(-2147483648), i32(-21), i32(-20), i32(0), i32(19), i32(20), i32(2147483647)]! {
			for ints in [false, true]! {
				for preempt in [u32(0), u32(1), u32(17)]! {
					for irq in [u32(0), u32(1), u32(3)]! {
						for identity in 0 .. 5 {
							configure(cpu, -7, true)
							irq_enabled = ints
							preempt_value = preempt
							C.wph_set_preempt(cpu, preempt)
							cpu_state.maskable_irq_depth = irq
							match identity {
								0 {}
								1 { current_task = unsafe { nil } }
								2 { task.process = unsafe { &other_owner } }
								3 { task.process = unsafe { nil } }
								else { task.is_dead = true }
							}
							if nice < -20 || nice > 19 {
								invoke(nice, -22, ints, 0, 0)
							} else if !ints || preempt != 0 || irq != 0 {
								invoke(nice, -11, ints, 2, 0)
							} else {
								invoke(nice, if identity == 0 { 0 } else { -1 }, ints, 2, 1)
							}
						}
					}
				}
			}
		}
	}
}

fn historical_controls() {
	configure(0, -7, false)
	task.process = unsafe { &other_owner }
	expected_nice = -20
	capture()
	check(C.wph_historical_identity(-20) == 0 && unchanged(true) && store_count == 2 && reschedules == 1, 11)
	historical_cases++
	configure(0, -7, false)
	cpu_state.maskable_irq_depth = 1
	expected_nice = -20
	capture()
	check(C.wph_historical_irq(-20) == 0 && unchanged(true) && store_count == 2 && reschedules == 1, 12)
	historical_cases++
}

@[export:'main']
pub fn run() int {
	valid_matrix()
	refusal_matrix()
	historical_controls()
	C.printf(c'PASS: V worker nice ownership, maskable IRQ refusal, publication and error precedence; cases=%u historical=%u assertions=%u\n', cases, historical_cases, assertions)
	return 0
}
