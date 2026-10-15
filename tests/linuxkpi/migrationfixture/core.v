// SPDX-License-Identifier: GPL-2.0-or-later
// Real generated migration/policy/queue bodies; explicit host observations.
@[has_globals; translated]
module migrationfixture

#include "contract.h"

@[typedef]
struct C.mh_array {
mut:
	data         voidptr
	len          i64
	cap          i64
	element_size i64
}

@[typedef]
struct C.mh_string {
	str &u8
	len i64
}

@[typedef]
struct C.mh_jump {}

@[typedef]
struct C.mh_thread {}

fn C.memset(voidptr, int, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) int
fn C.strstr(&char, &char) &char
fn C.printf(&char, ...)

@[noreturn]
fn C.exit(int)

fn C.mh_setjmp(voidptr) int

@[noreturn]
fn C.mh_longjmp(voidptr)

fn C.pthread_create(voidptr, voidptr, fn (voidptr) voidptr, voidptr) int
fn C.pthread_join(C.mh_thread, voidptr) int
fn C.sched_yield() int

@[c:'__atomic_load_n']
fn C.load8(&u8, int) u8

@[c:'__atomic_load_n']
fn C.load32(&u32, int) u32

@[c:'__atomic_load_n']
fn C.load64(&u64, int) u64

@[c:'__atomic_store_n']
fn C.store8(&u8, u8, int)

@[c:'__atomic_store_n']
fn C.store32(&u32, u32, int)

@[c:'__atomic_store_n']
fn C.store64(&u64, u64, int)

@[c:'__atomic_fetch_add']
fn C.add32(&u32, u32, int) u32

@[c:'__atomic_compare_exchange_n']
fn C.cas32(&u32, &u32, u32, bool, int, int) bool

fn C.migrate_disable()
fn C.migrate_enable()
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable()
fn C.vinix_linuxkpi_preempt_check_resched()
fn C.vinix_linuxkpi_worker_bind(u32) int
fn C.vinix_linuxkpi_test_worker_route(voidptr, u32) int
fn C.mh_configure_cpus(i64)
fn C.mh_configure_policy()
fn C.mh_configure_bridge()
fn C.mh_get_bridge(u32, u32) u64
fn C.mh_set_bridge(u32, u32, u64)
fn C.mh_configure_queue(u32, voidptr)
fn C.mh_queue_load(u32, u64, u32)
fn C.mh_parking(u32, u64)
fn C.mh_may_run(voidptr, u64) bool
fn C.mh_place(voidptr) u64
fn C.mh_preferred(voidptr, u64) bool
fn C.mh_scan(u64, &i64, bool) voidptr
fn C.mh_request(voidptr, u32) bool
fn C.mh_historical_request(voidptr, u32) bool

pub struct Lock {
pub mut:
	word u32
	role u32
}

pub struct Params {
pub mut:
	util_min        u32
	util_max        u32 = 1024
	dl_abs_deadline u64
}

pub struct State {
pub mut:
	value u64
}

pub struct Process {
pub mut:
	identity u64
}

pub struct Thread {
pub mut:
	self                   voidptr
	process                &Process = unsafe { nil }
	is_dead                bool
	running_on             u64
	linuxkpi_migration_pin u64
	affinity_mask          u64 = ~u64(0)
	numa_node              int = -1
	tid                    int
	sched                  Params
	l                      Lock
	queue_previous         &Thread = unsafe { nil }
	queue_next             &Thread = unsafe { nil }
	queue_cpu              u32
	gpr_state              State
}

pub struct Local {
pub mut:
	cpu_number         u64
	online             u64
	maskable_irq_depth u32
	is_idle            bool
	lapic_id           u32
}

__global (
	records                  [257]Local
	members                  [257]&Local
	tasks                    [3]Thread
	kernel_owner             Process
	other_owner              Process
	current_task             &Thread
	current_local            &Local
	irq_enabled              bool
	wake_count               u32
	wakes                    [1024]u32
	reschedule_count         u32
	load_count               u32
	store_count              u32
	asserts                  u32
	fatal_cases              u32
	race_cases               u32
	affinity_race_cases      u32
	observer_stop            u32
	observer_entered         u32
	capture_tasks            [3]Thread
	capture_records          [257]Local
	capture_bridge           [256][2]u64
	capture_wake             u32
	capture_reschedules      u32
	capture_store            u32
	jump_target              voidptr
	expected_message         &char
	expected_fatal_irq       bool
	allow_fatal_wake         bool
	hook_lock                voidptr
	hook_kind                int
	hook_hits                u32
	held_queue_locks         u32
	thread_releases          u32
	affinity_hook_armed      bool
	affinity_hook_cpu        u32
	affinity_hook_target     u32
	affinity_hook_reads      u32
	affinity_hook_hits       u32
	affinity_hook_historical bool
)

pub fn check(passed bool, code int) {
	unsafe { C.add32(&asserts, 1, 0) }
	if !passed {
		C.printf(c'FAIL: migration condition %d, fatal=%u race=%u\n', code, fatal_cases, race_cases)
		C.exit(1)
	}
}

pub fn (mut value Lock) acquire() {
	check(value.word == 0, 1)
	value.word = 1
	if value.role == 0 { held_queue_locks++ }
}

pub fn (mut value Lock) release() {
	check(value.word == 1, 2)
	value.word = 0
	if value.role == 0 {
		check(held_queue_locks != 0, 48)
		held_queue_locks--
	} else {
		thread_releases++
	}
}

pub fn (mut value Lock) test_and_acquire() bool {
	if voidptr(&value) == hook_lock {
		check(held_queue_locks == 1 && hook_hits == 0, 3)
		hook_hits++
		match hook_kind {
			1 { C.migrate_disable() }
			2 { unsafe { C.store8(&u8(&tasks[0].is_dead), 1, 5) } }
			3 { check(C.vinix_linuxkpi_test_worker_route(unsafe { &tasks[0] }, 0) == 0, 4) }
			else { check(false, 5) }
		}
	}
	mut expected := u32(0)
	return unsafe { C.cas32(&value.word, &expected, 1, false, 5, 5) }
}

pub fn load[T](value &T) T {
	unsafe { C.add32(&load_count, 1, 0) }
	if affinity_hook_armed && sizeof(T) == 8 && voidptr(value) == unsafe { voidptr(&records[affinity_hook_cpu].online) } {
		affinity_hook_reads++
		if affinity_hook_reads == 2 {
			affinity_hook_armed = false
			affinity_hook_hits++
			check(!irq_enabled && tasks[0].linuxkpi_migration_pin == 0, 53)
			check(C.vinix_linuxkpi_test_worker_route(unsafe { &tasks[0] }, affinity_hook_target) == 0, 54)
			// The labeled historical helper fails after this independent valid
			// producer mutation. Its own state must remain unchanged thereafter.
			if affinity_hook_historical { capture() }
		}
	}
	if sizeof(T) == 1 { return T(unsafe { C.load8(&u8(value), 2) }) }
	if sizeof(T) == 4 { return T(unsafe { C.load32(&u32(value), 2) }) }
	return T(unsafe { C.load64(&u64(value), 2) })
}

pub fn store[T](value &T, item T) {
	unsafe { C.add32(&store_count, 1, 0) }
	if sizeof(T) == 1 {
		unsafe { C.store8(&u8(value), u8(item), 5) }
		return
	}
	if sizeof(T) == 4 {
		unsafe { C.store32(&u32(value), u32(item), 5) }
		return
	}
	unsafe { C.store64(&u64(value), u64(item), 5) }
}

@[direct_array_access]
pub fn configure_cpus(descriptor voidptr, count i64) {
	for i in 0 .. 257 {
		records[i] = Local{ cpu_number: u64(i), online: 1, is_idle: true, lapic_id: u32(i + 4096) }
		members[i] = unsafe { &records[i] }
	}
	mut array := unsafe { &C.mh_array(descriptor) }
	unsafe { C.memset(array, 0, sizeof(C.mh_array)) }
	array.data = unsafe { &members[0] }
	array.len = count
	array.cap = count
	array.element_size = sizeof(&Local)
	current_local = unsafe { &records[0] }
}

@[direct_array_access]
pub fn kernel_owner_pointer() &Process { return unsafe { &kernel_owner } }

pub fn current_thread() &Thread { return current_task }

pub fn cpu_local() &Local { return current_local }

pub fn interrupt_state() bool { return irq_enabled }

pub fn interrupt_toggle(next bool) bool {
	prior := irq_enabled
	irq_enabled = next
	return prior
}

@[direct_array_access]
pub fn lapic_send_ipi(lapic u32, _vector u64) {
	check(wake_count < 1024 && lapic >= 4096 && lapic < 4353, 7)
	wakes[wake_count] = lapic - 4096
	wake_count++
}

pub fn dispatch() {
	check(irq_enabled && current_local.maskable_irq_depth == 0 && C.mh_get_bridge(u32(current_local.cpu_number), 0) == 0, 8)
	destination := C.mh_place(current_task)
	check(destination < 256 && C.mh_may_run(current_task, destination), 9)
	reschedule_count++
	current_local = unsafe { &records[destination] }
	current_task.running_on = destination
}

@[direct_array_access]
fn configure(count int, cpu u32) {
	C.mh_configure_cpus(i64(count))
	C.mh_configure_bridge()
	C.mh_configure_policy()
	kernel_owner = Process{ identity: 1 }
	for i in 0 .. 3 {
		tasks[i] = Thread{ self: unsafe { &tasks[i] }, process: kernel_owner_pointer(), running_on: u64(cpu), tid: i + 1, l: Lock{ role: 1 } }
	}
	current_task = unsafe { &tasks[0] }
	current_local = unsafe { &records[cpu] }
	irq_enabled = true
	wake_count = 0
	reschedule_count = 0
	load_count = 0
	store_count = 0
	hook_lock = unsafe { nil }
	hook_kind = 0
	hook_hits = 0
	held_queue_locks = 0
	thread_releases = 0
	affinity_hook_armed = false
	affinity_hook_reads = 0
	affinity_hook_hits = 0
	affinity_hook_historical = false
}

@[direct_array_access]
fn select_task(index int, cpu u32) {
	current_task = unsafe { &tasks[index] }
	current_local = unsafe { &records[cpu] }
	current_task.running_on = u64(cpu)
}

@[direct_array_access]
fn capture() {
	unsafe {
		C.memcpy(&capture_tasks[0], &tasks[0], sizeof(tasks))
		C.memcpy(&capture_records[0], &records[0], sizeof(records))
	}
	for i in 0 .. 256 {
		for field in 0 .. 2 { capture_bridge[i][field] = C.mh_get_bridge(u32(i), u32(field)) }
	}
	capture_wake = wake_count
	capture_reschedules = reschedule_count
	capture_store = store_count
}

@[direct_array_access]
fn same_state() bool {
	if unsafe { C.memcmp(&capture_tasks[0], &tasks[0], sizeof(tasks)) } != 0 || unsafe { C.memcmp(&capture_records[0], &records[0], sizeof(records)) } != 0 {
		return false
	}
	for i in 0 .. 256 {
		for field in 0 .. 2 {
			if capture_bridge[i][field] != C.mh_get_bridge(u32(i), u32(field)) { return false }
		}
	}
	return capture_reschedules == reschedule_count && capture_store == store_count && (allow_fatal_wake || capture_wake == wake_count)
}

@[noreturn]
pub fn fatal(message &char) {
	if jump_target != unsafe { nil } {
		check(irq_enabled == expected_fatal_irq && same_state(), 10)
		check(unsafe { C.strstr(message, expected_message) } != unsafe { nil }, 11)
		C.mh_longjmp(jump_target)
	}
	C.printf(c'FAIL: unexpected migration panic: %s\n', message)
	C.exit(1)
}

@[export:'array_get']
pub fn borrowed_index(value C.mh_array, index i64) voidptr {
	check(index >= 0 && index < value.len && value.data != unsafe { nil }, 12)
	return unsafe { voidptr(usize(value.data) + usize(index) * usize(value.element_size)) }
}

@[export:'mh_fixed_index']
pub fn fixed_index(index i64, length i64) i64 {
	check(index >= 0 && index < length, 49)
	return index
}

@[export:'mh_fixed_index_u64']
pub fn fixed_index_unsigned(index u64, length i64) i64 {
	check(length >= 0 && index < u64(length), 50)
	return i64(index)
}

@[export:'v3_eprint_lit']
pub fn generated_diagnostic(message &char) {
	C.printf(c'%s', message)
}

@[export:'v_panic']
@[noreturn]
pub fn unexpected_panic(message C.mh_string) { fatal(unsafe { &char(message.str) }) }

@[export:'_v_panic']
@[noreturn]
pub fn unexpected_assert(message C.mh_string, _file C.mh_string, _line i64) {
	fatal(unsafe { &char(message.str) })
}

fn failure(kind int, message &char) {
	mut jump := C.mh_jump{}
	capture()
	expected_fatal_irq = if kind >= 2 { irq_enabled } else { false }
	jump_target = unsafe { &jump }
	expected_message = message
	if C.mh_setjmp(unsafe { &jump }) == 0 {
		match kind {
			0 { C.migrate_disable() }
			1 { C.migrate_enable() }
			2 { C.mh_request(current_task, u32(current_local.cpu_number)) }
			3 { C.mh_historical_request(current_task, u32(current_local.cpu_number)) }
			else { check(false, 13) }
		}
		check(false, 14)
	}
	jump_target = unsafe { nil }
	expected_message = unsafe { nil }
	fatal_cases++
	irq_enabled = true
}

@[direct_array_access]
fn scalar_matrix() {
	for count in [1, 2, 4, 64, 65, 128, 256]! {
		for cpu in 0 .. count {
			for ints in [false, true]! {
				for preempt in [u32(0), u32(1), u32(17)]! {
					for irq in [u32(0), u32(1), u32(3)]! {
						configure(count, u32(cpu))
						irq_enabled = ints
						records[cpu].maskable_irq_depth = irq
						C.mh_set_bridge(u32(cpu), 0, u64(preempt))
						mask := tasks[0].affinity_mask
						numa := tasks[0].numa_node
						C.migrate_disable()
						check(tasks[0].linuxkpi_migration_pin == (u64(1) << 32) | u64(cpu + 1), 15)
						C.migrate_disable()
						check(tasks[0].linuxkpi_migration_pin == (u64(2) << 32) | u64(cpu + 1), 16)
						C.migrate_enable()
						check(tasks[0].linuxkpi_migration_pin == (u64(1) << 32) | u64(cpu + 1), 17)
						C.migrate_enable()
						check(tasks[0].linuxkpi_migration_pin == 0 && irq_enabled == ints && C.mh_get_bridge(u32(cpu), 0) == u64(preempt) && C.mh_get_bridge(u32(cpu), 1) == 0 && wake_count == 0 && reschedule_count == 0 && tasks[0].affinity_mask == mask && tasks[0].numa_node == numa, 18)
					}
				}
			}
		}
	}
}

@[direct_array_access]
fn policy_matrix() {
	configure(256, 0)
	for owner in u32(1) .. u32(257) {
		for depth in [u32(1), u32(2), u32(65534), u32(65535)]! {
			tasks[0].linuxkpi_migration_pin = (u64(depth) << 32) | owner
			tasks[0].affinity_mask = 0
			for cpu in u64(0) .. u64(257) {
				check(C.mh_may_run(unsafe { &tasks[0] }, cpu) == (cpu == u64(owner - 1)), 19)
			}
			for i in 0 .. 256 {
				C.mh_queue_load(u32(i), if u32(i) == owner - 1 { u64(1000000) } else { u64(0) }, if u32(i) == owner - 1 {
					u32(1)
				} else {
					u32(1024)
				})
			}
			tasks[0].sched.util_min = 1024
			tasks[0].sched.util_max = 128
			check(C.mh_place(unsafe { &tasks[0] }) == u64(owner - 1) && C.mh_preferred(unsafe { &tasks[0] }, u64(owner - 1)), 20)
			C.mh_parking(1, if owner == 1 { u64(1) } else { u64(0) })
			check(!C.mh_may_run(unsafe { &tasks[0] }, u64(owner - 1)), 21)
			C.mh_parking(0, 0)
		}
	}
	for word in [u64(1), u64(256), u64(1) << 32, (u64(65536) << 32) | 1, (u64(1) << 32) | 257,
		~u64(0)]! {
		tasks[0].linuxkpi_migration_pin = word
		for cpu in u64(0) .. u64(257) { check(!C.mh_may_run(unsafe { &tasks[0] }, cpu), 22) }
	}
	tasks[0].linuxkpi_migration_pin = 0
	for mask in [u64(0), u64(1), u64(0xaaaaaaaaaaaaaaaa), ~u64(0)]! {
		tasks[0].affinity_mask = mask
		for cpu in u64(0) .. u64(256) {
			check(C.mh_may_run(unsafe { &tasks[0] }, cpu) == (cpu >= 64 || mask & (u64(1) << u32(cpu % 64)) != 0), 23)
		}
	}
}

@[direct_array_access]
fn invalid_matrix() {
	for count in [i64(-1), i64(0), i64(257), i64(0x100000001), i64(9223372036854775807)]! {
		configure(4, 0)
		C.mh_configure_cpus(count)
		failure(0, c'invalid migration CPU domain')
	}
	for cpu in 0 .. 256 {
		for kind in 0 .. 10 {
			configure(256, u32(cpu))
			match kind {
				0 { records[cpu].online = 0 }
				1 { records[cpu].online = 2 }
				2 { records[cpu].cpu_number = 256 }
				3 { members[cpu] = unsafe { &records[(cpu + 1) % 256] } }
				4 { current_task = unsafe { nil } }
				5 { tasks[0].self = unsafe { nil } }
				6 { tasks[0].process = unsafe { nil } }
				7 { tasks[0].is_dead = true }
				8 { tasks[0].running_on = u64((cpu + 1) % 256) }
				else { tasks[0].running_on = u64(cpu) + 0x100000000 }
			}
			failure(0, if kind < 4 { c'invalid migration CPU domain' } else { c'live current task' })
		}
		for word in [u64(1), u64(cpu + 1), (u64(1) << 32), (u64(65536) << 32) | u64(cpu + 1),
			(u64(1) << 32) | u64((cpu + 1) % 256 + 1), ~u64(0)]! {
			configure(256, u32(cpu))
			tasks[0].linuxkpi_migration_pin = word
			failure(0, c'corrupt or misplaced migration pin')
		}
		configure(256, u32(cpu))
		tasks[0].linuxkpi_migration_pin = (u64(65535) << 32) | u64(cpu + 1)
		failure(0, c'nesting overflow')
		configure(256, u32(cpu))
		failure(1, c'unbalanced migrate_enable')
		configure(256, u32(cpu))
		tasks[0].linuxkpi_migration_pin = (u64(65534) << 32) | u64(cpu + 1)
		C.migrate_disable()
		C.migrate_enable()
		check(tasks[0].linuxkpi_migration_pin == (u64(65534) << 32) | u64(cpu + 1), 24)
	}
}

@[direct_array_access]
fn deferred_affinity() {
	for source in u32(0) .. u32(4) {
		for target in u32(0) .. u32(4) {
			if source == target { continue }
			for guard in 0 .. 4 {
				configure(4, source)
				C.migrate_disable()
				C.migrate_disable()
				check(C.vinix_linuxkpi_test_worker_route(unsafe { &tasks[0] }, target) == 0, 25)
				check(tasks[0].affinity_mask == u64(1) << target && tasks[0].linuxkpi_migration_pin == (u64(2) << 32) | u64(source + 1), 26)
				for _ in 0 .. 20 { check(C.mh_place(unsafe { &tasks[0] }) == u64(source), 27) }
				C.migrate_enable()
				check(tasks[0].linuxkpi_migration_pin == (u64(1) << 32) | u64(source + 1), 28)
				wake_count = 0
				match guard {
					0 {}
					1 { irq_enabled = false }
					2 { C.vinix_linuxkpi_preempt_disable() }
					else { records[source].maskable_irq_depth = 1 }
				}
				C.migrate_enable()
				check(tasks[0].linuxkpi_migration_pin == 0 && C.mh_get_bridge(source, 1) == 1 && wake_count == 2 && wakes[0] == source && wakes[1] == target && reschedule_count == 0, 29)
				if guard == 1 {
					C.vinix_linuxkpi_preempt_check_resched()
					check(reschedule_count == 0, 30)
					irq_enabled = true
				}
				if guard == 3 {
					C.vinix_linuxkpi_preempt_check_resched()
					check(reschedule_count == 0, 31)
					records[source].maskable_irq_depth = 0
				}
				if guard == 2 {
					C.vinix_linuxkpi_preempt_check_resched()
					check(reschedule_count == 0, 32)
					C.vinix_linuxkpi_preempt_enable()
				} else {
					C.vinix_linuxkpi_preempt_check_resched()
				}
				check(current_local.cpu_number == u64(target) && reschedule_count == 1 && C.mh_get_bridge(source, 1) == 0, 33)
			}
		}
	}
	// Two tasks using one CPU own independent pin words; ordinary requested
	// affinity remains visible while a pin temporarily controls eligibility.
	configure(4, 0)
	C.migrate_disable()
	select_task(1, 0)
	C.migrate_disable()
	C.migrate_disable()
	select_task(0, 0)
	check(tasks[0].linuxkpi_migration_pin == (u64(1) << 32) | 1 && tasks[1].linuxkpi_migration_pin == (u64(2) << 32) | 1, 34)
	C.migrate_enable()
	select_task(1, 0)
	C.migrate_enable()
	C.migrate_enable()
	check(tasks[0].linuxkpi_migration_pin == 0 && tasks[1].linuxkpi_migration_pin == 0, 35)
}

@[direct_array_access]
fn helper_invalid_matrix() {
	for kind in 0 .. 12 {
		configure(4, 0)
		irq_enabled = false
		match kind {
			0 { irq_enabled = true }
			1 { C.mh_configure_cpus(0) }
			2 { records[0].cpu_number = 4 }
			3 { records[0].online = 0 }
			4 { current_task = unsafe { nil } }
			5 { tasks[0].self = unsafe { nil } }
			6 { tasks[0].process = unsafe { nil } }
			7 { tasks[0].is_dead = true }
			8 { tasks[0].running_on = 1 }
			9 { tasks[0].linuxkpi_migration_pin = (u64(1) << 32) | 1 }
			10 { tasks[0].affinity_mask = 0 }
			else {
				tasks[0].affinity_mask = 2
				records[1].online = 0
			}
		}
		failure(2, if kind == 0 {
			c'requires disabled IRQs'
		} else if kind < 4 {
			c'invalid migration release CPU domain'
		} else if kind < 10 {
			c'unpinned live current task'
		} else {
			c'no eligible destination'
		})
	}
}

@[direct_array_access]
fn binding_guards() {
	// Distinct Process objects with identical fields must fail identity checks.
	for ints in [false, true]! {
		configure(4, 0)
		other_owner = kernel_owner
		tasks[0].process = unsafe { &other_owner }
		tasks[0].numa_node = 37
		irq_enabled = ints
		capture()
		check(C.vinix_linuxkpi_test_worker_route(unsafe { &tasks[0] }, 1) == -1 && irq_enabled == ints && same_state(), 51)
		if ints {
			check(C.vinix_linuxkpi_worker_bind(1) == -1 && irq_enabled && same_state(), 52)
		}
	}
	for source in u32(0) .. u32(4) {
		for target in u32(0) .. u32(4) {
			if source == target { continue }
			configure(4, source)
			C.migrate_disable()
			tasks[0].numa_node = 37
			before_mask := tasks[0].affinity_mask
			before_pin := tasks[0].linuxkpi_migration_pin
			check(C.vinix_linuxkpi_worker_bind(target) == -16, 36)
			check(irq_enabled && tasks[0].numa_node == 37 && tasks[0].affinity_mask == before_mask && tasks[0].linuxkpi_migration_pin == before_pin && wake_count == 0 && reschedule_count == 0, 37)
			check(C.vinix_linuxkpi_worker_bind(source) == 0 && tasks[0].numa_node == -1 && tasks[0].affinity_mask == u64(1) << source && tasks[0].linuxkpi_migration_pin == before_pin, 38)
			C.migrate_enable()
		}
	}
	for guard in 0 .. 3 {
		configure(4, 0)
		C.migrate_disable()
		mask := tasks[0].affinity_mask
		match guard {
			0 { irq_enabled = false }
			1 { C.mh_set_bridge(0, 0, 1) }
			else { records[0].maskable_irq_depth = 1 }
		}
		before_if := irq_enabled
		check(C.vinix_linuxkpi_worker_bind(1) == -11 && irq_enabled == before_if && tasks[0].affinity_mask == mask, 39)
	}
}

@[direct_array_access]
fn scanner_races() {
	for historical in [false, true]! {
		for kind in 1 .. 4 {
			configure(2, 0)
			tasks[0].affinity_mask = 3
			tasks[0].numa_node = -1
			C.mh_configure_queue(0, unsafe { &tasks[0] })
			hook_lock = unsafe { &tasks[0].l }
			hook_kind = kind
			mut last := -1
			selected := C.mh_scan(1, unsafe { &last }, historical)
			check(hook_hits == 1, 40)
			if historical {
				check(selected == unsafe { voidptr(&tasks[0]) } && tasks[0].l.word == 1, 41)
				tasks[0].l.word = 0
			} else {
				check(selected == unsafe { nil } && tasks[0].l.word == 0, 42)
			}
			check(held_queue_locks == 0, 43)
			hook_lock = unsafe { nil }
			hook_kind = 0
			if kind == 1 { C.migrate_enable() }
			race_cases++
		}
	}
}

@[direct_array_access]
fn affinity_publication_races() {
	for historical in [false, true]! {
		for source in u32(0) .. u32(4) {
			for first in u32(0) .. u32(4) {
				for latest in u32(0) .. u32(4) {
					if source == first || source == latest || first == latest { continue }
					configure(4, source)
					if !historical { C.migrate_disable() }
					tasks[0].affinity_mask = u64(1) << first
					affinity_hook_cpu = first
					affinity_hook_target = latest
					affinity_hook_historical = historical
					affinity_hook_armed = true
					if historical {
						irq_enabled = false
						failure(3, c'no eligible destination')
						check(wake_count == 1 && wakes[0] == latest, 55)
					} else {
						C.migrate_enable()
						check(irq_enabled && C.mh_get_bridge(source, 1) == 1 && reschedule_count == 0, 56)
						check(wake_count == 3 && wakes[0] == latest && wakes[1] == source && wakes[2] == first, 57)
						check(!C.mh_may_run(unsafe { &tasks[0] }, u64(first)) && C.mh_may_run(unsafe { &tasks[0] }, u64(latest)), 58)
						C.vinix_linuxkpi_preempt_check_resched()
						check(reschedule_count == 1 && current_local.cpu_number == u64(latest), 59)
					}
					check(affinity_hook_hits == 1 && affinity_hook_reads == 2 && !affinity_hook_armed && tasks[0].affinity_mask == u64(1) << latest && tasks[0].linuxkpi_migration_pin == 0, 60)
					affinity_race_cases++
				}
			}
		}
	}
}

fn observer(_arg voidptr) voidptr {
	unsafe { C.add32(&observer_entered, 1, 5) }
	for unsafe { C.load32(&observer_stop, 2) } == 0 {
		check(C.mh_may_run(unsafe { &tasks[0] }, 0) && !C.mh_may_run(unsafe { &tasks[0] }, 1) && !C.mh_may_run(unsafe { &tasks[0] }, 255), 44)
	}
	return unsafe { nil }
}

@[direct_array_access]
fn concurrent_observers() {
	configure(256, 0)
	tasks[0].affinity_mask = 2
	C.migrate_disable()
	observer_stop = 0
	observer_entered = 0
	mut threads := [8]C.mh_thread{}
	for i in 0 .. 8 {
		check(C.pthread_create(unsafe { &threads[i] }, unsafe { nil }, observer, unsafe { nil }) == 0, 45)
	}
	for unsafe { C.load32(&observer_entered, 2) } != 8 { C.sched_yield() }
	for _ in 0 .. 20000 {
		C.migrate_disable()
		C.migrate_enable()
	}
	unsafe { C.store32(&observer_stop, 1, 3) }
	for i in 0 .. 8 { check(C.pthread_join(threads[i], unsafe { nil }) == 0, 46) }
	tasks[0].affinity_mask = ~u64(0)
	C.migrate_enable()
	check(tasks[0].linuxkpi_migration_pin == 0, 47)
}

@[export:'main']
pub fn run() int {
	scalar_matrix()
	policy_matrix()
	invalid_matrix()
	helper_invalid_matrix()
	deferred_affinity()
	binding_guards()
	scanner_races()
	affinity_publication_races()
	concurrent_observers()
	C.printf(c'PASS: V sleep-preserving migration pins, policy/placement, deferred affinity and scanner races; assertions=%u fatal=%u races=%u affinity_races=%u\n', asserts, fatal_cases, race_cases, affinity_race_cases)
	return 0
}
