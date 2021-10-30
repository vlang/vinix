module stubs

import lib
import sched
import event
import proc

struct C.__mlibc_thread_data {}

struct C.__mlibc_threadattr {}

[export: 'pthread_create']
pub fn pthread_create(thread &&C.__mlibc_thread_data, const_attr &C.__mlibc_threadattr, start_routine fn (voidptr) voidptr, arg voidptr) int {
	if voidptr(const_attr) != voidptr(0) {
		lib.kpanic(voidptr(0), c'pthread_create() called with non-NULL attr')
	}

	unsafe {
		mut ptr := &voidptr(thread)
		*ptr = sched.new_kernel_thread(voidptr(start_routine), arg, true)
	}
	return 0
}

[export: 'pthread_detach']
pub fn pthread_detach(thread &C.__mlibc_thread_data) int {
	return 0
}

[export: 'pthread_join']
pub fn pthread_join(thread &C.__mlibc_thread_data, mut retval voidptr) int {
	unsafe {
		*retval = event.pthread_wait(&proc.Thread(thread))
	}
	return 0
}

[export: 'pthread_exit']
pub fn pthread_exit(retval voidptr) int {
	event.pthread_exit(retval)
	return 0 // doesn't actually return, the int return type seems to be a mlibc quirk
}
