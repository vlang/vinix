@[has_globals]
module event

import event.eventstruct
import proc

__global notification_count = u64(0)
__global wait_callback fn () = unsafe { nil }
__global listener_table_full = false
__global private_waits = 0
__global generation_wakes = 0

pub fn notifications() u64 { return notification_count }

pub fn generation(mut e eventstruct.Event) u64 {
	e.l.acquire()
	value := e.generation
	e.l.release()
	return value
}

pub fn trigger(mut e eventstruct.Event, _drop bool) u64 {
	e.l.acquire()
	e.generation++
	notification_count++
	e.l.release()
	return 0
}

pub fn before_wait(callback fn (), full bool) {
	wait_callback = callback
	listener_table_full = full
}

pub fn wait_counts() (int, int) { return private_waits, generation_wakes }

pub fn await_from_generation(mut events []&eventstruct.Event, block bool, index u64, sampled u64) ?u64 {
	assert block && index == 0 && events.len == 2
	if generation(mut events[index]) != sampled {
		generation_wakes++
		return index
	}
	if wait_callback != unsafe { nil } {
		callback := wait_callback
		wait_callback = unsafe { nil }
		callback()
	}
	if listener_table_full {
		listener_table_full = false
		return none
	}
	if generation(mut events[index]) != sampled { return index }
	if proc.interrupted() { return none }
	return 1
}

pub fn await(mut events []&eventstruct.Event, block bool) ?u64 {
	assert block && events.len == 1
	private_waits++
	if proc.interrupted() { return none }
	return 0
}
