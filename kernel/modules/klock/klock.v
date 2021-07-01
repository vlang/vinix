module klock

import katomic

pub struct Lock {
pub mut:
	l bool
	caller u64
}

fn C.__builtin_return_address(int) voidptr

pub fn (mut l Lock) acquire() {
	caller := u64(C.__builtin_return_address(0))

	for i := u64(0); i < u64(50000000); i++ {
		if l.test_and_acquire() == true {
			l.caller = caller
			return
		}
		asm volatile amd64 { pause ;;; memory }
	}

	C.printf(c'Lock address:   0x%llx\n', voidptr(l))
	C.printf(c'Current caller: 0x%llx\n', caller)
	C.printf(c'Last caller:    0x%llx\n', l.caller)
	panic('Deadlock detected')
}

pub fn (mut l Lock) release() {
	katomic.store(l.l, false)
}

pub fn (mut l Lock) test_and_acquire() bool {
	caller := u64(C.__builtin_return_address(0))

	ret := katomic.cas(l.l, false, true)
	if ret == true {
		l.caller = caller
	}

	return ret
}
