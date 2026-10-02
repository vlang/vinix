@[has_globals]
module event

import proc
import sched
import event.eventstruct
import katomic

__global (
	waiting_event_count = u64(0)
)

fn duplicate_event_before(events []&eventstruct.Event, index u64) bool {
	for previous := u64(0); previous < index; previous++ {
		if events[previous] == events[index] {
			return true
		}
	}
	return false
}

fn check_for_pending(mut events []&eventstruct.Event) ?u64 {
	for i := u64(0); i < events.len; i++ {
		if events[i].pending > 0 {
			events[i].pending--
			return i
		}
	}

	return none
}

// Returns false when the fixed-size listener tables cannot take this waiter.
// Userspace can reach that with enough threads on one futex, so it has to unwind
// and report an interruption rather than take the kernel down; every caller here
// already retries, which is also what a spurious futex wakeup would ask of them.
fn attach_listeners(mut events []&eventstruct.Event, mut t proc.Thread) bool {
	t.attached_events_i = 0

	for i := u64(0); i < events.len; i++ {
		// poll/select callers may name the same underlying resource more than
		// once. One listener is sufficient and avoids enqueueing a thread
		// repeatedly when that shared event fires.
		if duplicate_event_before(events, i) {
			continue
		}
		mut e := events[i]

		if t.attached_events_i == proc.max_events || !e.reserve() {
			detach_listeners(mut t)
			return false
		}

		mut listener := e.slot(e.listeners_i)

		listener.thrd = voidptr(t)
		listener.which = i

		e.listeners_i++

		t.attached_events[t.attached_events_i] = e
		t.attached_events_i++
	}

	return true
}

fn detach_listeners(mut t proc.Thread) {
	for i := u64(0); i < t.attached_events_i; i++ {
		mut e := t.attached_events[i]

		for j := u64(0); j < e.listeners_i; j++ {
			mut listener := e.slot(j)

			if listener.thrd != voidptr(t) {
				continue
			}

			unsafe {
				*listener = *e.slot(e.listeners_i - 1)
			}
			e.listeners_i--
			e.shrink()

			break
		}
	}

	t.attached_events_i = 0
}

// Every waiter takes the locks of the events it waits on in one order, by
// address, and gives them back in the reverse. Taken in the order they were
// listed, two threads waiting on the same two events -- one listing them
// [a, b], the other [b, a] -- could each hold one and spin for the other with
// interrupts off, and every CPU that then touched either event stopped too:
// the machine froze without a word, at the busiest moments of container
// starts and exits. An event listed twice is locked once.
fn lock_events(mut events []&eventstruct.Event) {
	mut last := u64(0)
	for {
		index := next_event_above(events, last)
		if index < 0 {
			return
		}
		events[index].@lock.acquire()
		last = u64(voidptr(events[index]))
	}
}

fn unlock_events(mut events []&eventstruct.Event) {
	mut last := u64(-1)
	for {
		index := next_event_below(events, last)
		if index < 0 {
			return
		}
		events[index].@lock.release()
		last = u64(voidptr(events[index]))
	}
}

// The event with the lowest address above `bound`, or -1.
fn next_event_above(events []&eventstruct.Event, bound u64) int {
	mut chosen := -1
	mut lowest := u64(-1)
	for i := 0; i < events.len; i++ {
		address := u64(voidptr(events[i]))
		if address > bound && address <= lowest {
			lowest = address
			chosen = i
		}
	}
	return chosen
}

// The event with the highest address below `bound`, or -1.
fn next_event_below(events []&eventstruct.Event, bound u64) int {
	mut chosen := -1
	mut highest := u64(0)
	for i := 0; i < events.len; i++ {
		address := u64(voidptr(events[i]))
		if address < bound && address >= highest {
			highest = address
			chosen = i
		}
	}
	return chosen
}

fn await_internal(mut events []&eventstruct.Event, block bool, watch_generation bool,
	watched_index u64, generation u64, generations []u64, explicit_mask bool, interrupt_mask u64) ?u64 {
	mut t := proc.current_thread()

	interrupt_toggle(false)
	defer {
		interrupt_toggle(true)
	}

	lock_events(mut events)

	if i := check_for_pending(mut events) {
		unlock_events(mut events)
		return i
	}
	// A futex wake between sampling its word and attaching the listener is a
	// valid spurious wake, and must not turn into an indefinite sleep.
	if watch_generation && events[watched_index].generation != generation {
		unlock_events(mut events)
		return watched_index
	}
	// Pollers sample every generation before rechecking readiness. A wake
	// consumed by another waiter between that scan and registration must
	// still cause a rescan, even when no consumable pending count remains.
	for i in 0 .. generations.len {
		if events[i].generation != generations[i] {
			unlock_events(mut events)
			return u64(i)
		}
	}

	// A thread its process has told to exit must not go to sleep again: the
	// sibling tearing the process down is waiting for it to unwind and leave.
	if block == false || katomic.load(&t.must_exit) {
		unlock_events(mut events)
		return none
	}
	// Nor go to sleep with a signal it does not block already pending: the wait
	// ends as interrupted, as Linux's signal_pending() check ends it. A signal
	// sent while the thread was not asleep had nothing to wake, and the next
	// wait slept through it for as long as its timeout, or for good: none of
	// postgres's processes saw the SIGTERM of a shutdown.
	// A signal delivered while this thread was running leaves a wake marker,
	// even after its handler consumed the signal. Retire that old marker before
	// sampling pending signals. A sender racing before this clear is observed
	// in pending_signals; one racing after the sample republishes the marker
	// checked after dequeue. Clearing it later would lose that second wake.
	katomic.store(mut &t.enqueued_by_signal, false)
	mask := if explicit_mask { interrupt_mask } else { ~t.masked_signals }
	if katomic.load(&t.pending_signals) & mask != 0 {
		unlock_events(mut events)
		return none
	}

	katomic.inc(mut &waiting_event_count)
	t.which_event = u64(-1)

	if !attach_listeners(mut events, mut t) {
		katomic.dec(mut &waiting_event_count)
		unlock_events(mut events)
		return none
	}

	defer {
		interrupt_toggle(false)
		lock_events(mut events)
		detach_listeners(mut t)
		unlock_events(mut events)
		interrupt_toggle(true)
	}

	sched.dequeue_thread(t)

	interrupted_before_yield := katomic.load(&t.enqueued_by_signal)
	if interrupted_before_yield {
		sched.enqueue_thread(t, false)
	}

	unlock_events(mut events)

	if !interrupted_before_yield {
		sched.yield(true)
	}

	katomic.dec(mut &waiting_event_count)

	interrupted_by_signal := katomic.load(&t.enqueued_by_signal)
	if interrupted_by_signal {
		katomic.store(mut &t.enqueued_by_signal, false)
	}
	// Child exit raises an event and SIGCHLD together. If both wake this wait,
	// retain the consumed event; otherwise waitpid loses the zombie forever.
	if (interrupted_by_signal || katomic.load(&t.must_exit)) && t.which_event == u64(-1) {
		if katomic.load(&t.must_exit) || katomic.load(&t.pending_signals) & mask != 0 {
			return none
		}
		// A sender can publish its wake after the target already consumed the
		// signal. With no applicable signal left, this is a spurious wake;
		// await_valid retries it rather than manufacturing a user EINTR.
		return u64(-1)
	}

	return t.which_event
}

// One wait, repeated while it only ends in a spurious wake: woken without one
// of these events having fired for it, or told of an index that is not into
// this wait's list. Handing such an index back had callers index their own
// lists out of range, which panicked the kernel.
fn await_valid(mut events []&eventstruct.Event, block bool, watch_generation bool,
	watched_index u64, generation u64, generations []u64, explicit_mask bool, interrupt_mask u64) ?u64 {
	for {
		which := await_internal(mut events, block, watch_generation, watched_index,
			generation, generations, explicit_mask, interrupt_mask)?
		if which < u64(events.len) {
			return which
		}
	}
	return none
}

pub fn await(mut events []&eventstruct.Event, block bool) ?u64 {
	return await_valid(mut events, block, false, 0, 0, []u64{}, false, 0)
}

// Signal acceptance waits must also wake for their requested blocked signals.
// Keep the same mask for both the pre-sleep check and wake classification.
pub fn await_masked(mut events []&eventstruct.Event, block bool, interrupt_mask u64) ?u64 {
	return await_valid(mut events, block, false, 0, 0, []u64{}, true, interrupt_mask)
}

pub fn await_from_generation(mut events []&eventstruct.Event, block bool, watched_index u64,
	generation u64) ?u64 {
	return await_valid(mut events, block, true, watched_index, generation, []u64{}, false, 0)
}

pub fn await_changes(mut events []&eventstruct.Event, generations []u64, block bool) ?u64 {
	if generations.len != events.len { return none }
	return await_valid(mut events, block, false, 0, 0, generations, false, 0)
}

// Job-control waits retain ordinary pending signals while stopped without
// changing the userspace signal mask. must_exit always interrupts a wait.
pub fn await_one_masked(mut e eventstruct.Event, interrupt_mask u64) ?u64 {
	mut storage := [&e]!
	mut events := unsafe { stack_list(&storage[0], 1) }
	return await_valid(mut events, true, false, 0, 0, []u64{}, true, interrupt_mask)
}

pub fn generation(mut e eventstruct.Event) u64 {
	interrupts := interrupt_state()
	interrupt_toggle(false)
	e.@lock.acquire()
	value := e.generation
	e.@lock.release()
	if interrupts {
		interrupt_toggle(true)
	}
	return value
}

pub fn trigger(mut e eventstruct.Event, drop bool) u64 {
	ints := interrupt_state()

	interrupt_toggle(false)
	defer {
		if ints == true {
			interrupt_toggle(true)
		}
	}

	e.@lock.acquire()
	defer {
		e.@lock.release()
	}
	e.generation++

	if e.listeners_i == 0 {
		if drop == false {
			e.pending++
		}
		return 0
	}

	mut preserve_pending := false
	for i := u64(0); i < e.listeners_i; i++ {
		listener := e.slot(i)
		mut t := unsafe { &proc.Thread(listener.thrd) }

		// A thread may listen to several events. Once one has made it runnable,
		// do not overwrite that selection; retain this event for its next await.
		if katomic.load(&t.is_in_queue) {
			preserve_pending = true
			continue
		}
		t.which_event = listener.which

		if !sched.enqueue_thread(t, false) {
			preserve_pending = true
		}
	}
	if preserve_pending && drop == false {
		e.pending++
	}

	ret := e.listeners_i

	e.listeners_i = 0
	e.shrink()

	return ret
}

pub fn pthread_exit(ret voidptr) {
	interrupt_toggle(false)

	mut current_thread := proc.current_thread()

	katomic.store(mut &current_thread.is_dead, true)
	sched.dequeue_thread(current_thread)
	current_thread.exit_value = ret
	katomic.store(mut &current_thread.pthread_exited, true)
	trigger(mut current_thread.exited, false)
	sched.dequeue_and_die()
	// A thread taken off the run queue is never switched back to.
	for {}
}

pub fn pthread_wait(t &proc.Thread) voidptr {
	mut storage := [&t.exited]!
	mut events := unsafe { stack_list(&storage[0], storage.len) }
	for !katomic.load(&t.pthread_exited) {
		await(mut events, true) or { sched.reschedule() }
	}
	exit_value := t.exit_value
	// pthread_create owns this join reference before the thread can run.
	// The scheduler frees the thread only once it is off its stacks and its
	// last reference is gone. It may still be leaving this CPU right now.
	proc.unpin_thread(t)
	sched.reap_deferred()
	return exit_value
}
