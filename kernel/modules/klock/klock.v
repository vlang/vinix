module klock

import katomic

pub struct Lock {
pub mut:
	l bool
	caller voidptr
}

fn C.__sync_bool_compare_and_swap(ptr &bool, old bool, new bool) bool
fn C.__builtin_return_address(level u32) voidptr

pub fn (mut l Lock) acquire() {
	caller := C.__builtin_return_address(0)
	for {
		for i := u64(0); i < u64(500000000); i++ {
			if katomic.cas(&l.l, false, true) == true {
				l.caller = caller
				return
			}
		}
		C.printf(c'POTENTIAL DEADLOCK!!!\n')
		C.printf(c'Lock address:   0x%llx\n', l)
		C.printf(c'Current caller: 0x%llx\n', caller)
		C.printf(c'Last caller:    0x%llx\n', l.caller)
	}
}

pub fn (mut l Lock) release() {
	katomic.cas(&l.l, true, false)
}

pub fn (mut l Lock) test_and_acquire() bool {
	ret := katomic.cas(&l.l, false, true)
	if ret == true {
		l.caller = C.__builtin_return_address(0)
	}
	return ret
}
