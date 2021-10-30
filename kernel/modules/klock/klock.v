module klock

import katomic
import trace

pub struct Lock {
pub mut:
	l      bool
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
		asm volatile amd64 {
			pause
			; ; ; memory
		}
	}

	C.printf_panic(c'Lock address:   0x%llx\n', voidptr(l))
	mut offset, mut symbol := trace.address(caller) or { return }
	C.printf_panic(c'Current caller: 0x%llx  <%s+0x%llx>\n', caller, symbol.name, offset)
	offset, symbol = trace.address(l.caller) or { return }
	C.printf_panic(c'Last caller:    0x%llx  <%s+0x%llx>\n', l.caller, symbol.name, offset)
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
