module klock

import sync

pub struct Lock {
mut:
 mutex &sync.Mutex = sync.new_mutex()
}

pub fn (mut guard Lock) acquire() { guard.mutex.lock() }
pub fn (mut guard Lock) release() { guard.mutex.unlock() }
