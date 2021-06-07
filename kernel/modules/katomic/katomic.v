module katomic

pub fn cas<T>(_here &T, _ifthis T, writethis T) bool {
	mut ret := false
	mut here := unsafe { _here }
	mut ifthis := _ifthis
	unsafe { asm volatile amd64 {
		lock
		cmpxchg here, writethis
		; +a (ifthis)
		  +m (here[0]) as here
		  =@ccz (ret)
		; r (writethis)
		; memory
	} }
	return ret
}

pub fn inc<T>(var &T) {
	unsafe { asm volatile amd64 {
		lock
		inc var
		; +m (var[0]) as var
		;
		; memory
	} }
}

pub fn dec<T>(var &T) bool {
	mut ret := false
	unsafe { asm volatile amd64 {
		lock
		dec var
		; +m (var[0]) as var
		  =@ccnz (ret)
		;
		; memory
	} }
	return ret
}

pub fn store<T>(var &T, value T) {
	unsafe { asm volatile amd64 {
		lock
		xchg var, value
		; +m (var[0]) as var
		  +r (value)
		;
		; memory
	} }
}

pub fn load<T>(var &T) T {
	mut ret := T(0)
	unsafe { asm volatile amd64 {
		lock
		xadd var, ret
		; +m (var[0]) as var
		  +r (ret)
		;
		; memory
	} }
	return ret
}
