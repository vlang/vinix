module katomic

pub fn bts<T>(var &T, bit byte) bool {
	mut ret := false
	unsafe { asm volatile amd64 {
		lock
		bts var, bit
		; +m (var[0]) as var
		  =@ccc (ret)
		; r (u16(bit)) as bit
		; memory
	} }
	return ret
}

pub fn btr<T>(var &T, bit byte) bool {
	mut ret := false
	unsafe { asm volatile amd64 {
		lock
		btr var, bit
		; +m (var[0]) as var
		  =@ccc (ret)
		; r (u16(bit)) as bit
		; memory
	} }
	return ret
}

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
	mut diff := T(1)
	unsafe { asm volatile amd64 {
		lock
		xadd var, diff
		; +m (var[0]) as var
		  +r (diff)
		;
		; memory
	} }
}

pub fn dec<T>(var &T) bool {
	mut ret := false
	mut diff := T(-1)
	unsafe { asm volatile amd64 {
		lock
		xadd var, diff
		; +m (var[0]) as var
		  +r (diff)
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
