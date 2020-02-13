module sync

pub struct Mutex {
	state byte
}

const (
	SPIN_LIMIT = 40
)

pub fn (mutex &Mutex) lock() {
	//TODO Implement mutex
}

pub fn (mutex &Mutex) try_lock() bool {
	//TODO Implement mutex
	return true
}

pub fn (mutex &Mutex) unlock() {
	//TODO Implement mutex
}