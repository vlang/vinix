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
	$if T is u64 {
		asm volatile amd64 {
			lock
			incq [var]
			;
			; r (var)
			; memory
		}
	} $else {
		typestr := unsafe { typeof(var[0]).name }
		panic('atomic_inc not supported for type ${typestr}')
	}
}

pub fn dec<T>(var &T) bool {
	mut ret := false
	$if T is u64 {
		asm volatile amd64 {
			lock
			decq [var]
			; =@ccnz (ret)
			; r (var)
			; memory
		}
	} $else {
		typestr := unsafe { typeof(var[0]).name }
		panic('atomic_dec not supported for type ${typestr}')
	}
	return ret
}

pub fn store<T>(var &T, value T) {
	$if T is u64 {
		asm volatile amd64 {
			lock
			xchgq [var], value
			;
			; r (var)
			  ri (value)
			; memory
		}
	} $else $if T is byte {
		asm volatile amd64 {
			lock
			xchgb [var], value
			;
			; r (var)
			  ri (value)
			; memory
		}
	} $else {
		typestr := unsafe { typeof(var[0]).name }
		panic('atomic_store not supported for type ${typestr}')
	}
}

pub fn load<T>(var &T) T {
	$if T is u64 {
		mut ret := u64(0)
		asm volatile amd64 {
			lock
			xaddq [var], ret
			; +r (ret)
			; r (var)
			; memory
		}
		return ret
	} $else $if T is byte {
		mut ret := byte(0)
		asm volatile amd64 {
			lock
			xaddb [var], ret
			; +r (ret)
			; r (var)
			; memory
		}
		return ret
	} $else $if T is bool {
		mut ret := false
		asm volatile amd64 {
			lock
			xaddb [var], ret
			; +r (ret)
			; r (var)
			; memory
		}
		return ret
	} $else {
		typestr := unsafe { typeof(var[0]).name }
		panic('atomic_load not supported for type ${typestr}')
	}
}
