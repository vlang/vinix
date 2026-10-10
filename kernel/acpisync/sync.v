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
	// Nonzero while a wait must not wait: see forbid_waiting().
	acpisync_no_waiting u32
)

// From here until allow_waiting(), a wait that would have to wait gives up
// at once, as one with no time allowed does. For the moment a caller is on
// the only running processor with interrupts off and calls into ACPI code
// that takes its sleeping locks: nobody is there to let go of one, and
// waiting for it means giving up the processor, which turns interrupts back
// on under the caller. A lock that is free is taken as ever.
pub fn forbid_waiting() {
	katomic.store(mut &acpisync_no_waiting, u32(1))
}

pub fn allow_waiting() {
	katomic.store(mut &acpisync_no_waiting, u32(0))
}

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
	return wait_for(handle, timeout, true)
}

// wait() for the locks inside the kernel's ACPI code: uACPI's own mutexes,
// and those of drivers its methods end up in. It differs in two ways.
//
// A thread that waits without limit for a mutex it is recorded as holding is
// refused by wait(), since it would wait for itself. For uACPI the record is
// not who holds the mutex: its reader-writer lock has the first reader take
// the writers' mutex for all readers, so that reader, done reading while
// another still reads, is still on record when it comes back to write. It
// has to wait for the other reader like anybody else; refused, the method it
// was about to run failed with nothing wrong. uACPI keeps its own account of
// the mutexes that may be taken twice by one thread.
//
// And a thread with a signal waiting for it may not sleep, so wait() gives
// up with an error, which is right for a wait a signal should end. A method
// is evaluated in the context of whoever reads a file in /sys, and whether
// that program has a signal coming is no reason for the method to fail half
// way: here such a thread takes turns with the others until the mutex is
// free, which is as long as its holder needs and no longer.
@[export: 'vinix_acpi_sync_acquire']
pub fn acquire(handle voidptr, timeout u16) int {
	return wait_for(handle, timeout, false)
}

// `strict` is wait(): refuse the holder on record, and end the wait for a
// signal.
fn wait_for(handle voidptr, timeout u16, strict bool) int {
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
	if timeout == 0 || katomic.load(&acpisync_no_waiting) != 0 {
		gate.lock.release()
		return 18
	}
	if strict && gate.mutex && gate.owner == identity && timeout == 0xffff {
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
			which := event.await_from_generation(mut events, true, 0, generation) or {
				if strict {
					return 10
				}
				sched.reschedule()
				continue
			}
			timer_expired = which == 1
		} else {
			mut storage := [&gate.wake]!
			mut events := unsafe { event.stack_list(&storage[0], storage.len) }
			event.await_from_generation(mut events, true, 0, generation) or {
				if strict {
					return 10
				}
				sched.reschedule()
				continue
			}
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

// Give a held mutex back, whichever thread took it. signal() refuses a
// release by anybody but the owner, which is right for a lock one thread
// takes and gives back. uACPI's reader-writer lock is not that: the first
// reader in takes the writers' mutex and the last reader out gives it back,
// and with two threads reading at once those are different threads. Refused,
// that mutex stayed taken for good and every later evaluation waited on it
// for ever. False when the mutex is not held at all.
@[export: 'vinix_acpi_sync_release']
pub fn release(handle voidptr) bool {
	if handle == unsafe { nil } {
		return false
	}
	mut gate := unsafe { &Gate(handle) }
	gate.lock.acquire()
	defer { gate.lock.release() }
	if !gate.mutex || gate.owner == 0 {
		return false
	}
	gate.owner = 0
	gate.permits = 1
	event.trigger(mut gate.wake, true)
	return true
}

// Whether the calling thread holds the mutex `handle`: for a caller that may
// be reached both with and without it, and must not wait for itself.
pub fn held_by_caller(handle voidptr) bool {
	if handle == unsafe { nil } {
		return false
	}
	mut gate := unsafe { &Gate(handle) }
	identity := thread_id()
	gate.lock.acquire()
	held := gate.mutex && gate.owner == identity
	gate.lock.release()
	return held
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

fn C.vinix_acpi_sync_native_test() i32
fn C.vinix_acpi_sync_boot_test() i32

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
