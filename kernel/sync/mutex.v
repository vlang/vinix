module sync

pub struct Mutex {
	thread_yield fn()
	state byte
}

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