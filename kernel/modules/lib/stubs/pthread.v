// pthread.v: Stubs for the generated V code.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module stubs

import lib
import sched
import event
import proc

struct C.__thread_data {}

struct C.__threadattr {}

@[export: 'pthread_create']
pub fn pthread_create(t &&C.__thread_data, attr &C.__threadattr, start_routine fn (voidptr) voidptr, arg voidptr) int {
	if voidptr(attr) != voidptr(0) {
		lib.kpanic(voidptr(0), c'pthread_create() called with non-NULL attr')
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
