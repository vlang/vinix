@[has_globals]
module event

import event.eventstruct

__global notification_count = u64(0)

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
