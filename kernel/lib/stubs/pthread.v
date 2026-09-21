module stubs

import lib
import sched
import event
import proc

struct C.__thread_data {}

struct C.__threadattr {}

@[export: 'pthread_create']
pub fn pthread_create(t &&C.__thread_data, attr &C.__threadattr, start_routine fn (voidptr) voidptr, arg voidptr) int {
	if attr != unsafe { nil } {
		lib.kpanic(unsafe { nil }, c'pthread_create() called with non-NULL attr')
	}

	unsafe {
		mut ptr := &voidptr(t)
		*ptr = sched.new_kernel_thread(voidptr(start_routine), arg, true)
	}
	return 0
}

@[export: 'pthread_detach']
pub fn pthread_detach(t &C.__thread_data) int {
	return 0
}

@[export: 'pthread_join']
pub fn pthread_join(t &C.__thread_data, mut retval voidptr) int {
	unsafe {
		*retval = event.pthread_wait(&proc.Thread(t))
	}
	return 0
}

@[export: 'pthread_exit']
@[noreturn]
pub fn pthread_exit(retval voidptr) {
	event.pthread_exit(retval)
	for {}
}

// V's generated thread runtime sets a stack size on an attribute object before
// spawning. A kernel thread's stack is chosen by the scheduler, so the attribute
// is accepted and ignored; reporting success keeps the runtime on its normal path
// instead of aborting.
@[export: 'pthread_attr_init']
pub fn pthread_attr_init(attr &C.__threadattr) int {
	return 0
}

@[export: 'pthread_attr_setstacksize']
pub fn pthread_attr_setstacksize(attr &C.__threadattr, stacksize u64) int {
	return 0
}

@[export: 'pthread_attr_destroy']
pub fn pthread_attr_destroy(attr &C.__threadattr) int {
	return 0
}

@[export: 'pthread_equal']
pub fn pthread_equal(a &C.__thread_data, b &C.__thread_data) int {
	return if a == b { 1 } else { 0 }
}
