module klock

import katomic
import x86.cpu

pub struct Lock {
pub mut:
	l    bool
	ints bool
}

fn C.__builtin_return_address(int) voidptr

pub fn (mut l Lock) acquire() {
	for {
		if l.test_and_acquire() == true {
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
	cpu.interrupt_toggle(l.ints)
}

pub fn (mut l Lock) test_and_acquire() bool {
	ints := cpu.interrupt_toggle(false)

	ret := katomic.cas(mut &l.l, false, true)
	if ret == true {
		l.ints = ints
	} else {
		cpu.interrupt_toggle(ints)
	}

	return ret
}
