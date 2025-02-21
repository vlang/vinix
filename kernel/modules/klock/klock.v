// klock.v: Locking mechanisms for kernel code.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module klock

import katomic

pub struct Lock {
pub mut:
	l      bool
	caller u64
}

fn C.__builtin_return_address(int) voidptr

pub fn (mut l Lock) acquire() {
	caller := u64(C.__builtin_return_address(0))

	for {
		if l.test_and_acquire() == true {
			l.caller = caller
			return
		}
		asm volatile amd64 {
			pause
			; ; ; memory
		}
	}
}

pub fn (mut l Lock) release() {
	katomic.store(mut &l.l, false)
}

pub fn (mut l Lock) test_and_acquire() bool {
	caller := u64(C.__builtin_return_address(0))

	ret := katomic.cas(mut &l.l, false, true)
	if ret == true {
		l.caller = caller
	}

	return ret
}
