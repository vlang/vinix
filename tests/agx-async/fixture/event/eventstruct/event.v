module eventstruct

import klock

pub struct Event {
pub mut:
	l klock.Lock
	generation u64
}
