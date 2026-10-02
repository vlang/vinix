@[has_globals]
module acpisync

import event
import event.eventstruct
import katomic
import klock
import memory
import proc
import sched
import time

// Native uACPI mutexes are nonrecursive; AML recursion is handled by uACPI.
// A wake is only a hint to inspect permits. event.trigger broadcasts, whereas
// one AML Signal must release exactly one successful Wait.
struct Gate {
mut:
	lock    klock.Lock
	wake    eventstruct.Event
	permits u64
	owner   u64
	waiters u64
	mutex   bool
}

__global (
	scheduler_available = u32(0)
)

pub fn scheduler_ready() {
	katomic.store(mut &scheduler_available, u32(1))
}

@[export: 'vinix_acpi_sync_thread_id']
pub fn thread_id() u64 {
	// Before SMP and the scheduler exist, AML runs only on the boot thread.
	// Do not read GS/TPIDR or dereference a Thread before that initialization.
	if katomic.load(&scheduler_available) == 0 {
		return 1
	}
	current := proc.current_thread()
	return if current == unsafe { nil } { 1 } else { u64(voidptr(current)) }
}

@[export: 'vinix_acpi_sync_create']
pub fn create(mutex bool) voidptr {
	allocation := memory.malloc_packed_fallible(sizeof(Gate))
	if allocation == unsafe { nil } {
		return unsafe { nil }
	}
	mut gate := unsafe { &Gate(allocation) }
	unsafe {
		*gate = Gate{permits: if mutex { u64(1) } else { u64(0) }, mutex: mutex}
	}
	return allocation
}

// The host must quiesce every user before destruction. Refuse destruction
// when that contract is observably violated, rather than free live listeners.
@[export: 'vinix_acpi_sync_destroy']
pub fn destroy(handle voidptr) bool {
	if handle == unsafe { nil } {
		return true
	}
	mut gate := unsafe { &Gate(handle) }
	gate.lock.acquire()
	if gate.waiters != 0 || gate.owner != 0 {
		gate.lock.release()
		return false
	}
	gate.wake.@lock.acquire()
	quiet := gate.wake.listeners_i == 0 && gate.wake.overflow == unsafe { nil }
	gate.wake.@lock.release()
	gate.lock.release()
	if !quiet {
		return false
	}
	unsafe { free(handle) }
	return true
}

// uACPI status numbers: OK=0, INVALID_ARGUMENT=7, INTERNAL_ERROR=10,
// TIMEOUT=18, DENIED=20. A timeout of zero never allocates or schedules.
@[export: 'vinix_acpi_sync_wait']
pub fn wait(handle voidptr, timeout u16) int {
	if handle == unsafe { nil } {
		return 7
	}
	mut gate := unsafe { &Gate(handle) }
	identity := thread_id()
	gate.lock.acquire()
	if gate.permits != 0 {
		gate.permits--
		if gate.mutex {
			gate.owner = identity
		}
		gate.lock.release()
		return 0
	}
	if timeout == 0 {
		gate.lock.release()
		return 18
	}
	if gate.mutex && gate.owner == identity && timeout == 0xffff {
		gate.lock.release()
		return 20
	}
	gate.waiters++
	gate.lock.release()

	mut timer := unsafe { &time.Timer(nil) }
	defer {
		// await detaches all listeners before returning. disarm holds the same
		// timers_lock as expiry, so the IRQ cannot retain this timer afterwards.
		if timer != unsafe { nil } {
			timer.disarm()
			unsafe { free(timer) }
		}
		gate.lock.acquire()
		gate.waiters--
		gate.lock.release()
	}
	finite := timeout != 0xffff
	started := clock_ns()
	duration := u64(timeout) * 1000000
	can_sleep := katomic.load(&scheduler_available) != 0
	if finite && can_sleep {
		timer = time.new_timer(time.TimeSpec{i64(timeout / 1000), i64(timeout % 1000) * 1000000})
	}
	mut timer_expired := false
	for {
		gate.lock.acquire()
		if gate.permits != 0 {
			gate.permits--
			if gate.mutex {
				gate.owner = identity
			}
			gate.lock.release()
			return 0
		}
		if finite && clock_ns() - started >= duration {
			gate.lock.release()
			return 18
		}
		generation := event.generation(mut gate.wake)
		gate.lock.release()
		if !can_sleep {
			spin_hint()
			continue
		}
		// The x86 timer clock advances in whole IRQ ticks. A timer armed just
		// before a tick can fire less than one tick before its full duration.
		// Once consumed, its event will not fire twice: yield through that tail
		// rather than sleep again on an already-fired timer or return too early.
		if timer_expired {
			sched.reschedule()
			continue
		}
		if finite {
			mut storage := [&gate.wake, &timer.event]!
			mut events := unsafe { event.stack_list(&storage[0], storage.len) }
			which := event.await_from_generation(mut events, true, 0, generation) or { return 10 }
			timer_expired = which == 1
		} else {
			mut storage := [&gate.wake]!
			mut events := unsafe { event.stack_list(&storage[0], storage.len) }
			event.await_from_generation(mut events, true, 0, generation) or { return 10 }
		}
	}
	return 10
}

@[export: 'vinix_acpi_sync_sleep']
pub fn sleep(msec u64) {
	if msec == 0 {
		return
	}
	started := clock_ns()
	duration := if msec > ~u64(0) / 1000000 { ~u64(0) } else { msec * 1000000 }
	if katomic.load(&scheduler_available) == 0 {
		for clock_ns() - started < duration {
			spin_hint()
		}
		return
	}
	mut timer := time.new_timer(time.TimeSpec{i64(msec / 1000), i64(msec % 1000) * 1000000})
	defer {
		timer.disarm()
		unsafe { free(timer) }
	}
	event.await_one(mut timer.event, true) or { return }
	for clock_ns() - started < duration {
		sched.reschedule()
	}
}

@[export: 'vinix_acpi_sync_signal']
pub fn signal(handle voidptr) bool {
	if handle == unsafe { nil } {
		return false
	}
	mut gate := unsafe { &Gate(handle) }
	gate.lock.acquire()
	defer { gate.lock.release() }
	if gate.mutex {
		if gate.owner == 0 || gate.owner != thread_id() {
			return false
		}
		gate.owner = 0
		gate.permits = 1
	} else if gate.permits != ~u64(0) {
		gate.permits++
	}
	event.trigger(mut gate.wake, true)
	return true
}

@[export: 'vinix_acpi_sync_reset']
pub fn reset(handle voidptr) {
	if handle == unsafe { nil } {
		return
	}
	mut gate := unsafe { &Gate(handle) }
	gate.lock.acquire()
	if !gate.mutex {
		gate.permits = 0
	}
	gate.lock.release()
}

fn C.vinix_acpi_sync_native_test() int
fn C.vinix_acpi_sync_boot_test() int

pub fn test_boot() {
	$if acpi_sync_test ? {
		if C.vinix_acpi_sync_boot_test() != 0 {
			panic('ACPI synchronization bootstrap test failed')
		}
	}
}

pub fn test_native() {
	$if acpi_sync_test ? {
		if C.vinix_acpi_sync_native_test() != 0 {
			panic('ACPI synchronization native test failed')
		}
	}
}
