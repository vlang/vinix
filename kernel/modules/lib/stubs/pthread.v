module stubs

import lib
import sched
import event
import proc

[export: 'pthread_create']
pub fn pthread_create(thread &C.pthread_t, const_attr &C.pthread_attr_t, start_routine fn(voidptr) voidptr, arg voidptr) int {
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
pub fn pthread_detach(thread &C.pthread_t) int {
	return 0
}

[export: 'pthread_join']
pub fn pthread_join(thread &C.pthread_t, mut retval voidptr) int {
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
